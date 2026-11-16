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
  var text: String
  var isLive = false
  var action: Action?

  var actionTitle: String? {
    switch action {
    case .arm: "ARM"
    case .join: "JOIN"
    case .open: "OPEN"
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
      return RecorderTape(tag: "REC", text: recordingTitle.uppercased(), isLive: true)
    }
    let last = latest.map {
      RecorderTape(
        tag: "LAST",
        text: "\($0.title.uppercased()) · \(MarkdownExporter.timestamp($0.duration))",
        action: .open($0.id))
    }
    if isBusy { return last }
    if let prepared {
      return RecorderTape(
        tag: "ARMED", text: describe(prepared, now: now, calendar: calendar), action: .join)
    }
    if let next {
      return RecorderTape(
        tag: "NEXT", text: describe(next, now: now, calendar: calendar), action: .arm(next))
    }
    return last
  }

  private static func describe(_ meeting: CalendarMeeting, now: Date, calendar: Calendar)
    -> String
  {
    let time = meeting.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    let day =
      calendar.isDate(meeting.start, inSameDayAs: now)
      ? "" : meeting.start.formatted(.dateTime.weekday(.abbreviated)).uppercased() + " "
    return "\(meeting.title.uppercased()) · \(day)\(time)"
  }
}

enum RecorderSpeakers {
  static let maximum = 20

  /// 0 is Automatic; the counter steps between Automatic and 1–20.
  static func step(_ count: Int, by delta: Int) -> Int {
    min(max(count + delta, 0), maximum)
  }

  static func label(_ count: Int) -> String { count == 0 ? "AUTO" : "\(count)" }
}

/// The small label shown above the timer while the recorder is busy.
enum RecorderWorkingLabel {
  static func label(for status: String) -> String {
    status.hasPrefix("Starting") || status.hasPrefix("Loading") ? "STARTING" : "TRANSCRIBING"
  }
}

// MARK: Views

struct RecorderSpeakersCounter: View {
  @Binding var count: Int
  var isEnabled: Bool

  var body: some View {
    VStack(spacing: 4) {
      Text("SPEAKERS").font(.system(size: 9, weight: .semibold)).tracking(1.2)
        .foregroundStyle(.secondary)
      HStack(spacing: 2) {
        Button {
          count = RecorderSpeakers.step(count, by: -1)
        } label: {
          Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
            .frame(width: 18, height: 22).contentShape(Rectangle())
        }
        .disabled(count == 0)
        .accessibilityLabel("Fewer speakers")
        RecorderSlot {
          Text(RecorderSpeakers.label(count))
            .font(.system(size: 12, design: .monospaced)).tracking(1)
            .frame(minWidth: 40)
        }
        Button {
          count = RecorderSpeakers.step(count, by: 1)
        } label: {
          Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            .frame(width: 18, height: 22).contentShape(Rectangle())
        }
        .disabled(count == RecorderSpeakers.maximum)
        .accessibilityLabel("More speakers")
      }
      .buttonStyle(.plain)
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.55)
    .help("Other participants, excluding you")
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Other participants")
    .accessibilityValue(count == 0 ? "Automatic" : "\(count)")
  }
}

struct RecorderTapeView: View {
  let tape: RecorderTape
  var onAction: (RecorderTape.Action) -> Void

  var body: some View {
    RecorderSlot(alignment: .leading) {
      HStack(spacing: 10) {
        Text(tape.tag)
          .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.3)
          .foregroundStyle(tape.isLive ? Color(red: 1, green: 0.42, blue: 0.24) : Color.gray)
        Text(tape.text)
          .font(.system(size: 11, design: .monospaced)).tracking(1.1)
          .lineLimit(1).truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let title = tape.actionTitle, let action = tape.action {
          Button(title) { onAction(action) }
            .buttonStyle(TapeKeyStyle())
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A recessed dark window in the recorder's face, as on a label maker.
struct RecorderSlot<Content: View>: View {
  var alignment: Alignment = .center
  @ViewBuilder let content: Content

  var body: some View {
    content
      .foregroundStyle(RecorderFinish.ivory)
      .padding(.horizontal, 8).padding(.vertical, 5)
      .frame(alignment: alignment)
      .background {
        RoundedRectangle(cornerRadius: 5)
          .fill(Color(red: 0.15, green: 0.16, blue: 0.15))
          .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
          .overlay(
            RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.45), lineWidth: 0.5)
              .offset(y: 0.5).mask(RoundedRectangle(cornerRadius: 5).padding(.top, 1))
          )
      }
  }
}

private struct TapeKeyStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2)
      .foregroundStyle(Color(red: 0.15, green: 0.16, blue: 0.15))
      .padding(.horizontal, 9).padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 4).fill(RecorderFinish.ivory)
          .opacity(configuration.isPressed ? 0.75 : 1))
  }
}
