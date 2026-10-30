import AVFoundation
import Foundation

let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
let format = file.processingFormat
print("Input:", format, "layout:", format.channelLayout?.layoutTag as Any)
let target = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
let converter = AVAudioConverter(from: format, to: target)!
let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16384)!
let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 5462)!
var rawEnergy = 0.0
var rawCount = 0
var outputEnergy = 0.0
var outputPeak = 0.0
var outputCount = 0
while true {
  var error: NSError?
  let status = converter.convert(to: output, error: &error) { _, state in
    let count = AVAudioFrameCount(min(16384, file.length - file.framePosition))
    if count == 0 { state.pointee = .endOfStream; return nil }
    try! file.read(into: input, frameCount: count)
    for channel in 0..<Int(format.channelCount) {
      for frame in 0..<Int(input.frameLength) {
        let value = Double(input.floatChannelData![channel][frame])
        rawEnergy += value * value
        rawCount += 1
      }
    }
    state.pointee = .haveData
    return input
  }
  if let error { throw error }
  for frame in 0..<Int(output.frameLength) {
    let value = Double(output.floatChannelData![0][frame])
    outputEnergy += value * value
    outputPeak = max(outputPeak, abs(value))
    outputCount += 1
  }
  if status == .endOfStream { break }
}
print("Raw RMS:", sqrt(rawEnergy / Double(rawCount)))
print("Converted samples:", outputCount, "RMS:", sqrt(outputEnergy / Double(outputCount)), "peak:", outputPeak)
