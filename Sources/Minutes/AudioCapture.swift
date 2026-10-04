import AVFoundation
import ScreenCaptureKit

struct AudioTracks: Codable, Sendable {
  var remote: URL?
  var microphone: URL?
  var remoteOffset: Double
  var microphoneOffset: Double
}

enum MinutesError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

// All mutable state in this sink is confined to the stream's serial callback queue.
final class AudioSink: NSObject, SCStreamOutput, @unchecked Sendable {
  let directory: URL
  var files: [SCStreamOutputType: AVAudioFile] = [:]
  var firstTimes: [SCStreamOutputType: Double] = [:]
  var failure: Error?
  let onFailure: (@Sendable (String) -> Void)?

  init(directory: URL, onFailure: (@Sendable (String) -> Void)? = nil) {
    self.directory = directory
    self.onFailure = onFailure
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    consume(sampleBuffer, of: outputType)
  }

  func consume(_ sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
    guard failure == nil, outputType == .audio || outputType == .microphone,
      sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
      let description = sampleBuffer.formatDescription,
      let format = AVAudioFormat(cmAudioFormatDescription: description) as AVAudioFormat?,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0,
      frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList)
    guard status == noErr else {
      failure = MinutesError.message("Audio buffer conversion failed (\(status)).")
      onFailure?(failure!.localizedDescription)
      return
    }
    do {
      let time = sampleBuffer.presentationTimeStamp.seconds
      guard time.isFinite else {
        throw MinutesError.message("The audio device returned an invalid timestamp.")
      }
      if files[outputType] == nil {
        let name = outputType == .audio ? "remote.caf" : "microphone.caf"
        files[outputType] = try AVAudioFile(
          forWriting: directory.appendingPathComponent(name),
          settings: format.settings, commonFormat: format.commonFormat,
          interleaved: format.isInterleaved)
        firstTimes[outputType] = time
      }
      guard let file = files[outputType], let first = firstTimes[outputType] else { return }
      // Preserve silence between callbacks so independent tracks stay synchronized.
      let expected = AVAudioFramePosition(max(0, (time - first) * format.sampleRate))
      var gap = expected - file.framePosition
      if gap > AVAudioFramePosition(format.sampleRate * 60) {
        throw MinutesError.message(
          "Audio capture was interrupted for over a minute. The partial recording is retained.")
      }
      while gap > 1 {
        let count = AVAudioFrameCount(min(gap, 8192))
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
        silence.frameLength = count
        for audioBuffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
          if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
        }
        try file.write(from: silence)
        gap -= AVAudioFramePosition(count)
      }
      try file.write(from: buffer)
    } catch {
      failure = error
      onFailure?(error.localizedDescription)
    }
  }

  func finish() throws -> AudioTracks {
    let remote = files[.audio]?.url
    let microphone = files[.microphone]?.url
    let origin = firstTimes.values.min() ?? 0
    files.removeAll()  // Finalize CAF headers before inference opens them.
    guard remote != nil || microphone != nil else {
      throw MinutesError.message(
        "No audio was captured. Check the selected browser and microphone permissions.")
    }
    let tracks = AudioTracks(
      remote: remote, microphone: microphone,
      remoteOffset: (firstTimes[.audio] ?? origin) - origin,
      microphoneOffset: (firstTimes[.microphone] ?? origin) - origin)
    try JSONEncoder().encode(tracks).write(
      to: directory.appendingPathComponent("tracks.json"), options: .atomic)
    if let failure { throw failure }
    return tracks
  }
}

@MainActor
final class AudioCapture: NSObject, SCStreamDelegate {
  private var stream: SCStream?
  private var sink: AudioSink?
  private let queue = DispatchQueue(label: "app.scribe.audio", qos: .userInitiated)
  var onFailure: ((String) -> Void)?

  func start(applicationID: pid_t, directory: URL) async throws {
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw MinutesError.message(
        "Enable Microphone access for Minutes in System Settings → Privacy & Security.")
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let display = content.displays.first,
      let application = content.applications.first(where: { $0.processID == applicationID })
    else {
      throw MinutesError.message(
        "The selected browser is no longer available. Open it and try again.")
    }
    let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.captureMicrophone = true
    configuration.excludesCurrentProcessAudio = true
    configuration.sampleRate = 16_000
    configuration.channelCount = 1
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    let sink = AudioSink(directory: directory) { [weak self] message in
      Task { @MainActor [weak self] in self?.onFailure?(message) }
    }
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: queue)
    try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: queue)
    self.sink = sink
    self.stream = stream
    do { try await stream.startCapture() } catch {
      self.stream = nil
      self.sink = nil
      throw error
    }
  }

  func stop() async throws -> AudioTracks {
    guard let stream, let sink else { throw MinutesError.message("There is no active recording.") }
    var stopError: Error?
    do { try await stream.stopCapture() } catch { stopError = error }
    self.stream = nil
    self.sink = nil
    let tracks = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<AudioTracks, Error>) in
      queue.async { continuation.resume(with: Result { try sink.finish() }) }
    }
    if let stopError { throw stopError }
    return tracks
  }

  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    let message = error.localizedDescription
    Task { @MainActor [weak self] in self?.onFailure?(message) }
  }
}
