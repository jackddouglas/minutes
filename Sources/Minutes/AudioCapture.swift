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

extension AVAudioPCMBuffer {
  /// Copies captured audio into PCM, or nil when the sample buffer carries none.
  static func copying(_ sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer? {
    guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer),
      let description = sampleBuffer.formatDescription
    else { return nil }
    guard let raw = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
      throw MinutesError.message("The audio device returned no audio format.")
    }
    try CaptureAudioFormat.validate(raw.pointee)
    guard sampleBuffer.numSamples > 0, sampleBuffer.numSamples <= Int(Int32.max),
      let format = AVAudioFormat(cmAudioFormatDescription: description) as AVAudioFormat?,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples))
    else { return nil }
    buffer.frameLength = buffer.frameCapacity
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0,
      frameCount: Int32(buffer.frameLength), into: buffer.mutableAudioBufferList)
    guard status == noErr else {
      throw MinutesError.message("Audio buffer conversion failed (\(status)).")
    }
    return buffer
  }
}

// All mutable state in this sink is confined to the stream's serial callback queue.
enum CaptureTrack { case audio, microphone }

final class AudioSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
  let directory: URL
  var files: [CaptureTrack: AVAudioFile] = [:]
  private var writtenFrames: [CaptureTrack: AVAudioFramePosition] = [:]
  var firstTimes: [CaptureTrack: Double] = [:]
  var failure: Error?
  var microphoneClock: CMClock?
  let onFailure: (@Sendable (String) -> Void)?
  private var microphoneLevel = RecordingLevelAccumulator()
  private var systemLevel = RecordingLevelAccumulator()
  private var signal = RecordingLevelAccumulator()
  private var heardSignal = false

  func takeLevels() -> RecordingLevels {
    RecordingLevels(
      microphone: microphoneLevel.takeReading(), system: systemLevel.takeReading())
  }

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
    guard failure == nil, outputType == .audio || outputType == .microphone else { return }
    let buffer: AVAudioPCMBuffer
    do {
      guard let converted = try AVAudioPCMBuffer.copying(sampleBuffer) else { return }
      buffer = outputType == .microphone ? try CaptureAudioFormat.microphone(converted) : converted
    } catch {
      failure = error
      onFailure?(error.localizedDescription)
      return
    }
    consume(buffer, at: time ?? sampleBuffer.presentationTimeStamp.seconds, of: outputType)
  }

  func consume(_ buffer: AVAudioPCMBuffer, at time: Double, of outputType: CaptureTrack) {
    guard failure == nil else { return }
    let format = buffer.format
    do {
      try CaptureAudioFormat.validate(format.streamDescription.pointee)
      guard buffer.frameLength > 0 else { return }
      if let file = files[outputType], file.processingFormat != format {
        throw MinutesError.message("The audio format changed during recording. " + CaptureAudioFormat.guidance)
      }
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
        writtenFrames[outputType] = 0
      }
      guard let file = files[outputType], let first = firstTimes[outputType] else { return }
      // Preserve silence between callbacks so independent tracks stay synchronized.
      let elapsedFrames = max(0, (time - first) * format.sampleRate)
      guard elapsedFrames.isFinite, elapsedFrames < Double(Int64.max) else {
        throw MinutesError.message("The audio device returned an invalid timestamp.")
      }
      let expected = AVAudioFramePosition(elapsedFrames)
      // framePosition can raise an Objective-C exception that Swift catch cannot handle.
      // These files are append-only; count frames only after successful writes instead.
      var gap = expected - writtenFrames[outputType, default: 0]
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
        writtenFrames[outputType, default: 0] += AVAudioFramePosition(count)
        gap -= AVAudioFramePosition(count)
      }
      try file.write(from: buffer)
      signal.consume(buffer)
      let peak = signal.takeReading().peak
      heardSignal = heardSignal || peak > 0
      writtenFrames[outputType, default: 0] += AVAudioFramePosition(buffer.frameLength)
      switch outputType {
      case .audio: systemLevel.consume(buffer)
      case .microphone: microphoneLevel.consume(buffer)
      }
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
      if let failure { throw failure }
      throw MinutesError.message(
        "No audio was captured. Check the selected app and microphone permissions. \(CaptureAudioFormat.guidance)")
    }
    let tracks = AudioTracks(
      remote: remote, microphone: microphone,
      remoteOffset: (firstTimes[.audio] ?? origin) - origin,
      microphoneOffset: (firstTimes[.microphone] ?? origin) - origin)
    try JSONEncoder().encode(tracks).write(
      to: directory.appendingPathComponent("tracks.json"), options: .atomic)
    if let failure { throw failure }
    guard heardSignal else {
      throw MinutesError.message("No audio signal was detected. The recording is retained. " + CaptureAudioFormat.guidance)
    }
    return tracks
  }
}

@MainActor
final class AudioCapture {
  private var appTap: AppAudioTap?
  private var microphone: AVCaptureSession?
  private var sink: AudioSink?
  private var microphoneObserver: NSObjectProtocol?
  private let queue = DispatchQueue(label: "app.minutes.audio", qos: .userInitiated)
  var onFailure: ((String) -> Void)?

  func levels() async -> RecordingLevels {
    guard let sink else { return RecordingLevels() }
    return await withCheckedContinuation { continuation in
      queue.async { continuation.resume(returning: sink.takeLevels()) }
    }
  }

  func start(applicationID: pid_t, directory: URL) async throws {
    guard sink == nil else { throw MinutesError.message("A recording is already in progress.") }
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw MinutesError.message(
        "Enable Microphone access for Minutes in System Settings → Privacy & Security.")
    }
    let sink = AudioSink(directory: directory) { [weak self] message in
      Task { @MainActor [weak self] in self?.onFailure?(message) }
    }
    let tap = AppAudioTap(queue: queue, sink: sink)
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
      try CaptureAudioFormat.configure(output, device: device)
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
      appTap = tap
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
    appTap?.stop()
    microphone = nil
    appTap = nil
    self.sink = nil
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<AudioTracks, Error>) in
      queue.async { continuation.resume(with: Result { try sink.finish() }) }
    }
  }
}
