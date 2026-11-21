import AppKit
import SwiftUI

// Explicitly select the stable property wrapper. The macOS 27 beta SDK also
// exports a same-named macro whose plugin is absent from Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct MinutesApp: App {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject private var updater = AppUpdater.shared
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @ViewState private var model = AppModel()
  @ViewState private var preferences = AppPreferences()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    Window("Minutes", id: "main") {
      ContentView(model: model)
        .background(WindowDockPresence())
        .environment(\.openRecorder, openRecorder)

    }
    .defaultSize(width: 1080, height: 740)
    .defaultLaunchBehavior(preferences.menuBarOnly ? .suppressed : .presented)
    .onChange(of: scenePhase, initial: true) { _, _ in
      configureBackgroundServices()
    }
    .onChange(of: model.isBusy || model.isRecording) { _, _ in
      updater.resumeInstallationIfIdle()
    }
    .commands {
      TranscriptFindCommands()
      CommandGroup(after: .appInfo) {
        if updater.isAvailable {
          Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates || model.isBusy || model.isRecording)
        }
      }
      CommandGroup(replacing: .newItem) {
        Button("New Recording…") { openRecorder() }
          .keyboardShortcut("n", modifiers: .command)
          .disabled(model.isBusy || model.isRecording)
        Button("Import Recording…") { model.importRecording() }
          .keyboardShortcut("i", modifiers: .command)
          .disabled(model.isBusy || model.isRecording)
        Button("Import System Audio & Microphone…") { model.importRecording(paired: true) }
          .disabled(model.isBusy || model.isRecording)
      }
      CommandGroup(after: .pasteboard) {
        Button("Move Meeting to Trash…") { model.meetingToDelete = model.selectedMeeting }
          .keyboardShortcut(.delete, modifiers: .command)
          .disabled(model.selectedMeeting == nil || model.isBusy || model.isRecording)
      }
    }
    Settings {
      MinutesSettingsView(model: model, preferences: preferences)
        .background(WindowDockPresence())
    }.windowResizability(.contentSize)

  }

  private var openRecorder: OpenRecorderAction {
    OpenRecorderAction { [delegate] in delegate.recorderPanel?.showDocked() }
  }

  private func configureBackgroundServices() {
    delegate.showMainWindow = {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    if delegate.recorderPanel == nil {
      delegate.recorderPanel = RecorderPanelController(model: model) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    model.calendarMonitor.showMeetEndRecorder = { delegate.recorderPanel?.showDocked() }
    model.calendarMonitor.onOpenMeeting = { id in
      model.selection = id
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    model.calendarMonitor.onOpen = { meeting in
      model.prepareRecording(for: meeting)
      delegate.recorderPanel?.showDocked()
    }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1))
      delegate.recorderPanel?.introduceIfNeeded()
    }
    GlobalHotKey.shared.action = { delegate.recorderPanel?.toggleFromShortcut() }
    RecorderSettings.shared.onShortcutChange = { GlobalHotKey.shared.register($0) }
    GlobalHotKey.shared.register(RecorderSettings.shared.shortcut)
    model.calendarMonitor.startMonitoring()
    WindowDockController.shared.refresh()
    delegate.isWorking = { model.isRecording || model.isBusy }
    updater.isWorking = { model.isRecording || model.isBusy }
    updater.start()
    delegate.installPlaybackShortcut {
      guard !model.isBusy, !model.isRecording,
        model.selectedMeeting?.isTranscribed == true
      else { return false }
      model.togglePlayback()
      return true
    }
  }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var isWorking: () -> Bool = { false }
  var showMainWindow: () -> Void = {}
  var recorderPanel: RecorderPanelController?
  private var playbackMonitor: Any?
  private var togglePlayback: (() -> Bool)?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showMainWindow()
    return false
  }

  func installPlaybackShortcut(_ action: @escaping () -> Bool) {
    togglePlayback = action
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
