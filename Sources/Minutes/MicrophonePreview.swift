import AVFoundation

/// Opt-in microphone monitoring before capture, so levels can be checked
/// without recording. Nothing is written to disk.
@MainActor
final class MicrophonePreview {
  private var session: AVCaptureSession?
  private var wanted = false
  private let meter = PreviewMeter()
  private let queue = DispatchQueue(label: "app.minutes.preview", qos: .userInitiated)

  var isRunning: Bool { session != nil }

  func start() async throws {
    wanted = true
    guard session == nil else { return }
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw MinutesError.message(
        "Enable Microphone access for Minutes in System Settings → Privacy & Security.")
    }
    // stop() may have been requested while the permission prompt was open.
    guard wanted, session == nil else { return }
    guard let device = AVCaptureDevice.default(for: .audio) else {
      throw MinutesError.message("No microphone is available.")
    }
    let session = AVCaptureSession()
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureAudioDataOutput()
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw MinutesError.message("The microphone could not be opened.")
    }
    session.addInput(input)
    session.addOutput(output)
    try CaptureAudioFormat.configure(output, device: device)
    output.setSampleBufferDelegate(meter, queue: queue)
    session.startRunning()
    guard session.isRunning else { throw MinutesError.message("The microphone could not start.") }
    self.session = session
  }

  func stop() {
    wanted = false
    guard let session else { return }
    session.stopRunning()
    self.session = nil
    queue.sync { meter.reset() }
  }

  func level() async -> RecordingLevel {
    await withCheckedContinuation { continuation in
      queue.async { [meter] in continuation.resume(returning: meter.takeReading()) }
    }
  }
}

// All mutable state is confined to the preview's serial callback queue.
private final class PreviewMeter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private var accumulator = RecordingLevelAccumulator()

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let buffer = try? AVAudioPCMBuffer.copying(sampleBuffer),
      let microphone = try? CaptureAudioFormat.microphone(buffer) else { return }
    accumulator.consume(microphone)
  }

  func takeReading() -> RecordingLevel { accumulator.takeReading() }
  func reset() { accumulator = RecordingLevelAccumulator() }
}
