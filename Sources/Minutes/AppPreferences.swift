import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class AppPreferences {
  private let defaults: UserDefaults
  var menuBarOnly: Bool {
    didSet {
      defaults.set(menuBarOnly, forKey: "menuBarOnly")
      NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }
  }
  private(set) var loginStatus = SMAppService.mainApp.status
  private(set) var changingLogin = false
  var loginError: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    menuBarOnly = defaults.bool(forKey: "menuBarOnly")
  }

  var opensAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

  func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

  func setOpenAtLogin(_ enabled: Bool) {
    guard !changingLogin else { return }
    changingLogin = true
    loginError = nil
    Task {
      defer {
        refreshLoginStatus()
        changingLogin = false
      }
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try await SMAppService.mainApp.unregister()
        }
      } catch {
        loginError = "Could not change Open at login. Try again from the installed Minutes app."
      }
    }
  }

}
