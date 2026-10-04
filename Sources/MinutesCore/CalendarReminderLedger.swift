import Foundation

/// Deduplicates recurring-event occurrences across polls, sleep, and app restarts.
public struct CalendarReminderLedger: Sendable {
  public private(set) var notified: [String: Double]

  public init(notified: [String: Double] = [:]) { self.notified = notified }

  public mutating func claimDue(_ meetings: [CalendarMeeting], at now: Date) -> [CalendarMeeting] {
    notified = notified.filter { now.timeIntervalSince1970 - $0.value < 172_800 }
    return meetings.filter { meeting in
      guard meeting.isDue(at: now), notified[meeting.id] == nil else { return false }
      notified[meeting.id] = now.timeIntervalSince1970
      return true
    }
  }
}
