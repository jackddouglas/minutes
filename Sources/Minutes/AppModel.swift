import AVFoundation
import AppKit
import MinutesCore
import Observation
import UniformTypeIdentifiers

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
  var calendarPrompt: CalendarMeeting?
  var applications: [BrowserSource] = []
  var sourceID: Int32 = 0
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
  var savedSpeakers: [String] {
    didSet { preferences.set(savedSpeakers, forKey: "savedSpeakers") }
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
  var recordingStarted: Date?
  var exportDirectory: URL {
    didSet { preferences.set(exportDirectory.path, forKey: "exportDirectory") }
  }

  private let modelIdleMinuteDuration: Duration
  private let preferences: UserDefaults
  private let capture = AudioCapture()
  private let transcription = TranscriptionService()
  private let store: MeetingStore
  private let recordingsDirectory: URL
  private var activeMeeting: Meeting?

  var selectedMeeting: Meeting? { meetings.first { $0.id == selection } }
  var canStart: Bool { !isBusy && !isRecording && sourceID != 0 }

  init(
    supportDirectory: URL? = nil, preferences: UserDefaults = .standard,
    modelIdleMinuteDuration: Duration = .seconds(60)
  ) {
    self.modelIdleMinuteDuration = modelIdleMinuteDuration
    self.preferences = preferences
    modelIdleMinutes = max(0, preferences.object(forKey: "modelIdleMinutes") as? Int ?? 10)
    calendarMonitor = CalendarMonitor(preferences: preferences)
    defaultQuality =
      TranscriptionOptions.Quality(
        rawValue: preferences.string(forKey: "transcriptionQuality") ?? "") ?? .thorough
    savedSpeakers = preferences.stringArray(forKey: "savedSpeakers") ?? []
    let support =
      supportDirectory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ]
      .appendingPathComponent("Scribe", isDirectory: true)
    store = MeetingStore(directory: support.appendingPathComponent("Meetings"))
    recordingsDirectory = support.appendingPathComponent("Recordings")
    let saved = preferences.string(forKey: "exportDirectory")
    exportDirectory =
      saved.map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Scribe")
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

  func refreshSources() {
    guard !isBusy && !isRecording else { return }
    applications = BrowserSource.running()
    if !applications.contains(where: { $0.processID == sourceID }) {
      sourceID = applications.first?.processID ?? 0
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

  private func retain(_ meeting: Meeting) throws {
    try store.save(meeting)
    if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
      meetings[index] = meeting
    } else {
      meetings.insert(meeting, at: 0)
    }
    selection = meeting.id
  }

  func start(systemSpeakers: Int? = nil) {
    guard canStart else { return }
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
            ? "Untitled meeting" : title)
        meeting.transcriptionOptions = options
        let directory = recordingDirectory(meeting)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try retain(meeting)
        try await capture.start(applicationID: sourceID, directory: directory)
        activeMeeting = meeting
        recordingStarted = Date()
        isRecording = true
        recordingSystemSpeakers = 0
        status = "Recording browser audio and your microphone"
      } catch {
        self.error = error.localizedDescription
        status = "Recording could not start"
      }
    }
  }

  func stop() {
    guard isRecording, let meeting = activeMeeting, !isBusy else { return }
    isRecording = false
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
    updated.utterances = try await transcription.transcribe(tracks, options: options) {
      [weak self] text in
      await self?.setStatus(text)
    }
    updated.duration = max(updated.duration, updated.utterances.map(\.end).max() ?? 0)
    updated.transcribedAt = Date()
    modelsReady = true
    try retain(updated)  // Save before export, so a folder error cannot lose the transcript.
    let exported = try writeExport(updated)
    status = "Exported \(exported.lastPathComponent)"
  }

  func addSavedSpeaker(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !savedSpeakers.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    else { return }
    savedSpeakers.append(trimmed)
    savedSpeakers.sort { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  func newMeeting() {
    guard !isBusy && !isRecording else { return }
    selection = nil
    title = ""
    recordingSystemSpeakers = 0
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
    guard !isBusy && !isRecording,
      let current = meetings.first(where: { $0.id == meeting.id })
    else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != current.title else { return }
    var updated = current
    updated.title = trimmed
    do {
      try retain(updated)
      if updated.isTranscribed { try writeExport(updated) }
    } catch { self.error = error.localizedDescription }
  }

  func export(_ meeting: Meeting) {
    do {
      let url = try writeExport(meeting)
      status = "Markdown exported"
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
      try retain(current)
    }
    return try MarkdownExporter.write(current, to: exportDirectory)
  }

  func moveToTrash(_ meeting: Meeting) {
    guard !isBusy && !isRecording else { return }
    playback.stop()
    isBusy = true
    status = "Moving meeting to Trash…"
    let current = meetings.first(where: { $0.id == meeting.id }) ?? meeting
    let remaining = meetings.filter { $0.id != meeting.id }
    let store = self.store
    let recordings = recordingsDirectory
    let exports = [
      exportDirectory,
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Scribe"),
    ]
    let shares = FileManager.default.temporaryDirectory.appendingPathComponent("ScribeShare")
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
        "Choose your microphone recording. Both files must start at the same point in the meeting. Microphone speech will be labelled You."
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
