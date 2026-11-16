import AppKit
import Carbon.HIToolbox
import Testing

@testable import Minutes

private func defaults() -> UserDefaults {
  let name = "RecorderSettingsTests.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: name)!
  defaults.removePersistentDomain(forName: name)
  return defaults
}

@Test func defaultShortcutIsOptionCommandR() {
  let shortcut = RecorderShortcut.default
  #expect(shortcut.displayString == "\u{2325}\u{2318}R")
  #expect(shortcut.carbonModifiers == UInt32(optionKey | cmdKey))
  #expect(shortcut.keyCode == UInt16(kVK_ANSI_R))
  #expect(shortcut.isValid)
}

@Test func shortcutsNeedCommandControlOrOption() {
  let shiftOnly = RecorderShortcut(
    keyCode: UInt16(kVK_ANSI_R), modifiers: NSEvent.ModifierFlags.shift.rawValue, key: "r")
  #expect(!shiftOnly.isValid)
  let all = RecorderShortcut(
    keyCode: UInt16(kVK_ANSI_M),
    modifiers: NSEvent.ModifierFlags([.control, .option, .shift, .command]).rawValue, key: "m")
  #expect(all.isValid)
  #expect(all.displayString == "\u{2303}\u{2325}\u{21E7}\u{2318}M")
  #expect(all.carbonModifiers == UInt32(controlKey | optionKey | shiftKey | cmdKey))
}

@Test @MainActor func settingsKeepLayoutAndShortcutIncludingAClearedOne() {
  let store = defaults()
  let fresh = RecorderSettings(defaults: store)
  #expect(fresh.layout == .full)
  #expect(fresh.shortcut == .default)

  var changes: [RecorderShortcut?] = []
  fresh.onShortcutChange = { changes.append($0) }
  fresh.layout = .compact
  let custom = RecorderShortcut(
    keyCode: UInt16(kVK_ANSI_M), modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue,
    key: "m")
  fresh.shortcut = custom
  #expect(changes == [custom])
  let reloaded = RecorderSettings(defaults: store)
  #expect(reloaded.layout == .compact)
  #expect(reloaded.shortcut == custom)

  // Clearing is a choice: it must not come back as the default.
  reloaded.shortcut = nil
  #expect(RecorderSettings(defaults: store).shortcut == nil)
}
