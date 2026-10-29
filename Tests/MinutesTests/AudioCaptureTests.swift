import AVFoundation
import Testing

@testable import Minutes

private func sample(at time: Double) throws -> CMSampleBuffer {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
  pcm.frameLength = 16_000
  for index in 0..<16_000 { pcm.floatChannelData![0][index] = 0.25 }
  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: 16_000),
    presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 16_000),
    decodeTimeStamp: .invalid)
  var buffer: CMSampleBuffer?
  let status = CMSampleBufferCreate(
    allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true,
    makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
    sampleCount: 16_000, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
    sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
  #expect(status == noErr)
  let result = try #require(buffer)
  #expect(
    CMSampleBufferSetDataBufferFromAudioBufferList(
      result, blockBufferAllocator: kCFAllocatorDefault,
      blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList)
      == noErr)
  return result
}

@Test func capturePreservesSilenceAndTrackOffsets() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let sink = AudioSink(directory: directory)
  sink.consume(try sample(at: 100), of: .audio)
  sink.consume(try sample(at: 102), of: .microphone)
  sink.consume(try sample(at: 103), of: .audio)
  let tracks = try sink.finish()
  #expect(tracks.remoteOffset == 0)
  #expect(tracks.microphoneOffset == 2)
  let file = try AVAudioFile(forReading: #require(tracks.remote))
  #expect(file.length == 64_000)
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 64_000))
  try file.read(into: buffer)
  #expect(buffer.floatChannelData![0][0] == 0.25)
  #expect(buffer.floatChannelData![0][20_000] == 0)
  #expect(buffer.floatChannelData![0][50_000] == 0.25)
  #expect(
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("tracks.json").path))
}

@Test func emptyCaptureFailsExplicitly() {
  let sink = AudioSink(directory: FileManager.default.temporaryDirectory)
  #expect(throws: (any Error).self) { try sink.finish() }
}

@Test func tapPCMAndMicrophoneUseSharedHostTimeline() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
  let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
  pcm.frameLength = 480
  for channel in 0..<2 {
    for frame in 0..<480 { pcm.floatChannelData![channel][frame] = 0.125 }
  }
  let sink = AudioSink(directory: directory)
  let hostTime = AVAudioTime.hostTime(forSeconds: 100)
  sink.consume(pcm, at: AVAudioTime.seconds(forHostTime: hostTime), of: .audio)
  // Capture-session timestamps are converted to host time before reaching the sink.
  sink.consume(try sample(at: 8), of: .microphone, at: 100.25)
  let tracks = try sink.finish()
  #expect(abs(tracks.microphoneOffset - 0.25) < 0.0001)
  let remote = try AVAudioFile(forReading: #require(tracks.remote))
  #expect(remote.length == 480)
  #expect(remote.processingFormat.channelCount == 2)
  let restored = try #require(
    AVAudioPCMBuffer(pcmFormat: remote.processingFormat, frameCapacity: 480))
  try remote.read(into: restored)
  #expect(restored.floatChannelData![1][479] == 0.125)
}

@Test func closedCaptureWriterFailsWithoutAborting() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let sink = AudioSink(directory: directory)
  sink.consume(try sample(at: 100), of: .microphone)
  let writer = try #require(sink.files[.microphone])
  writer.close()
  sink.consume(try sample(at: 101), of: .microphone)
  #expect(sink.failure != nil)
  #expect(throws: (any Error).self) { try sink.finish() }
  let retained = try AVAudioFile(forReading: directory.appendingPathComponent("microphone.caf"))
  #expect(retained.length == 16_000)
  #expect(
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("tracks.json").path))
}

// Fault injection for the Objective-C exception in the supplied crash report.
// Swift do/catch cannot intercept a failure raised by this nonthrowing getter.
private final class PositionUnavailableAudioFile: AVAudioFile, @unchecked Sendable {
  override var framePosition: AVAudioFramePosition {
    get {
      NSException(
        name: .internalInconsistencyException,
        reason: "Injected AVAudioFile.framePosition failure", userInfo: nil
      ).raise()
      return 0
    }
    set { super.framePosition = newValue }
  }
}

@Test func captureDoesNotQueryWriterPosition() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let sink = AudioSink(directory: directory)
  sink.files[.microphone] = try PositionUnavailableAudioFile(
    forWriting: directory.appendingPathComponent("microphone.caf"), settings: format.settings)
  sink.firstTimes[.microphone] = 100
  sink.consume(try sample(at: 100), of: .microphone)
  sink.consume(try sample(at: 100.5), of: .audio)
  sink.consume(try sample(at: 103), of: .microphone)
  sink.consume(try sample(at: 104), of: .microphone)
  sink.consume(try sample(at: 102.5), of: .audio)
  let tracks = try sink.finish()
  #expect(tracks.microphoneOffset == 0)
  #expect(tracks.remoteOffset == 0.5)
  let file = try AVAudioFile(forReading: #require(tracks.microphone))
  #expect(file.length == 80_000)
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192))
  var samples: [Float] = []
  while samples.count < Int(file.length) {
    try file.read(
      into: buffer, frameCount: AVAudioFrameCount(min(8192, Int(file.length) - samples.count)))
    try #require(buffer.frameLength > 0)
    samples.append(
      contentsOf: UnsafeBufferPointer(
        start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
  }
  #expect(samples[0] == 0.25)
  #expect(samples[20_000] == 0)
  #expect(samples[47_999] == 0)
  #expect(samples[48_000] == 0.25)
  #expect(samples[79_999] == 0.25)
  let remote = try AVAudioFile(forReading: #require(tracks.remote))
  #expect(remote.length == 48_000)
}

@Test func invalidDeviceFormatsAreRejectedBeforeAVFoundation() throws {
  var description = AudioStreamBasicDescription()
  description.mFormatID = kAudioFormatLinearPCM
  description.mChannelsPerFrame = 4
  for rate in [0.0, -1, Double.nan, Double.infinity] {
    description.mSampleRate = rate
    #expect(throws: (any Error).self) { try CaptureAudioFormat.validate(description) }
  }
  description.mSampleRate = 48000
  try CaptureAudioFormat.validate(description)
  description.mChannelsPerFrame = 0
  #expect(throws: (any Error).self) { try CaptureAudioFormat.validate(description) }
}

@Test func microphoneFindsSignalOnChannelsThreeAndFour() throws {
  var description = AudioStreamBasicDescription(
    mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
    mChannelsPerFrame: 4, mBitsPerChannel: 32, mReserved: 0)
  let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Quadraphonic))
  let format = try #require(AVAudioFormat(streamDescription: &description, channelLayout: layout))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
  buffer.frameLength = 480
  for frame in 0..<480 {
    buffer.floatChannelData![0][frame] = 0
    buffer.floatChannelData![1][frame] = 0
    buffer.floatChannelData![2][frame] = 0.5
    buffer.floatChannelData![3][frame] = -0.5
  }
  let mono = try CaptureAudioFormat.microphone(buffer)
  #expect(mono.format.channelCount == 1)
  #expect(mono.frameLength == 480)
  #expect(mono.floatChannelData![0][479] == 0.5)
  for frame in 0..<480 { buffer.floatChannelData![3][frame] = 0.75 }
  let fourthChannel = try CaptureAudioFormat.microphone(buffer)
  #expect(fourthChannel.floatChannelData![0][0] == 0.75)
}

@Test func silentRecordingIsRetainedWithRoutingError() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
  buffer.frameLength = 480
  for frame in 0..<480 { buffer.floatChannelData![0][frame] = 0 }
  let sink = AudioSink(directory: directory)
  sink.consume(buffer, at: 100, of: .microphone)
  #expect(sink.failure == nil)
  do {
    _ = try sink.finish()
    Issue.record("Expected a routing error")
  } catch {
    #expect(error.localizedDescription.contains("Audio MIDI Setup"))
  }
  #expect(try AVAudioFile(forReading: directory.appendingPathComponent("microphone.caf")).length == 480)
}
