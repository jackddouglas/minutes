import AVFoundation
import Foundation
import Testing

@testable import Minutes

private func makeAudio(_ url: URL, seconds: Int) throws {
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
  let buffer = try #require(
    AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 16_000)))
  buffer.frameLength = buffer.frameCapacity
  for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = 0.25 }
  let file = try AVAudioFile(forWriting: url, settings: format.settings)
  try file.write(from: buffer)
}

@Test func pairedImportRetainsBothTracksForRetry() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let remote = root.appendingPathComponent("remote.caf")
  let microphone = root.appendingPathComponent("mic.caf")
  try makeAudio(remote, seconds: 1)
  try makeAudio(microphone, seconds: 2)
  let directory = root.appendingPathComponent("retained")
  let imported = try RecordingImport.retain(remote: remote, microphone: microphone, in: directory)
  #expect(imported.duration == 2)
  try FileManager.default.removeItem(at: remote)
  try FileManager.default.removeItem(at: microphone)
  let saved = try JSONDecoder().decode(
    AudioTracks.self, from: Data(contentsOf: directory.appendingPathComponent("tracks.json")))
  #expect(saved.remote == imported.tracks.remote)
  #expect(saved.microphone == imported.tracks.microphone)
  #expect(saved.remoteOffset == 0)
  #expect(saved.microphoneOffset == 0)
  #expect(try AVAudioFile(forReading: #require(saved.remote)).length == 16_000)
  #expect(try AVAudioFile(forReading: #require(saved.microphone)).length == 32_000)
}

@Test func singleImportAndInvalidPair() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let remote = root.appendingPathComponent("remote.caf")
  try makeAudio(remote, seconds: 1)
  let imported = try RecordingImport.retain(
    remote: remote, microphone: nil, in: root.appendingPathComponent("single"))
  #expect(imported.duration == 1)
  #expect(imported.tracks.microphone == nil)
  let rejected = root.appendingPathComponent("rejected")
  #expect(throws: (any Error).self) {
    try RecordingImport.retain(remote: remote, microphone: remote, in: rejected)
  }
  let invalid = root.appendingPathComponent("invalid.caf")
  try Data("not audio".utf8).write(to: invalid)
  #expect(throws: (any Error).self) {
    try RecordingImport.retain(remote: remote, microphone: invalid, in: rejected)
  }
  #expect(!FileManager.default.fileExists(atPath: rejected.path))
}

@Test @MainActor func pairedPlaybackLoadsSeeksPausesAndStops() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  let remote = root.appendingPathComponent("remote.caf")
  let microphone = root.appendingPathComponent("mic.caf")
  try makeAudio(remote, seconds: 1)
  try makeAudio(microphone, seconds: 2)
  let playback = RecordingPlayback()
  defer { playback.stop() }
  try playback.load(
    AudioTracks(remote: remote, microphone: microphone, remoteOffset: 0, microphoneOffset: 1))
  #expect(playback.duration == 3)
  try playback.play(from: 0, until: 0.2)
  for _ in 0..<30 where playback.isPlaying {
    try await Task.sleep(for: .milliseconds(100))
  }
  #expect(!playback.isPlaying)
  #expect(playback.position == 0.2)
  // A new clip must replace the old stop boundary.
  try playback.play(from: 0.1, until: 0.15)
  try playback.play(from: 0.1, until: 0.4)
  for _ in 0..<30 where playback.isPlaying {
    try await Task.sleep(for: .milliseconds(100))
  }
  #expect(!playback.isPlaying)
  #expect(playback.position == 0.4)
  try playback.play(from: 0.5)
  #expect(playback.isPlaying)
  #expect(playback.position == 0.5)
  playback.pause()
  #expect(!playback.isPlaying)
  try playback.play(from: 2.9)
  // Bounded wait for the real player timeline to reach the end.
  for _ in 0..<30 where playback.isPlaying {
    try await Task.sleep(for: .milliseconds(100))
  }
  #expect(!playback.isPlaying)
  #expect(playback.position == 3)
  try playback.play(from: 0)
  #expect(playback.isPlaying)
  playback.stop()
  #expect(!playback.isPlaying)
  #expect(playback.position == 0)
  #expect(playback.duration == 0)
}
