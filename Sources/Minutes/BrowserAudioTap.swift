import AVFoundation
import AppKit
import CoreAudio
import Darwin

// The tap includes only this browser and its embedded helpers. An empty process
// list stays silent; it must never become an exclusive (global) tap.
struct BrowserAudioScope {
  let processID: pid_t
  let bundleID: String
  let bundlePath: String

  func includes(pid: pid_t, bundle: String?, executablePath: String?) -> Bool {
    pid == processID || bundle == bundleID
      || executablePath?.hasPrefix(bundlePath + "/") == true
  }
}

@MainActor
final class BrowserAudioTap {
  private var tapID: AudioObjectID = kAudioObjectUnknown
  private var deviceID: AudioObjectID = kAudioObjectUnknown
  private var ioProc: AudioDeviceIOProcID?
  private var listener: AudioObjectPropertyListenerBlock?
  private var description: CATapDescription?
  private var scope: BrowserAudioScope?
  private var processIDs: [AudioObjectID] = []
  private let queue: DispatchQueue
  private let sink: AudioSink

  init(queue: DispatchQueue, sink: AudioSink) {
    self.queue = queue
    self.sink = sink
  }

  func start(applicationID: pid_t) throws {
    guard let app = NSRunningApplication(processIdentifier: applicationID), !app.isTerminated,
      let bundleID = app.bundleIdentifier, let url = app.bundleURL
    else { throw MinutesError.message("The selected browser is no longer available.") }
    scope = BrowserAudioScope(processID: applicationID, bundleID: bundleID, bundlePath: url.path)
    do {
      processIDs = try matchingProcesses()
      let description = CATapDescription(stereoMixdownOfProcesses: processIDs)
      description.name = "Minutes browser audio"
      description.isPrivate = true
      description.isExclusive = false
      description.muteBehavior = .unmuted
      if #available(macOS 26.0, *) { description.bundleIDs = [bundleID] }
      self.description = description
      try check(AudioHardwareCreateProcessTap(description, &tapID), "Start browser audio capture")
      var format = AudioStreamBasicDescription()
      var address = property(kAudioTapPropertyFormat)
      var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      try check(
        AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "Read audio format")
      guard let audioFormat = AVAudioFormat(streamDescription: &format) else {
        throw MinutesError.message("The browser returned an unsupported audio format.")
      }
      let aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Minutes browser audio",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [
          [
            kAudioSubTapUIDKey: description.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true,
          ]
        ],
      ]
      try check(
        AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID),
        "Open browser audio")
      try check(
        AudioDeviceCreateIOProcIDWithBlock(
          &ioProc, deviceID, queue, Self.makeIOCallback(format: audioFormat, sink: sink)),
        "Prepare browser audio")
      try check(AudioDeviceStart(deviceID, ioProc), "Record browser audio")
      let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor [weak self] in self?.refreshProcesses() }
      }
      var processes = property(kAudioHardwarePropertyProcessObjectList)
      try check(
        AudioObjectAddPropertyListenerBlock(
          AudioObjectID(kAudioObjectSystemObject), &processes, .main, listener),
        "Watch browser audio processes")
      self.listener = listener
      refreshProcesses()
    } catch {
      stop()
      throw error
    }
  }

  // Core Audio invokes this on the capture queue. Constructing the block outside
  // MainActor prevents it from inheriting start()'s main-thread isolation.
  nonisolated static func makeIOCallback(
    format: AVAudioFormat, sink: AudioSink
  ) -> @Sendable (
    UnsafePointer<AudioTimeStamp>, UnsafePointer<AudioBufferList>,
    UnsafePointer<AudioTimeStamp>, UnsafeMutablePointer<AudioBufferList>,
    UnsafePointer<AudioTimeStamp>
  ) -> Void {
    { _, input, timestamp, _, _ in
      guard timestamp.pointee.mFlags.contains(.hostTimeValid),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input)
      else { return }
      sink.consume(
        buffer, at: AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime), of: .audio)
    }
  }

  func stop() {
    if let listener {
      var address = property(kAudioHardwarePropertyProcessObjectList)
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }
    listener = nil
    if let ioProc {
      AudioDeviceStop(deviceID, ioProc)
      AudioDeviceDestroyIOProcID(deviceID, ioProc)
    }
    ioProc = nil
    if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
    deviceID = kAudioObjectUnknown
    if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    tapID = kAudioObjectUnknown
    description = nil
    scope = nil
    processIDs = []
  }

  private func refreshProcesses() {
    guard tapID != kAudioObjectUnknown, let description else { return }
    do {
      let current = try matchingProcesses()
      guard current != processIDs else { return }
      description.processes = current
      var value = Unmanaged.passUnretained(description).toOpaque()
      var address = property(kAudioTapPropertyDescription)
      try check(
        AudioObjectSetPropertyData(
          tapID, &address, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), &value),
        "Update browser audio processes")
      processIDs = current
    } catch {
      sink.onFailure?(error.localizedDescription)
    }
  }

  private func matchingProcesses() throws -> [AudioObjectID] {
    guard let scope else { return [] }
    var address = property(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size), "Find browser audio")
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !objects.isEmpty else { return [] }
    try check(
      AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects), "Find browser audio")
    return objects.filter { object in
      var pid: pid_t = 0
      var pidSize = UInt32(MemoryLayout<pid_t>.size)
      var pidAddress = property(kAudioProcessPropertyPID)
      guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else {
        return false
      }
      var bundle: Unmanaged<CFString>?
      var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      var bundleAddress = property(kAudioProcessPropertyBundleID)
      let bundleStatus = AudioObjectGetPropertyData(
        object, &bundleAddress, 0, nil, &bundleSize, &bundle)
      let bundleID = bundleStatus == noErr ? bundle?.takeRetainedValue() as String? : nil
      var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
      let length = proc_pidpath(pid, &path, UInt32(path.count))
      let executable =
        length > 0
        ? String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        : nil
      return scope.includes(pid: pid, bundle: bundleID, executablePath: executable)
    }.sorted()
  }

  private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }

  private func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else {
      throw MinutesError.message(
        "\(action) failed (\(status)). Check Minutes in System Settings → Privacy & Security → Screen & System Audio Recording."
      )
    }
  }
}
