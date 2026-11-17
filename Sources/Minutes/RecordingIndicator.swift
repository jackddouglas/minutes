import MinutesCore
import SwiftUI

/// Persistent capture status while the library displays another meeting.
struct RecordingIndicator: View {
  let startedAt: Date?
  let showRecording: () -> Void

  var body: some View {
    Button(action: showRecording) {
      HStack(spacing: 10) {
        Circle().fill(RecorderFinish.orange).frame(width: 7, height: 7)
        Text("Recording").fontWeight(.medium)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          Text(
            MarkdownExporter.timestamp(context.date.timeIntervalSince(startedAt ?? context.date))
          )
          .monospacedDigit().foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      .padding(.horizontal, 16).padding(.vertical, 11)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .modifier(RecordingPillSurface())
    .help("Return to the current recording")
    .accessibilityLabel("Recording in progress. Show recorder")
  }
}

private struct RecordingPillSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
        .overlay {
          Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5).allowsHitTesting(false)
        }
    } else if #available(macOS 26, *) {
      content.glassEffect(.regular.interactive(), in: Capsule())
    } else {
      content.background(.regularMaterial, in: Capsule())
    }
  }
}
