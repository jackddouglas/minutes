import AppKit
import Testing

@testable import Minutes

@Test @MainActor func dockFollowsOpenWindowsAndRestoresOnReopen() {
  var policies: [NSApplication.ActivationPolicy] = []
  let controller = WindowDockController { policies.append($0) }
  let main = NSWindow()
  let settings = NSWindow()
  controller.refresh()
  controller.opened(main)
  controller.opened(main)
  controller.opened(settings)
  controller.closed(main)
  #expect(policies == [.accessory, .regular])
  // Visibility and focus changes do not close a window. Even an off-screen
  // window remains part of the app until its actual close notification.
  controller.refresh()
  #expect(policies == [.accessory, .regular])
  controller.closed(settings)
  controller.opened(main)
  #expect(policies == [.accessory, .regular, .accessory, .regular])
}
