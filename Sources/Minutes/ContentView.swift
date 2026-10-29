import CoreTransferable
import MinutesCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @Bindable var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @ViewState private var showSpeakers = false
  @ViewState private var sidebarVisibility: NavigationSplitViewVisibility = .all
  @ViewState private var isNarrowWindow = false
  @ViewState private var search = ""
  @ViewState private var searchScope = MeetingSearchScope.fullTranscript
  @ViewState private var renamingMeeting: Meeting?
  @ViewState private var meetingName = ""
  @ViewState private var reprocessingMeeting: Meeting?
  @ViewState private var reviewingMeeting: Meeting?
  @ViewState private var datingMeeting: Meeting?
  @ViewState private var recordingDate = Date()
  @ViewState private var sidebarNow = Date()

  private var filteredMeetings: [Meeting] {
    model.meetings.filter {
      searchScope.matches($0, query: search)
    }
  }

  var body: some View {
    NavigationSplitView(
      columnVisibility: Binding(
        get: { sidebarVisibility },
        set: { visibility in
          if visibility == .all && isNarrowWindow { showSpeakers = false }
          sidebarVisibility = visibility
        }
      )
    ) {
      meetingSidebar
    } detail: {
      meetingDetail
        // Keep inspector presentation from renegotiating the sidebar's width.
        .navigationSplitViewColumnWidth(min: 320, ideal: 550)
    }
    .toolbarBackgroundVisibility(Visibility.hidden, for: ToolbarPlacement.windowToolbar)
    // Before and during capture an editable name field stands in for the title. The
    // title stays, empty, because removing it also drops the trailing toolbar layout.
    .navigationTitle(showsNameField ? "" : model.selectedMeeting?.title ?? "")
    .toolbar { meetingToolbar }
    .frame(minWidth: 840, minHeight: 620)
    // At compact widths, keep only one sidebar open so native split-view
    // constraints cannot oscillate while presenting the inspector or overflow.
    .onGeometryChange(for: Bool.self) { geometry in
      geometry.size.width < 1080
    } action: { narrow in
      isNarrowWindow = narrow
      if narrow && showSpeakers { sidebarVisibility = .detailOnly }
    }
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
    .alert(
      "Move meeting to Trash?",
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
        "“\(meeting.title)” and its recordings, transcript, and Minutes exports will be moved to Finder’s Trash."
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
      model.summaryError == nil ? "Minutes" : "Summary failed",
      isPresented: Binding(
        get: { model.error != nil || model.summaryError != nil },
        set: {
          if !$0 {
            model.error = nil
            model.summaryError = nil
          }
        })
    ) {
      Button("OK") {
        model.error = nil
        model.summaryError = nil
      }
    } message: {
      Text(model.summaryError ?? model.error ?? "")
    }
  }

  private var meetingSidebar: some View {
      List(selection: $model.selection) {
        ForEach(MeetingDay.group(filteredMeetings)) { day in
          Section(dayTitle(day.date)) {
            ForEach(day.meetings) { meeting in
              let live = meeting.id == model.recordingMeetingID
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: meeting.isTranscribed ? "text.bubble" : "waveform")
                  .foregroundStyle(
                    live ? AnyShapeStyle(RecorderFinish.orange) : AnyShapeStyle(.secondary)
                  )
                  .padding(.top, 2)
                  .accessibilityLabel(live ? "Recording" : "")
                VStack(alignment: .leading, spacing: 5) {
                  Text(meeting.title).fontWeight(.medium).lineLimit(2).help(meeting.title)
                  HStack {
                    Text(meeting.date, format: .dateTime.hour().minute())
                    Text("·")
                    if live {
                      TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(
                          MarkdownExporter.timestamp(
                            context.date.timeIntervalSince(model.recordingStarted ?? context.date)))
                      }
                    } else {
                      Text(MarkdownExporter.timestamp(meeting.duration))
                    }
                  }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
              }.padding(.vertical, 5).tag(meeting.id)
                .contextMenu {
                  Group {
                    Button("Rename…") { beginRename(meeting) }
                    Button("Change Recording Date…") { beginDate(meeting) }
                    Button("Export Markdown…") { model.export(meeting) }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { model.meetingToDelete = meeting }
                  }.disabled(model.isBusy || model.isRecording)
                }
                .disabled(model.isBusy)
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
            .background(.regularMaterial)
        }
        .overlay {
          if filteredMeetings.isEmpty && !search.isEmpty {
            ContentUnavailableView.search(text: search)
          }
        }
  }

  @ToolbarContentBuilder private var meetingToolbar: some ToolbarContent {
      ToolbarItem(placement: .navigation) {
        Button("New Meeting", systemImage: "square.and.pencil") { model.newMeeting() }
          .help("New meeting").disabled(model.isBusy || model.isRecording)
      }
      if showsNameField {
        if #available(macOS 26.0, *) {
          ToolbarItem(placement: .navigation) { MeetingNameField(model: model) }
            .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .navigation) { MeetingNameField(model: model) }
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        if model.selectedMeeting == nil {
          Menu {
            Button("Single Recording…", systemImage: "waveform") { model.importRecording() }
            Button("System & Microphone…", systemImage: "waveform.badge.mic") {
              model.importRecording(paired: true)
            }
          } label: {
            Label("Import Audio", systemImage: "waveform.badge.plus")
          }
          .menuIndicator(.hidden)
          .help("Import audio").disabled(model.isBusy || model.isRecording)
        }
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
        }
      }
      if #available(macOS 26.0, *) {
        ToolbarItem(placement: .primaryAction) {
          MeetingSearchField(text: $search, scope: $searchScope)
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
            .glassEffect(.regular, in: .capsule)
        }.sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
      } else {
        ToolbarItem(placement: .primaryAction) {
          MeetingSearchField(text: $search, scope: $searchScope)
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        if model.selectedMeeting?.isTranscribed == true {
          Button("Speakers", systemImage: "sidebar.right") {
            if !showSpeakers && isNarrowWindow { sidebarVisibility = .detailOnly }
            showSpeakers.toggle()
          }
          .help(showSpeakers ? "Hide speakers" : "Show speakers")
        }
      }
  }

  private var meetingDetail: some View {
    VStack(spacing: 0) {
      if let invitation = model.calendarMonitor.invitations.first {
        calendarBanner(invitation)
      }
      if let recordingID = model.recordingMeetingID, model.selection == recordingID {
        LiveRecordingView(model: model)
      } else if let meeting = model.selectedMeeting, meeting.isTranscribed {
        TranscriptView(model: model, meeting: meeting, showSpeakers: $showSpeakers)
          .id(meeting.id)
      } else if let meeting = model.selectedMeeting, !model.isBusy {
        ContentUnavailableView {
          Label(meeting.title, systemImage: "waveform")
        } description: {
          Text("This session has not been transcribed.")
        } actions: {
          Button("Transcribe") { model.retry(meeting) }.disabled(model.isRecording)
        }
      } else {
        recorder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Color(nsColor: .windowBackgroundColor).ignoresSafeArea(.container, edges: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let recordingID = model.recordingMeetingID, model.selection != recordingID {
        RecordingIndicator(startedAt: model.recordingStarted) {
          model.selection = recordingID
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
      }
    }
    .overlay(alignment: .bottom) {
      if model.isBusy && !model.isRecording {
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

  private var showsNameField: Bool {
    model.selectedMeeting == nil || model.selection == model.recordingMeetingID
  }

  /// The new-meeting surface is the recorder itself: the meters carry their
  /// sources and the transport key starts capture.
  private var recorder: some View {
    ReadyRecorderView(model: model) {
      AudioSourceMenu(model: model).disabled(model.isBusy || model.isRecording)
    } accessory: {
      VStack(spacing: 24) {
        HStack(spacing: 8) {
          Menu {
            ParticipantCountPicker(count: $model.recordingSystemSpeakers).pickerStyle(.inline)
          } label: {
            Label(
              model.recordingSystemSpeakers == 0 ? "Automatic" : "\(model.recordingSystemSpeakers)",
              systemImage: "person.2")
          }
          .menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).fixedSize()
          .help("Other participants, excluding you")
          .accessibilityLabel("Other participants")
          .accessibilityValue(
            model.recordingSystemSpeakers == 0 ? "Automatic" : "\(model.recordingSystemSpeakers)")
          if let meeting = model.preparedCalendarMeeting {
            Button("Google Meet", systemImage: "video") { NSWorkspace.shared.open(meeting.url) }
              .buttonStyle(.bordered).buttonBorderShape(.capsule)
              .help("Join \(meeting.title)")
          }
        }
        if !model.calendarMonitor.upcoming.isEmpty {
          GroupBox("Upcoming Meetings") {
            VStack(spacing: 0) {
              ForEach(
                Array(model.calendarMonitor.upcoming.prefix(3).enumerated()), id: \.element.id
              ) {
                index, meeting in
                if index > 0 { Divider() }
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.headline)
                    Text(meeting.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button("Record…") { model.prepareRecording(for: meeting) }
                }.padding(8)
              }
            }
          }.frame(maxWidth: 500)
        }
      }
      .disabled(model.isBusy || model.isRecording)
    }
    .background(Color(nsColor: .windowBackgroundColor))
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
      Button("Record…") { model.prepareRecording(for: meeting) }
        .buttonStyle(.bordered).disabled(model.isBusy || model.isRecording)
    }.padding(16).controlSurface().padding(12)
  }

}

/// Names a new meeting before capture, or the meeting being recorded during it.
private struct MeetingNameField: View {
  @Bindable var model: AppModel
  @ViewState private var draft = ""
  @FocusState private var focused: Bool

  private var recording: Meeting? {
    model.recordingMeetingID.flatMap { id in model.meetings.first { $0.id == id } }
  }

  var body: some View {
    TextField("Meeting name", text: $draft, prompt: Text(Meeting.untitled))
      .textFieldStyle(.plain)
      .font(.title3.weight(.semibold))
      .frame(minWidth: 160, idealWidth: 320, maxWidth: 420)
      .focused($focused)
      .help("Meeting name")
      .disabled(model.isBusy)
      .onAppear(perform: load)
      .onChange(of: model.recordingMeetingID) { load() }
      .onChange(of: model.title) { if recording == nil, draft != model.title { load() } }
      // A new meeting takes the name as typed; a recording is renamed once editing ends.
      .onChange(of: draft) { if recording == nil { model.title = draft } }
      .onSubmit(commit)
      .onChange(of: focused) { if !focused { commit() } }
  }

  private func load() { draft = recording?.title ?? model.title }

  private func commit() {
    guard let meeting = recording else { return }
    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      draft = meeting.title
    } else {
      model.renameMeeting(meeting, to: draft)
    }
  }
}

private struct TranscriptView: View {
  @Bindable var model: AppModel
  let meeting: Meeting
  @Binding var showSpeakers: Bool
  @ViewState private var speakerToRename: String?
  @ViewState private var passageToRename: UUID?
  @ViewState private var speakerName = ""
  @ViewState private var transcriptQuery = ""
  @ViewState private var searchResultIndex = 0
  @ViewState private var searchFocusRequest = 0
  @ViewState private var isFindVisible = false
  @ViewState private var searchOptions = TranscriptSearch.Options()

  private func showFind() {
    isFindVisible = true
    searchFocusRequest += 1
  }

  private func dismissFind() {
    isFindVisible = false
    transcriptQuery = ""
    searchResultIndex = 0
  }

  private var searchMatches: [TranscriptSearch.Match] {
    TranscriptSearch.matches(in: meeting.utterances, query: transcriptQuery, options: searchOptions)
  }

  private func highlightedText(
    _ utterance: Utterance, selected: TranscriptSearch.Match?
  ) -> Text {
    var result = Text("")
    var start = utterance.text.startIndex
    for range in TranscriptSearch.ranges(
      in: utterance.text, query: transcriptQuery, options: searchOptions)
    {
      result = result + Text(String(utterance.text[start..<range.lowerBound]))
      let isSelected = selected?.utteranceID == utterance.id && selected?.range == range
      result =
        result
        + Text(String(utterance.text[range]))
        .foregroundColor(.black).customAttribute(FindHighlight(selected: isSelected))
      start = range.upperBound
    }
    return result + Text(String(utterance.text[start...]))
  }

  private func canMoveSearch(by offset: Int) -> Bool {
    isFindVisible
      && TranscriptSearch.nextIndex(
        from: searchResultIndex, offset: offset, count: searchMatches.count,
        wrapAround: searchOptions.wrapAround) != nil
  }

  private func searchBar(scroll: ScrollViewProxy) -> some View {
    let matches = searchMatches
    return HStack(spacing: 8) {
      TranscriptSearchField(
        text: $transcriptQuery, options: $searchOptions, focusRequest: searchFocusRequest,
        next: { moveSearchResult(by: 1, matches: matches, scroll: scroll) },
        previous: { moveSearchResult(by: -1, matches: matches, scroll: scroll) },
        dismiss: dismissFind
      )
      .frame(minWidth: 100, maxWidth: .infinity)
      .frame(height: 22)
      if !transcriptQuery.isEmpty {
        Text(
          matches.isEmpty ? "No matches" : "\(searchResultIndex + 1) of \(matches.count) matches"
        )
        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      ControlGroup {
        Button("Previous Match", systemImage: "chevron.left") {
          moveSearchResult(by: -1, matches: matches, scroll: scroll)
        }.help("Previous match (Shift-Return)").disabled(!canMoveSearch(by: -1))
        Button("Next Match", systemImage: "chevron.right") {
          moveSearchResult(by: 1, matches: matches, scroll: scroll)
        }.help("Next match (Return)").disabled(!canMoveSearch(by: 1))
      }
      .disabled(matches.isEmpty)
      Button("Done", action: dismissFind)
        .keyboardShortcut(.cancelAction)
    }
    .labelStyle(.iconOnly).controlSize(.small)
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: transcriptQuery) {
      searchResultIndex = 0
      if let first = searchMatches.first { scroll.scrollTo(first.utteranceID, anchor: .center) }
    }
    .onChange(of: meeting.id) {
      transcriptQuery = ""
      searchResultIndex = 0
    }
    .onChange(of: matches) {
      searchResultIndex = 0
      if let first = matches.first { scroll.scrollTo(first.utteranceID, anchor: .center) }
    }
  }

  private func moveSearchResult(
    by offset: Int, matches: [TranscriptSearch.Match], scroll: ScrollViewProxy
  ) {
    guard
      let next = TranscriptSearch.nextIndex(
        from: searchResultIndex, offset: offset, count: matches.count,
        wrapAround: searchOptions.wrapAround)
    else { return }
    searchResultIndex = next
    scroll.scrollTo(matches[searchResultIndex].utteranceID, anchor: .center)
  }

  private func speakerSidebar(scroll: ScrollViewProxy) -> some View {
    List {
      Section {
        if meeting.firstSpeakerUtterances.isEmpty {
          ContentUnavailableView(
            "No speakers", systemImage: "person.2", description: Text("No speech was detected."))
        } else {
          ForEach(meeting.firstSpeakerUtterances) { first in
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
              if first.speaker != "Unassigned" {
                Menu {
                  bulkNameActions(first.speaker)
                } label: {
                  HStack(spacing: 4) {
                    Text("Assign Person")
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                      .accessibilityHidden(true)
                  }
                  .foregroundStyle(.primary)
                }
                .menuStyle(.button).menuIndicator(.hidden)
                .buttonStyle(.plain).fixedSize()
              }
            }.padding(.vertical, 6)
              .disabled(model.isBusy || model.isRecording)
          }
        }
      } header: {
        Text("Speakers")
      } footer: {
        Text(
          "Click a speaker to jump to their first appearance and listen. Assign a saved person or enter a name."
        )
      }
    }
    .listStyle(.sidebar)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let matches = searchMatches
    let selected = matches.indices.contains(searchResultIndex) ? matches[searchResultIndex] : nil
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
          MeetingSummaryView(
            summary: meeting.currentSummary,
            isGenerating: model.summarizingMeetingID == meeting.id,
            canGenerate: !meeting.utterances.isEmpty && !model.isBusy && !model.isRecording
              && !model.chatGPT.busy && model.summarizingMeetingID == nil,
            generate: { model.generateSummary(meeting) }
          ).id(meeting.id)
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
                highlightedText(utterance, selected: selected)
                  .textRenderer(FindHighlightRenderer())
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
      }.background {
        Color(nsColor: .windowBackgroundColor)
        if !matches.isEmpty {
          // Mail's find presentation keeps matches white against a dimmed document.
          Color.black.opacity(0.22)
        }
      }
      .clipped()
      .safeAreaInset(edge: .top, spacing: 0) {
        if isFindVisible {
          VStack(spacing: 0) {
            searchBar(scroll: scroll)
            Divider()
          }
        }
      }
      .focusedSceneValue(
        \.transcriptFind,
        TranscriptFindActions(
          show: showFind,
          next: { moveSearchResult(by: 1, matches: searchMatches, scroll: scroll) },
          previous: { moveSearchResult(by: -1, matches: searchMatches, scroll: scroll) },
          canGoNext: canMoveSearch(by: 1), canGoPrevious: canMoveSearch(by: -1))
      )
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
        }.font(.title).imageScale(.large).frame(width: 34)
        Button("Forward 15 seconds", systemImage: "goforward.15") {
          model.play(meeting, from: min(meeting.duration, model.playback.position + 15))
        }
      }
      .labelStyle(.iconOnly).buttonStyle(.plain).font(.title3)
      .disabled(model.isBusy || model.isRecording)

      PlaybackSeekBar(
        position: model.playback.position, duration: meeting.duration,
        enabled: !model.isBusy && !model.isRecording,
        seek: { model.play(meeting, from: $0) }
      ) {
        let speakers = meeting.speakers(at: model.playback.position)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(meeting.title).font(.headline).lineLimit(1).layoutPriority(1)
          Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
          Text(speakers.isEmpty ? "No speech" : speakers.joined(separator: ", "))
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            .help(speakers.joined(separator: ", "))
            .accessibilityLabel("Current speaker")
            .accessibilityValue(speakers.isEmpty ? "No speech" : speakers.joined(separator: ", "))
        }
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
