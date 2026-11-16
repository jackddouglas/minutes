import SwiftUI

/// First launch: the recorder appears in the middle of the screen, floats up
/// into its menu bar item, and a tip says where it lives and how to call it.
/// Reduce Motion shows only the tip.
struct RecorderIntroView: View {
  let model: AppModel
  /// The menu bar item's centre, in this view's top-left coordinates.
  let itemPoint: CGPoint
  /// The top of the tip, just below the menu bar.
  let tipTop: CGFloat
  let shortcut: String?
  let onArrive: () -> Void
  let onFinish: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState private var stage = Stage.hidden

  enum Stage { case hidden, shown, flown, tip, done }

  var body: some View {
    GeometryReader { geometry in
      let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
      ZStack(alignment: .topLeading) {
        if !reduceMotion {
          RecordingView(levels: RecordingLevels(), isRecording: false) {
            Text(sourceName)
          }
          .environment(\.recorderFitsContent, true)
          .environment(\.recorderCompact, RecorderSettings.shared.layout == .compact)
          .fixedSize()
          .scaleEffect(scale)
          .opacity(recorderOpacity)
          .position(stage == .hidden || stage == .shown ? centre : itemPoint)
        }
        tip
          .fixedSize()
          .opacity(stage == .tip ? 1 : 0)
          .offset(y: stage == .tip ? 0 : -6)
          .position(
            x: min(max(itemPoint.x, 240), geometry.size.width - 240), y: tipTop + 22)
      }
    }
    .accessibilityElement(children: .combine)
    .task { await play() }
  }

  private var sourceName: String {
    model.applications.first { $0.processID == model.sourceID }?.applicationName ?? "App audio"
  }

  private var scale: CGFloat {
    switch stage {
    case .hidden: 0.94
    case .shown: 1
    case .flown, .tip, .done: 0.04
    }
  }

  private var recorderOpacity: Double {
    switch stage {
    case .hidden: 0
    case .shown: 1
    case .flown: 0.7
    case .tip, .done: 0
    }
  }

  private var tip: some View {
    HStack(spacing: 8) {
      Text("Minutes lives up here.")
      if let shortcut {
        Text("Click it, or press")
        Text(shortcut)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color(red: 0.15, green: 0.16, blue: 0.15))
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(RoundedRectangle(cornerRadius: 5).fill(RecorderFinish.ivory))
        Text("in any app.")
      } else {
        Text("Click it to record a meeting.")
      }
    }
    .font(.system(size: 13))
    .foregroundStyle(.white)
    .padding(.horizontal, 14).padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12).opacity(0.85)))
    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
  }

  private func play() async {
    if !reduceMotion {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { stage = .shown }
      try? await Task.sleep(for: .seconds(1.8))
      withAnimation(.timingCurve(0.55, 0, 0.25, 1, duration: 0.85)) { stage = .flown }
      try? await Task.sleep(for: .seconds(0.8))
    }
    onArrive()
    withAnimation(.easeOut(duration: 0.3)) { stage = .tip }
    try? await Task.sleep(for: .seconds(5))
    withAnimation(.easeIn(duration: 0.3)) { stage = .done }
    try? await Task.sleep(for: .seconds(0.35))
    onFinish()
  }
}
