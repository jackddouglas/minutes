import Foundation
import Testing

@testable import Minutes

@MainActor @Test func calendarSelectionPersistsExplicitChoices() throws {
  let suite = "MinutesCalendarSelectionTests-\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  defer { preferences.removePersistentDomain(forName: suite) }
  let monitor = CalendarMonitor(preferences: preferences)
  #expect(monitor.selectedCalendarIDs.isEmpty)
  monitor.setCalendar("work", selected: true)
  monitor.setCalendar("personal", selected: true)
  monitor.setCalendar("personal", selected: false)
  let restored = CalendarMonitor(preferences: preferences)
  #expect(restored.selectedCalendarIDs == ["work"])
  #expect(!restored.selectedCalendarIDs.contains("new-calendar"))
  restored.setCalendar("work", selected: false)
  #expect(CalendarMonitor(preferences: preferences).selectedCalendarIDs.isEmpty)
}
