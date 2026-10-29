import AVFoundation

/// Validate raw descriptions before AVFoundation can raise an Objective-C exception.
enum CaptureAudioFormat {
  static let guidance = "Check the input/output device and sample rate in Audio MIDI Setup, and the USB routing on your mixer (including channels 3/4)."

  static func validate(_ description: AudioStreamBasicDescription) throws {
    guard description.mSampleRate.isFinite, description.mSampleRate > 0,
      description.mChannelsPerFrame > 0, description.mFormatID == kAudioFormatLinearPCM
    else {
      throw MinutesError.message("The audio device returned an invalid audio format. \(guidance)")
    }
  }

  static func configure(_ output: AVCaptureAudioDataOutput, device: AVCaptureDevice) throws {
    guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(
      device.activeFormat.formatDescription)
    else { throw MinutesError.message("The microphone has no audio format. \(guidance)") }
    try validate(description.pointee)
    // Explicitly retain the interface's channels instead of accepting a default stereo mix.
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: description.pointee.mSampleRate,
      AVNumberOfChannelsKey: description.pointee.mChannelsPerFrame,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsNonInterleaved: true,
    ]
  }

  /// Use the strongest microphone channel, avoiding silent 1/2 and phase cancellation
  /// when an interface exposes the same microphone on several channels.
  static func microphone(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    guard buffer.format.channelCount > 1 else { return buffer }
    guard let channels = buffer.floatChannelData, !buffer.format.isInterleaved else {
      throw MinutesError.message("The microphone returned an unsupported channel layout. \(guidance)")
    }
    let frames = Int(buffer.frameLength)
    var best = 0
    var bestEnergy = -Double.infinity
    for channel in 0..<Int(buffer.format.channelCount) {
      var energy = 0.0
      for frame in 0..<frames {
        let value = Double(channels[channel][frame])
        if value.isFinite { energy += value * value }
      }
      if energy > bestEnergy { best = channel; bestEnergy = energy }
    }
    guard let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate, channels: 1),
      let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)
    else { throw MinutesError.message("Could not prepare microphone audio.") }
    mono.frameLength = buffer.frameLength
    mono.floatChannelData![0].update(from: channels[best], count: frames)
    return mono
  }
}
