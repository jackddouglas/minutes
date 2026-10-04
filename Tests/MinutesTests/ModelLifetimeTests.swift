import Foundation
import Testing

@testable import Minutes

@Test @MainActor func modelIdleUnloadRespectsActivityAndPreferences() async throws {
  let suite = "MinutesTests.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let model = AppModel(
    supportDirectory: directory, preferences: preferences,
    modelIdleMinuteDuration: .milliseconds(20))
  #expect(model.modelIdleMinutes == 10)
  model.sourceID = 1
  #expect(model.canStart)  // Recording no longer requires a separate preparation action.
  model.modelsReady = true
  model.modelIdleMinutes = 1
  model.isRecording = true
  try await Task.sleep(for: .milliseconds(80))
  #expect(model.modelsReady)
  model.isRecording = false
  model.isBusy = true
  try await Task.sleep(for: .milliseconds(80))
  #expect(model.modelsReady)
  model.isBusy = false
  try await Task.sleep(for: .milliseconds(100))
  #expect(!model.modelsReady)
  model.modelsReady = true
  model.modelIdleMinutes = 0
  try await Task.sleep(for: .milliseconds(80))
  #expect(model.modelsReady)
  let restored = AppModel(supportDirectory: directory, preferences: preferences)
  #expect(restored.modelIdleMinutes == 0)
  model.isRecording = true
  model.unloadModels()
  #expect(model.modelsReady)
  model.isRecording = false
  model.unloadModels()
  try await Task.sleep(for: .milliseconds(80))
  #expect(!model.modelsReady)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIBE_MODEL_SMOKE"] == "1"))
func realModelsReuseUnloadAndReload() async throws {
  let service = TranscriptionService()
  try await service.prepare { print($0) }
  #expect(await service.isLoaded)
  // Cached preparation must not report any loading stages.
  try await service.prepare { _ in Issue.record("Cached models were loaded again") }
  await service.unload()
  #expect(await !service.isLoaded)
  try await service.prepare { print($0) }
  #expect(await service.isLoaded)
  await service.unload()
  #expect(await !service.isLoaded)
}
