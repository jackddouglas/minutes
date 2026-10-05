import Foundation
import Testing

@testable import MinutesCore

@Test func reprocessingStartsFreshWithoutChangingOriginal() throws {
  let original = Meeting(
    title: "Original",
    utterances: [
      .init(speaker: "Speaker 1", start: 0, end: 1, text: "Hi", assignedName: "Alice")
    ], speakerNames: ["Speaker 1": "Bob"])
  let options = TranscriptionOptions(expectedSystemSpeakers: 3)
  let draft = original.reprocessedDraft(options: options)
  #expect(draft.id == original.id)
  #expect(draft.title == original.title)
  #expect(draft.date == original.date)
  #expect(draft.duration == original.duration)
  #expect(draft.utterances.isEmpty)
  #expect(draft.speakerNames.isEmpty)
  #expect(original.utterances[0].assignedName == "Alice")
  let reloaded = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(draft))
  #expect(reloaded.transcriptionOptions == options)
}

@Test func speakerSidebarUsesEarliestOccurrenceAndDetectedIdentity() {
  let later = Utterance(speaker: "A", start: 20, end: 21, text: "Later")
  let first = Utterance(speaker: "A", start: 2, end: 3, text: "First")
  let other = Utterance(speaker: "B", start: 1, end: 2, text: "Other")
  let unknown = Utterance(speaker: "Unassigned", start: 4, end: 5, text: "Unknown")
  let meeting = Meeting(
    title: "Test", utterances: [later, first, other, unknown],
    speakerNames: ["A": "Alex", "B": "Alex"])
  #expect(meeting.firstSpeakerUtterances.map(\.id) == [other.id, first.id, unknown.id])
  #expect(Meeting(title: "Empty").firstSpeakerUtterances.isEmpty)
}

@Test func markdownOrdersSpeakersAndEscapesContent() {
  let meeting = Meeting(
    title: "Weekly [sync]",
    utterances: [
      Utterance(speaker: "B", start: 65, end: 70, text: "A *decision*."),
      Utterance(speaker: "A", start: 2, end: 4, text: "Hello"),
    ], speakerNames: ["A": "Jack"])
  let result = MarkdownExporter.render(meeting)
  #expect(result.contains("# Weekly \\[sync\\]"))
  #expect(result.contains("**Jack** · 00:02"))
  #expect(result.contains("A \\*decision\\*."))
  #expect(result.range(of: "Hello")!.lowerBound < result.range(of: "decision")!.lowerBound)
}

@Test func exportIsStableAndCannotEscapeDestination() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let meeting = Meeting(title: "../../bad/title")
  let first = try MarkdownExporter.write(meeting, to: directory)
  let second = try MarkdownExporter.write(meeting, to: directory)
  #expect(first == second)
  #expect(
    first.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
  )
  #expect(try String(contentsOf: first, encoding: .utf8) == MarkdownExporter.render(meeting))
  let other = Meeting(title: meeting.title, date: meeting.date)
  let collision = try MarkdownExporter.write(other, to: directory)
  #expect(collision != first)
  #expect(collision.lastPathComponent.hasSuffix(" (2).md"))
  #expect(try MarkdownExporter.write(other, to: directory) == collision)
  #expect(MarkdownExporter.owns(first, meeting: meeting))
  #expect(!MarkdownExporter.owns(first, meeting: other))
  #expect(try String(contentsOf: first, encoding: .utf8) == MarkdownExporter.render(meeting))
}

@Test func persistenceRoundTrips() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = MeetingStore(directory: directory)
  #expect(try store.load().isEmpty)
  let meeting = Meeting(
    title: "Test", utterances: [.init(speaker: "You", start: 0, end: 2, text: "Hi")])
  try store.save(meeting)
  #expect(try store.load() == [meeting])
}

@Test func timestampsHandleHoursAndInvalidValues() {
  #expect(MarkdownExporter.timestamp(3661) == "1:01:01")
  #expect(MarkdownExporter.timestamp(-2) == "00:00")
  #expect(MarkdownExporter.timestamp(.nan) == "00:00")
}

@Test func silentCompletedMeetingIsDistinctFromPendingSession() {
  var meeting = Meeting(title: "Silent meeting")
  #expect(!meeting.isTranscribed)
  meeting.transcribedAt = Date()
  #expect(meeting.isTranscribed)
}

@Test func markdownFilenameUsesRecordingDayAndReadableTitle() throws {
  let date = try #require(ISO8601DateFormatter().date(from: "2026-10-03T23:30:00Z"))
  let zone = try #require(TimeZone(identifier: "Europe/London"))
  let meeting = Meeting(title: "Water Cooler Time", date: date)
  #expect(MarkdownExporter.filename(meeting, timeZone: zone) == "2026-10-04 Water Cooler Time.md")
  let empty = Meeting(title: "../ : \\ ", date: date)
  #expect(MarkdownExporter.filename(empty, timeZone: zone) == "2026-10-04 Meeting.md")
  let long = Meeting(title: String(repeating: "界", count: 200), date: date)
  #expect(MarkdownExporter.filename(long).utf8.count < 255)
}

@Test func markdownExportPreservesUnrelatedFile() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let meeting = Meeting(title: "Planning")
  let occupied = directory.appendingPathComponent(MarkdownExporter.filename(meeting))
  try "Personal notes".write(to: occupied, atomically: true, encoding: .utf8)
  let exported = try MarkdownExporter.write(meeting, to: directory)
  #expect(exported != occupied)
  #expect(try String(contentsOf: occupied, encoding: .utf8) == "Personal notes")
}

@Test func markdownExportOmitsInternalMarkerAndRetainsOwnership() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let meeting = Meeting(title: "Planning")
  let url = directory.appendingPathComponent(MarkdownExporter.filename(meeting))
  #expect(try MarkdownExporter.write(meeting, to: directory) == url)
  let text = try String(contentsOf: url, encoding: .utf8)
  #expect(!text.contains("<!--"))
  #expect(!text.contains(meeting.id.uuidString))
  #expect(MarkdownExporter.owns(url, meeting: meeting))
  let moved = directory.appendingPathComponent("Renamed.md")
  try FileManager.default.moveItem(at: url, to: moved)
  #expect(MarkdownExporter.owns(moved, meeting: meeting))
}
