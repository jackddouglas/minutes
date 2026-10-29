import Foundation
import Testing

@testable import Minutes

@Test func updateConfigurationRequiresHTTPSAndSigningKey() {
  let valid: [String: Any] = [
    "SUFeedURL": "https://example.com/appcast.xml",
    "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
  ]
  #expect(AppUpdater.isEnabled(info: valid, bundlePath: "/Applications/Minutes.app"))
  #expect(!AppUpdater.isEnabled(info: [:], bundlePath: "/Applications/Minutes.app"))
  for path in [
    "/nix/store/abc-minutes/Applications/Minutes.app", "/Applications/Nix Apps/Minutes.app",
  ] {
    #expect(!AppUpdater.isEnabled(info: valid, bundlePath: path))
  }
  var invalid = valid
  invalid["SUFeedURL"] = "http://example.com/appcast.xml"
  #expect(!AppUpdater.isEnabled(info: invalid, bundlePath: "/Applications/Minutes.app"))
  invalid = valid
  invalid["SUPublicEDKey"] = "invalid"
  #expect(!AppUpdater.isEnabled(info: invalid, bundlePath: "/Applications/Minutes.app"))
}

@Test @MainActor func updateInstallationWaitsUntilIdleAndResumesOnce() {
  let updater = AppUpdater()
  #expect(
    updater.responds(
      to: NSSelectorFromString("updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:")))
  var working = true
  var installations = 0
  updater.isWorking = { working }
  #expect(updater.postponeInstallationIfWorking { installations += 1 })
  updater.resumeInstallationIfIdle()
  #expect(installations == 0)
  working = false
  updater.resumeInstallationIfIdle()
  updater.resumeInstallationIfIdle()
  #expect(installations == 1)
  #expect(!updater.postponeInstallationIfWorking { installations += 1 })
}
