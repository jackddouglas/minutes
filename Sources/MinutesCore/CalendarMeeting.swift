import Foundation

public struct CalendarMeeting: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let start: Date
  public let end: Date
  public let url: URL

  public init(eventID: String, title: String, start: Date, end: Date, url: URL) {
    self.id = "\(eventID)|\(start.timeIntervalSince1970)"
    self.title = title
    self.start = start
    self.end = end
    self.url = url
  }

  public func isDue(at now: Date) -> Bool {
    start <= now && end > now && now.timeIntervalSince(start) <= 600
  }

  public static func googleMeetURL(in fields: [String]) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    for text in fields {
      for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url, url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "meet.google.com", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443,
          url.path.split(separator: "/").first?.contains("-") == true
        else { continue }
        return url
      }
    }
    return nil
  }
}
