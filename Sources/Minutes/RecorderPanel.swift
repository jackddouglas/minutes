import AppKit
import MinutesCore
import OSLog
import Observation
import SwiftUI

/// The recorder as an object that drops from its own menu bar item. The main
/// window holds only the library; it opens this same recorder from its toolbar.
@MainActor
final class RecorderPanelController: NSObject, NSWindowDelegate {
  static let liftScale: CGFloat = 1.02
  private static let log = Logger(subsystem: "app.minutes.meetings", category: "RecorderPanel")

  private let model: AppModel
  private let openMainWindow: () -> Void
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let visibility = RecorderPanelVisibility()
  private let panel: RecorderPanel
  private let hosting: NSHostingView<RecorderPanelContent>
  private let dropTarget = RecorderDropTarget()
  private(set) var mode = RecorderPanelMode.hidden
  private let dragRelay = RecorderPanelDragRelay()
  private var dragStart: (mouse: CGPoint, origin: CGPoint)?
  private var movingProgrammatically = false
  private var monitors: [Any] = []
  private var clock: Timer?
  /// Where the recorder hangs when it was not opened from its menu bar item:
  /// below the window's record key, or centred on screen. Cleared when the
  /// recorder is put away or dragged, so the menu bar item is home again.
  private var customAnchor: ((CGSize) -> (anchor: CGRect, visibleFrame: CGRect))?
  private var customAnchorKey: CGRect?

  init(model: AppModel, openMainWindow: @escaping () -> Void) {
    self.model = model
    self.openMainWindow = openMainWindow
    hosting = NSHostingView(
      rootView: RecorderPanelContent(model: model, visibility: visibility, drag: dragRelay))
    panel = RecorderPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: true)
    super.init()

    panel.contentView = hosting
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.apply(self?.mode.dismissed() ?? .hidden) }
    dragRelay.changed = { [weak self] in self?.dragChanged() }
    dragRelay.ended = { [weak self] in self?.dragFinished() }
    dragRelay.openMeeting = { [weak self] id in
      guard let self else { return }
      self.model.selection = id
      self.apply(self.mode.dismissed())
      self.openMainWindow()
    }

    if let button = statusItem.button {
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    updateStatusItem()
    observeRecording()
    installDismissMonitors()
  }

  /// Opens the recorder below the menu bar item, for example for a calendar event.
  func showDocked() {
    customAnchor = nil
    customAnchorKey = nil
    apply(.docked)
  }

  /// Opens or closes the recorder below a key in a window, such as the
  /// library's record key. `key` is in screen coordinates.
  func toggle(below key: CGRect) {
    if mode != .hidden, customAnchorKey == key {
      apply(.hidden)
      return
    }
    let screen =
      NSScreen.screens.first { $0.frame.contains(CGPoint(x: key.midX, y: key.midY)) }
      ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? key
    customAnchor = { _ in (key, visibleFrame) }
    customAnchorKey = key
    apply(.docked)
  }

  /// Opens the recorder centred on the screen with the pointer, or puts it
  /// away when it is open.
  func toggleCentred() {
    if mode != .hidden {
      apply(.hidden)
      return
    }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    customAnchor = { size in
      let recorderHeight = size.height - 2 * RecorderPanelPlacement.shadowInset
      let top = visibleFrame.midY + recorderHeight / 2 + RecorderPanelPlacement.gap
      return (CGRect(x: visibleFrame.midX, y: top, width: 0, height: 0), visibleFrame)
    }
    customAnchorKey = nil
    apply(.docked)
  }

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
    menu.autoenablesItems = false
    menu.addAction("Open Minutes") { [weak self] in self?.openMainWindow() }
    if model.isRecording {
      menu.addAction("Stop & Transcribe", enabled: !model.isBusy) { [weak self] in
        self?.model.stop()
      }
    } else if model.isBusy {
      menu.addAction(model.status, enabled: false) {}
    } else {
      menu.addAction("New Recording…") { [weak self] in self?.showDocked() }
    }
    if model.error != nil {
      menu.addAction("Recording or Transcription Needs Attention…") { [weak self] in
        self?.openMainWindow()
      }
    }
    menu.addItem(.separator())
    let calendar = model.calendarMonitor
    if calendar.invitations.isEmpty {
      menu.addAction(calendar.menuStatus, enabled: false) {}
    } else {
      for meeting in calendar.invitations {
        menu.addAction("Record \(meeting.title)…", enabled: !model.isBusy && !model.isRecording) {
          [weak self] in
          self?.model.prepareRecording(for: meeting)
          self?.showDocked()
        }
      }
    }
    menu.addItem(.separator())
    menu.addAction("Settings…") {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    let updater = AppUpdater.shared
    if updater.isAvailable {
      menu.addAction(
        "Check for Updates…",
        enabled: updater.canCheckForUpdates && !model.isBusy && !model.isRecording
      ) { updater.checkForUpdates() }
    }
    menu.addAction("Quit Minutes") { NSApp.terminate(nil) }
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  /// Idle: a waveform. Recording: a red dot and the elapsed time. Busy, for
  /// example transcribing: an hourglass.
  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    if model.isRecording {
      let elapsed = Date().timeIntervalSince(model.recordingStarted ?? Date())
      let time = MarkdownExporter.timestamp(elapsed)
      button.image = nil
      button.attributedTitle = RecorderStatusTitle.recording(time: time)
      button.setAccessibilityLabel("Minutes, recording \(time)")
      if clock == nil {
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.updateStatusItem() }
        }
      }
      return
    }
    clock?.invalidate()
    clock = nil
    button.attributedTitle = NSAttributedString()
    let busy = model.isBusy
    button.image = NSImage(
      systemSymbolName: busy ? "hourglass" : "waveform",
      accessibilityDescription: busy ? "Minutes, \(model.status)" : "Minutes")
    button.setAccessibilityLabel(busy ? "Minutes, \(model.status)" : "Minutes")
  }

  // MARK: Modes

  private func apply(_ next: RecorderPanelMode) {
    let previous = mode
    mode = next
    if next == .hidden {
      customAnchor = nil
      customAnchorKey = nil
    }
    statusItem.button?.highlight(next == .docked)
    switch next {
    case .hidden where previous != .hidden:
      hide()
    case .docked:
      show(fromHidden: previous == .hidden)
    case .detached, .hidden:
      break
    }
  }

  private func show(fromHidden: Bool) {
    if !model.isRecording { model.refreshSources() }
    visibility.isVisible = true
    if fromHidden { visibility.isPresented = false }
    hosting.layoutSubtreeIfNeeded()
    guard let target = dockedFrame(size: hosting.fittingSize) else { return }
    guard fromHidden else {
      // A dropped or recalled recorder glides into its home.
      animate { self.panel.animator().setFrame(target, display: true) }
      panel.makeKey()
      return
    }
    // The window appears in place; the recorder inside unfolds from its item.
    visibility.unfoldAnchor = unfoldAnchor(in: target)
    setFrame(target, animated: false)
    panel.alphaValue = 1
    panel.makeKeyAndOrderFront(nil)
    Task { @MainActor in
      withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
        self.visibility.isPresented = true
      }
    }
  }

  private func hide() {
    withAnimation(.easeIn(duration: 0.12)) { visibility.isPresented = false }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard let self, self.mode == .hidden else { return }
      self.panel.orderOut(nil)
      self.visibility.isVisible = false
    }
  }

  /// The point on the recorder's top edge below its anchor, in the panel's
  /// content, which includes the shadow margin.
  private func unfoldAnchor(in frame: CGRect) -> UnitPoint {
    let anchor = anchor(for: frame.size)?.anchor
    let x = ((anchor?.midX ?? frame.midX) - frame.minX) / max(frame.width, 1)
    return UnitPoint(
      x: min(max(x, 0), 1), y: RecorderPanelPlacement.shadowInset / max(frame.height, 1))
  }

  private func anchor(for size: CGSize) -> (anchor: CGRect, visibleFrame: CGRect)? {
    if let customAnchor { return customAnchor(size) }
    guard let itemWindow = statusItem.button?.window,
      let screen = itemWindow.screen ?? NSScreen.main
    else { return nil }
    let anchor = RecorderPanelPlacement.anchor(
      for: itemWindow.frame, screens: NSScreen.screens.map(\.frame),
      fallback: screen.visibleFrame)
    return (anchor, screen.visibleFrame)
  }

  private func dockedFrame(size: CGSize) -> CGRect? {
    guard let (anchor, visibleFrame) = anchor(for: size) else { return nil }
    return RecorderPanelPlacement.dockedFrame(
      size: size, below: anchor, visibleFrame: visibleFrame)
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
    let wasRecording = model.isRecording
    withObservationTracking {
      _ = model.isRecording
      _ = model.isBusy
      _ = model.status
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.updateStatusItem()
        if self.model.isRecording && !wasRecording {
          self.apply(self.mode.recordingStarted())
        }
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
          // The key that opened the recorder closes it itself.
          guard let self, event.window !== self.panel,
            event.window !== self.statusItem.button?.window,
            self.customAnchorKey?.contains(NSEvent.mouseLocation) != true
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

  /// The app moves the panel itself: a window-server drag would stop the
  /// panel's top edge at the menu bar, keeping the recorder a shadow margin
  /// below it. Here the recorder itself stops at the menu bar.
  private func dragChanged() {
    guard mode != .hidden, let screen = panel.screen ?? NSScreen.main else { return }
    let mouse = NSEvent.mouseLocation
    if dragStart == nil {
      dragStart = (mouse, panel.frame.origin)
      // Once moved, the recorder's home is its menu bar item.
      customAnchor = nil
      customAnchorKey = nil
    }
    guard let start = dragStart else { return }
    pickUp()
    var origin = CGPoint(
      x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
    // Stop when the recorder's highest corner meets the bottom of the menu bar.
    // The lift scales it about its centre; the tilt turns it about the middle
    // of its top edge.
    let inset = RecorderPanelPlacement.shadowInset
    let objectHeight = panel.frame.height - 2 * inset
    let lift = visibility.isLifted ? objectHeight * (Self.liftScale - 1) / 2 : 0
    let halfWidth = (panel.frame.width / 2 - inset) * (visibility.isLifted ? Self.liftScale : 1)
    let corner = halfWidth * sin(abs(visibility.tilt) * .pi / 180)
    let highest = screen.visibleFrame.maxY + inset - lift - corner - panel.frame.height
    origin.y = min(origin.y, highest)
    setFrame(CGRect(origin: origin, size: panel.frame.size), animated: false)
    showDropTarget()
  }

  private func dragFinished() {
    guard dragStart != nil else { return }
    dragStart = nil
    dragEnded()
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
    let goesHome = next == .docked
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
  /// Opening unfolds the recorder from the point below its menu bar item.
  var isPresented = false
  var unfoldAnchor = UnitPoint.top
  var tilt: Double = 0
}

/// Forwards the recorder's drag gesture to the controller, which positions the
/// panel from the pointer's screen location.
@MainActor
final class RecorderPanelDragRelay {
  var changed: () -> Void = {}
  var ended: () -> Void = {}
  var openMeeting: (Meeting.ID) -> Void = { _ in }
}

/// The menu bar title while recording: a red dot and the elapsed time.
enum RecorderStatusTitle {
  static func recording(time: String) -> NSAttributedString {
    let size = NSFont.menuBarFont(ofSize: 0).pointSize
    let title = NSMutableAttributedString(
      string: "\u{25CF} ",
      attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: size - 3)])
    title.append(
      NSAttributedString(
        string: time,
        attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]))
    return title
  }
}

private final class MenuAction: NSObject {
  let run: () -> Void
  init(_ run: @escaping () -> Void) { self.run = run }
  @objc func runAction() { run() }
}

extension NSMenu {
  fileprivate func addAction(_ title: String, enabled: Bool = true, run: @escaping () -> Void) {
    let action = MenuAction(run)
    let item = addItem(withTitle: title, action: #selector(MenuAction.runAction), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    item.isEnabled = enabled
  }
}

/// Opens the menu bar recorder from a view, below the given screen rect, or
/// below its menu bar item when there is none.
struct OpenRecorderAction: Sendable {
  var open: @MainActor @Sendable (CGRect?) -> Void = { _ in }
  @MainActor func callAsFunction(below key: CGRect? = nil) { open(key) }
}

private struct OpenRecorderKey: EnvironmentKey {
  static let defaultValue = OpenRecorderAction()
}

extension EnvironmentValues {
  var openRecorder: OpenRecorderAction {
    get { self[OpenRecorderKey.self] }
    set { self[OpenRecorderKey.self] = newValue }
  }
}

struct RecorderPanelContent: View {
  @Bindable var model: AppModel
  let visibility: RecorderPanelVisibility
  let drag: RecorderPanelDragRelay

  private var faceplate: RecorderFaceplate {
    let recording = model.recordingMeetingID.flatMap { id in model.meetings.first { $0.id == id } }
    let latest = model.meetings.first
    return RecorderFaceplate(
      speakers: $model.recordingSystemSpeakers,
      speakersEnabled: !model.isRecording && !model.isBusy,
      tape: RecorderTape.content(
        isRecording: model.isRecording, isBusy: model.isBusy,
        recordingTitle: recording?.title ?? Meeting.untitled,
        prepared: model.preparedCalendarMeeting,
        next: model.calendarMonitor.upcoming.first, latest: latest),
      onTape: { action in
        switch action {
        case .arm(let meeting): model.prepareRecording(for: meeting)
        case .join: model.joinPreparedMeeting()
        case .open(let id): drag.openMeeting(id)
        }
      },
      working: model.isBusy && !model.isRecording
        ? (
          RecorderWorkingLabel.label(for: model.status),
          MarkdownExporter.timestamp(latest?.duration ?? 0)
        ) : nil)
  }

  var body: some View {
    if visibility.isVisible {
      Group {
        if model.isRecording {
          LiveRecordingView(model: model, faceplate: faceplate)
        } else {
          ReadyRecorderView(model: model, faceplate: faceplate) {
            AudioSourceMenu(model: model).disabled(model.isBusy)
          } accessory: {
            EmptyView()
          }
        }
      }
      .environment(\.recorderFitsContent, true)
      .modifier(Unfold(isPresented: visibility.isPresented, anchor: visibility.unfoldAnchor))
      .scaleEffect(visibility.isLifted ? RecorderPanelController.liftScale : 1)
      .rotationEffect(.degrees(visibility.tilt), anchor: .top)
      // After the rotation, so the lifted shadow falls straight down from the
      // tilted shape: a wide, soft ambient layer and a close contact layer.
      .shadow(color: .black.opacity(visibility.isLifted ? 0.14 : 0), radius: 22, y: 16)
      .shadow(color: .black.opacity(visibility.isLifted ? 0.08 : 0), radius: 4, y: 3)
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: visibility.tilt)
      .animation(.easeOut(duration: 0.15), value: visibility.isLifted)
      .gesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
          .onChanged { _ in drag.changed() }
          .onEnded { _ in drag.ended() })
    }
  }
}

/// Opening grows the recorder out of the point below its menu bar item;
/// Reduce Motion keeps only the fade.
private struct Unfold: ViewModifier {
  let isPresented: Bool
  let anchor: UnitPoint
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let moves = !isPresented && !reduceMotion
    content
      .scaleEffect(moves ? 0.9 : 1, anchor: anchor)
      .offset(y: moves ? -8 : 0)
      .opacity(isPresented ? 1 : 0)
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
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool { true }

  // The transparent shadow margin may overlap the menu bar; AppKit would
  // otherwise push the panel down and the recorder would miss its outline.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }

  override func cancelOperation(_ sender: Any?) { onCancel() }
}
