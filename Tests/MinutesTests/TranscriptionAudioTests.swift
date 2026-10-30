import AVFoundation
import FluidAudio
import Testing

@testable import Minutes

@Test func discreteStereoSurvivesCaptureAndBothTranscriptionConverters() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let standard = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
  var description = standard.streamDescription.pointee
  let layout = try #require(
    AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 2))
  let format = try #require(AVAudioFormat(streamDescription: &description, channelLayout: layout))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
  buffer.frameLength = 48000
  for frame in 0..<48000 {
    let sample = Float(sin(Double(frame) * 2 * .pi * 440 / 48000)) * 0.25
    buffer.floatChannelData![0][frame] = sample
    buffer.floatChannelData![1][frame] = sample * 0.5
  }
  let legacy = directory.appendingPathComponent("legacy.caf")
  do {
    let writer = try AVAudioFile(forWriting: legacy, settings: format.settings)
    try writer.write(from: buffer)
  }
  let original = try Data(contentsOf: legacy)
  let prepared = try TranscriptionAudio(legacy)
  defer { prepared.cleanup() }
  #expect(prepared.url != legacy)
  #expect(try Data(contentsOf: legacy) == original)
  let repaired = try AVAudioFile(forReading: prepared.url)
  #expect(repaired.length == 48000)
  let samples = try #require(
    AVAudioPCMBuffer(pcmFormat: repaired.processingFormat, frameCapacity: 48000))
  try repaired.read(into: samples)
  for channel in 0..<2 {
    for frame in 0..<48000 {
      #expect(samples.floatChannelData![channel][frame] == buffer.floatChannelData![channel][frame])
    }
  }

  func checkConverters(_ url: URL) throws {
    let short = try AudioConverter().resampleAudioFile(url)
    #expect(short.count > 15000)
    #expect(short.map { abs($0) }.max()! > 0.1)
    let (long, _) = try AudioSourceFactory().makeDiskBackedSource(
      from: url, targetSampleRate: 16000)
    defer { long.cleanup() }
    var values = [Float](repeating: 0, count: long.sampleCount)
    try values.withUnsafeMutableBufferPointer {
      try long.copySamples(into: $0.baseAddress!, offset: 0, count: $0.count)
    }
    #expect(values.count > 15000)
    #expect(values.map { abs($0) }.max()! > 0.1)
  }
  try checkConverters(prepared.url)
  let unchanged = try TranscriptionAudio(prepared.url)
  #expect(unchanged.url == prepared.url)
  unchanged.cleanup()
  #expect(FileManager.default.fileExists(atPath: prepared.url.path))

  let sink = AudioSink(directory: directory)
  let callback = AppAudioTap.makeIOCallback(format: format, sink: sink)
  var timestamp = AudioTimeStamp()
  timestamp.mHostTime = AVAudioTime.hostTime(forSeconds: 100)
  timestamp.mFlags = .hostTimeValid
  withUnsafePointer(to: &timestamp) { time in
    callback(time, buffer.audioBufferList, time, buffer.mutableAudioBufferList, time)
  }
  let tracks = try sink.finish()
  let captured = try #require(tracks.remote)
  try checkConverters(captured)
  let capturedPrepared = try TranscriptionAudio(captured)
  #expect(capturedPrepared.url == captured)
  prepared.cleanup()
  #expect(!FileManager.default.fileExists(atPath: prepared.url.path))
  #expect(try Data(contentsOf: legacy) == original)
}

@Test(arguments: [1, 4])
func transcriptionPreparationPreservesOtherChannelLayouts(channels: Int) throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  var description = AudioStreamBasicDescription(
    mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
      | kAudioFormatFlagIsNonInterleaved,
    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
    mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
  let layout = try #require(
    AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)))
  let format = try #require(AVAudioFormat(streamDescription: &description, channelLayout: layout))
  let source = directory.appendingPathComponent("other.caf")
  do {
    let writer = try AVAudioFile(forWriting: source, settings: format.settings)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48))
    buffer.frameLength = 48
    for channel in 0..<channels {
      for frame in 0..<48 { buffer.floatChannelData![channel][frame] = 0.125 }
    }
    try writer.write(from: buffer)
  }
  let original = try Data(contentsOf: source)
  let prepared = try TranscriptionAudio(source)
  #expect(prepared.url == source)
  prepared.cleanup()
  #expect(try Data(contentsOf: source) == original)
}
