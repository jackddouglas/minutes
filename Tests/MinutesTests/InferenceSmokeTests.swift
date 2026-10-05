import AVFoundation
import Foundation
import MinutesCore
import Testing

@testable import Minutes

// Explicit opt-in: downloads real models and runs Core ML on synthesized speech.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MINUTES_INFERENCE_SMOKE"] == "1"))
func localInferenceAndAutomaticMarkdown() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "minutes-inference-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let turns = [
    (
      "Daniel",
      "Welcome to the project meeting. Today we need to discuss the launch schedule and the customer feedback. I think we should finish the audio recording feature before we start adding new integrations. The first release needs to be simple and reliable."
    ),
    (
      "Samantha",
      "That sounds like a good plan. I have reviewed the customer feedback and most people want clear transcripts with speaker names. We should also make sure the notes are exported automatically so nobody has to remember to save them after a meeting."
    ),
    (
      "Daniel",
      "I agree with your suggestion. Let us schedule a review for next Friday and test the app with a small group first. I will take responsibility for the audio capture and make sure we can recover recordings when something goes wrong."
    ),
    (
      "Samantha",
      "Perfect. I will work on the documentation and prepare the test checklist. We should test both short meetings and longer conversations with several participants. Thank you for the update. I will share the final notes after our review next Friday."
    ),
  ]
  let audio = directory.appendingPathComponent("synthetic-meeting.caf")
  var writer: AVAudioFile?
  for (index, turn) in turns.enumerated() {
    let url = directory.appendingPathComponent("turn-\(index).aiff")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", turn.0, "-r", "155", "-o", url.path, turn.1]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let file = try AVAudioFile(forReading: url)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    if writer == nil {
      writer = try AVAudioFile(forWriting: audio, settings: file.processingFormat.settings)
    }
    try writer?.write(from: buffer)
  }
  writer = nil
  let tracks = AudioTracks(remote: audio, microphone: nil, remoteOffset: 0, microphoneOffset: 0)
  let utterances = try await TranscriptionService().transcribe(tracks) { message in print(message) }
  #expect(!utterances.isEmpty)
  #expect(Set(utterances.map(\.speaker)) == ["Speaker 1", "Speaker 2"])
  let text = utterances.map(\.text).joined(separator: " ").lowercased()
  #expect(text.contains("project"))
  #expect(text.contains("friday"))
  let meeting = Meeting(
    title: "Synthetic verification meeting", duration: utterances.last?.end ?? 0,
    utterances: utterances)
  let export = try MarkdownExporter.write(meeting, to: directory)
  #expect(try String(contentsOf: export, encoding: .utf8).contains("## Transcript"))
  print("Inference verification artifact: \(export.path)")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MINUTES_INFERENCE_SMOKE"] == "1"))
func pairedImportTranscribesBothVoices() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "minutes-paired-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let remote = directory.appendingPathComponent("system.aiff")
  let microphone = directory.appendingPathComponent("microphone.aiff")
  for (url, voice, text) in [
    (
      remote, "Daniel",
      "Welcome to the project meeting. We need to discuss the launch schedule and customer feedback. The first release needs to be simple and reliable."
    ),
    (
      microphone, "Samantha",
      "I will prepare the documentation and write the checklist. We should test the audio recordings before our review next Friday. Thank you for the update."
    ),
  ] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-v", voice, "-r", "155", "-o", url.path, text]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
  }
  let imported = try RecordingImport.retain(
    remote: remote, microphone: microphone, in: directory.appendingPathComponent("retained"))
  let utterances = try await TranscriptionService().transcribe(imported.tracks) { print($0) }
  let localText = utterances.filter { $0.speaker == "You" }.map(\.text).joined(separator: " ")
  let remoteText = utterances.filter { $0.speaker.hasPrefix("Speaker ") }.map(\.text).joined(
    separator: " ")
  #expect(localText.lowercased().contains("documentation"))
  #expect(remoteText.lowercased().contains("launch"))
  #expect(utterances.map(\.start) == utterances.map(\.start).sorted())
  let meeting = Meeting(title: "Paired import", duration: imported.duration, utterances: utterances)
  let exported = try MarkdownExporter.write(meeting, to: directory)
  let markdown = try String(contentsOf: exported, encoding: .utf8)
  #expect(markdown.contains("**You**"))
  #expect(markdown.contains("**Speaker 1**"))
}
