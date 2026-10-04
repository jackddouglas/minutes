import Foundation
import MinutesCore
import Testing

@testable import Minutes

@Test func qualityAndSpeakerCountReachDiarizer() throws {
  let standard = try TranscriptionService.diarizationConfig(.init(quality: .standard))
  #expect(standard.segmentation.stepRatio == 0.2)
  #expect(standard.clustering.numSpeakers == nil)
  let thorough = try TranscriptionService.diarizationConfig(.init(expectedSystemSpeakers: 3))
  #expect(thorough.segmentation.stepRatio == 0.1)
  #expect(thorough.embedding.minSegmentDurationSeconds == 0)
  #expect(thorough.clustering.numSpeakers == 3)
  #expect(throws: (any Error).self) {
    try TranscriptionService.diarizationConfig(.init(expectedSystemSpeakers: 0))
  }
}

@Test @MainActor func passageAssignmentDoesNotRenameOtherUnknownPassages() throws {
  let suite = "MinutesPassageTests.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let first = Utterance(speaker: "Unassigned", start: 1, end: 2, text: "First")
  let second = Utterance(speaker: "Unassigned", start: 3, end: 4, text: "Second")
  let meeting = Meeting(
    title: "Test", utterances: [first, second], speakerNames: ["Unassigned": "Old bulk name"])
  let store = MeetingStore(directory: directory.appendingPathComponent("Meetings"))
  try store.save(meeting)
  let model = AppModel(supportDirectory: directory, preferences: preferences)
  model.exportDirectory = directory.appendingPathComponent("exports")
  model.assignPassage(first.id, to: "Alice", in: meeting)
  model.assignPassage(second.id, to: "Bob", in: meeting)  // stale view must not undo Alice
  let saved = try #require(store.load().first)
  #expect(saved.name(for: saved.utterances[0]) == "Alice")
  #expect(saved.name(for: saved.utterances[1]) == "Bob")
  #expect(saved.name(for: "Unassigned") == "Unassigned")
  model.renameSpeaker("Unassigned", to: "Everybody", in: saved)
  #expect(try store.load().first == saved)
  let markdown = MarkdownExporter.render(saved)
  #expect(markdown.contains("**Alice**"))
  #expect(markdown.contains("**Bob**"))
  model.assignPassage(first.id, to: nil, in: saved)
  #expect(try store.load().first?.utterances[0].assignedName == nil)
}

@Test @MainActor func newMeetingsIgnoreLegacyGlobalSpeakerCount() throws {
  let suite = "MinutesAutomaticSpeakers.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  preferences.set(3, forKey: "expectedSystemSpeakers")
  let model = AppModel(supportDirectory: directory, preferences: preferences)
  #expect(model.defaultTranscriptionOptions.expectedSystemSpeakers == nil)
  let config = try TranscriptionService.diarizationConfig(model.defaultTranscriptionOptions)
  #expect(config.clustering.numSpeakers == nil)
}
