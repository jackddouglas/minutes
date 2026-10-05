import AVFoundation
import CoreAudio

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
enum CaptureTrack { case audio, microphone }

final class AudioSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
  let directory: URL
  var files: [CaptureTrack: AVAudioFile] = [:]
  var firstTimes: [CaptureTrack: Double] = [:]
  var failure: Error?
  var microphoneClock: CMClock?
  let onFailure: (@Sendable (String) -> Void)?

  init(directory: URL, onFailure: (@Sendable (String) -> Void)? = nil) {
    self.directory = directory
    self.onFailure = onFailure
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let microphoneClock else { return }
    let time = CMSyncConvertTime(
      sampleBuffer.presentationTimeStamp, from: microphoneClock, to: CMClockGetHostTimeClock())
    consume(sampleBuffer, of: .microphone, at: time.seconds)
  }

  func consume(
    _ sampleBuffer: CMSampleBuffer, of outputType: CaptureTrack, at time: Double? = nil
  ) {
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
    consume(buffer, at: time ?? sampleBuffer.presentationTimeStamp.seconds, of: outputType)
  }

  func consume(_ buffer: AVAudioPCMBuffer, at time: Double, of outputType: CaptureTrack) {
    guard failure == nil else { return }
    let format = buffer.format
    do {
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
final class AudioCapture {
  private var browserTap: BrowserAudioTap?
  private var microphone: AVCaptureSession?
  private var sink: AudioSink?
  private var microphoneObserver: NSObjectProtocol?
  private let queue = DispatchQueue(label: "app.scribe.audio", qos: .userInitiated)
  var onFailure: ((String) -> Void)?

  func start(applicationID: pid_t, directory: URL) async throws {
    guard sink == nil else { throw MinutesError.message("A recording is already in progress.") }
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw MinutesError.message(
        "Enable Microphone access for Minutes in System Settings → Privacy & Security.")
    }
    let sink = AudioSink(directory: directory) { [weak self] message in
      Task { @MainActor [weak self] in self?.onFailure?(message) }
    }
    let tap = BrowserAudioTap(queue: queue, sink: sink)
    let session = AVCaptureSession()
    do {
      guard let device = AVCaptureDevice.default(for: .audio) else {
        throw MinutesError.message("No microphone is available.")
      }
      let input = try AVCaptureDeviceInput(device: device)
      let output = AVCaptureAudioDataOutput()
      guard session.canAddInput(input), session.canAddOutput(output) else {
        throw MinutesError.message("The microphone could not be opened.")
      }
      session.addInput(input)
      session.addOutput(output)
      output.setSampleBufferDelegate(sink, queue: queue)
      try tap.start(applicationID: applicationID)
      session.startRunning()
      guard session.isRunning else { throw MinutesError.message("The microphone could not start.") }
      guard let clock = session.synchronizationClock else {
        throw MinutesError.message("The microphone clock is unavailable.")
      }
      queue.sync { sink.microphoneClock = clock }
      microphoneObserver = NotificationCenter.default.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.onFailure?(
            "Microphone recording was interrupted. The partial recording is retained.")
        }
      }
      browserTap = tap
      microphone = session
      self.sink = sink
    } catch {
      session.stopRunning()
      tap.stop()
      // Drain pending callbacks and retain any partial audio before reporting failure.
      queue.sync { _ = try? sink.finish() }
      throw error
    }
  }

  func stop() async throws -> AudioTracks {
    guard let sink else { throw MinutesError.message("There is no active recording.") }
    if let microphoneObserver { NotificationCenter.default.removeObserver(microphoneObserver) }
    microphoneObserver = nil
    microphone?.stopRunning()
    browserTap?.stop()
    microphone = nil
    browserTap = nil
    self.sink = nil
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<AudioTracks, Error>) in
      queue.async { continuation.resume(with: Result { try sink.finish() }) }
    }
  }
}
