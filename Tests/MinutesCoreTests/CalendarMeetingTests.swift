import Foundation
import Testing

@testable import MinutesCore

@Test func calendarRemindersDeduplicateAndHandleWakeAndRecurrence() {
  let now = Date(timeIntervalSince1970: 10000)
  let url = URL(string: "https://meet.google.com/abc-defg-hij")!
  let due = CalendarMeeting(
    eventID: "series", title: "Due", start: now.addingTimeInterval(-60),
    end: now.addingTimeInterval(1800), url: url)
  let future = CalendarMeeting(
    eventID: "series", title: "Tomorrow", start: now.addingTimeInterval(86400),
    end: now.addingTimeInterval(90000), url: url)
  let expired = CalendarMeeting(
    eventID: "old", title: "Missed", start: now.addingTimeInterval(-900),
    end: now.addingTimeInterval(600), url: url)
  var ledger = CalendarReminderLedger()
  #expect(ledger.claimDue([due, due, future, expired], at: now) == [due])
  #expect(ledger.claimDue([due], at: now.addingTimeInterval(30)).isEmpty)
  var restored = CalendarReminderLedger(notified: ledger.notified)
  #expect(restored.claimDue([due], at: now.addingTimeInterval(60)).isEmpty)
  #expect(restored.claimDue([future], at: future.start) == [future])
}

@Test func calendarMeetingFiltersLinksAndPromptTimes() throws {
  #expect(
    CalendarMeeting.googleMeetURL(in: ["https://meet.google.com.evil.example/abc-defg-hij"]) == nil)
  #expect(
    CalendarMeeting.googleMeetURL(in: ["https://evil.example/meet.google.com/abc-defg-hij"]) == nil)
  #expect(CalendarMeeting.googleMeetURL(in: ["https://meet.google.com/"]) == nil)
  let url = try #require(
    CalendarMeeting.googleMeetURL(in: ["Join: https://meet.google.com/abc-defg-hij?authuser=1"]))
  let now = Date(timeIntervalSince1970: 10000)
  let event = CalendarMeeting(
    eventID: "series", title: "Meeting", start: now, end: now.addingTimeInterval(3600), url: url)
  #expect(!event.isDue(at: now.addingTimeInterval(-1)))
  #expect(event.isDue(at: now))
  #expect(event.isDue(at: now.addingTimeInterval(600)))
  #expect(!event.isDue(at: now.addingTimeInterval(601)))
  #expect(
    event.id
      != CalendarMeeting(
        eventID: "series", title: "Meeting", start: now.addingTimeInterval(86400),
        end: now.addingTimeInterval(90000), url: url
      ).id)
}
