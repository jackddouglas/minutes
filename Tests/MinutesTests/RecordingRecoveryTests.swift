import Foundation
import MinutesCore
import Testing

@testable import Minutes

// Opt-in recovery verification. Writes only staged output, never the source meeting.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MINUTES_RECOVERY_MEETING"] != nil))
func regenerateRetainedRecording() async throws {
  let environment = ProcessInfo.processInfo.environment
  let meetingURL = URL(fileURLWithPath: try #require(environment["MINUTES_RECOVERY_MEETING"]))
  let tracksURL = URL(fileURLWithPath: try #require(environment["MINUTES_RECOVERY_TRACKS"]))
  let output = URL(fileURLWithPath: try #require(environment["MINUTES_RECOVERY_OUTPUT"]))
  let originalData = try Data(contentsOf: meetingURL)
  let original = try JSONDecoder().decode(Meeting.self, from: originalData)
  let tracks = try JSONDecoder().decode(AudioTracks.self, from: Data(contentsOf: tracksURL))
  let preferences = try #require(UserDefaults(suiteName: "app.minutes.meetings"))
  let corrections =
    preferences.data(forKey: "transcriptCorrections").flatMap {
      try? JSONDecoder().decode(TranscriptCorrections.self, from: $0)
    } ?? .init()
  let options = original.transcriptionOptions ?? .init()
  var regenerated = original.reprocessedDraft(options: options)
  regenerated.utterances = try await TranscriptionService().transcribe(
    tracks, options: options, corrections: corrections
  ) { print($0) }
  let local = regenerated.utterances.filter { $0.speaker == "You" }
  let remote = regenerated.utterances.filter { $0.speaker != "You" }
  try #require(!local.isEmpty)
  try #require(!remote.isEmpty)
  regenerated.speakerNames["You"] = original.speakerNames["You"]
  regenerated.duration = max(original.duration, regenerated.utterances.map(\.end).max() ?? 0)
  regenerated.transcribedAt = Date()
  try #require(try Data(contentsOf: meetingURL) == originalData)
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  try originalData.write(to: output.appendingPathComponent("original.json"), options: .atomic)
  try MeetingStore(directory: output).save(regenerated)
  try MarkdownExporter.render(regenerated).write(
    to: output.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
  print(
    "RECOVERY VERIFIED: local=\(local.count), remote=\(remote.count), speakers=\(Set(remote.map(\.speaker)).sorted())"
  )
}
