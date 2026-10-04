import AppKit
import SwiftUI

// Explicitly select the stable property wrapper. The macOS 27 beta SDK also
// exports a same-named macro whose plugin is absent from Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct MinutesApp: App {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @ViewState private var model = AppModel()

  var body: some Scene {
    Window("Minutes", id: "main") {
      ContentView(model: model)
        .onAppear {
          model.calendarMonitor.onOpen = { meeting in
            openWindow(id: "main")
            model.calendarPrompt = meeting
          }
          model.calendarMonitor.startMonitoring()
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
          delegate.isWorking = { model.isRecording || model.isBusy }
          delegate.installPlaybackShortcut {
            guard !model.isBusy, !model.isRecording,
              model.selectedMeeting?.isTranscribed == true
            else { return false }
            model.togglePlayback()
            return true
          }
        }
    }
    .defaultSize(width: 1080, height: 740)
    .defaultLaunchBehavior(.presented)
    .commands {
      CommandGroup(replacing: .appSettings) {
        Button("Settings…") { openSettings() }
          .keyboardShortcut(",", modifiers: .command)
      }
      CommandGroup(replacing: .newItem) {
        Button("New Meeting") {
          openWindow(id: "main")
          model.newMeeting()
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(model.isBusy || model.isRecording)
        Button("Import recording…") { model.importRecording() }
          .keyboardShortcut("i", modifiers: .command)
          .disabled(model.isBusy || model.isRecording)
        Button("Import system audio & microphone…") { model.importRecording(paired: true) }
          .disabled(model.isBusy || model.isRecording)
      }
      CommandGroup(after: .pasteboard) {
        Button("Move Meeting to Trash…") { model.meetingToDelete = model.selectedMeeting }
          .keyboardShortcut(.delete, modifiers: .command)
          .disabled(model.selectedMeeting == nil || model.isBusy || model.isRecording)
      }
    }
    Settings {
      MinutesSettingsView(model: model)
    }.windowResizability(.contentSize)

    MenuBarExtra {
      MinutesMenu(model: model)
    } label: {
      Label(
        model.isRecording ? "Minutes — Recording" : "Minutes",
        systemImage: model.isRecording ? "record.circle.fill" : "waveform")
    }
  }
}

private struct MinutesMenu: View {
  let model: AppModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Open Minutes") { showWindow() }
    if model.isRecording {
      Text("Recording")
      Button("Stop & Transcribe") { model.stop() }
        .disabled(model.isBusy)
    } else if model.isBusy {
      Text(model.status)
    } else {
      Button("New Recording…") {
        model.newMeeting()
        showWindow()
      }
    }
    if let error = model.error {
      Button("Recording or transcription needs attention…") { showWindow() }
        .help(error)
    }
    Divider()
    if model.calendarMonitor.invitations.isEmpty {
      Text(model.calendarMonitor.menuStatus)
    } else {
      ForEach(model.calendarMonitor.invitations) { meeting in
        Button("Record \(meeting.title)…") {
          model.calendarPrompt = meeting
          showWindow()
        }
        .disabled(model.isBusy || model.isRecording)
      }
    }
    Divider()
    Button("Settings…") {
      openSettings()
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("Quit Minutes") { NSApp.terminate(nil) }
      .disabled(model.isBusy || model.isRecording)
  }

  private func showWindow() {
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var isWorking: () -> Bool = { false }
  private var playbackMonitor: Any?
  private var togglePlayback: (() -> Bool)?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func installPlaybackShortcut(_ action: @escaping () -> Bool) {
    togglePlayback = action
    guard playbackMonitor == nil else { return }
    guard playbackMonitor == nil else { return }
    playbackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard event.keyCode == 49,
          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
          let window = NSApp.keyWindow, window.identifier?.rawValue == "main",
          window.attachedSheet == nil, NSApp.modalWindow == nil
        else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        if window.firstResponder is NSTextField { return false }
        guard !event.isARepeat else { return true }
        return self?.togglePlayback?() == true
      }
      return consumed ? nil : event
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard isWorking() else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "Minutes is still working"
    alert.informativeText = "Stop the recording and let transcription finish before quitting."
    alert.addButton(withTitle: "Keep Minutes open")
    alert.runModal()
    return .terminateCancel
  }
}
