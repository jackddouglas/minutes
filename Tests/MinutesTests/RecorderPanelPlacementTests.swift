import CoreGraphics
import Testing

@testable import Minutes

private let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
private let item = CGRect(x: 1174, y: 870, width: 36, height: 30)
private let size = CGSize(width: 504, height: 480)

@Test func dockedRecorderHangsBelowItsMenuBarItem() {
  let frame = RecorderPanelPlacement.dockedFrame(size: size, below: item, visibleFrame: visible)
  let inset = RecorderPanelPlacement.shadowInset
  #expect(frame.maxY - inset == item.minY - RecorderPanelPlacement.gap)
  #expect(frame.midX == item.midX)
  // Near the right edge the recorder moves left, but its shadow may overhang.
  let edge = RecorderPanelPlacement.dockedFrame(
    size: size, below: CGRect(x: 1390, y: 870, width: 36, height: 30), visibleFrame: visible)
  #expect(edge.maxX - inset == visible.maxX)
  let centred = RecorderPanelPlacement.dockedFrame(
    size: size, below: CGRect(x: 700, y: 870, width: 36, height: 30), visibleFrame: visible)
  #expect(centred.midX == 718)
}

@Test func hiddenMenuBarItemDocksAtTheTopCentreOfTheScreen() {
  let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
  #expect(RecorderPanelPlacement.anchor(for: item, screens: screens, fallback: visible) == item)
  // A menu bar manager parks hidden items below the bottom of the display.
  let parked = CGRect(x: 7, y: -280, width: 24, height: 24)
  let anchor = RecorderPanelPlacement.anchor(for: parked, screens: screens, fallback: visible)
  let frame = RecorderPanelPlacement.dockedFrame(size: size, below: anchor, visibleFrame: visible)
  #expect(frame.midX == visible.midX)
  #expect(
    frame.maxY - RecorderPanelPlacement.shadowInset == visible.maxY - RecorderPanelPlacement.gap)
}

@Test func clicksOpenCloseAndCallADetachedRecorderHome() {
  #expect(RecorderPanelMode.hidden.itemClicked() == .docked)
  #expect(RecorderPanelMode.docked.itemClicked() == .hidden)
  #expect(RecorderPanelMode.detached.itemClicked() == .docked)
  #expect(RecorderPanelMode.docked.dismissed() == .hidden)
  #expect(RecorderPanelMode.detached.dismissed() == .detached)
}

@Test func onlyADockedRecorderPutsItselfAwayWhenRecordingStarts() {
  #expect(RecorderPanelMode.docked.recordingStarted() == .hidden)
  #expect(RecorderPanelMode.detached.recordingStarted() == .detached)
  #expect(RecorderPanelMode.hidden.recordingStarted() == .hidden)
}

@Test func draggingOffTheMenuBarDetachesAndDroppingBackDocks() {
  let docked = RecorderPanelPlacement.dockedFrame(size: size, below: item, visibleFrame: visible)
  let nudged = docked.offsetBy(dx: -12, dy: -10)
  #expect(
    RecorderPanelMode.docked.dragEnded(at: nudged, docked: docked, visibleFrame: visible) == .docked
  )
  let away = docked.offsetBy(dx: -400, dy: -200)
  #expect(
    RecorderPanelMode.docked.dragEnded(at: away, docked: docked, visibleFrame: visible) == .detached
  )
  #expect(
    RecorderPanelMode.detached.dragEnded(at: away, docked: docked, visibleFrame: visible)
      == .detached)
  // macOS stops a dragged window at the menu bar, so the panel top meets it.
  // Anywhere along the menu bar counts, not only under the item.
  let raised = CGRect(
    x: 300, y: visible.maxY - size.height, width: size.width, height: size.height)
  #expect(
    RecorderPanelMode.detached.dragEnded(at: raised, docked: docked, visibleFrame: visible)
      == .docked)
  #expect(
    RecorderPanelMode.detached.dragEnded(
      at: raised.offsetBy(dx: 0, dy: -60), docked: docked, visibleFrame: visible) == .detached)
  // Dropping on the home outline below the item also docks it.
  #expect(
    RecorderPanelMode.detached.dragEnded(at: nudged, docked: docked, visibleFrame: visible)
      == .docked)
}
