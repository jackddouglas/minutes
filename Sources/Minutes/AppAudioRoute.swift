import AVFoundation
import CoreAudio

struct AppAudioRoute {
  let deviceUID: String
  let streamIndex: Int
  let channelCount: UInt32
  let stereoChannels: [Int]

  /// Follow the selected app's output, falling back to the default before playback begins.
  static func resolve(processes: [AudioObjectID]) throws -> AppAudioRoute? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let defaultDevice = try values(system, kAudioHardwarePropertyDefaultOutputDevice).first
    let devices = try processes.flatMap {
      try values($0, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
    }
    guard let device = devices.first(where: { $0 == defaultDevice }) ?? devices.first ?? defaultDevice
    else { return nil }
    let scope = kAudioObjectPropertyScopeOutput
    let streams = try values(device, kAudioDevicePropertyStreams, scope: scope)
    let preferred = (try? values(device, kAudioDevicePropertyPreferredChannelsForStereo, scope: scope)) ?? [1, 2]
    var formats: [AudioStreamBasicDescription] = []
    for stream in streams {
      var address = address(kAudioStreamPropertyVirtualFormat)
      var format = AudioStreamBasicDescription()
      var size = UInt32(MemoryLayout.size(ofValue: format))
      guard AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr else {
        throw MinutesError.message("Could not read the output device's channel format.")
      }
      try CaptureAudioFormat.validate(format)
      formats.append(format)
    }
    // Ordinary stereo outputs retain the cross-device mixdown behavior.
    guard formats.reduce(0, { $0 + $1.mChannelsPerFrame }) > 2 else { return nil }
    guard let selection = selection(channelCounts: formats.map(\.mChannelsPerFrame), preferred: preferred) else {
      throw MinutesError.message("The output stereo pair spans separate audio streams. " + CaptureAudioFormat.guidance)
    }
    var uidAddress = address(kAudioDevicePropertyDeviceUID)
    var uid: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout.size(ofValue: uid))
    guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &uid) == noErr,
      let uid = uid?.takeRetainedValue() as String?
    else { throw MinutesError.message("Could not identify the selected app's output device.") }
    return AppAudioRoute(deviceUID: uid, streamIndex: selection.stream,
      channelCount: formats[selection.stream].mChannelsPerFrame, stereoChannels: selection.channels)
  }

  static func selection(channelCounts: [UInt32], preferred: [UInt32]) -> (stream: Int, channels: [Int])? {
    guard preferred.count == 2, preferred.allSatisfy({ $0 > 0 }) else { return nil }
    var first: UInt32 = 1
    for (index, count) in channelCounts.enumerated() {
      if preferred.allSatisfy({ $0 >= first && $0 - first < count }) {
        return (index, preferred.map { Int($0 - first) })
      }
      first += count
    }
    return nil
  }

  private static func address(_ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static func values(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [UInt32] {
    var address = address(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else {
      throw MinutesError.message("Could not inspect the app's audio routing.")
    }
    guard size > 0 else { return [] }
    var result = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else {
      throw MinutesError.message("Could not read the app's audio routing.")
    }
    return result
  }
}

extension CaptureAudioFormat {
  static func stereo(_ buffer: AVAudioPCMBuffer, channels: [Int]) throws -> AVAudioPCMBuffer {
    guard channels.count == 2,
      channels.allSatisfy({ $0 >= 0 && $0 < Int(buffer.format.channelCount) }),
      let format = AVAudioFormat(
        standardFormatWithSampleRate: buffer.format.sampleRate, channels: 2),
      let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)
    else {
      throw MinutesError.message(
        "The output device returned an unsupported channel layout. " + guidance)
    }
    result.frameLength = buffer.frameLength
    let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    func copy<Sample>(_ type: Sample.Type, convert: (Sample) -> Float) throws {
      for (destination, channel) in channels.enumerated() {
        let plane = buffer.format.isInterleaved ? 0 : channel
        guard let data = buffers[plane].mData else {
          throw MinutesError.message("The output device returned no audio data. " + guidance)
        }
        let source = data.assumingMemoryBound(to: Sample.self)
        let offset = buffer.format.isInterleaved ? channel : 0
        for frame in 0..<Int(buffer.frameLength) {
          result.floatChannelData![destination][frame] = convert(
            source[frame * buffer.stride + offset])
        }
      }
    }
    // Device-specific taps retain the stream's PCM type. Normalize integer samples
    // to the same full-scale range as floating-point audio before writing stereo.
    switch buffer.format.commonFormat {
    case .pcmFormatFloat32: try copy(Float.self) { $0 }
    case .pcmFormatFloat64: try copy(Double.self) { Float($0) }
    case .pcmFormatInt16: try copy(Int16.self) { Float($0) / 32768 }
    case .pcmFormatInt32: try copy(Int32.self) { Float($0) / 2_147_483_648 }
    default:
      throw MinutesError.message(
        "The output device returned an unsupported PCM format. " + guidance)
    }
    return result
  }
}
