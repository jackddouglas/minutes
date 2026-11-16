import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum RecorderLayout: String, CaseIterable {
  /// Meters, speakers counter, timer, key and label tape.
  case full
  /// Meters, timer and key in a narrow bar.
  case compact
}

/// A global keyboard shortcut, stored with the key's character for display.
struct RecorderShortcut: Codable, Equatable {
  var keyCode: UInt16
  /// `NSEvent.ModifierFlags` raw value, device-independent flags only.
  var modifiers: UInt
  var key: String

  static let `default` = RecorderShortcut(
    keyCode: UInt16(kVK_ANSI_R), modifiers: NSEvent.ModifierFlags([.option, .command]).rawValue,
    key: "R")

  var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

  /// A global shortcut needs Command, Control or Option, so typing is unaffected.
  var isValid: Bool { !flags.intersection([.command, .control, .option]).isEmpty }

  var carbonModifiers: UInt32 {
    var result: UInt32 = 0
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.control) { result |= UInt32(controlKey) }
    if flags.contains(.shift) { result |= UInt32(shiftKey) }
    return result
  }

  var displayString: String {
    var result = ""
    if flags.contains(.control) { result += "\u{2303}" }
    if flags.contains(.option) { result += "\u{2325}" }
    if flags.contains(.shift) { result += "\u{21E7}" }
    if flags.contains(.command) { result += "\u{2318}" }
    return result + key.uppercased()
  }

  init(keyCode: UInt16, modifiers: UInt, key: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.key = key
  }

  init?(event: NSEvent) {
    guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return nil }
    let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    self.init(keyCode: event.keyCode, modifiers: flags.rawValue, key: key)
    guard isValid else { return nil }
  }
}

/// The recorder's layout and shortcut, kept in user defaults.
@MainActor @Observable
final class RecorderSettings {
  static let shared = RecorderSettings()
  private static let layoutKey = "recorderLayout"
  private static let shortcutKey = "recorderShortcut"
  private let defaults: UserDefaults

  var layout: RecorderLayout {
    didSet { defaults.set(layout.rawValue, forKey: Self.layoutKey) }
  }

  /// `nil` when the user cleared the shortcut.
  var shortcut: RecorderShortcut? {
    didSet {
      defaults.set(
        shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: Self.shortcutKey)
      onShortcutChange(shortcut)
    }
  }

  @ObservationIgnored var onShortcutChange: (RecorderShortcut?) -> Void = { _ in }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    layout = defaults.string(forKey: Self.layoutKey).flatMap(RecorderLayout.init) ?? .full
    // No value yet: the default shortcut. An empty value: cleared on purpose.
    if let data = defaults.data(forKey: Self.shortcutKey) {
      shortcut = try? JSONDecoder().decode(RecorderShortcut.self, from: data)
    } else {
      shortcut = .default
    }
  }
}

/// One system-wide hotkey through Carbon, which needs no accessibility access.
@MainActor
final class GlobalHotKey {
  static let shared = GlobalHotKey()
  var action: () -> Void = {}
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?

  func register(_ shortcut: RecorderShortcut?) {
    unregister()
    guard let shortcut, shortcut.isValid else { return }
    installHandler()
    let id = EventHotKeyID(signature: OSType(0x4D4E_5453), id: 1)  // "MNTS"
    RegisterEventHotKey(
      UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0,
      &hotKey)
  }

  func unregister() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
  }

  private func installHandler() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.shared.action() } }
        return noErr
      }, 1, &spec, nil, &handler)
  }
}

// MARK: Settings

struct RecorderSettingsView: View {
  @Bindable var settings = RecorderSettings.shared

  var body: some View {
    Form {
      Section("Layout") {
        HStack(spacing: 14) {
          LayoutChoice(
            layout: .full, selection: $settings.layout, title: "Full",
            detail: "Meters, speakers and next meeting")
          LayoutChoice(
            layout: .compact, selection: $settings.layout, title: "Compact",
            detail: "Meters, timer and record key")
        }
        .padding(.vertical, 4)
      }
      Section {
        LabeledContent("Open recorder") {
          ShortcutField(shortcut: $settings.shortcut)
        }
      } header: {
        Text("Keyboard")
      } footer: {
        Text(
          "The shortcut opens the recorder in the middle of the screen from any app. Drag the recorder off the menu bar to keep it on screen; drag it back to the menu bar to put it away again."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped).scrollContentBackground(.hidden)
  }
}

private struct LayoutChoice: View {
  let layout: RecorderLayout
  @Binding var selection: RecorderLayout
  let title: String
  let detail: String

  var body: some View {
    let selected = selection == layout
    Button {
      selection = layout
    } label: {
      VStack(spacing: 8) {
        Group {
          if layout == .full { fullThumbnail } else { compactThumbnail }
        }
        .frame(height: 100)
        Text(title).font(.callout.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10).fill(
          selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10).strokeBorder(
          selected ? Color.accentColor : .clear, lineWidth: 2)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }

  private var face: some ShapeStyle {
    LinearGradient(
      colors: [RecorderFinish.ivory, RecorderFinish.lowerIvory], startPoint: .topLeading,
      endPoint: .bottomTrailing)
  }

  private var dial: some View {
    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.9, green: 0.9, blue: 0.83))
      .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(white: 0.15), lineWidth: 1.5))
  }

  private var key: some View {
    Circle().fill(Color(white: 0.93))
      .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
      .overlay(Circle().fill(RecorderFinish.orange).frame(width: 6, height: 6))
      .frame(width: 18, height: 18)
  }

  private var fullThumbnail: some View {
    VStack(spacing: 6) {
      HStack(spacing: 5) {
        dial
        dial
      }.frame(height: 26)
      HStack {
        Capsule().fill(.black.opacity(0.2)).frame(width: 26, height: 5)
        Spacer()
        key
      }
      RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.16)).frame(height: 7)
    }
    .padding(9)
    .frame(width: 92)
    .background(RoundedRectangle(cornerRadius: 9).fill(face))
    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }

  private var compactThumbnail: some View {
    HStack(spacing: 5) {
      dial.frame(width: 22, height: 14)
      dial.frame(width: 22, height: 14)
      Capsule().fill(.black.opacity(0.2)).frame(height: 5).padding(.horizontal, 4)
      key
    }
    .padding(.horizontal, 7).padding(.vertical, 5)
    .frame(width: 150)
    .background(RoundedRectangle(cornerRadius: 8).fill(face))
    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
  }
}

/// Click, then type the new shortcut. Escape cancels; the clear key removes it.
private struct ShortcutField: View {
  @Binding var shortcut: RecorderShortcut?
  @ViewState private var recording = false
  @ViewState private var monitor: Any?

  var body: some View {
    HStack(spacing: 6) {
      Button {
        recording ? stop() : start()
      } label: {
        Text(recording ? "Type shortcut…" : shortcut?.displayString ?? "None")
          .monospacedDigit()
          .frame(minWidth: 110)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel(
        recording ? "Recording shortcut" : "Shortcut, \(shortcut?.displayString ?? "none")")
      if shortcut != nil && !recording {
        Button {
          shortcut = nil
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear shortcut")
      }
    }
    .onDisappear { stop() }
  }

  private func start() {
    recording = true
    GlobalHotKey.shared.unregister()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      MainActor.assumeIsolated {
        if event.keyCode == UInt16(kVK_Escape) {
          stop()
        } else if let new = RecorderShortcut(event: event) {
          shortcut = new
          stop()
        }
      }
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    guard recording else { return }
    recording = false
    GlobalHotKey.shared.register(shortcut)
  }
}
