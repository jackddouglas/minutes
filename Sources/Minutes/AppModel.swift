import AVFoundation
import AppKit
import MinutesCore
import Observation
import UniformTypeIdentifiers

extension Meeting {
  static let untitled = "Untitled meeting"
}

@MainActor @Observable
final class AppModel {
  var meetings: [Meeting] = []
  var selection: UUID? {
    didSet { if selection != oldValue { playback.stop() } }
  }
  var title = ""
  var recordingSystemSpeakers = 0
  var meetingToDelete: Meeting?
  let calendarMonitor: CalendarMonitor
  /// The calendar event a new meeting was prefilled from, so its call can be joined.
  private(set) var preparedCalendarMeeting: CalendarMeeting?
  var applications: [AudioSource] = []
  var sourceID: Int32 = 0
  private var explicitSourceBundleID: String?
  private let runningAudioSources: () -> [AudioSource]
  private let defaultBrowserBundleID: (URL) -> String?
  var isRecording = false {
    didSet { scheduleModelUnload() }
  }
  var isBusy = false {
    didSet {
      if isBusy { playback.stop() }
      scheduleModelUnload()
    }
  }
  let playback = RecordingPlayback()
  let chatGPT: ChatGPTConnection
  var savedSpeakers: [String] {
    didSet { preferences.set(savedSpeakers, forKey: "savedSpeakers") }
  }
  var defaultMicrophoneSpeaker: String {
    didSet { preferences.set(defaultMicrophoneSpeaker, forKey: "defaultMicrophoneSpeaker") }
  }
  var corrections: TranscriptCorrections {
    didSet {
      preferences.set(try? JSONEncoder().encode(corrections), forKey: "transcriptCorrections")
    }
  }
  var defaultQuality: TranscriptionOptions.Quality {
    didSet { preferences.set(defaultQuality.rawValue, forKey: "transcriptionQuality") }
  }
  var defaultTranscriptionOptions: TranscriptionOptions {
    .init(quality: defaultQuality, expectedSystemSpeakers: nil)
  }
  var modelIdleMinutes: Int {
    didSet {
      preferences.set(modelIdleMinutes, forKey: "modelIdleMinutes")
      scheduleModelUnload()
    }
  }
  private var modelUnloadTask: Task<Void, Never>?
  var modelsReady = false
  var status = "Ready when you are"
  var error: String?
  var summaryError: String?
  private(set) var summarizingMeetingID: UUID?
  private var summaryTask: Task<Void, Never>?
  var recordingStarted: Date?
  private(set) var recordingLevels = RecordingLevels()
  /// Remembered so a deliberate opt-in carries over to the next new meeting.
  var previewsMicrophone: Bool {
    didSet { preferences.set(previewsMicrophone, forKey: "previewsMicrophone") }
  }
  private(set) var previewLevel = RecordingLevel()
  var exportDirectory: URL {
    didSet { preferences.set(exportDirectory.path, forKey: "exportDirectory") }
  }

  private let modelIdleMinuteDuration: Duration
  private let preferences: UserDefaults
  private let capture = AudioCapture()
  private let microphonePreview = MicrophonePreview()
  private let recordingSounds = RecordingSounds()
  private let transcription = TranscriptionService()
  private let store: MeetingStore
  private let recordingsDirectory: URL
  private var activeMeeting: Meeting?

  var recordingMeetingID: UUID? { isRecording ? activeMeeting?.id : nil }

  var selectedMeeting: Meeting? { meetings.first { $0.id == selection } }
  var canStart: Bool { !isBusy && !isRecording && sourceID != 0 }

  init(
    supportDirectory: URL? = nil, preferences: UserDefaults = .standard,
    modelIdleMinuteDuration: Duration = .seconds(60), chatGPT: ChatGPTConnection? = nil,
    runningAudioSources: @escaping () -> [AudioSource] = { AudioSource.running() },
    defaultBrowserBundleID: @escaping (URL) -> String? = { url in
      NSWorkspace.shared.urlForApplication(toOpen: url).flatMap {
        Bundle(url: $0)?.bundleIdentifier
      }
    }
  ) {
    self.runningAudioSources = runningAudioSources
    self.defaultBrowserBundleID = defaultBrowserBundleID
    self.modelIdleMinuteDuration = modelIdleMinuteDuration
    self.preferences = preferences
    self.chatGPT = chatGPT ?? ChatGPTConnection(defaults: preferences)
    modelIdleMinutes = max(0, preferences.object(forKey: "modelIdleMinutes") as? Int ?? 10)
    calendarMonitor = CalendarMonitor(preferences: preferences)
    defaultQuality =
      TranscriptionOptions.Quality(
        rawValue: preferences.string(forKey: "transcriptionQuality") ?? "") ?? .thorough
    savedSpeakers = preferences.stringArray(forKey: "savedSpeakers") ?? []
    defaultMicrophoneSpeaker = preferences.string(forKey: "defaultMicrophoneSpeaker") ?? ""
    previewsMicrophone = preferences.bool(forKey: "previewsMicrophone")
    corrections =
      preferences.data(forKey: "transcriptCorrections").flatMap {
        try? JSONDecoder().decode(TranscriptCorrections.self, from: $0)
      } ?? .init()
    let support =
      supportDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ]
      .appendingPathComponent("Minutes", isDirectory: true)
    store = MeetingStore(directory: support.appendingPathComponent("Meetings"))
    recordingsDirectory = support.appendingPathComponent("Recordings")
    let saved = preferences.string(forKey: "exportDirectory")
    exportDirectory =
      saved.map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Minutes")
    do {
      meetings = try store.load()
      selection = meetings.first?.id
    } catch { self.error = "Could not read the meeting library: \(error.localizedDescription)" }
    capture.onFailure = { [weak self] message in
      guard let self, self.isRecording else { return }
      self.error = "Capture stopped: \(message). The recording will be retained."
      self.stop()
    }
  }

  func refreshRecordingLevels() async {
    let levels = await capture.levels()
    guard isRecording else { return }
    recordingLevels = levels
  }

  func startMicrophonePreview() async {
    guard previewsMicrophone, !isBusy, !isRecording else { return }
    do {
      try await microphonePreview.start()
    } catch {
      previewsMicrophone = false
      self.error = error.localizedDescription
    }
  }

  func stopMicrophonePreview() {
    microphonePreview.stop()
    previewLevel = RecordingLevel()
  }

  func refreshPreviewLevel() async {
    let level = await microphonePreview.level()
    guard microphonePreview.isRunning else { return }
    previewLevel = level
  }

  func refreshSources() {
    guard !isBusy && !isRecording else { return }
    applications = runningAudioSources().sorted {
      $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
    }
    let rankedIDs = [
      explicitSourceBundleID,
      preferredMeetingBrowserBundleID,
      preferences.string(forKey: "lastAudioSourceBundleID"),
    ].compactMap { $0 }
    sourceID =
      rankedIDs.lazy.compactMap { id in
        self.applications.first { $0.bundleID == id }?.processID
      }.first ?? applications.first?.processID ?? 0
  }

  private var preferredMeetingBrowserBundleID: String? {
    guard let meeting = preparedCalendarMeeting else { return nil }
    return preferences.string(forKey: "googleMeetBrowserBundleID")
      ?? defaultBrowserBundleID(meeting.url)
  }

  func selectSource(_ processID: Int32) {
    guard !isBusy, !isRecording,
      let source = applications.first(where: { $0.processID == processID })
    else { return }
    explicitSourceBundleID = source.bundleID
    sourceID = source.processID
    preferences.set(source.bundleID, forKey: "lastAudioSourceBundleID")
    if preparedCalendarMeeting != nil, source.kind == .browser {
      preferences.set(source.bundleID, forKey: "googleMeetBrowserBundleID")
    }
  }

  /// Join in the selected browser, including a temporary browser fallback.
  var meetingBrowserBundleID: String? {
    guard preparedCalendarMeeting != nil else { return nil }
    return applications.first { $0.processID == sourceID && $0.kind == .browser }?.bundleID
      ?? preferredMeetingBrowserBundleID
  }

  func joinPreparedMeeting() {
    guard let meeting = preparedCalendarMeeting else { return }
    if let bundleID = meetingBrowserBundleID,
      let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    {
      NSWorkspace.shared.open(
        [meeting.url], withApplicationAt: applicationURL,
        configuration: NSWorkspace.OpenConfiguration())
    } else {
      NSWorkspace.shared.open(meeting.url)
    }
  }

  func unloadModels() {
    guard !isBusy && !isRecording else { return }
    isBusy = true
    Task {
      await transcription.unload()
      modelsReady = false
      isBusy = false
    }
  }

  private func scheduleModelUnload() {
    modelUnloadTask?.cancel()
    modelUnloadTask = nil
    guard modelsReady, !isBusy, !isRecording, modelIdleMinutes > 0 else { return }
    let delay = modelIdleMinuteDuration * modelIdleMinutes
    modelUnloadTask = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard !Task.isCancelled else { return }
      self?.unloadModels()
    }
  }

  private func loadModels() async throws {
    do {
      try await transcription.prepare { [weak self] text in await self?.setStatus(text) }
      modelsReady = true
    } catch {
      modelsReady = false
      throw error
    }
  }

  private func setStatus(_ text: String) { status = text }

  private func retain(_ meeting: Meeting, select: Bool = true) throws {
    try store.save(meeting)
    if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
      meetings[index] = meeting
    } else {
      meetings.insert(meeting, at: 0)
    }
    if select { selection = meeting.id }
  }

  func start(systemSpeakers: Int? = nil) {
    guard canStart else { return }
    stopMicrophonePreview()
    let count = systemSpeakers ?? recordingSystemSpeakers
    let options = TranscriptionOptions(
      quality: defaultQuality, expectedSystemSpeakers: count == 0 ? nil : count)
    isBusy = true
    status = "Starting audio capture…"
    Task {
      defer { isBusy = false }
      do {
        try await loadModels()
        status = "Starting audio capture…"
        var meeting = Meeting(
          title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Meeting.untitled : title)
        meeting.transcriptionOptions = options
        let directory = recordingDirectory(meeting)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try retain(meeting)
        if preferences.object(forKey: "recordingSounds") as? Bool ?? true {
          try await recordingSounds.beforeCapture()
        }
        try await capture.start(applicationID: sourceID, directory: directory)
        activeMeeting = meeting
        recordingStarted = Date()
        recordingLevels = RecordingLevels()
        isRecording = true
        recordingSystemSpeakers = 0
        preparedCalendarMeeting = nil
        status = "Recording app audio and your microphone"
      } catch {
        self.error = error.localizedDescription
        status = "Recording could not start"
      }
    }
  }

  func stop() {
    guard isRecording, let meeting = activeMeeting, !isBusy else { return }
    isRecording = false
    recordingLevels = RecordingLevels()
    isBusy = true
    status = "Finishing recording…"
    Task {
      defer {
        isBusy = false
        activeMeeting = nil
        recordingStarted = nil
      }
      do {
        var updated = meeting
        updated.duration = Date().timeIntervalSince(recordingStarted ?? meeting.date)
        try retain(updated)
        let tracks = try await capture.stop()
        playRecordingSound(.stop)
        try await process(updated, tracks: tracks)
      } catch {
        self.error = error.localizedDescription
        status = "Recording retained. Retry transcription from the library."
      }
    }
  }

  func retry(_ meeting: Meeting) {
    if meeting.isTranscribed {
      reprocess(meeting, options: meeting.transcriptionOptions ?? defaultTranscriptionOptions)
      return
    }
    guard !isBusy && !isRecording else { return }
    isBusy = true
    Task {
      defer { isBusy = false }
      do {
        let url = recordingDirectory(meeting).appendingPathComponent("tracks.json")
        let tracks = try JSONDecoder().decode(AudioTracks.self, from: Data(contentsOf: url))
        try await process(meeting, tracks: tracks)
      } catch {
        self.error = error.localizedDescription
        status = "Transcription failed. Recording retained."
      }
    }
  }

  func reprocess(_ meeting: Meeting, options: TranscriptionOptions) {
    guard !isBusy && !isRecording else { return }
    isBusy = true
    status = "Reprocessing transcript…"
    Task {
      defer { isBusy = false }
      do {
        _ = try TranscriptionService.diarizationConfig(options)
        let metadata = recordingDirectory(meeting).appendingPathComponent("tracks.json")
        let tracks = try JSONDecoder().decode(AudioTracks.self, from: Data(contentsOf: metadata))
        let result = meeting.reprocessedDraft(options: options)
        try await process(result, tracks: tracks)
      } catch {
        self.error = error.localizedDescription
        status = "Reprocessing failed. The original transcript and recordings are retained."
      }
    }
  }

  func assignPassage(_ id: UUID, to name: String?, in meeting: Meeting) {
    guard !isBusy && !isRecording,
      var current = meetings.first(where: { $0.id == meeting.id }),
      let index = current.utterances.firstIndex(where: { $0.id == id })
    else { return }
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    current.utterances[index].assignedName = trimmed?.isEmpty == false ? trimmed : nil
    do {
      try retain(current)
      try writeExport(current)
    } catch { self.error = error.localizedDescription }
  }

  private func process(_ meeting: Meeting, tracks: AudioTracks) async throws {
    var updated = meeting
    let options = meeting.transcriptionOptions ?? defaultTranscriptionOptions
    updated.transcriptionOptions = options
    try await loadModels()
    updated.utterances = try await transcription.transcribe(
      tracks, options: options, corrections: corrections
    ) {
      [weak self] text in
      await self?.setStatus(text)
    }
    updated.duration = max(updated.duration, updated.utterances.map(\.end).max() ?? 0)
    applyDefaultMicrophoneSpeaker(to: &updated)
    updated.transcribedAt = Date()
    modelsReady = true
    try retain(updated)  // Save before export, so a folder error cannot lose the transcript.
    let exported = try writeExport(updated)
    status = "Exported \(exported.lastPathComponent)"
    playRecordingSound(.finished)
    if chatGPT.automaticSummaries && !updated.utterances.isEmpty {
      startSummary(updated)
    }
  }

  private func playRecordingSound(_ cue: RecordingSounds.Cue) {
    guard preferences.object(forKey: "recordingSounds") as? Bool ?? true else { return }
    recordingSounds.play(cue)
  }

  func applyDefaultMicrophoneSpeaker(to meeting: inout Meeting) {
    let name = defaultMicrophoneSpeaker.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, meeting.speakerNames["You"] == nil,
      meeting.utterances.contains(where: { $0.speaker == "You" })
    else { return }
    meeting.speakerNames["You"] = name
  }

  func addSavedSpeaker(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !savedSpeakers.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    else { return }
    savedSpeakers.append(trimmed)
    savedSpeakers.sort { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  func addDictionaryTerm(_ term: String) {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !corrections.dictionary.contains(trimmed) else { return }
    // A new spelling of the same letters replaces the old one, e.g. Openai → OpenAI.
    let key = TranscriptCorrections.spellingKey(trimmed)
    guard !key.isEmpty else { return }
    corrections.dictionary.removeAll { TranscriptCorrections.spellingKey($0) == key }
    corrections.dictionary.append(trimmed)
    corrections.dictionary.sort { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  func addReplacement(heard: String, replacement: String) {
    let heard = heard.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !heard.isEmpty, !replacement.isEmpty, heard != replacement else { return }
    corrections.replacements.removeAll { $0.heard.caseInsensitiveCompare(heard) == .orderedSame }
    corrections.replacements.append(.init(heard: heard, replacement: replacement))
    corrections.replacements.sort {
      $0.heard.localizedStandardCompare($1.heard) == .orderedAscending
    }
  }

  func newMeeting() {
    guard !isBusy && !isRecording else { return }
    selection = nil
    title = ""
    recordingSystemSpeakers = 0
    preparedCalendarMeeting = nil
    explicitSourceBundleID = nil
    refreshSources()
  }

  /// Calendar reminders lead to the ordinary recorder, named after the event.
  func prepareRecording(for meeting: CalendarMeeting) {
    guard !isBusy && !isRecording else { return }
    newMeeting()
    title = meeting.title
    preparedCalendarMeeting = meeting
    refreshSources()
    calendarMonitor.dismiss(meeting)
  }

  func togglePlayback() {
    guard !isBusy && !isRecording, let meeting = selectedMeeting, meeting.isTranscribed else {
      return
    }
    if playback.isPlaying {
      playback.pause()
    } else {
      play(meeting, from: playback.position >= playback.duration ? 0 : playback.position)
    }
  }

  func play(_ meeting: Meeting, from time: Double, until end: Double? = nil) {
    guard !isBusy && !isRecording, selection == meeting.id else { return }
    do {
      if playback.duration == 0 {
        let url = recordingDirectory(meeting).appendingPathComponent("tracks.json")
        let tracks = try JSONDecoder().decode(AudioTracks.self, from: Data(contentsOf: url))
        try playback.load(tracks)
      }
      try playback.play(from: time, until: end)
    } catch {
      playback.stop()
      self.error = "Could not play this recording: \(error.localizedDescription)"
    }
  }

  func renameSpeaker(_ speaker: String, to name: String, in meeting: Meeting) {
    guard speaker != "Unassigned", !isBusy && !isRecording else { return }
    var updated = meetings.first(where: { $0.id == meeting.id }) ?? meeting
    updated.speakerNames[speaker] =
      name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    do {
      try retain(updated)
      try writeExport(updated)
    } catch { self.error = error.localizedDescription }
  }

  func renameMeeting(_ meeting: Meeting, to name: String) {
    // The meeting being recorded may be named mid-call; capture keeps its copy current.
    guard !isBusy, !isRecording || meeting.id == activeMeeting?.id,
      let current = meetings.first(where: { $0.id == meeting.id })
    else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != current.title else { return }
    var updated = current
    updated.title = trimmed
    do {
      try retain(updated)
      if activeMeeting?.id == updated.id { activeMeeting?.title = trimmed }
      if updated.isTranscribed { try writeExport(updated) }
    } catch { self.error = error.localizedDescription }
  }

  func generateSummary(_ meeting: Meeting) {
    guard !isBusy && !isRecording else { return }
    startSummary(meeting)
  }

  private func startSummary(_ meeting: Meeting) {
    guard summarizingMeetingID == nil, !chatGPT.busy,
      let snapshot = meetings.first(where: { $0.id == meeting.id })
    else { return }
    summarizingMeetingID = snapshot.id
    summaryError = nil
    summaryTask = Task {
      defer {
        summarizingMeetingID = nil
        summaryTask = nil
      }
      do {
        let summary = try await chatGPT.summarize(snapshot)
        try Task.checkCancellation()
        // Keep concurrent edits/export metadata and never restore a deleted meeting.
        guard var current = meetings.first(where: { $0.id == snapshot.id }) else { return }
        guard current.summaryInputDigest == snapshot.summaryInputDigest else {
          throw ChatGPTError(
            "The transcript changed while summarizing. Click Summarize to try again.")
        }
        current.summary = summary
        try retain(current, select: false)
        try writeExport(current)
      } catch is CancellationError {
      } catch {
        if !Task.isCancelled { summaryError = error.localizedDescription }
      }
    }
  }

  func export(_ meeting: Meeting) {
    guard !isBusy && !isRecording else { return }
    do {
      let current = meetings.first(where: { $0.id == meeting.id }) ?? meeting
      let url = try writeExport(current)
      status = "Markdown exported"
      if chatGPT.automaticSummaries && current.currentSummary == nil
        && !current.utterances.isEmpty
      {
        startSummary(current)
      }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch { self.error = error.localizedDescription }
  }

  func chooseExportDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Use folder"
    if panel.runModal() == .OK, let url = panel.url { exportDirectory = url }
  }

  @discardableResult
  private func writeExport(_ meeting: Meeting) throws -> URL {
    var current = meetings.first(where: { $0.id == meeting.id }) ?? meeting
    let destination = MarkdownExporter.destination(current, in: exportDirectory)
    if !(current.exportFiles ?? []).contains(destination) {
      current.exportFiles = (current.exportFiles ?? []) + [destination]
      try retain(current, select: false)
    }
    return try MarkdownExporter.write(current, to: exportDirectory)
  }

  func moveToTrash(_ meeting: Meeting) {
    guard !isBusy && !isRecording else { return }
    if summarizingMeetingID == meeting.id { summaryTask?.cancel() }
    playback.stop()
    isBusy = true
    status = "Moving meeting to Trash…"
    let current = meetings.first(where: { $0.id == meeting.id }) ?? meeting
    let remaining = meetings.filter { $0.id != meeting.id }
    let store = self.store
    let recordings = recordingsDirectory
    let exports = [
      exportDirectory,
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Minutes"),
    ]
    let shares = FileManager.default.temporaryDirectory.appendingPathComponent("MinutesShare")
    Task {
      defer { isBusy = false }
      do {
        try await Task.detached {
          try MeetingTrash.move(
            current, remaining: remaining, store: store,
            recordings: recordings, exportDirectories: exports, shareDirectory: shares)
        }.value
        meetings.removeAll { $0.id == meeting.id }
        if selection == meeting.id { selection = meetings.sorted { $0.date > $1.date }.first?.id }
        status = "Meeting moved to Trash"
      } catch { self.error = error.localizedDescription }
    }
  }

  func changeRecordingDate(_ meeting: Meeting, to date: Date) {
    guard !isBusy && !isRecording,
      var current = meetings.first(where: { $0.id == meeting.id })
    else { return }
    current.date = date
    do {
      try retain(current)
      if current.isTranscribed { try writeExport(current) }
    } catch { self.error = error.localizedDescription }
  }

  func importRecording(paired: Bool = false) {
    guard !isBusy && !isRecording else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = false
    panel.title = paired ? "Choose System Audio" : "Import Recording"
    panel.message = paired ? "Choose the system recording containing the other speakers." : ""
    panel.prompt = paired ? "Next" : "Import"
    guard panel.runModal() == .OK, let remote = panel.url else { return }
    var microphone: URL?
    if paired {
      panel.title = "Choose Microphone Audio"
      panel.message =
        "Choose your microphone recording. Both files must start at the same point in the meeting. Set your name in Settings → Speakers to label your microphone speech."
      panel.prompt = "Import Both"
      guard panel.runModal() == .OK, let url = panel.url else { return }
      microphone = url
    }
    isBusy = true
    status = "Importing audio…"
    Task {
      defer { isBusy = false }
      do {
        var meeting = Meeting(title: remote.deletingPathExtension().lastPathComponent)
        meeting.date = await RecordingImport.recordingDate(remote) ?? meeting.date
        meeting.transcriptionOptions = defaultTranscriptionOptions
        let imported = try RecordingImport.retain(
          remote: remote, microphone: microphone, in: recordingDirectory(meeting))
        meeting.duration = imported.duration
        try retain(meeting)
        try await process(meeting, tracks: imported.tracks)
      } catch {
        self.error = error.localizedDescription
        status = "Import failed. Any copied audio is retained."
      }
    }
  }

  private func recordingDirectory(_ meeting: Meeting) -> URL {
    recordingsDirectory.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
  }
}
