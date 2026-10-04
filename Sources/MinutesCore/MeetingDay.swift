import Foundation

public struct MeetingDay: Identifiable {
  public var id: Date { date }
  public let date: Date
  public let meetings: [Meeting]

  public static func group(_ meetings: [Meeting], calendar: Calendar = .current) -> [MeetingDay] {
    Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.date) }
      .map { date, meetings in
        MeetingDay(
          date: date,
          meetings: meetings.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
          })
      }.sorted { $0.date > $1.date }
  }
}
