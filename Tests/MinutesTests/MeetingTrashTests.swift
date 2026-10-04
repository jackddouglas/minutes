import Foundation
import MinutesCore
import Testing

@testable import Minutes

@Test func trashPreservesSharedAudioAndRollsBackFailure() throws {
  let files = FileManager.default
  let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? files.removeItem(at: root) }
  let store = MeetingStore(directory: root.appendingPathComponent("Meetings"))
  let recordings = root.appendingPathComponent("Recordings")
  let exports = root.appendingPathComponent("Exports")
  let bin = root.appendingPathComponent("Trash")
  try files.createDirectory(at: bin, withIntermediateDirectories: true)
  let original = Meeting(title: "Original")
  let survivor = Meeting(title: "Reprocessed")
  try store.save(original)
  try store.save(survivor)
  let owned = recordings.appendingPathComponent(original.id.uuidString)
  let other = recordings.appendingPathComponent(survivor.id.uuidString)
  for directory in [owned, other] {
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  let audio = owned.appendingPathComponent("system.caf")
  try Data([1, 2, 3]).write(to: audio)
  let tracks = AudioTracks(remote: audio, microphone: nil, remoteOffset: 2, microphoneOffset: 0)
  let metadata = try JSONEncoder().encode(tracks)
  for directory in [owned, other] {
    try metadata.write(to: directory.appendingPathComponent("tracks.json"))
  }
  let export = try MarkdownExporter.write(original, to: exports)
  var attempts = 0
  #expect(throws: (any Error).self) {
    try MeetingTrash.move(
      original, remaining: [survivor], store: store, recordings: recordings,
      exportDirectories: [exports], shareDirectory: root.appendingPathComponent("Share")
    ) { url in
      attempts += 1
      if attempts == 2 { throw MinutesError.message("Injected Trash failure") }
      let destination = bin.appendingPathComponent(url.lastPathComponent)
      try files.moveItem(at: url, to: destination)
      return destination
    }
  }
  #expect(files.fileExists(atPath: audio.path))
  #expect(files.fileExists(atPath: export.path))
  #expect(try Data(contentsOf: other.appendingPathComponent("tracks.json")) == metadata)
  try MeetingTrash.move(
    original, remaining: [survivor], store: store, recordings: recordings,
    exportDirectories: [exports], shareDirectory: root.appendingPathComponent("Share")
  ) { url in
    let destination = bin.appendingPathComponent(url.lastPathComponent)
    try files.moveItem(at: url, to: destination)
    return destination
  }
  let retained = try JSONDecoder().decode(
    AudioTracks.self, from: Data(contentsOf: other.appendingPathComponent("tracks.json")))
  #expect(retained.remote != audio)
  #expect(try Data(contentsOf: #require(retained.remote)) == Data([1, 2, 3]))
  #expect(retained.remoteOffset == 2)
  #expect(try store.load().map(\.id) == [survivor.id])
  #expect(!files.fileExists(atPath: export.path))
  #expect(files.fileExists(atPath: bin.appendingPathComponent(original.id.uuidString).path))
}

@Test func meetingDaysUseRecordingDateAndLocalCalendar() {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
  let a = Meeting(title: "a", date: Date(timeIntervalSince1970: 0))
  let b = Meeting(title: "b", date: Date(timeIntervalSince1970: -3601))
  let c = Meeting(title: "c", date: Date(timeIntervalSince1970: 100))
  let groups = MeetingDay.group([b, a, c], calendar: calendar)
  #expect(groups.count == 2)
  #expect(groups[0].meetings.map(\.id) == [c.id, a.id])
  #expect(groups[1].meetings.map(\.id) == [b.id])
}
