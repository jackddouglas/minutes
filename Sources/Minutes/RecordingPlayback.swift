import AVFoundation
import Observation

struct PlaybackPosition: Equatable {
  let fileTime: Double
  let delay: Double

  static func at(_ time: Double, offset: Double, duration: Double) -> Self? {
    guard time.isFinite, offset.isFinite, duration.isFinite,
      time >= 0, offset >= 0, duration > 0, time < offset + duration
    else { return nil }
    return Self(fileTime: max(0, time - offset), delay: max(0, offset - time))
  }
}

@MainActor @Observable
final class RecordingPlayback {
  private(set) var isPlaying = false
  private(set) var position: Double = 0
  private(set) var duration: Double = 0
  private var players: [(player: AVAudioPlayer, offset: Double)] = []
  private var updateTask: Task<Void, Never>?

  func load(_ tracks: AudioTracks) throws {
    stop()
    var loaded: [(player: AVAudioPlayer, offset: Double)] = []
    for (url, offset) in [
      (tracks.remote, tracks.remoteOffset), (tracks.microphone, tracks.microphoneOffset),
    ] {
      guard let url else { continue }
      guard offset.isFinite, offset >= 0 else {
        throw MinutesError.message("This recording has invalid track timing.")
      }
      let player = try AVAudioPlayer(contentsOf: url)
      guard player.prepareToPlay() else {
        throw MinutesError.message("Could not prepare \(url.lastPathComponent) for playback.")
      }
      loaded.append((player, offset))
    }
    guard !loaded.isEmpty else {
      throw MinutesError.message("No recording is available for playback.")
    }
    players = loaded
    duration = loaded.map { $0.offset + $0.player.duration }.max() ?? 0
  }

  func play(from time: Double, until end: Double? = nil) throws {
    pause()
    guard time.isFinite, !players.isEmpty else { return }
    position = min(max(0, time), duration)
    let stopAt = end.map { $0.isFinite ? min(duration, max(position, $0)) : duration } ?? duration
    guard position < stopAt else { return }
    let leadIn = 0.1
    let deviceStart = players[0].player.deviceCurrentTime + leadIn
    for (player, offset) in players {
      guard let seek = PlaybackPosition.at(position, offset: offset, duration: player.duration)
      else { continue }
      player.currentTime = seek.fileTime
      guard player.play(atTime: deviceStart + seek.delay) else {
        pause()
        throw MinutesError.message("The recording could not be played.")
      }
    }
    isPlaying = true
    let initialPosition = position
    let started = ProcessInfo.processInfo.systemUptime + leadIn
    updateTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard let self else { return }
        self.position = min(
          stopAt, initialPosition + max(0, ProcessInfo.processInfo.systemUptime - started))
        if self.position >= stopAt {
          self.pause()
          return
        }
      }
    }
  }

  func pause() {
    updateTask?.cancel()
    updateTask = nil
    for (player, _) in players { player.stop() }
    isPlaying = false
  }

  func stop() {
    pause()
    players = []
    position = 0
    duration = 0
  }
}
