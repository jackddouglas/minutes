import AVFoundation

/// Older process-tap recordings label their stereo mix as discrete channels,
/// which AVAudioConverter drops when mixing to mono. Repair a temporary copy
/// for both recognition and diarization, retaining the original recording.
struct TranscriptionAudio {
  let url: URL
  private let temporaryDirectory: URL?

  init(_ source: URL) throws {
    let file = try AVAudioFile(forReading: source)
    let format = file.processingFormat
    guard format.channelCount == 2,
      format.channelLayout?.layoutTag == (kAudioChannelLayoutTag_DiscreteInOrder | 2)
    else {
      url = source
      temporaryDirectory = nil
      return
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("stereo.caf")
    do {
      let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)!
      let writer = try AVAudioFile(forWriting: destination, settings: stereo.settings)
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384) else {
        throw MinutesError.message("Could not prepare system audio for transcription.")
      }
      while file.framePosition < file.length {
        try file.read(into: buffer)
        guard buffer.frameLength > 0 else { break }
        try writer.write(from: CaptureAudioFormat.stereo(buffer, channels: [0, 1]))
      }
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
    url = destination
    temporaryDirectory = directory
  }

  func cleanup() {
    if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
  }
}
