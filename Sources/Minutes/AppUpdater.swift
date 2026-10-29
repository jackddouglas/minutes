import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
  static let shared = AppUpdater()

  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var isAvailable = false
  var isWorking: () -> Bool = { false }
  private var controller: SPUStandardUpdaterController?
  private var pendingInstallation: (() -> Void)?

  nonisolated static func isEnabled(info: [String: Any], bundlePath: String) -> Bool {
    guard !bundlePath.hasPrefix("/nix/store/"),
      !bundlePath.hasPrefix("/Applications/Nix Apps/"),
      let feed = info["SUFeedURL"] as? String,
      let url = URL(string: feed), url.scheme == "https", url.host != nil,
      let key = info["SUPublicEDKey"] as? String,
      Data(base64Encoded: key)?.count == 32
    else { return false }
    return true
  }

  func start() {
    guard controller == nil,
      Self.isEnabled(
        info: Bundle.main.infoDictionary ?? [:],
        bundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path)
    else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    isAvailable = true
    controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
  }

  func checkForUpdates() {
    guard !isWorking() else { return }
    controller?.checkForUpdates(nil)
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    guard !isWorking() else {
      throw NSError(
        domain: "app.minutes.meetings.updates", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Updates wait until recording and transcription finish."
        ])
    }
  }

  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate update: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    postponeInstallationIfWorking(installHandler)
  }

  func postponeInstallationIfWorking(_ install: @escaping () -> Void) -> Bool {
    guard isWorking() else { return false }
    pendingInstallation = install
    return true
  }

  func resumeInstallationIfIdle() {
    guard !isWorking(), let install = pendingInstallation else { return }
    pendingInstallation = nil
    install()
  }
}
