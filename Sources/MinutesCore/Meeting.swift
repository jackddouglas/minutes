import Darwin
import Foundation

public struct Utterance: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var speaker: String
  public var start: Double
  public var end: Double
  public var text: String
  public var words: [TimedWord]?
  public var assignedName: String?

  public init(
    id: UUID = UUID(), speaker: String, start: Double, end: Double, text: String,
    words: [TimedWord]? = nil, assignedName: String? = nil
  ) {
    self.id = id
    self.speaker = speaker
    self.start = start
    self.end = end
    self.text = text
    self.words = words
    self.assignedName = assignedName
  }
}

public struct Meeting: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var date: Date
  public var duration: Double
  public var utterances: [Utterance]
  public var speakerNames: [String: String]
  public var transcribedAt: Date?
  public var transcriptionOptions: TranscriptionOptions?
  public var exportFiles: [URL]?

  public init(
    id: UUID = UUID(), title: String, date: Date = Date(), duration: Double = 0,
    utterances: [Utterance] = [], speakerNames: [String: String] = [:]
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.duration = duration
    self.utterances = utterances
    self.speakerNames = speakerNames
    self.transcribedAt = nil
  }

  /// One entry per detected speaker, ordered by their earliest appearance.
  /// Keep detected identities distinct even when they share an assigned name.
  public var firstSpeakerUtterances: [Utterance] {
    var seen = Set<String>()
    return utterances.enumerated().sorted {
      $0.element.start == $1.element.start
        ? $0.offset < $1.offset : $0.element.start < $1.element.start
    }.compactMap { entry in
      seen.insert(entry.element.speaker).inserted ? entry.element : nil
    }
  }

  public func name(for speaker: String) -> String {
    speaker == "Unassigned" ? "Unassigned" : speakerNames[speaker] ?? speaker
  }
  public func name(for utterance: Utterance) -> String {
    utterance.assignedName ?? name(for: utterance.speaker)
  }

  /// Active passage names at the playback position; overlapping voices appear together.
  public func speakers(at time: Double) -> [String] {
    guard time.isFinite, time >= 0 else { return [] }
    var seen = Set<String>()
    return utterances.compactMap { utterance in
      guard utterance.start <= time, time < utterance.end else { return nil }
      let speaker = name(for: utterance)
      return seen.insert(speaker).inserted ? speaker : nil
    }
  }

  /// Unknown passages and unnamed detected speakers, in listening order.
  /// A historical bulk Unassigned alias is not evidence of a single identity.
  public var passagesNeedingSpeakerReview: [Utterance] {
    utterances.enumerated().filter { _, utterance in
      if let name = utterance.assignedName,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return false
      }
      if utterance.speaker == "Unassigned" { return true }
      if utterance.speaker == "You" { return false }
      return speakerNames[utterance.speaker]?
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }.sorted {
      $0.element.start == $1.element.start
        ? $0.offset < $1.offset : $0.element.start < $1.element.start
    }.map(\.element)
  }
  public func reprocessedDraft(options: TranscriptionOptions) -> Meeting {
    var result = self
    result.utterances = []
    result.speakerNames = [:]
    result.transcribedAt = nil
    result.transcriptionOptions = options
    return result
  }
  public var isTranscribed: Bool { transcribedAt != nil || !utterances.isEmpty }
}

public enum MarkdownExporter {
  private static let meetingAttribute = "app.minutes.meeting-id"
  public static func timestamp(_ seconds: Double) -> String {
    let total = seconds.isFinite ? Int(max(0, min(seconds, 359_999))) : 0
    return total >= 3600
      ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
      : String(format: "%02d:%02d", total / 60, total % 60)
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .reduce(into: "") { result, character in
        if "`*_{}[]<>#|".contains(character) { result.append("\\") }
        result.append(character)
      }
  }

  public static func render(_ meeting: Meeting) -> String {
    let date = ISO8601DateFormatter().string(from: meeting.date)
    var lines = [
      "# \(escape(meeting.title))", "", "Date: \(date)",
      "Duration: \(timestamp(meeting.duration))", "", "## Transcript", "",
    ]
    for utterance in meeting.utterances.sorted(by: { $0.start < $1.start }) {
      lines += [
        "**\(escape(meeting.name(for: utterance)))** · \(timestamp(utterance.start))",
        "", escape(utterance.text), "",
      ]
    }
    return lines.joined(separator: "\n")
  }

  public static func filename(_ meeting: Meeting, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
    let title = meeting.title.components(separatedBy: unsafe).joined(separator: " ")
      .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    // Bound UTF-8 bytes, including room for a collision suffix, to fit filesystem limits.
    var safeTitle = ""
    for character in title {
      guard safeTitle.utf8.count + String(character).utf8.count <= 180 else { break }
      safeTitle.append(character)
    }
    return "\(formatter.string(from: meeting.date)) \(safeTitle.isEmpty ? "Meeting" : safeTitle).md"
  }

  public static func owns(_ url: URL, meeting: Meeting) -> Bool {
    guard url.isFileURL, url.pathExtension == "md" else { return false }
    var identifier = [UInt8](repeating: 0, count: 36)
    let count = getxattr(url.path, meetingAttribute, &identifier, identifier.count, 0, 0)
    if count == identifier.count {
      return String(decoding: identifier, as: UTF8.self) == meeting.id.uuidString
    }
    return false
  }

  public static func destination(_ meeting: Meeting, in directory: URL) -> URL {
    let base = directory.appendingPathComponent(filename(meeting))
    var candidate = base
    var suffix = 2
    while FileManager.default.fileExists(atPath: candidate.path)
      && !owns(candidate, meeting: meeting)
    {
      candidate = directory.appendingPathComponent(
        "\(base.deletingPathExtension().lastPathComponent) (\(suffix)).md")
      suffix += 1
    }
    return candidate
  }

  @discardableResult
  public static func write(_ meeting: Meeting, to directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = destination(meeting, in: directory)
    let temporary = directory.appendingPathComponent(".\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try render(meeting).write(to: temporary, atomically: true, encoding: .utf8)
    let identifier = Array(meeting.id.uuidString.utf8)
    let result = identifier.withUnsafeBytes {
      setxattr(temporary.path, meetingAttribute, $0.baseAddress, $0.count, 0, 0)
    }
    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    // Publish content and ownership together, preserving the previous export on failure.
    guard rename(temporary.path, url.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return url
  }

}

public struct MeetingStore: Sendable {
  public let directory: URL
  public init(directory: URL) { self.directory = directory }

  public func save(_ meeting: Meeting) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(meeting).write(
      to: directory.appendingPathComponent(meeting.id.uuidString + ".json"), options: .atomic)
  }

  public func load() throws -> [Meeting] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .map { try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: $0)) }
    .sorted { $0.date > $1.date }
  }
}
