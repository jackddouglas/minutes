import AVFoundation
import FluidAudio
import Foundation
import MinutesCore
import Testing

@testable import Minutes

// Local opt-in diagnostic. Source paths and personal transcripts are never checked in.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MINUTES_BOUNDARY_EVAL"] == "1"))
func evaluateSpeakerBoundaries() async throws {
  let env = ProcessInfo.processInfo.environment
  let source = URL(fileURLWithPath: try #require(env["MINUTES_BOUNDARY_AUDIO"]))
  let destination = URL(fileURLWithPath: try #require(env["MINUTES_BOUNDARY_OUTPUT"]))
  try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
  let start = Double(env["MINUTES_BOUNDARY_START"] ?? "780") ?? 780
  let duration = Double(env["MINUTES_BOUNDARY_DURATION"] ?? "100") ?? 100
  let file = try AVAudioFile(forReading: source)
  file.framePosition = AVAudioFramePosition(start * file.processingFormat.sampleRate)
  let buffer = try #require(
    AVAudioPCMBuffer(
      pcmFormat: file.processingFormat,
      frameCapacity: AVAudioFrameCount(duration * file.processingFormat.sampleRate)))
  try file.read(into: buffer)
  let excerpt = destination.appendingPathComponent("excerpt.caf")
  do {
    let output = try AVAudioFile(forWriting: excerpt, settings: file.processingFormat.settings)
    try output.write(from: buffer)
  }
  let modelDirectory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Minutes/Models")
  let models = try await OfflineDiarizerModels.load(
    from: modelDirectory.appendingPathComponent("Diarization"))
  var config = try TranscriptionService.diarizationConfig(
    .init(
      quality: .thorough, expectedSystemSpeakers: Int(env["MINUTES_BOUNDARY_SPEAKERS"] ?? "2")))
  config.postProcessing.exclusiveSegments = false
  let diarizer = OfflineDiarizerManager(config: config)
  diarizer.initialize(models: models)
  let result = try await diarizer.process(excerpt)
  let spans: [[String: Any]] = result.segments.map {
    [
      "speaker": $0.speakerId, "start": Double($0.startTimeSeconds) + start,
      "end": Double($0.endTimeSeconds) + start, "quality": $0.qualityScore,
    ]
  }
  try JSONSerialization.data(withJSONObject: spans, options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appendingPathComponent("raw-spans.json"))
  let speech = try await AsrModels.downloadAndLoad(to: modelDirectory, version: .v3)
  let asr = AsrManager(config: .default)
  try await asr.loadModels(speech)
  var decoderState = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
  let text = try await asr.transcribe(excerpt, decoderState: &decoderState)
  let words = try WordTiming.words(try #require(text.tokenTimings)).map {
    TimedWord(text: $0.text, start: $0.start + start, end: $0.end + start)
  }
  try JSONEncoder().encode(words).write(
    to: destination.appendingPathComponent("excerpt-words.json"))
  let passages = try await TranscriptionService().transcribe(
    AudioTracks(remote: excerpt, microphone: nil, remoteOffset: start, microphoneOffset: 0),
    options: .init(
      quality: .thorough, expectedSystemSpeakers: Int(env["MINUTES_BOUNDARY_SPEAKERS"] ?? "2"))
  ) { print($0) }
  try JSONEncoder().encode(passages).write(to: destination.appendingPathComponent("passages.json"))
  print("Boundary diagnostic: \(spans.count) raw spans, \(words.count) words; \(destination.path)")
  #expect(!spans.isEmpty)
  #expect(!words.isEmpty)
}
