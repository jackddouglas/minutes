import AppKit
import SwiftUI

struct BrowserSource: Identifiable {
  let processID: pid_t
  let applicationName: String
  var id: pid_t { processID }

  static func isBrowser(_ bundleID: String) -> Bool {
    [
      "com.apple.Safari", "com.apple.SafariTechnologyPreview",
      "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev",
      "com.google.Chrome.canary",
      "org.chromium.Chromium", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
      "org.mozilla.nightly",
      "net.imput.helium", "company.thebrowser.Browser",
      "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
      "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
      "com.microsoft.edgemac.Canary",
      "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi",
      "com.kagi.kagimacOS", "app.zen-browser.zen", "com.duckduckgo.macos.browser",
    ].contains(bundleID)
  }

  @MainActor static func running() -> [BrowserSource] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.activationPolicy == .regular, !app.isTerminated,
        let bundleID = app.bundleIdentifier, isBrowser(bundleID), let name = app.localizedName
      else { return nil }
      return BrowserSource(processID: app.processIdentifier, applicationName: name)
    }.sorted {
      $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
    }
  }
}

struct BrowserPicker: View {
  @Bindable var model: AppModel

  var body: some View {
    Group {
      if model.applications.isEmpty {
        LabeledContent("Browser", value: "Open a browser to record")
          .foregroundStyle(.secondary)
      } else {
        Picker("Browser", selection: $model.sourceID) {
          ForEach(model.applications) { app in
            Text(app.applicationName).tag(app.processID)
          }
        }
      }
    }
    .onAppear { model.refreshSources() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      model.refreshSources()
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didLaunchApplicationNotification)
    ) { _ in
      model.refreshSources()
    }
    .onReceive(
      NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.didTerminateApplicationNotification)
    ) { _ in
      model.refreshSources()
    }
  }
}
