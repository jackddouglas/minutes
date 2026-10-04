import Foundation
import MinutesCore
import Testing

@testable import Minutes

@Test @MainActor func speakerReviewQueueAdvancesAfterIndividualAndGroupAssignments() throws {
  let suite = "MinutesReviewTests.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let unknown = Utterance(speaker: "Unassigned", start: 1, end: 2, text: "Unknown")
  let first = Utterance(speaker: "Speaker 1", start: 3, end: 4, text: "First")
  let second = Utterance(speaker: "Speaker 1", start: 5, end: 6, text: "Second")
  let anotherUnknown = Utterance(speaker: "Unassigned", start: 7, end: 8, text: "Other")
  let corrected = Utterance(
    speaker: "Speaker 1", start: 9, end: 10, text: "Corrected", assignedName: "Bob")
  let known = Utterance(speaker: "Speaker 2", start: 11, end: 12, text: "Known")
  let microphone = Utterance(speaker: "You", start: 0, end: 1, text: "Me")
  let meeting = Meeting(
    title: "Review",
    utterances: [corrected, second, microphone, known, anotherUnknown, first, unknown],
    speakerNames: ["Unassigned": "Old alias", "Speaker 2": "Carol"])
  let store = MeetingStore(directory: directory.appendingPathComponent("Meetings"))
  try store.save(meeting)
  let model = AppModel(supportDirectory: directory, preferences: preferences)
  model.exportDirectory = directory.appendingPathComponent("exports")
  #expect(
    model.selectedMeeting?.passagesNeedingSpeakerReview.map(\.id) == [
      unknown.id, first.id, second.id, anotherUnknown.id,
    ])
  model.assignPassage(unknown.id, to: "Alice", in: meeting)
  #expect(model.selectedMeeting?.passagesNeedingSpeakerReview.first?.id == first.id)
  model.renameSpeaker("Speaker 1", to: "Alice", in: meeting)
  #expect(model.selectedMeeting?.passagesNeedingSpeakerReview.map(\.id) == [anotherUnknown.id])
  let saved = try #require(store.load().first)
  #expect(saved.name(for: corrected) == "Bob")
  #expect(saved.name(for: anotherUnknown) == "Unassigned")
  model.assignPassage(anotherUnknown.id, to: "Carol", in: meeting)
  #expect(model.selectedMeeting?.passagesNeedingSpeakerReview.isEmpty == true)
  #expect(try store.load().first?.passagesNeedingSpeakerReview.isEmpty == true)
}
