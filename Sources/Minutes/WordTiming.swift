import FluidAudio
import Foundation
import MinutesCore

enum WordTiming {
  // The long-file decoder omits token durations and falls back to the next
  // emission, which may follow minutes of silence. Such ends are not speech
  // boundaries. Use one encoder frame for these ambiguous tokens instead.
  static let maximumTokenInterval = 1.0
  static let encoderFrame = 0.08

  static func words(_ tokens: [TokenTiming]) throws -> [TimedWord] {
    var words: [TimedWord] = []
    var previousStart: Double?
    for token in tokens {
      guard token.startTime.isFinite, token.endTime.isFinite, token.startTime >= 0,
        token.endTime >= token.startTime,
        previousStart.map({ token.startTime >= $0 }) ?? true
      else {
        throw MinutesError.message("The speech model returned invalid or unordered word timing.")
      }
      previousStart = token.startTime
      let startsWord = token.token.hasPrefix("▁") || token.token.hasPrefix(" ")
      let text = token.token.replacingOccurrences(of: "▁", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let end =
        token.endTime - token.startTime > maximumTokenInterval
        ? token.startTime + encoderFrame : max(token.endTime, token.startTime + encoderFrame)
      let punctuation = text.unicodeScalars.allSatisfy {
        CharacterSet.punctuationCharacters.contains($0)
      }
      if punctuation, !words.isEmpty {
        // Punctuation has no acoustic duration, including delayed punctuation.
        words[words.count - 1].text += text
      } else if !startsWord, let last = words.last,
        token.startTime - last.end <= maximumTokenInterval
      {
        words[words.count - 1].text += text
        words[words.count - 1].end = max(last.end, end)
      } else {
        words.append(TimedWord(text: text, start: token.startTime, end: end))
      }
    }
    return words
  }
}
