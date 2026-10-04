import AVFoundation
import Foundation

enum RecordingImport {
  static func recordingDate(_ url: URL) async -> Date? {
    let asset = AVURLAsset(url: url)
    if let item = try? await asset.load(.creationDate),
      let date = try? await item.load(.dateValue)
    {
      return date
    }
    return try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
  }
  static func retain(remote: URL, microphone: URL?, in directory: URL) throws
    -> (tracks: AudioTracks, duration: Double)
  {
    if let microphone,
      remote.resolvingSymlinksInPath().standardizedFileURL
        == microphone.resolvingSymlinksInPath().standardizedFileURL
    {
      throw MinutesError.message("Choose different files for system audio and microphone audio.")
    }
    // Validate every source before copying anything into the library.
    func duration(_ url: URL) throws -> Double {
      let file = try AVAudioFile(forReading: url)
      guard file.length > 0, file.processingFormat.sampleRate > 0 else {
        throw MinutesError.message("The audio file \(url.lastPathComponent) is empty.")
      }
      return Double(file.length) / file.processingFormat.sampleRate
    }
    let remoteDuration = try duration(remote)
    let microphoneDuration = try microphone.map(duration) ?? 0
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func copy(_ source: URL, name: String) throws -> URL {
      let destination = directory.appendingPathComponent(name).appendingPathExtension(
        source.pathExtension)
      try FileManager.default.copyItem(at: source, to: destination)
      return destination
    }
    let remoteCopy = try copy(remote, name: "system")
    let microphoneCopy = try microphone.map { try copy($0, name: "microphone") }
    let tracks = AudioTracks(
      remote: remoteCopy, microphone: microphoneCopy, remoteOffset: 0, microphoneOffset: 0)
    try JSONEncoder().encode(tracks).write(
      to: directory.appendingPathComponent("tracks.json"), options: .atomic)
    return (tracks, max(remoteDuration, microphoneDuration))
  }
}
