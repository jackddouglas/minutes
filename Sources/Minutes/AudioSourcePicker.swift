import AppKit
import SwiftUI

struct AudioSource: Identifiable {
  enum Kind { case callApp, browser }

  let processID: pid_t
  let applicationName: String
  let kind: Kind
  var id: pid_t { processID }

  static func kind(of bundleID: String) -> Kind? {
    if isCallApp(bundleID) { return .callApp }
    if isBrowser(bundleID) { return .browser }
    return nil
  }

  static func isCallApp(_ bundleID: String) -> Bool {
    [
      "com.apple.FaceTime", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
      "com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary",
      "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
      "com.tinyspeck.slackmacgap", "Cisco-Systems.Spark",
      "org.whispersystems.signal-desktop", "ru.keepcoder.Telegram", "org.telegram.desktop",
    ].contains(bundleID)
  }

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

  @MainActor static func running() -> [AudioSource] {
    NSWorkspace.shared.runningApplications.compactMap { app in
      guard app.activationPolicy == .regular, !app.isTerminated,
        let bundleID = app.bundleIdentifier, let kind = kind(of: bundleID),
        let name = app.localizedName
      else { return nil }
      return AudioSource(processID: app.processIdentifier, applicationName: name, kind: kind)
    }.sorted {
      return $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName)
        == .orderedAscending
    }
  }
}

/// The recorder's system-audio source: the selected app as a quiet menu.
struct AudioSourceMenu: View {
  @Bindable var model: AppModel

  var body: some View {
    Group {
      if let selected = model.applications.first(where: { $0.processID == model.sourceID }) {
        Menu {
          Picker("Source", selection: $model.sourceID) {
            ForEach(model.applications) { app in
              Text(app.applicationName).tag(app.processID)
            }
          }.pickerStyle(.inline)
        } label: {
          // A plain style lets the label inherit the meter caption's type.
          HStack(spacing: 3) {
            Text(selected.applicationName)
            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
          }
          .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("App to record")
      } else {
        Text("No app open")
      }
    }
    .refreshingAudioSources(model)
  }
}

extension View {
  fileprivate func refreshingAudioSources(_ model: AppModel) -> some View {
    self
      .onAppear { model.refreshSources() }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
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
