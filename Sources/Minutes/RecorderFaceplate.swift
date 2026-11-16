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
  var openLibrary: (() -> Void)?
}

/// The meeting printed along the foot of the recorder.
struct RecorderTape: Equatable {
  enum Action: Equatable {
    /// Name the recording, open the call and start recording, in one press.
    case join(CalendarMeeting)
    case open(Meeting.ID)
  }

  /// How long before its start a meeting can be joined from the recorder.
  static let joinLead: TimeInterval = 600

  var tag: String
  var title: String
  /// A time or a length, set in the meters' monospaced type.
  var detail: String?
  var isLive = false
  var action: Action?

  var actionTitle: String? {
    switch action {
    case .join: "Join"
    case .open: "Open"
    case nil: nil
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
        tag: "Last", title: $0.title, detail: MarkdownExporter.timestamp($0.duration),
        action: .open($0.id))
    }
    if isBusy { return last }
    if let meeting = prepared ?? next, meeting.end > now {
      let started = meeting.start <= now
      let joinable = meeting.start.timeIntervalSince(now) <= joinLead
      return RecorderTape(
        tag: started ? "Now" : "Next", title: meeting.title,
        detail: when(meeting, now: now, calendar: calendar),
        action: joinable ? .join(meeting) : nil)
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
  let tape: RecorderTape
  var onAction: (RecorderTape.Action) -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 5) {
        if tape.isLive {
          Circle().fill(RecorderFinish.orange).frame(width: 5, height: 5)
        }
        Text(tape.tag).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Text(tape.title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1).truncationMode(.tail)
        .help(tape.title)
      if let detail = tape.detail {
        Text(detail)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      Spacer(minLength: 4)
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
    }
    .padding(.leading, 24).padding(.trailing, 16)
    .frame(height: 44)
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
    .accessibilityElement(children: .combine)
  }

  private func help(for action: RecorderTape.Action) -> String {
    switch action {
    case .join: "Open the call and start recording it"
    case .open: "Show this meeting in the library"
    }
  }
}

/// A text key on the band: ink type, with a faint ground on hover and press.
private struct BandKeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    BandKey(configuration: configuration)
  }

  private struct BandKey: View {
    let configuration: ButtonStyleConfiguration
    @ViewState private var hovering = false

    var body: some View {
      configuration.label
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8).frame(height: 26)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.055 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
  }
}

/// A quiet way into the library from the recorder's top corner.
struct RecorderLibraryKey: View {
  let open: () -> Void
  @ViewState private var hovering = false

  var body: some View {
    Button(action: open) {
      Image(systemName: "list.bullet.rectangle")
        .font(.system(size: 13))
        .foregroundStyle(hovering ? .primary : .secondary)
        .frame(width: 26, height: 26)
        .background(Circle().fill(.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help("Open the library of past meetings")
    .accessibilityLabel("Open library")
  }
}
