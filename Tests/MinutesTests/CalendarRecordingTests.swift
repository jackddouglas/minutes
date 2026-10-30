import Foundation
import MinutesCore
import Testing

@testable import Minutes

@Test @MainActor func calendarRecordOpensNewMeetingNamedForTheEvent() throws {
  let suite = "MinutesTests.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let model = AppModel(supportDirectory: directory, preferences: preferences)
  let previous = Meeting(title: "Earlier")
  model.meetings = [previous]
  model.selection = previous.id
  model.title = "Leftover draft"
  model.recordingSystemSpeakers = 4
  let event = CalendarMeeting(
    eventID: "standup", title: "Design Review", start: .now, end: .now.addingTimeInterval(1800),
    url: try #require(URL(string: "https://meet.google.com/abc-defg-hij")))
  model.calendarMonitor.invitations = [event]

  model.prepareRecording(for: event)

  #expect(model.selection == nil)
  #expect(model.title == "Design Review")
  #expect(model.recordingSystemSpeakers == 0)
  #expect(model.preparedCalendarMeeting == event)
  #expect(model.calendarMonitor.invitations.isEmpty)

  model.newMeeting()
  #expect(model.title.isEmpty)
  #expect(model.preparedCalendarMeeting == nil)
}

@Test @MainActor func calendarAudioSourceRankingPersistsChoicesAndPreservesFallbacks() throws {
  let suite = "MinutesTests.\(UUID().uuidString)"
  let preferences = try #require(UserDefaults(suiteName: suite))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer {
    preferences.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
  let discord = AudioSource(
    processID: 1, applicationName: "Discord", bundleID: "com.hnc.Discord", kind: .callApp)
  let helium = AudioSource(
    processID: 2, applicationName: "Helium", bundleID: "net.imput.helium", kind: .browser)
  let safari = AudioSource(
    processID: 3, applicationName: "Safari", bundleID: "com.apple.Safari", kind: .browser)
  var running = [safari, helium, discord]
  func makeModel() -> AppModel {
    AppModel(
      supportDirectory: directory, preferences: preferences,
      runningAudioSources: { running }, defaultBrowserBundleID: { _ in safari.bundleID })
  }
  let event = CalendarMeeting(
    eventID: "meet", title: "Meeting", start: .now, end: .now.addingTimeInterval(1800),
    url: try #require(URL(string: "https://meet.google.com/abc-defg-hij")))
  let model = makeModel()
  model.refreshSources()
  #expect(model.sourceID == discord.processID)
  model.prepareRecording(for: event)
  #expect(model.sourceID == safari.processID)
  model.selectSource(helium.processID)
  #expect(model.meetingBrowserBundleID == helium.bundleID)

  // Relaunching both apps restores the stable bundle identity, not the old PID.
  let reopenedHelium = AudioSource(
    processID: 20, applicationName: "Helium", bundleID: helium.bundleID, kind: .browser)
  running = [discord, reopenedHelium, safari]
  let restored = makeModel()
  restored.refreshSources()
  #expect(restored.sourceID == reopenedHelium.processID)
  restored.prepareRecording(for: event)
  #expect(restored.sourceID == reopenedHelium.processID)

  // A manual recording choice does not erase the separate Google Meet preference.
  restored.newMeeting()
  restored.selectSource(safari.processID)
  restored.prepareRecording(for: event)
  #expect(restored.sourceID == reopenedHelium.processID)
  running = [discord, safari]
  restored.refreshSources()
  #expect(restored.sourceID == safari.processID)
  #expect(restored.meetingBrowserBundleID == safari.bundleID)
  running = [discord]
  restored.refreshSources()
  #expect(restored.sourceID == discord.processID)
  #expect(preferences.string(forKey: "googleMeetBrowserBundleID") == helium.bundleID)
  #expect(preferences.string(forKey: "lastAudioSourceBundleID") == safari.bundleID)
  running = [discord, reopenedHelium, safari]
  restored.refreshSources()
  #expect(restored.sourceID == reopenedHelium.processID)

  // An explicit session override wins even when the preferred browser returns.
  restored.selectSource(discord.processID)
  restored.refreshSources()
  #expect(restored.sourceID == discord.processID)
  #expect(preferences.string(forKey: "googleMeetBrowserBundleID") == helium.bundleID)
  restored.prepareRecording(for: event)
  #expect(restored.sourceID == reopenedHelium.processID)

  // App lifecycle notifications cannot change the source during capture or setup.
  running = [discord]
  restored.isRecording = true
  restored.refreshSources()
  restored.selectSource(discord.processID)
  #expect(restored.sourceID == reopenedHelium.processID)
  restored.isRecording = false
  restored.isBusy = true
  restored.refreshSources()
  #expect(restored.sourceID == reopenedHelium.processID)
  restored.isBusy = false
  running = []
  restored.refreshSources()
  #expect(restored.sourceID == 0)
  #expect(!restored.canStart)
}
