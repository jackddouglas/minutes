import SwiftUI

/// Glass belongs to controls above content, not the transcript reading surface.
struct ControlSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(
        Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
    } else if #available(macOS 26, *) {
      content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    } else {
      content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
  }
}

extension View {
  func controlSurface() -> some View { modifier(ControlSurface()) }
}
