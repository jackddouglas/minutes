import AVFoundation
import CoreAudio
import Testing

@testable import Minutes

@Test func browserAudioScopeIncludesOnlySelectedBrowserAndEmbeddedHelpers() {
  let scope = BrowserAudioScope(
    processID: 42, bundleID: "net.imput.helium", bundlePath: "/Applications/Helium.app")
  #expect(scope.includes(pid: 42, bundle: nil, executablePath: nil))
  #expect(scope.includes(pid: 80, bundle: "net.imput.helium", executablePath: nil))
  #expect(
    scope.includes(
      pid: 81, bundle: "net.imput.helium.helper",
      executablePath:
        "/Applications/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper"
    ))
  #expect(
    !scope.includes(
      pid: 82, bundle: "com.apple.Music",
      executablePath: "/System/Applications/Music.app/Contents/MacOS/Music"))
  #expect(
    !scope.includes(
      pid: 83, bundle: "net.imput.helium.other",
      executablePath: "/Applications/Helium.app.other/Contents/MacOS/Other"))
  #expect(!scope.includes(pid: 84, bundle: nil, executablePath: nil))
}

@Test @MainActor func browserAudioCallbackRunsOnCaptureQueue() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let sink = AudioSink(directory: directory)
  let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
  let callback = BrowserAudioTap.makeIOCallback(format: format, sink: sink)
  let queue = DispatchQueue(label: "minutes.test.capture")
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    queue.async {
      do {
        #expect(!Thread.isMainThread)
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
        for channel in 0..<2 {
          for frame in 0..<480 { pcm.floatChannelData![channel][frame] = 0.125 }
        }
        var timestamp = AudioTimeStamp()
        timestamp.mHostTime = AVAudioTime.hostTime(forSeconds: 100)
        timestamp.mFlags = .hostTimeValid
        withUnsafePointer(to: &timestamp) { time in
          callback(time, pcm.audioBufferList, time, pcm.mutableAudioBufferList, time)
        }
        let tracks = try sink.finish()
        let file = try AVAudioFile(forReading: #require(tracks.remote))
        #expect(file.length == 480)
        let restored = try #require(
          AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
        try file.read(into: restored)
        #expect(restored.floatChannelData![1][479] == 0.125)
        continuation.resume()
      } catch { continuation.resume(throwing: error) }
    }
  }
}
