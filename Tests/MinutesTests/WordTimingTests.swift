import FluidAudio
import Testing

@testable import Minutes

private func token(_ text: String, _ start: Double, _ end: Double) -> TokenTiming {
  TokenTiming(token: text, tokenId: 0, startTime: start, endTime: end, confidence: 1)
}

@Test func tokenSilenceDoesNotBecomeSpeechOrJoinWords() throws {
  let words = try WordTiming.words([
    token(" Oh", 13.6, 211.12), token(".", 211.12, 211.2),
    token("Hello", 220, 220.24), token(" there", 220.24, 220.48),
    token("!", 220.48, 880),
  ])
  #expect(words.map(\.text) == ["Oh.", "Hello", "there!"])
  #expect(abs(words[0].end - 13.68) < 0.0001)
  #expect(words[2].end == 220.48)
}

@Test func wordPiecesKeepTheirRealInterval() throws {
  let words = try WordTiming.words([
    token("▁tran", 1, 1.16), token("script", 1.16, 1.48), token("ion", 1.48, 1.8),
    token(" works", 2, 2.4),
  ])
  #expect(words.map(\.text) == ["transcription", "works"])
  #expect(words[0].start == 1)
  #expect(words[0].end == 1.8)
  #expect(throws: (any Error).self) { try WordTiming.words([token("bad", .nan, 1)]) }
}
