import Testing

@testable import MinutesCore

@Test func playbackSpeakersRespectAssignmentsOverlapsAndGaps() {
  let meeting = Meeting(
    title: "Test",
    utterances: [
      .init(speaker: "Speaker 1", start: 1, end: 3, text: "Hello"),
      .init(speaker: "You", start: 2, end: 4, text: "Yes"),
      .init(speaker: "Unassigned", start: 5, end: 6, text: "Hi", assignedName: "Sam"),
      .init(speaker: "Speaker 2", start: 5, end: 6, text: "Again", assignedName: "Sam"),
      .init(speaker: "Unassigned", start: 7, end: 8, text: "Unknown"),
    ], speakerNames: ["Speaker 1": "Alice"])
  #expect(meeting.speakers(at: 0).isEmpty)
  #expect(meeting.speakers(at: 1) == ["Alice"])
  #expect(meeting.speakers(at: 2) == ["Alice", "You"])
  #expect(meeting.speakers(at: 3) == ["You"])
  #expect(meeting.speakers(at: 4).isEmpty)
  #expect(meeting.speakers(at: 5) == ["Sam"])
  #expect(meeting.speakers(at: 7) == ["Unassigned"])
  #expect(meeting.speakers(at: 8).isEmpty)
  #expect(meeting.speakers(at: .nan).isEmpty)
}
