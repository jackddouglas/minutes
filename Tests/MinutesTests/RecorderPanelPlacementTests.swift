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
  let inset = RecorderPanelPlacement.shadowInset
  func drop(_ mode: RecorderPanelMode, recorderTop: CGFloat, x: CGFloat = 300) -> RecorderPanelMode
  {
    let frame = CGRect(
      x: x, y: recorderTop + inset - size.height, width: size.width, height: size.height)
    return mode.dragEnded(at: frame, docked: docked, visibleFrame: visible)
  }
  // A small nudge, or a drop on the home outline, docks either way.
  let nudged = docked.offsetBy(dx: -12, dy: -10)
  #expect(
    RecorderPanelMode.docked.dragEnded(at: nudged, docked: docked, visibleFrame: visible) == .docked
  )
  #expect(
    RecorderPanelMode.detached.dragEnded(at: nudged, docked: docked, visibleFrame: visible)
      == .docked)
  // Pulled well below the menu bar, it stays where it was put.
  #expect(drop(.docked, recorderTop: visible.maxY - 200) == .detached)
  #expect(drop(.detached, recorderTop: visible.maxY - 200) == .detached)
  // Anywhere within the snap band along the menu bar docks it, including up
  // over the menu bar itself.
  #expect(drop(.detached, recorderTop: visible.maxY - 90) == .docked)
  #expect(drop(.detached, recorderTop: visible.maxY + 30) == .docked)
  #expect(drop(.docked, recorderTop: visible.maxY - 20) == .docked)
  #expect(drop(.detached, recorderTop: visible.maxY - 110) == .detached)
  #expect(drop(.hidden, recorderTop: visible.maxY) == .hidden)
}
