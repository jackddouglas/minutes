import ServiceManagement
import SwiftUI

struct MinutesSettingsView: View {
  @Bindable var model: AppModel
  @Bindable var preferences: AppPreferences
  @ViewState private var newSpeakerName = ""
  @ViewState private var choosingCalendars = false

  var body: some View {
    VStack(spacing: 0) {
      TabView {
        Form {
          Section("Startup") {
            Toggle(
              "Open at login",
              isOn: Binding(
                get: { preferences.opensAtLogin },
                set: { preferences.setOpenAtLogin($0) })
            )
            .disabled(preferences.changingLogin)
            if preferences.loginStatus == .requiresApproval {
              Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = preferences.loginError {
              Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle("Hide Dock icon", isOn: $preferences.menuBarOnly)
          }
          Section("Calendar") {
            Toggle(
              "Detect Google Meet meetings",
              isOn: Binding(
                get: { model.calendarMonitor.enabled },
                set: { model.calendarMonitor.setEnabled($0) })
            )
            .disabled(model.calendarMonitor.requestingAccess)
            if model.calendarMonitor.requestingAccess { ProgressView("Requesting permission…") }
            Text(model.calendarMonitor.status).font(.callout).foregroundStyle(.secondary)
            if model.calendarMonitor.enabled && !model.calendarMonitor.notificationsAllowed {
              Text(
                "Notifications are off. Prompts still appear in Minutes. Enable banners in System Settings → Notifications → Minutes for reminders while using other apps."
              )
              .font(.caption).foregroundStyle(.secondary)
            }
            Button("Refresh Calendar") { model.calendarMonitor.refresh() }
              .disabled(!model.calendarMonitor.enabled)
          }
          if !model.calendarMonitor.calendars.isEmpty {
            LabeledContent("Calendars to Monitor") {
              Button {
                choosingCalendars.toggle()
              } label: {
                HStack(spacing: 6) {
                  Text(calendarSelectionLabel).lineLimit(1)
                  Image(systemName: "chevron.down").font(.caption)
                }
              }
              .accessibilityLabel("Calendars to Monitor: \(calendarSelectionLabel)")
              .popover(isPresented: $choosingCalendars, arrowEdge: .bottom) {
                ScrollView {
                  VStack(alignment: .leading, spacing: 12) {
                    ForEach(calendarSources, id: \.self) { source in
                      VStack(alignment: .leading, spacing: 8) {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                        ForEach(model.calendarMonitor.calendars.filter { $0.source == source }) {
                          calendar in
                          Toggle(
                            isOn: Binding(
                              get: {
                                model.calendarMonitor.selectedCalendarIDs.contains(calendar.id)
                              },
                              set: { model.calendarMonitor.setCalendar(calendar.id, selected: $0) }
                            )
                          ) {
                            HStack(spacing: 8) {
                              Circle().fill(Color(cgColor: calendar.color))
                                .frame(width: 10, height: 10)
                              Text(calendar.title)
                            }
                          }
                          .toggleStyle(.checkbox)
                          .accessibilityLabel("\(calendar.title), \(calendar.source)")
                        }
                      }
                    }
                  }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 320, height: 360)
              }
            }
          }
          Section("Markdown Export") {
            LabeledContent("Folder") {
              Text(model.exportDirectory.path).lineLimit(3).textSelection(.enabled)
                .help(model.exportDirectory.path)
            }
            Button("Choose Folder…") { model.chooseExportDirectory() }
              .disabled(model.isBusy || model.isRecording)
          }
        }.formStyle(.grouped).scrollContentBackground(.hidden).tabItem {
          Label("General", systemImage: "gearshape")
        }
        Form {
          Section("Saved Speakers") {
            if model.savedSpeakers.isEmpty {
              Text("Add the people you meet with, then name their passages in Review Speakers.")
                .foregroundStyle(.secondary)
            }
            ForEach(model.savedSpeakers, id: \.self) { name in
              LabeledContent(name) {
                Button("Remove", systemImage: "minus.circle") {
                  model.savedSpeakers.removeAll { $0 == name }
                }.labelStyle(.iconOnly).help("Remove \(name) from saved speakers")
              }
            }
            HStack {
              TextField("Speaker name", text: $newSpeakerName).onSubmit { saveSpeaker() }
              Button("Add") { saveSpeaker() }
                .disabled(newSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(
              "Names are shortcuts for manual assignment, not voice profiles. Removing a name leaves existing transcripts unchanged."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped).scrollContentBackground(.hidden).tabItem {
          Label("Speakers", systemImage: "person.2")
        }
        Form {
          Section("Speaker Analysis") {
            SpeakerAnalysisPicker(quality: $model.defaultQuality)
          }
          Section("Local Models") {
            LabeledContent("Status", value: model.modelsReady ? "Loaded" : "Not loaded")
            Picker("Unload after idle", selection: $model.modelIdleMinutes) {
              Text("Never").tag(0)
              Text("1 minute").tag(1)
              Text("5 minutes").tag(5)
              Text("10 minutes").tag(10)
              Text("30 minutes").tag(30)
              Text("1 hour").tag(60)
            }
            Button("Unload Models") { model.unloadModels() }
              .disabled(!model.modelsReady || model.isBusy || model.isRecording)
            Text(
              "Models download on first use and load automatically. Unloading frees memory and keeps downloaded files."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped).scrollContentBackground(.hidden).tabItem {
          Label("Transcription", systemImage: "waveform")
        }
      }
    }.frame(width: 600, height: 590)
      .onAppear { preferences.refreshLoginStatus() }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        preferences.refreshLoginStatus()
      }
      .background(Color(nsColor: .windowBackgroundColor))
  }

  private var calendarSources: [String] {
    Set(model.calendarMonitor.calendars.map(\.source)).sorted()
  }

  private var calendarSelectionLabel: String {
    let selected = model.calendarMonitor.calendars.filter {
      model.calendarMonitor.selectedCalendarIDs.contains($0.id)
    }
    if selected.count == 1 { return selected[0].title }
    return selected.isEmpty ? "Choose Calendars…" : "\(selected.count) calendars selected"
  }

  private func saveSpeaker() {
    model.addSavedSpeaker(newSpeakerName)
    newSpeakerName = ""
  }
}
