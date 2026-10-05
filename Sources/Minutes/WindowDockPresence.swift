import AppKit
import SwiftUI

@MainActor
final class WindowDockController {
  static let shared = WindowDockController { NSApp.setActivationPolicy($0) }
  private let windows = NSHashTable<NSWindow>.weakObjects()
  private let setPolicy: (NSApplication.ActivationPolicy) -> Void
  private var lastPolicy: NSApplication.ActivationPolicy?

  init(setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void) {
    self.setPolicy = setPolicy
  }

  func opened(_ window: NSWindow) {
    windows.add(window)
    refresh()
  }

  func closed(_ window: NSWindow) {
    windows.remove(window)
    refresh()
  }

  func refresh() {
    let policy: NSApplication.ActivationPolicy = windows.allObjects.isEmpty ? .accessory : .regular
    guard policy != lastPolicy else { return }
    lastPolicy = policy
    setPolicy(policy)
  }
}

// Observe real window closure, not scene inactivity: switching apps, minimizing,
// or hiding Minutes must leave its open windows reachable through Command-Tab.
struct WindowDockPresence: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowObserver { WindowObserver() }
  func updateNSView(_ nsView: WindowObserver, context: Context) {}

  @MainActor
  final class WindowObserver: NSView {
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard observedWindow !== window else { return }
      NotificationCenter.default.removeObserver(self)
      if let observedWindow { WindowDockController.shared.closed(observedWindow) }
      observedWindow = window
      guard let window else { return }
      WindowDockController.shared.opened(window)
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowOpened(_:)), name: NSWindow.didBecomeKeyNotification,
        object: window)
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification,
        object: window)
    }

    @objc private func windowOpened(_ notification: Notification) {
      if let observedWindow { WindowDockController.shared.opened(observedWindow) }
    }

    @objc private func windowClosed(_ notification: Notification) {
      if let observedWindow { WindowDockController.shared.closed(observedWindow) }
    }
  }
}
