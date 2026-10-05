import Foundation
import Testing

@testable import MinutesCore

@Test func speakerChangesOffsetsAndUnknownSpeech() {
  let result = SpeakerAlignment.align(
    words: [
      .init(text: "Hello", start: 0, end: 1), .init(text: "there.", start: 1, end: 2),
      .init(text: "Yes.", start: 2, end: 3), .init(text: "Unknown.", start: 6, end: 7),
    ],
    spans: [
      .init(speaker: "Speaker 1", start: 0, end: 2), .init(speaker: "Speaker 2", start: 2, end: 4),
    ], offset: 5)
  #expect(result.map(\.speaker) == ["Speaker 1", "Speaker 2", "Unassigned"])
  #expect(result[0].text == "Hello there.")
  #expect(result[0].start == 5)
  #expect(result[1].end == 8)
  #expect(
    result[0].words == [
      TimedWord(text: "Hello", start: 5, end: 6), TimedWord(text: "there.", start: 6, end: 7),
    ])
  #expect(result[1].words?.first?.start == 7)
}

@Test func wordTimingsPersistAndOldTranscriptsStillLoad() throws {
  let oldJSON = """
    {"id":"00000000-0000-0000-0000-000000000001","speaker":"Speaker 1","start":1,"end":3,"text":"Hello there"}
    """
  let old = try JSONDecoder().decode(Utterance.self, from: Data(oldJSON.utf8))
  #expect(old.words == nil)
  #expect(old.text == "Hello there")
  let result = SpeakerAlignment.align(
    words: [.init(text: "Hello", start: 1, end: 2), .init(text: "there", start: 2, end: 3)],
    spans: [], offset: 4, fixedSpeaker: "You")
  let roundTrip = try JSONDecoder().decode([Utterance].self, from: JSONEncoder().encode(result))
  #expect(roundTrip == result)
  #expect(roundTrip[0].words?.map(\.start) == [5, 6])
}

@Test func localTrackHasKnownSpeakerAndSplitsAtPauses() {
  let result = SpeakerAlignment.align(
    words: [.init(text: "One", start: 0, end: 1), .init(text: "Two", start: 5, end: 6)], spans: [],
    fixedSpeaker: "You")
  #expect(result.count == 2)
  #expect(result.allSatisfy { $0.speaker == "You" })
}

@Test func shortTrailingWordUsesNearbySpeakerWithoutSplittingPassage() {
  let result = SpeakerAlignment.align(
    words: [
      .init(text: "I", start: 5.4, end: 5.76),
      .init(text: "think.", start: 5.76, end: 6.08),
    ], spans: [.init(speaker: "A", start: 4, end: 5.74)])
  #expect(result.count == 1)
  #expect(result.first?.speaker == "A")
  #expect(result.first?.text == "I think.")
  #expect(result.first?.end == 6.08)
}

@Test func gapRepairDoesNotGuessAcrossSpeakersOrLongSilence() {
  let words = [TimedWord(text: "yes", start: 1.1, end: 1.2)]
  let competing = SpeakerAlignment.align(
    words: words,
    spans: [
      .init(speaker: "A", start: 0, end: 1),
      .init(speaker: "B", start: 1.3, end: 2),
    ])
  #expect(competing.first?.speaker == "Unassigned")
  let distant = SpeakerAlignment.align(
    words: words, spans: [.init(speaker: "A", start: 0, end: 0.5)])
  #expect(distant.first?.speaker == "Unassigned")
  let long = SpeakerAlignment.align(
    words: [.init(text: "uncertain phrase", start: 1.1, end: 2)],
    spans: [.init(speaker: "A", start: 0, end: 1)])
  #expect(long.first?.speaker == "Unassigned")
  let interjection = SpeakerAlignment.align(
    words: words,
    spans: [
      .init(speaker: "A", start: 0, end: 1),
      .init(speaker: "B", start: 1.1, end: 1.2),
      .init(speaker: "A", start: 1.3, end: 2),
    ])
  #expect(interjection.first?.speaker == "B")
}
