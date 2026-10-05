import CoreTransferable
import MinutesCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Bindable var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @ViewState private var showSpeakers = false
  @ViewState private var search = ""
  @ViewState private var renamingMeeting: Meeting?
  @ViewState private var meetingName = ""
  @ViewState private var reprocessingMeeting: Meeting?
  @ViewState private var reviewingMeeting: Meeting?
  @ViewState private var datingMeeting: Meeting?
  @ViewState private var recordingDate = Date()
  @ViewState private var sidebarNow = Date()

  private var filteredMeetings: [Meeting] {
    model.meetings.filter {
      search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        || $0.utterances.contains { $0.text.localizedCaseInsensitiveContains(search) }
    }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selection) {
        ForEach(MeetingDay.group(filteredMeetings)) { day in
          Section(dayTitle(day.date)) {
            ForEach(day.meetings) { meeting in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: meeting.isTranscribed ? "text.bubble" : "waveform")
                  .foregroundStyle(.secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                  Text(meeting.title).fontWeight(.medium).lineLimit(2).help(meeting.title)
                  HStack {
                    Text(meeting.date, format: .dateTime.hour().minute())
                    Text("·")
                    Text(MarkdownExporter.timestamp(meeting.duration))
                  }.font(.caption).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 5).tag(meeting.id)
                .contextMenu {
                  Button("Rename…") { beginRename(meeting) }
                  Button("Change Recording Date…") { beginDate(meeting) }
                  Button("Export Markdown…") { model.export(meeting) }
                  Divider()
                  Button("Move to Trash…", role: .destructive) { model.meetingToDelete = meeting }
                }
                .disabled(model.isBusy || model.isRecording)
            }
          }
        }
      }.listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 380)
        .safeAreaInset(edge: .bottom) {
          HStack {
            Text("\(model.meetings.count) meetings").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Settings", systemImage: "gearshape") { openSettings() }
              .labelStyle(.iconOnly).buttonStyle(.borderless).help("Settings")
          }.padding(14)
        }
        .overlay {
          if filteredMeetings.isEmpty && !search.isEmpty {
            ContentUnavailableView.search(text: search)
          }
        }
    } detail: {
      meetingDetail
    }
    .toolbarBackgroundVisibility(Visibility.hidden, for: ToolbarPlacement.windowToolbar)
    .navigationTitle(model.selectedMeeting?.title ?? "New Meeting")
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button("New Meeting", systemImage: "square.and.pencil") { model.newMeeting() }
          .help("New meeting").disabled(model.isBusy || model.isRecording)
      }
      ToolbarItemGroup(placement: .primaryAction) {
        if let meeting = model.selectedMeeting {
          if meeting.isTranscribed {
            Button("Review Speakers", systemImage: "person.crop.circle.badge.questionmark") {
              reviewingMeeting = meeting
            }.help("Review unresolved speakers").disabled(model.isBusy || model.isRecording)
            ShareLink(item: TranscriptShare(meeting: meeting), preview: SharePreview(meeting.title))
              .help("Share transcript").disabled(model.isBusy || model.isRecording)
          }
          Menu {
            Button("Rename…") { beginRename(meeting) }
            Button("Change Recording Date…") { beginDate(meeting) }
            if meeting.isTranscribed {
              Button("Reprocess Transcript…") { reprocessingMeeting = meeting }
              Button("Export Markdown…") { model.export(meeting) }
            }
            Divider()
            Button("Move to Trash…", role: .destructive) { model.meetingToDelete = meeting }
          } label: {
            Label("Meeting Actions", systemImage: "ellipsis.circle")
          }.help("Meeting actions").disabled(model.isBusy || model.isRecording)
          if meeting.isTranscribed {
            Button("Speakers", systemImage: "sidebar.right") { showSpeakers.toggle() }
              .help(showSpeakers ? "Hide speakers" : "Show speakers")
          }
        }
      }
    }
    .frame(minWidth: 840, minHeight: 620)
    .searchable(text: $search, placement: .sidebar, prompt: "Search meetings")
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      sidebarNow = Date()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      sidebarNow = Date()
    }
    .sheet(item: $reprocessingMeeting) { meeting in
      ReprocessTranscriptView(model: model, meeting: meeting)
    }
    .sheet(item: $reviewingMeeting) { meeting in
      SpeakerReviewView(model: model, meetingID: meeting.id)
    }
    .sheet(item: $datingMeeting) { meeting in
      VStack(alignment: .leading, spacing: 20) {
        Text("Recording Date").font(.title2.bold())
        Text("Used to organize this meeting in your library.").foregroundStyle(.secondary)
        DatePicker("Recorded", selection: $recordingDate)
        HStack {
          Button("Cancel", role: .cancel) { datingMeeting = nil }.keyboardShortcut(.cancelAction)
          Spacer()
          Button("Save") {
            model.changeRecordingDate(meeting, to: recordingDate)
            datingMeeting = nil
          }.keyboardShortcut(.defaultAction)
        }
      }.padding(24).frame(width: 420)
    }
    .sheet(item: $model.calendarPrompt) { meeting in
      CalendarRecordingPrompt(model: model, meeting: meeting)
    }
    .alert(
      "Move Meeting to Trash?",
      isPresented: Binding(
        get: { model.meetingToDelete != nil }, set: { if !$0 { model.meetingToDelete = nil } }
      ), presenting: model.meetingToDelete
    ) { meeting in
      Button("Cancel", role: .cancel) { model.meetingToDelete = nil }
      Button("Move to Trash", role: .destructive) {
        model.moveToTrash(meeting)
        model.meetingToDelete = nil
      }
    } message: { meeting in
      Text(
        "“\(meeting.title)” and its recordings, transcript, and Minutes exports will be moved to Finder’s Trash. Audio needed by other meetings is preserved. You can recover the files from Trash until you empty it."
      )
    }
    .alert(
      "Rename Meeting",
      isPresented: Binding(
        get: { renamingMeeting != nil }, set: { if !$0 { renamingMeeting = nil } })
    ) {
      TextField("Meeting name", text: $meetingName)
      Button("Cancel", role: .cancel) { renamingMeeting = nil }
      Button("Rename") {
        if let meeting = renamingMeeting { model.renameMeeting(meeting, to: meetingName) }
        renamingMeeting = nil
      }.disabled(meetingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .alert(
      "Minutes",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }

  private var meetingDetail: some View {
    VStack(spacing: 0) {
      if let invitation = model.calendarMonitor.invitations.first {
        calendarBanner(invitation)
      }
      if let meeting = model.selectedMeeting, meeting.isTranscribed {
        TranscriptView(model: model, meeting: meeting, showSpeakers: $showSpeakers)
          .id(meeting.id)
      } else if let meeting = model.selectedMeeting, !model.isRecording && !model.isBusy {
        ContentUnavailableView {
          Label(meeting.title, systemImage: "waveform")
        } description: {
          Text("This session has not been transcribed.")
        } actions: {
          Button("Transcribe") { model.retry(meeting) }
        }
      } else {
        recorder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top)
    }
    .overlay(alignment: .bottom) {
      if model.isRecording {
        recordingControls
      } else if model.isBusy {
        activityBar
      }
    }
  }

  private func beginRename(_ meeting: Meeting) {
    renamingMeeting = meeting
    meetingName = meeting.title
  }

  private var activityBar: some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text(model.status).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20).padding(.vertical, 14)
    .frame(maxWidth: 520)
    .controlSurface(cornerRadius: 32, clearGlass: true)
    .padding(.horizontal, 24).padding(.bottom, 16)
  }

  private var recordingControls: some View {
    HStack(spacing: 12) {
      Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true)
      Text("Recording").fontWeight(.medium)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(
          MarkdownExporter.timestamp(
            context.date.timeIntervalSince(model.recordingStarted ?? context.date))
        )
        .monospacedDigit().foregroundStyle(.secondary)
        .accessibilityLabel("Recording duration")
      }
      Spacer(minLength: 20)
      Button("Stop & Transcribe", systemImage: "stop.fill") { model.stop() }
        .buttonStyle(.bordered)
    }
    .padding(.horizontal, 20).padding(.vertical, 14)
    .frame(maxWidth: 520)
    .controlSurface(cornerRadius: 32, clearGlass: true)
    .padding(.horizontal, 24).padding(.bottom, 16)
  }

  private var recorder: some View {
    VStack(alignment: .leading, spacing: 8) {
      Form {
        if !model.calendarMonitor.upcoming.isEmpty {
          Section("Upcoming Meetings") {
            ForEach(model.calendarMonitor.upcoming.prefix(3)) { meeting in
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(meeting.title).font(.headline)
                  Text(meeting.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Record…") { model.calendarPrompt = meeting }
              }
            }
          }
        }
        Section("New Recording") {
          TextField("Meeting name", text: $model.title, prompt: Text("Untitled meeting"))
          BrowserPicker(model: model)
          LabeledContent("Microphone", value: "System default")
          ParticipantCountPicker(count: $model.recordingSystemSpeakers)
          HStack {
            Spacer()
            Button("Start Recording", systemImage: "record.circle") { model.start() }
              .buttonStyle(.bordered).controlSize(.large)
              .keyboardShortcut(.defaultAction).disabled(!model.canStart)
          }
        }
        Section("Import Audio") {
          HStack {
            Button("Single Recording…", systemImage: "waveform") { model.importRecording() }
            Button("System & Microphone…", systemImage: "waveform.badge.mic") {
              model.importRecording(paired: true)
            }
          }
        }
      }.formStyle(.grouped).scrollContentBackground(.hidden)
        .contentMargins(.bottom, (model.isRecording || model.isBusy) ? 88 : 0, for: .scrollContent)
    }.frame(maxWidth: 760).frame(maxWidth: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
      .disabled(model.isBusy || model.isRecording)
  }

  private func dayTitle(_ date: Date) -> String {
    if Calendar.current.isDate(date, inSameDayAs: sidebarNow) { return "Today" }
    if Calendar.current.isDate(
      date,
      inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: sidebarNow) ?? sidebarNow)
    {
      return "Yesterday"
    }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
  }

  private func beginDate(_ meeting: Meeting) {
    recordingDate = meeting.date
    datingMeeting = meeting
  }

  private func calendarBanner(_ meeting: CalendarMeeting) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 3) {
        Text("Your meeting is starting").font(.headline)
        Text(meeting.title).lineLimit(1).help(meeting.title)
      }
      Spacer()
      Button("Not Now") { model.calendarMonitor.dismiss(meeting) }
      Button("Record…") { model.calendarPrompt = meeting }
        .buttonStyle(.bordered).disabled(model.isBusy || model.isRecording)
    }.padding(16).controlSurface().padding(12)
  }

}

private struct TranscriptView: View {
  @Bindable var model: AppModel
  let meeting: Meeting
  @Binding var showSpeakers: Bool
  @ViewState private var speakerToRename: String?
  @ViewState private var passageToRename: UUID?
  @ViewState private var speakerName = ""

  private func speakerSidebar(scroll: ScrollViewProxy) -> some View {
    VStack(spacing: 0) {
      Text("Speakers").font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading).padding()
      Divider()
      if meeting.firstSpeakerUtterances.isEmpty {
        ContentUnavailableView(
          "No speakers", systemImage: "person.2", description: Text("No speech was detected."))
      } else {
        List(meeting.firstSpeakerUtterances) { first in
          VStack(alignment: .leading, spacing: 8) {
            Button {
              scroll.scrollTo(first.id, anchor: .top)
              model.play(meeting, from: first.start)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(meeting.name(for: first.speaker)).font(.headline)
                Text("\(first.speaker) · \(MarkdownExporter.timestamp(first.start))")
                  .font(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
              .help("Go to and play the first appearance of \(meeting.name(for: first.speaker))")
            if first.speaker == "Unassigned" {
              Text(
                "These passages may contain different people. Assign each passage in the transcript."
              )
              .font(.caption).foregroundStyle(.secondary)
              if let legacyName = meeting.speakerNames["Unassigned"] {
                Text("Previous bulk label: \(legacyName). Review passages individually.")
                  .font(.caption).foregroundStyle(.secondary)
              }
            } else {
              Menu("Assign Person") {
                bulkNameActions(first.speaker)
              }.menuStyle(.borderlessButton).fixedSize()
            }
          }.padding(.vertical, 6)
            .disabled(model.isBusy || model.isRecording)
        }.listStyle(.plain).scrollContentBackground(.hidden)
      }
      Divider()
      Text(
        "Click a speaker to jump to their first appearance and listen. Assign a saved person or enter a name."
      )
      .font(.caption).foregroundStyle(.secondary).padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder
  private func bulkNameActions(_ speaker: String) -> some View {
    ForEach(model.savedSpeakers, id: \.self) { name in
      Button(name) { model.renameSpeaker(speaker, to: name, in: meeting) }
    }
    if !model.savedSpeakers.isEmpty { Divider() }
    Button("Enter Name…") {
      passageToRename = nil
      speakerToRename = speaker
      speakerName = meeting.name(for: speaker)
    }
  }

  @ViewBuilder
  private func passageNameActions(_ utterance: Utterance) -> some View {
    ForEach(model.savedSpeakers, id: \.self) { name in
      Button(name) { model.assignPassage(utterance.id, to: name, in: meeting) }
    }
    if !model.savedSpeakers.isEmpty { Divider() }
    Button("Enter Name…") {
      speakerToRename = nil
      passageToRename = utterance.id
      speakerName = utterance.assignedName ?? ""
    }
    if utterance.assignedName != nil {
      Button("Use Detected Speaker") { model.assignPassage(utterance.id, to: nil, in: meeting) }
    }
  }

  var body: some View {
    ScrollViewReader { scroll in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          Text(meeting.title).font(.largeTitle.bold()).textSelection(.enabled)
          HStack {
            Text(
              meeting.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
            Spacer()
            Text(
              "\(MarkdownExporter.timestamp(meeting.duration)) · \(Set(meeting.utterances.map(\.speaker).filter { $0 != "Unassigned" }).count) speakers"
            )
            .monospacedDigit()
          }.font(.subheadline).foregroundStyle(.secondary)
          Divider()
          if meeting.utterances.isEmpty {
            Text("No speech was detected in this recording.").foregroundStyle(.secondary)
          }
          ForEach(meeting.utterances) { utterance in
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline) {
                Menu {
                  Menu("Assign This Passage") { passageNameActions(utterance) }
                  if utterance.speaker != "Unassigned" {
                    Menu("Assign All \(utterance.speaker) Passages") {
                      bulkNameActions(utterance.speaker)
                    }
                  }
                } label: {
                  Text(meeting.name(for: utterance)).font(.headline)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Assign or rename speaker").disabled(model.isBusy || model.isRecording)
                Spacer()
                Button(MarkdownExporter.timestamp(utterance.start)) {
                  model.play(meeting, from: utterance.start)
                }.buttonStyle(.plain).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                  .help("Play from this timestamp").disabled(model.isBusy || model.isRecording)
              }
              Button {
                model.play(meeting, from: utterance.start)
              } label: {
                Text(utterance.text)
                  .font(.system(size: 16)).lineSpacing(6)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .help("Play from the start of this passage")
              .accessibilityHint("Play from the start of this passage")
              .disabled(model.isBusy || model.isRecording)
              .contextMenu {
                Button("Copy Passage") {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(utterance.text, forType: .string)
                }
              }
            }.id(utterance.id)
          }
        }.padding(28).padding(.bottom, 100).frame(maxWidth: 860).frame(maxWidth: .infinity)
      }.background(Color(nsColor: .windowBackgroundColor))
        .clipped()
        .overlay(alignment: .bottom) {
          if !model.isRecording && !model.isBusy {
            TranscriptPlaybackControls(model: model, meeting: meeting)
              .padding(.horizontal, 20).padding(.vertical, 12)
              .frame(maxWidth: 680).controlSurface(cornerRadius: 32, clearGlass: true)
              .padding(.horizontal, 24).padding(.bottom, 16)
          }
        }
        .inspector(isPresented: $showSpeakers) {
          speakerSidebar(scroll: scroll)
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }
    .alert(
      passageToRename == nil ? "Rename Speaker" : "Assign This Passage",
      isPresented: Binding(
        get: { speakerToRename != nil || passageToRename != nil },
        set: {
          if !$0 {
            speakerToRename = nil
            passageToRename = nil
          }
        })
    ) {
      TextField("Name", text: $speakerName)
      Button("Cancel", role: .cancel) {
        speakerToRename = nil
        passageToRename = nil
      }
      Button("Save") {
        if let id = passageToRename {
          model.assignPassage(id, to: speakerName, in: meeting)
        } else if let speaker = speakerToRename {
          model.renameSpeaker(speaker, to: speakerName, in: meeting)
        }
        speakerToRename = nil
        passageToRename = nil
      }
    }
  }
}

struct ParticipantCountPicker: View {
  @Binding var count: Int

  var body: some View {
    Picker("Participants (excluding you)", selection: $count) {
      Text("Automatic").tag(0)
      ForEach(1...20, id: \.self) { value in
        Text("\(value)").tag(value)
      }
    }
  }
}

struct SpeakerAnalysisPicker: View {
  @Binding var quality: TranscriptionOptions.Quality

  var body: some View {
    Picker("Speaker analysis", selection: $quality) {
      Text("Standard").tag(TranscriptionOptions.Quality.standard)
      Text("Thorough (slower)").tag(TranscriptionOptions.Quality.thorough)
    }
  }
}

struct DiarizationOptionsView: View {
  @Binding var quality: TranscriptionOptions.Quality
  @Binding var speakerCount: Int

  var body: some View {
    SpeakerAnalysisPicker(quality: $quality)
    Picker("Number of speakers", selection: $speakerCount) {
      Text("Automatic").tag(0)
      ForEach(1...20, id: \.self) { count in
        Text("\(count)").tag(count)
      }
    }
    Text("For this meeting only. Exclude yourself if your microphone was recorded separately.")
      .font(.caption).foregroundStyle(.secondary)
  }
}

private struct ReprocessTranscriptView: View {
  let model: AppModel
  let meeting: Meeting
  @Environment(\.dismiss) private var dismiss
  @ViewState private var quality = TranscriptionOptions.Quality.thorough
  @ViewState private var speakerCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Reprocess Transcript").font(.title2)
      Form {
        DiarizationOptionsView(quality: $quality, speakerCount: $speakerCount)
      }.formStyle(.grouped).scrollContentBackground(.hidden)
      HStack {
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Replace Transcript") {
          model.reprocess(
            meeting,
            options: .init(
              quality: quality, expectedSystemSpeakers: speakerCount == 0 ? nil : speakerCount))
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(model.isBusy || model.isRecording)
      }
    }.padding(24).frame(width: 500, height: 390)
      .background(Color(nsColor: .windowBackgroundColor))
      .onAppear {
        quality = meeting.transcriptionOptions?.quality ?? model.defaultQuality
        speakerCount = meeting.transcriptionOptions?.expectedSystemSpeakers ?? 0
      }
  }
}

// Keep playback observation out of TranscriptView: clock ticks must not rebuild
// passage views or relayout the scrolling transcript.
private struct TranscriptPlaybackControls: View {
  let model: AppModel
  let meeting: Meeting
  var body: some View {
    HStack(spacing: 20) {
      HStack(spacing: 16) {
        Button("Back 15 seconds", systemImage: "gobackward.15") {
          model.play(meeting, from: max(0, model.playback.position - 15))
        }
        Button(
          model.playback.isPlaying ? "Pause" : "Play",
          systemImage: model.playback.isPlaying ? "pause.fill" : "play.fill"
        ) {
          model.togglePlayback()
        }.font(.title2).frame(width: 28)
        Button("Forward 15 seconds", systemImage: "goforward.15") {
          model.play(meeting, from: min(meeting.duration, model.playback.position + 15))
        }
      }
      .labelStyle(.iconOnly).buttonStyle(.plain).font(.title3)
      .disabled(model.isBusy || model.isRecording)

      VStack(alignment: .leading, spacing: 6) {
        let speakers = meeting.speakers(at: model.playback.position)
        HStack(alignment: .firstTextBaseline) {
          Text(meeting.title).font(.headline).lineLimit(1)
          Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
          Text(speakers.isEmpty ? "No speech" : speakers.joined(separator: ", "))
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            .help(speakers.joined(separator: ", "))
            .accessibilityLabel("Current speaker")
            .accessibilityValue(speakers.isEmpty ? "No speech" : speakers.joined(separator: ", "))
          Spacer(minLength: 8)
          Text(
            "\(MarkdownExporter.timestamp(model.playback.position)) / \(MarkdownExporter.timestamp(meeting.duration))"
          )
          .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
        }
        ProgressView(
          value: min(model.playback.position, meeting.duration), total: max(1, meeting.duration)
        )
        .tint(.secondary)
        .accessibilityLabel("Playback progress")
        .accessibilityValue(MarkdownExporter.timestamp(model.playback.position))
      }
    }
  }
}

private struct TranscriptShare: Transferable {
  let meeting: Meeting
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .plainText) { item in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MinutesShare/\(UUID().uuidString)", isDirectory: true)
      let url = try MarkdownExporter.write(item.meeting, to: directory)
      return SentTransferredFile(url)
    }
  }
}
