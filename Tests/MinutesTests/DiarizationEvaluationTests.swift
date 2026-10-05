import AVFoundation
import Foundation
import MinutesCore
import Testing

@testable import Minutes

// Opt-in, local-only evaluation. Optional system-track URL is supplied through
// the environment; no personal recording path or transcript is checked in.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MINUTES_DIARIZATION_EVAL"] == "1"))
func compareDiarizationModes() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "minutes-diarization-evaluation-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let synthetic = directory.appendingPathComponent("three-speakers.caf")
  var writer: AVAudioFile?
  var references: [(speaker: Int, start: Double, end: Double)] = []
  var cursor = 0.0
  let voices = ["Daniel", "Samantha", "Karen"]
  let scripts = [
    "Welcome to the project meeting. Today we need to discuss the launch schedule and the customer feedback. I think the first release should be simple and reliable.",
    "I have reviewed the customer feedback. Most people want clear transcripts with speaker names. We should also make sure the notes are exported automatically after every meeting.",
    "That sounds like a good plan. I will prepare the documentation and the test checklist. Let us schedule another review next Friday before we release the recording feature.",
  ]
  for turn in 0..<6 {
    let speaker = turn % 3
    let url = directory.appendingPathComponent("turn-\(turn).aiff")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-v", voices[speaker], "-r", "155", "-o", url.path, scripts[speaker]]
    try say.run()
    say.waitUntilExit()
    #expect(say.terminationStatus == 0)
    let file = try AVAudioFile(forReading: url)
    if writer == nil {
      writer = try AVAudioFile(forWriting: synthetic, settings: file.processingFormat.settings)
    }
    #expect(writer?.processingFormat.sampleRate == file.processingFormat.sampleRate)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
    try file.read(into: buffer)
    try writer?.write(from: buffer)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    references.append((speaker, cursor, cursor + duration))
    cursor += duration
    let silence = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * 8)))
    silence.frameLength = silence.frameCapacity
    for channel in 0..<Int(silence.format.channelCount) {
      silence.floatChannelData![channel].initialize(repeating: 0, count: Int(silence.frameLength))
    }
    try writer?.write(from: silence)
    cursor += 8
  }
  writer = nil
  var inputs: [(String, URL)] = [("synthetic", synthetic)]
  if let source = ProcessInfo.processInfo.environment["MINUTES_EVAL_SYSTEM_AUDIO"] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: source))
    file.framePosition = AVAudioFramePosition(200 * file.processingFormat.sampleRate)
    let buffer = try #require(
      AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(120 * file.processingFormat.sampleRate)))
    try file.read(into: buffer)
    #expect(buffer.frameLength > 0)
    let excerpt = directory.appendingPathComponent("system-excerpt-200-320.caf")
    let out = try AVAudioFile(forWriting: excerpt, settings: file.processingFormat.settings)
    try out.write(from: buffer)
    inputs.append(("recording-excerpt", excerpt))
  }
  var reports: [[String: Any]] = []
  for (name, audio) in inputs {
    for quality in TranscriptionOptions.Quality.allCases {
      let start = Date()
      let utterances = try await TranscriptionService().transcribe(
        AudioTracks(remote: audio, microphone: nil, remoteOffset: 0, microphoneOffset: 0),
        options: .init(quality: quality, expectedSystemSpeakers: 3)
      ) { print("\(name)/\(quality.rawValue): \($0)") }
      let words = utterances.flatMap { $0.words ?? [] }
      #expect(!words.isEmpty)
      #expect(words.allSatisfy { $0.end - $0.start < 5 })
      var report: [String: Any] = [
        "input": name, "quality": quality.rawValue, "seconds": Date().timeIntervalSince(start),
        "words": words.count,
        "unknownWords": utterances.filter { $0.speaker == "Unassigned" }.flatMap { $0.words ?? [] }
          .count,
        "detectedSpeakers": Set(utterances.map(\.speaker).filter { $0 != "Unassigned" }).count,
        "maxWordSeconds": words.map { $0.end - $0.start }.max() ?? 0,
      ]
      if name == "synthetic" {
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var scored = 0
        var matrix = Array(repeating: Array(repeating: 0, count: 3), count: 3)
        for u in utterances {
          for word in u.words ?? [] {
            guard
              let reference = references.first(where: {
                word.start >= $0.start && word.start < $0.end
              })
            else { continue }
            scored += 1
            if let label = Int(u.speaker.replacingOccurrences(of: "Speaker ", with: "")),
              (1...3).contains(label)
            {
              matrix[reference.speaker][label - 1] += 1
            }
          }
        }
        let correct =
          permutations.map { p in (0..<3).reduce(0) { $0 + matrix[$1][p[$1]] } }.max() ?? 0
        report["speakerAgreementOnSyntheticWords"] = Double(correct) / Double(max(1, scored))
      }
      let encoded = try JSONEncoder().encode(utterances)
      try encoded.write(to: directory.appendingPathComponent("\(name)-\(quality.rawValue).json"))
      reports.append(report)
      print(
        String(
          data: try JSONSerialization.data(withJSONObject: report, options: .sortedKeys),
          encoding: .utf8)!)
    }
  }
  try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(
    to: directory.appendingPathComponent("report.json"))
  print("Diarization comparison report: \(directory.path)/report.json")
}
