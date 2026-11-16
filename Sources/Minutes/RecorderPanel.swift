import AppKit
import OSLog
import Observation
import SwiftUI

/// Spike: the recorder as an object that drops from its own menu bar item.
/// Enabled with `defaults write app.minutes.meetings recorderPanel -bool true`.
@MainActor
final class RecorderPanelController: NSObject, NSWindowDelegate {
  static let defaultsKey = "recorderPanel"
  private static let log = Logger(subsystem: "app.minutes.meetings", category: "RecorderPanel")

  private let model: AppModel
  private let openMainWindow: () -> Void
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let visibility = RecorderPanelVisibility()
  private let panel: RecorderPanel
  private let hosting: NSHostingView<RecorderPanelContent>
  private let dropTarget = RecorderDropTarget()
  private(set) var mode = RecorderPanelMode.hidden
  private var dragCheck: Task<Void, Never>?
  private var movingProgrammatically = false
  private var monitors: [Any] = []

  init(model: AppModel, openMainWindow: @escaping () -> Void) {
    self.model = model
    self.openMainWindow = openMainWindow
    hosting = NSHostingView(rootView: RecorderPanelContent(model: model, visibility: visibility))
    panel = RecorderPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: true)
    super.init()

    panel.contentView = hosting
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.apply(self?.mode.dismissed() ?? .hidden) }

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Minutes")
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    observeRecording()
    installDismissMonitors()
  }

  /// Opens the recorder below the menu bar item, for example for a calendar event.
  func showDocked() { apply(.docked) }

  // MARK: Status item

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      showMenu()
    } else {
      apply(mode.itemClicked())
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.addItem(withTitle: "Open Minutes", action: #selector(openMinutes), keyEquivalent: "")
      .target = self
    menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
      .target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Minutes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func openMinutes() { openMainWindow() }

  @objc private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  private func updateStatusImage() {
    let name = model.isRecording ? "record.circle.fill" : "waveform"
    statusItem.button?.image = NSImage(
      systemSymbolName: name,
      accessibilityDescription: model.isRecording ? "Minutes — Recording" : "Minutes")
  }

  // MARK: Modes

  private func apply(_ next: RecorderPanelMode) {
    let previous = mode
    mode = next
    statusItem.button?.highlight(next == .docked)
    switch next {
    case .hidden where previous != .hidden:
      hide(returningHome: previous == .detached)
    case .docked:
      show(fromHidden: previous == .hidden)
    case .detached, .hidden:
      break
    }
  }

  private func show(fromHidden: Bool) {
    if !model.isRecording { model.refreshSources() }
    visibility.isVisible = true
    hosting.layoutSubtreeIfNeeded()
    let size = hosting.fittingSize
    guard let target = dockedFrame(size: size) else { return }
    if fromHidden {
      setFrame(target.offsetBy(dx: 0, dy: 8), animated: false)
      panel.alphaValue = 0
      panel.makeKeyAndOrderFront(nil)
    }
    animate {
      self.panel.animator().setFrame(target, display: true)
      self.panel.animator().alphaValue = 1
    }
    panel.makeKey()
  }

  /// A recorder dropped on the menu bar slides home before it disappears.
  private func hide(returningHome: Bool) {
    let home = returningHome ? dockedFrame(size: panel.frame.size) : nil
    animate {
      if let home { self.panel.animator().setFrame(home, display: true) }
      self.panel.animator().alphaValue = 0
    } completion: {
      guard self.mode == .hidden else { return }
      self.panel.orderOut(nil)
      self.visibility.isVisible = false
    }
  }

  private func dockedFrame(size: CGSize) -> CGRect? {
    guard let itemWindow = statusItem.button?.window,
      let screen = itemWindow.screen ?? NSScreen.main
    else { return nil }
    let anchor = RecorderPanelPlacement.anchor(
      for: itemWindow.frame, screens: NSScreen.screens.map(\.frame),
      fallback: screen.visibleFrame)
    return RecorderPanelPlacement.dockedFrame(
      size: size, below: anchor, visibleFrame: screen.visibleFrame)
  }

  private func setFrame(_ frame: CGRect, animated: Bool) {
    movingProgrammatically = true
    panel.setFrame(frame, display: true, animate: animated)
    movingProgrammatically = false
  }

  private func animate(
    _ changes: @escaping @MainActor () -> Void, completion: (@MainActor () -> Void)? = nil
  ) {
    movingProgrammatically = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      changes()
    } completionHandler: {
      MainActor.assumeIsolated {
        self.movingProgrammatically = false
        completion?()
      }
    }
  }

  // MARK: Recording

  private func observeRecording() {
    withObservationTracking {
      _ = model.isRecording
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.updateStatusImage()
        if self.model.isRecording { self.apply(self.mode.recordingStarted()) }
        self.observeRecording()
      }
    }
  }

  // MARK: Dismissal

  private func installDismissMonitors() {
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: mask,
      handler: { [weak self] _ in
        MainActor.assumeIsolated { self?.dismissIfDocked() }
      })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { [weak self] event in
        MainActor.assumeIsolated {
          guard let self, event.window !== self.panel,
            event.window !== self.statusItem.button?.window
          else { return }
          self.dismissIfDocked()
        }
        return event
      })
    {
      monitors.append(local)
    }
  }

  private func dismissIfDocked() {
    if mode == .docked { apply(.hidden) }
  }

  // MARK: Dragging

  func windowDidMove(_ notification: Notification) {
    guard !movingProgrammatically, mode != .hidden else { return }
    showDropTarget()
    pickUp()
    dragCheck?.cancel()
    dragCheck = Task { [weak self] in
      // The window server moves the panel; wait for the mouse to come up.
      while NSEvent.pressedMouseButtons & 1 != 0 {
        do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
      }
      self?.dragEnded()
    }
  }

  /// At the start of a drag the recorder lifts and settles at a small random
  /// angle, as if picked up by hand. It keeps that angle until it is put down.
  private func pickUp() {
    guard !visibility.isLifted else { return }
    visibility.isLifted = true
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    visibility.tilt = Double.random(in: 1.5...3) * (Bool.random() ? 1 : -1)
  }

  /// While dragging, outline the recorder's home below the menu bar item. The
  /// outline lights up when letting go would send the recorder home.
  private func showDropTarget() {
    guard let docked = dockedFrame(size: panel.frame.size),
      let screen = panel.screen ?? NSScreen.main
    else { return }
    let next = mode.dragEnded(at: panel.frame, docked: docked, visibleFrame: screen.visibleFrame)
    let goesHome = next != .detached
    dropTarget.show(
      frame: docked.insetBy(
        dx: RecorderPanelPlacement.shadowInset, dy: RecorderPanelPlacement.shadowInset),
      active: goesHome, below: panel)
    statusItem.button?.highlight(goesHome)
  }

  private func dragEnded() {
    dropTarget.hide()
    visibility.tilt = 0
    visibility.isLifted = false
    guard let docked = dockedFrame(size: panel.frame.size),
      let screen = panel.screen ?? NSScreen.main
    else { return }
    // A short drag snaps back to the item; .docked re-applies the docked frame.
    let next = mode.dragEnded(at: panel.frame, docked: docked, visibleFrame: screen.visibleFrame)
    Self.log.debug(
      "drag ended \(String(describing: self.mode)) -> \(String(describing: next)) frame \(self.panel.frame.debugDescription) visible \(screen.visibleFrame.debugDescription)"
    )
    apply(next)
  }
}

/// The outline of the recorder's home, shown below the menu bar item while the
/// recorder is dragged. It never takes clicks.
@MainActor
final class RecorderDropTarget {
  private let state = RecorderDropTargetState()
  private let window: NSPanel

  init() {
    window = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: true)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = .floating
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.contentView = NSHostingView(rootView: RecorderDropTargetView(state: state))
  }

  func show(frame: CGRect, active: Bool, below panel: NSWindow) {
    state.isActive = active
    if window.frame != frame { window.setFrame(frame, display: true) }
    if !window.isVisible { window.order(.below, relativeTo: panel.windowNumber) }
  }

  func hide() { window.orderOut(nil) }
}

@MainActor @Observable
final class RecorderDropTargetState {
  var isActive = false
}

private struct RecorderDropTargetView: View {
  let state: RecorderDropTargetState

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 20)
    ZStack {
      shape.fill(Color.white.opacity(state.isActive ? 0.18 : 0))
      // A dark rule under the light one keeps the outline visible on any wallpaper.
      shape.strokeBorder(
        Color.black.opacity(0.25),
        style: StrokeStyle(lineWidth: 3, dash: state.isActive ? [] : [7, 5]))
      shape.strokeBorder(
        Color.white.opacity(state.isActive ? 0.95 : 0.7),
        style: StrokeStyle(lineWidth: state.isActive ? 2 : 1.5, dash: state.isActive ? [] : [7, 5]))
    }
    .animation(.easeOut(duration: 0.15), value: state.isActive)
    .accessibilityHidden(true)
  }
}

@MainActor @Observable
final class RecorderPanelVisibility {
  /// Hidden panels drop their content so meters stop polling.
  var isVisible = false
  /// While dragged, the recorder lifts and holds a small tilt from its top edge.
  var isLifted = false
  var tilt: Double = 0
}

struct RecorderPanelContent: View {
  let model: AppModel
  let visibility: RecorderPanelVisibility

  var body: some View {
    if visibility.isVisible {
      Group {
        if model.isRecording {
          LiveRecordingView(model: model)
        } else {
          ReadyRecorderView(model: model) {
            AudioSourceMenu(model: model).disabled(model.isBusy)
          } accessory: {
            EmptyView()
          }
        }
      }
      .environment(\.recorderFitsContent, true)
      .scaleEffect(visibility.isLifted ? 1.02 : 1)
      .shadow(color: .black.opacity(visibility.isLifted ? 0.18 : 0), radius: 18, y: 12)
      .rotationEffect(.degrees(visibility.tilt), anchor: .top)
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: visibility.tilt)
      .animation(.easeOut(duration: 0.15), value: visibility.isLifted)
      .gesture(WindowDragGesture())
    }
  }
}

final class RecorderPanel: NSPanel {
  var onCancel: () -> Void = {}

  override init(
    contentRect: NSRect, styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
  ) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .floating
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) { onCancel() }
}
