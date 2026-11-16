import MinutesCore
import SwiftUI

/// Controls the menu bar recorder carries on its face, beyond meters and key:
/// a speakers counter, a label tape for the meeting, and the transcribing state.
struct RecorderFaceplate {
  var speakers: Binding<Int>?
  var speakersEnabled = true
  var tape: RecorderTape?
  var onTape: (RecorderTape.Action) -> Void = { _ in }
  /// Shown in the timer window while the last recording is processed.
  var working: (label: String, duration: String)?
}

/// The label-maker tape along the bottom of the recorder.
struct RecorderTape: Equatable {
  enum Action: Equatable {
    case arm(CalendarMeeting)
    case join
    case open(Meeting.ID)
  }

  var tag: String
  var title: String
  /// A time or a length, set in the meters' monospaced type.
  var detail: String?
  var isLive = false
  var action: Action?

  var actionTitle: String? {
    switch action {
    case .arm: "Arm"
    case .join: "Join"
    case .open: "Open"
    case nil: nil
    }
  }

  /// What the tape reads: the recording, the meeting being processed, a
  /// prepared calendar meeting, the next one, or the latest recording.
  static func content(
    isRecording: Bool, isBusy: Bool, recordingTitle: String, prepared: CalendarMeeting?,
    next: CalendarMeeting?, latest: Meeting?, now: Date = Date(), calendar: Calendar = .current
  ) -> RecorderTape? {
    if isRecording {
      return RecorderTape(tag: "REC", title: recordingTitle, isLive: true)
    }
    let last = latest.map {
      RecorderTape(
        tag: "LAST", title: $0.title, detail: MarkdownExporter.timestamp($0.duration),
        action: .open($0.id))
    }
    if isBusy { return last }
    if let prepared {
      return RecorderTape(
        tag: "ARMED", title: prepared.title, detail: when(prepared, now: now, calendar: calendar),
        action: .join)
    }
    if let next {
      return RecorderTape(
        tag: "NEXT", title: next.title, detail: when(next, now: now, calendar: calendar),
        action: .arm(next))
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
        Text(tape.tag).font(.system(size: 9, weight: .semibold)).tracking(1.4)
          .foregroundStyle(
            tape.isLive ? AnyShapeStyle(RecorderFinish.orange) : AnyShapeStyle(.tertiary))
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
        Button(title) { onAction(action) }.buttonStyle(TapeKeyStyle())
      }
    }
    .padding(.horizontal, 24)
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
}

/// A small raised pill key in the recorder's ivory.
private struct TapeKeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(RecorderFinish.ink)
      .padding(.horizontal, 11).frame(height: 22)
      .background {
        Capsule()
          .fill(
            LinearGradient(
              colors: configuration.isPressed
                ? [RecorderFinish.lowerIvory, RecorderFinish.ivory]
                : [Color(red: 0.985, green: 0.98, blue: 0.96), RecorderFinish.ivory],
              startPoint: .top, endPoint: .bottom)
          )
          .overlay(Capsule().strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
          .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.12), radius: 1.5, y: 1)
      }
      .offset(y: configuration.isPressed ? 0.5 : 0)
  }
}
