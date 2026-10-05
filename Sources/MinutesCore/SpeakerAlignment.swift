import Foundation

public struct TimedWord: Codable, Equatable, Sendable {
  public var text: String
  public var start: Double
  public var end: Double
  public init(text: String, start: Double, end: Double) {
    self.text = text
    self.start = start
    self.end = end
  }
}

public struct SpeakerSpan: Sendable {
  public var speaker: String
  public var start: Double
  public var end: Double
  public init(speaker: String, start: Double, end: Double) {
    self.speaker = speaker
    self.start = start
    self.end = end
  }
}

public enum SpeakerAlignment {
  public static func align(
    words: [TimedWord], spans: [SpeakerSpan], offset: Double = 0,
    fixedSpeaker: String? = nil
  ) -> [Utterance] {
    var output: [Utterance] = []
    for word in words.sorted(by: { $0.start < $1.start })
    where !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let ranked = spans.map {
        ($0.speaker, max(0, min(word.end, $0.end) - max(word.start, $0.start)))
      }
      .sorted { $0.1 > $1.1 }
      let speaker =
        fixedSpeaker
        ?? ranked.first.flatMap { $0.1 > 0 ? $0.0 : nil }
        ?? nearbySpeaker(for: word, spans: spans)
        ?? "Unassigned"
      let start = word.start + offset
      let end = word.end + offset
      let timedWord = TimedWord(text: word.text, start: start, end: end)
      if let last = output.last, last.speaker == speaker, start - last.end < 1.5,
        end - last.start < 30
      {
        output[output.count - 1].text += " " + word.text
        output[output.count - 1].end = max(last.end, end)
        output[output.count - 1].words?.append(timedWord)
      } else {
        output.append(
          Utterance(speaker: speaker, start: start, end: end, text: word.text, words: [timedWord]))
      }
    }
    return output
  }

  private static func nearbySpeaker(for word: TimedWord, spans: [SpeakerSpan]) -> String? {
    // ASR token emissions can fall just outside the diarizer's speech boundary.
    // Repair only short words next to one speaker; never smooth a detected turn
    // or choose between competing speakers across a gap.
    guard word.end - word.start <= 0.6 else { return nil }
    let nearby = Set(
      spans.compactMap { span -> String? in
        guard span.start.isFinite, span.end.isFinite, span.end > span.start else { return nil }
        let distance = max(0, max(span.start - word.end, word.start - span.end))
        return distance <= 0.25 ? span.speaker : nil
      })
    return nearby.count == 1 ? nearby.first : nil
  }

}
