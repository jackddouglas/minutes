import MinutesCore
import SwiftUI

/// Controls the menu bar recorder carries on its face, beyond meters and key:
/// a speakers menu, the meeting band along its foot, the transcribing state,
/// and a way into the library.
struct RecorderFaceplate {
  var speakers: Binding<Int>?
  var speakersEnabled = true
  var tape: RecorderTape?
  var onTape: (RecorderTape.Action) -> Void = { _ in }
  /// Shown in the timer window while the last recording is processed.
  var working: (label: String, duration: String)?
  /// The name the next recording will take, from a chosen calendar meeting.
  var preparedTitle: String?
  /// Keep the line above the clock free for a chosen meeting's title.
  var reservesPreparedTitle: Bool { preparedTitle != nil || tape?.meeting != nil }
  var openLibrary: (() -> Void)?
}

/// The meeting printed along the foot of the recorder.
struct RecorderTape: Equatable {
  enum Action: Equatable {
    /// Fill in the next recording from the meeting: name and speakers.
    case prepare(CalendarMeeting)
    /// Clear a recording filled in from a meeting.
    case unprepare
    /// Fill in the recording and open the call. Recording stays the user's choice.
    case join(CalendarMeeting)
    case open(Meeting.ID)
  }

  /// How long before its start a meeting can be joined from the recorder.
  static let joinLead: TimeInterval = 600

  var tag: String
  var title: String
  /// A time of day, or a length in hours and minutes.
  var detail: String?
  var isLive = false
  var action: Action?
  /// The calendar meeting the band shows, which a click on the band chooses.
  var meeting: CalendarMeeting?
  var isPrepared = false

  /// What a click on the band itself does.
  var selectAction: Action? {
    guard let meeting else { return nil }
    return isPrepared ? .unprepare : .prepare(meeting)
  }

  var actionTitle: String? {
    switch action {
    case .join: "Join"
    case .open: "Open"
    case .prepare, .unprepare, nil: nil
    }
  }

  /// What the band reads: the recording, the meeting being processed, the
  /// next calendar meeting (joinable near its start), or the latest recording.
  static func content(
    isRecording: Bool, isBusy: Bool, recordingTitle: String, prepared: CalendarMeeting?,
    next: CalendarMeeting?, latest: Meeting?, now: Date = Date(), calendar: Calendar = .current
  ) -> RecorderTape? {
    if isRecording {
      return RecorderTape(tag: "Recording", title: recordingTitle, isLive: true)
    }
    let last = latest.map {
      RecorderTape(
        tag: "Last", title: $0.title, detail: MeetingLength.text($0.duration),
        action: .open($0.id))
    }
    if isBusy { return last }
    if let meeting = prepared ?? next, meeting.end > now {
      let started = meeting.start <= now
      let joinable = meeting.start.timeIntervalSince(now) <= joinLead
      return RecorderTape(
        tag: started ? "Now" : "Next", title: meeting.title,
        detail: when(meeting, now: now, calendar: calendar),
        action: joinable ? .join(meeting) : nil, meeting: meeting,
        isPrepared: prepared?.id == meeting.id)
    }
    return last
  }

  /// "10:00" today; "Thu 10:00" on another day.
  private static func when(_ meeting: CalendarMeeting, now: Date, calendar: Calendar) -> String {
    let time = meeting.start.formatted(
      .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    guard !calendar.isDate(meeting.start, inSameDayAs: now) else { return time }
    return "\(meeting.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
  }
}

/// A meeting's length in words, so it cannot read as a time of day:
/// "Under 1 min", "14 min", "1 h 6 min", "2 h".
enum MeetingLength {
  static func text(_ seconds: Double) -> String {
    let minutes = seconds.isFinite ? Int((max(0, seconds) / 60).rounded()) : 0
    guard minutes > 0 else { return "Under 1 min" }
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(minutes) min" }
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
  }
}

enum RecorderSpeakers {
  static let maximum = 20

  /// 0 is Automatic.
  static func label(_ count: Int) -> String { count == 0 ? "Auto" : "\(count)" }
}

/// The small label shown above the timer while the recorder is busy.
enum RecorderWorkingLabel {
  static func label(for status: String) -> String {
    status.hasPrefix("Starting") || status.hasPrefix("Loading") ? "STARTING" : "TRANSCRIBING"
  }
}

// MARK: Views

/// Other participants, as a quiet menu in the System Audio meter's header,
/// set like the source picker below that meter.
struct RecorderSpeakersMenu: View {
  @Binding var count: Int
  var isEnabled: Bool

  var body: some View {
    Menu {
      Picker("Other participants", selection: $count) {
        Text("Automatic").tag(0)
        Divider()
        ForEach(1...max(RecorderSpeakers.maximum, count), id: \.self) { value in
          Text("\(value)").tag(value)
        }
      }
      .pickerStyle(.inline)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "person.2").font(.system(size: 11))
        Text(RecorderSpeakers.label(count)).font(.system(size: 11, weight: .medium))
          .monospacedDigit()
        Image(systemName: "chevron.up.chevron.down").imageScale(.small)
      }
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .disabled(!isEnabled)
    .help("Other participants, excluding you")
    .accessibilityLabel("Other participants")
    .accessibilityValue(count == 0 ? "Automatic" : "\(count)")
  }
}

/// The meeting, printed along a slightly recessed band at the foot of the
/// recorder's face, as on a Braun panel: no window or slot, just a legend.
struct RecorderTapeView: View {
  let tape: RecorderTape?
  var onAction: (RecorderTape.Action) -> Void
  var openLibrary: (() -> Void)?
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 6) {
      if let tape {
        legend(tape)
        if let title = tape.actionTitle, let action = tape.action {
          Button {
            onAction(action)
          } label: {
            HStack(spacing: 5) {
              if case .join = action {
                Circle().fill(RecorderFinish.orange).frame(width: 6, height: 6)
              }
              Text(title)
              if case .open = action {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(BandKeyStyle())
          .help(help(for: action))
        }
      } else {
        Text("No meetings yet")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
        Spacer(minLength: 0)
      }
      if let openLibrary {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 0.5, height: 18)
          .padding(.horizontal, 2)
        Button(action: openLibrary) {
          Image(systemName: "list.bullet.rectangle").font(.system(size: 13))
        }
        .buttonStyle(BandKeyStyle())
        .help("Open the library of past meetings")
        .accessibilityLabel("Open library")
      }
    }
    .padding(.leading, 16).padding(.trailing, 12)
    .frame(height: 44)
    .animation(.easeOut(duration: 0.2), value: tape?.isPrepared)
    .background {
      // A shade darker than the face, lit along its upper edge.
      UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
        .fill(.black.opacity(colorScheme == .dark ? 0.14 : 0.035))
        .overlay(alignment: .top) {
          VStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5)
            Rectangle().fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.6)).frame(height: 0.5)
          }
        }
    }
  }

  /// The printed meeting. For a calendar meeting the whole legend is a key
  /// that fills in the next recording, or clears it again.
  @ViewBuilder private func legend(_ tape: RecorderTape) -> some View {
    let content = HStack(spacing: 10) {
      HStack(spacing: 5) {
        if tape.isLive {
          Circle().fill(RecorderFinish.orange).frame(width: 5, height: 5)
        }
        Text(tape.tag).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Text(tape.title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1).truncationMode(.tail)
      if let detail = tape.detail {
        Text(detail)
          .font(.system(size: 11)).monospacedDigit()
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      if tape.isPrepared {
        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .transition(.opacity.combined(with: .scale(scale: 0.6)))
      }
      Spacer(minLength: 4)
    }
    if let select = tape.selectAction {
      Button {
        onAction(select)
      } label: {
        content
      }
      .buttonStyle(BandKeyStyle(fill: true))
      .help(
        tape.isPrepared
          ? "Clear the recording’s name and speakers"
          : "Name the next recording after \(tape.title), with its attendees"
      )
      .accessibilityLabel("\(tape.tag), \(tape.title), \(tape.detail ?? "")")
      .accessibilityAddTraits(tape.isPrepared ? [.isSelected] : [])
    } else {
      content.padding(.horizontal, 8)
        .help(tape.title)
        .accessibilityElement(children: .combine)
    }
  }

  private func help(for action: RecorderTape.Action) -> String {
    switch action {
    case .join: "Open the call and name the recording after it"
    case .open: "Show this meeting in the library"
    case .prepare, .unprepare: ""
    }
  }
}

/// A text key on the band: ink type, with a faint ground on hover and press,
/// and a steady one while selected.
private struct BandKeyStyle: ButtonStyle {
  var selected = false
  var fill = false

  func makeBody(configuration: Configuration) -> some View {
    BandKey(configuration: configuration, selected: selected, fill: fill)
  }

  private struct BandKey: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let fill: Bool
    @ViewState private var hovering = false

    var body: some View {
      let ground =
        configuration.isPressed ? 0.1 : selected ? (hovering ? 0.09 : 0.07) : hovering ? 0.055 : 0
      configuration.label
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8).frame(maxWidth: fill ? .infinity : nil).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(ground)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
  }
}

/// The chosen meeting's title, set above the recorder's clock as the name of
/// the next recording. It rises into place; pointing at it offers to clear it.
struct RecorderPreparedTitle: View {
  let title: String
  var clear: () -> Void
  @ViewState private var hovering = false

  var body: some View {
    HStack(spacing: 5) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.tail)
      Button(action: clear) {
        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .opacity(hovering ? 1 : 0)
      .help("Clear the recording’s name and speakers")
      .accessibilityLabel("Clear \(title)")
    }
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Next recording, \(title)")
  }
}
