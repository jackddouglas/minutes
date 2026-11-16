import Foundation
import MinutesCore
import Testing

@testable import Minutes

private let now = Date(timeIntervalSince1970: 1_794_800_000)
private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

private func meeting(_ title: String, in seconds: TimeInterval) -> CalendarMeeting {
  CalendarMeeting(
    eventID: title, title: title, start: now.addingTimeInterval(seconds),
    end: now.addingTimeInterval(seconds + 1800), url: URL(string: "https://meet.google.com/x")!)
}

private func tape(
  recording: Bool = false, busy: Bool = false, prepared: CalendarMeeting? = nil,
  next: CalendarMeeting? = nil, latest: Meeting? = nil
) -> RecorderTape? {
  RecorderTape.content(
    isRecording: recording, isBusy: busy, recordingTitle: "Water Cooler Time", prepared: prepared,
    next: next, latest: latest, now: now, calendar: calendar)
}

@Test func tapeShowsTheRecordingFirst() {
  let next = meeting("First Standup", in: 3600)
  let shown = tape(recording: true, next: next)
  #expect(shown?.tag == "REC")
  #expect(shown?.text == "WATER COOLER TIME")
  #expect(shown?.isLive == true)
  #expect(shown?.action == nil)
}

@Test func tapeShowsTheMeetingBeingProcessedWhileBusy() {
  var latest = Meeting(title: "Water Cooler Time")
  latest.duration = 3966
  let shown = tape(busy: true, next: meeting("First Standup", in: 3600), latest: latest)
  #expect(shown?.tag == "LAST")
  #expect(shown?.text == "WATER COOLER TIME · 1:06:06")
  #expect(shown?.action == .open(latest.id))
}

@Test func tapeOffersToArmTheNextMeetingThenToJoinIt() {
  let next = meeting("First Standup", in: 3600)
  let offered = tape(next: next)
  #expect(offered?.tag == "NEXT")
  #expect(offered?.action == .arm(next))
  #expect(offered?.text.hasPrefix("FIRST STANDUP · ") == true)
  #expect(offered?.text.contains(" · MON ") == false)
  let armed = tape(prepared: next, next: next)
  #expect(armed?.tag == "ARMED")
  #expect(armed?.action == .join)
  // A meeting on another day names its weekday.
  let later = tape(next: meeting("Sprint Planning", in: 3 * 86_400))
  #expect(later?.text.split(separator: "·").last?.trimmingCharacters(in: .whitespaces).count == 9)
}

@Test func tapeFallsBackToTheLatestRecordingOrNothing() {
  let latest = Meeting(title: "Retro")
  #expect(tape(latest: latest)?.tag == "LAST")
  #expect(tape() == nil)
}

@Test func speakersCounterStepsBetweenAutomaticAndTwenty() {
  #expect(RecorderSpeakers.step(0, by: -1) == 0)
  #expect(RecorderSpeakers.step(0, by: 1) == 1)
  #expect(RecorderSpeakers.step(1, by: -1) == 0)
  #expect(RecorderSpeakers.step(20, by: 1) == 20)
  #expect(RecorderSpeakers.label(0) == "AUTO")
  #expect(RecorderSpeakers.label(4) == "4")
}

@Test func workingLabelDistinguishesStartingFromTranscribing() {
  #expect(RecorderWorkingLabel.label(for: "Starting audio capture…") == "STARTING")
  #expect(RecorderWorkingLabel.label(for: "Loading transcription model…") == "STARTING")
  #expect(RecorderWorkingLabel.label(for: "Transcribing the meeting…") == "TRANSCRIBING")
  #expect(RecorderWorkingLabel.label(for: "Finishing recording…") == "TRANSCRIBING")
}
