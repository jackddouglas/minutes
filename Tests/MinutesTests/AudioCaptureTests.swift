import AVFoundation
import ScreenCaptureKit
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
