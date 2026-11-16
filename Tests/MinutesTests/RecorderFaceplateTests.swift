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
  let next = meeting("First Standup", in: 60)
  let shown = tape(recording: true, next: next)
  #expect(shown?.tag == "Recording")
  #expect(shown?.title == "Water Cooler Time")
  #expect(shown?.detail == nil)
  #expect(shown?.isLive == true)
  #expect(shown?.action == nil)
}

@Test func tapeShowsTheMeetingBeingProcessedWhileBusy() {
  var latest = Meeting(title: "Water Cooler Time")
  latest.duration = 3966
  let shown = tape(busy: true, next: meeting("First Standup", in: 60), latest: latest)
  #expect(shown?.tag == "Last")
  #expect(shown?.title == "Water Cooler Time")
  #expect(shown?.detail == "1:06:06")
  #expect(shown?.action == .open(latest.id))
  #expect(shown?.actionTitle == "Open")
}

@Test func tapeOffersJoinOnlyNearAMeetingsStart() {
  // Well ahead: information only, with the time.
  let later = meeting("First Standup", in: 3600)
  let ahead = tape(next: later)
  #expect(ahead?.tag == "Next")
  #expect(ahead?.title == "First Standup")
  #expect(ahead?.action == nil)
  #expect(ahead?.detail?.wholeMatch(of: /\d{2}:\d{2}/) != nil)
  // Ten minutes before: one key joins and records.
  let soon = meeting("First Standup", in: RecorderTape.joinLead)
  #expect(tape(next: soon)?.action == .join(soon))
  #expect(tape(next: soon)?.actionTitle == "Join")
  // Under way: Now, still joinable.
  let started = meeting("First Standup", in: -300)
  #expect(tape(next: started)?.tag == "Now")
  #expect(tape(next: started)?.action == .join(started))
  // A meeting prepared from a calendar prompt takes precedence over the next one.
  let prepared = meeting("Debrief", in: 120)
  #expect(tape(prepared: prepared, next: later)?.title == "Debrief")
}

@Test func tapeShowsTimesOnTheHourAndOnOtherDays() {
  let hour = Calendar.current.dateInterval(of: .hour, for: now)!.start.addingTimeInterval(3600)
  let onTheHour = tape(next: meeting("Debrief", in: hour.timeIntervalSince(now)))
  #expect(onTheHour?.detail?.wholeMatch(of: /\d{2}:00/) != nil)
  let otherDay = tape(next: meeting("Sprint Planning", in: 3 * 86_400))
  #expect(otherDay?.detail?.split(separator: " ").count == 2)
}

@Test func tapeFallsBackToTheLatestRecordingOrNothing() {
  let latest = Meeting(title: "Retro")
  #expect(tape(latest: latest)?.tag == "Last")
  // A meeting that has ended is not offered.
  #expect(tape(next: meeting("Done", in: -7200), latest: latest)?.tag == "Last")
  #expect(tape() == nil)
}

@Test func speakersMenuNamesAutomaticAndCounts() {
  #expect(RecorderSpeakers.label(0) == "Auto")
  #expect(RecorderSpeakers.label(4) == "4")
}

@Test func workingLabelDistinguishesStartingFromTranscribing() {
  #expect(RecorderWorkingLabel.label(for: "Starting audio capture…") == "STARTING")
  #expect(RecorderWorkingLabel.label(for: "Loading transcription model…") == "STARTING")
  #expect(RecorderWorkingLabel.label(for: "Transcribing the meeting…") == "TRANSCRIBING")
  #expect(RecorderWorkingLabel.label(for: "Finishing recording…") == "TRANSCRIBING")
}
