import Foundation
import Testing

@testable import Minutes

@Test func playbackSeeksOnSharedTimeline() {
  #expect(
    PlaybackPosition.at(6, offset: 2, duration: 10) == PlaybackPosition(fileTime: 4, delay: 0))
  #expect(
    PlaybackPosition.at(1, offset: 3, duration: 10) == PlaybackPosition(fileTime: 0, delay: 2))
  #expect(PlaybackPosition.at(12, offset: 2, duration: 10) == nil)
  #expect(PlaybackPosition.at(.nan, offset: 0, duration: 10) == nil)
  #expect(PlaybackPosition.at(0, offset: -1, duration: 10) == nil)
}

@Test @MainActor func unavailablePlaybackFailsWithoutStarting() throws {
  let playback = RecordingPlayback()
  #expect(throws: (any Error).self) {
    try playback.load(
      AudioTracks(remote: nil, microphone: nil, remoteOffset: 0, microphoneOffset: 0))
  }
  #expect(throws: (any Error).self) {
    try playback.load(
      AudioTracks(
        remote: URL(fileURLWithPath: "/tmp/missing-scribe-\(UUID().uuidString).caf"),
        microphone: nil, remoteOffset: 0, microphoneOffset: 0))
  }
  #expect(!playback.isPlaying)
  #expect(playback.duration == 0)
}
