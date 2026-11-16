import CoreGraphics

/// Where the menu bar recorder is. A docked recorder hangs below its menu bar
/// item and puts itself away when recording starts. Dragging it off the menu
/// bar detaches it so it stays on screen; dropping it back on the menu bar docks
/// it again, open until it is dismissed.
enum RecorderPanelMode: Equatable {
  case hidden, docked, detached

  /// A click on the menu bar item opens the recorder, closes it, or calls a
  /// detached recorder home.
  func itemClicked() -> Self { self == .docked ? .hidden : .docked }

  func recordingStarted() -> Self { self == .docked ? .hidden : self }

  /// Escape and clicks elsewhere dismiss only a docked recorder.
  func dismissed() -> Self { self == .docked ? .hidden : self }

  /// Dropping the recorder near the menu bar, or on its home outline, docks
  /// it; anywhere else it stays where it was put. A docked recorder stays open
  /// until dismissed.
  func dragEnded(at frame: CGRect, docked: CGRect, visibleFrame: CGRect) -> Self {
    guard self != .hidden else { return .hidden }
    let snaps =
      RecorderPanelPlacement.reachesMenuBar(frame, visibleFrame: visibleFrame)
      || !RecorderPanelPlacement.isDetached(frame, from: docked)
    return snaps ? .docked : .detached
  }
}

enum RecorderPanelPlacement {
  /// Transparent margin around the recorder that leaves room for its shadow,
  /// including the deeper shadow of a lifted, tilted recorder while dragged.
  static let shadowInset: CGFloat = 64
  static let gap: CGFloat = 6
  static let detachDistance: CGFloat = 48
  static let menuBarBand: CGFloat = 100

  /// The panel frame that hangs the recorder below its menu bar item and keeps
  /// the recorder itself on screen.
  static func dockedFrame(size: CGSize, below item: CGRect, visibleFrame: CGRect) -> CGRect {
    let x = min(
      max(item.midX - size.width / 2, visibleFrame.minX - shadowInset),
      visibleFrame.maxX - size.width + shadowInset)
    let y = item.minY - gap - size.height + shadowInset
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  /// The menu bar item to hang from, or the top centre of the screen when the
  /// item is hidden: menu bar managers and the notch move items off screen.
  static func anchor(for item: CGRect, screens: [CGRect], fallback visibleFrame: CGRect)
    -> CGRect
  {
    let centre = CGPoint(x: item.midX, y: item.midY)
    if screens.contains(where: { $0.contains(centre) }) { return item }
    return CGRect(x: visibleFrame.midX, y: visibleFrame.maxY, width: 0, height: 0)
  }

  static func isDetached(_ frame: CGRect, from docked: CGRect) -> Bool {
    hypot(frame.midX - docked.midX, frame.maxY - docked.maxY) > detachDistance
  }

  /// Whether the recorder's top edge is within the snap band below the menu bar.
  static func reachesMenuBar(_ frame: CGRect, visibleFrame: CGRect) -> Bool {
    frame.maxY - shadowInset >= visibleFrame.maxY - menuBarBand
  }
}
