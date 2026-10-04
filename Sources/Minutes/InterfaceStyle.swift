import SwiftUI

/// Glass belongs to controls above content, not the transcript reading surface.
struct ControlSurface: ViewModifier {
  var cornerRadius: CGFloat = 20
  var clearGlass = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  func body(content: Content) -> some View {
    if reduceTransparency {
      content.background(
        Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius))
    } else if #available(macOS 26, *) {
      content.glassEffect(
        clearGlass ? .clear : .regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    } else {
      content.background(
        clearGlass ? .ultraThinMaterial : .regularMaterial,
        in: RoundedRectangle(cornerRadius: cornerRadius))
    }
  }
}

extension View {
  func controlSurface(cornerRadius: CGFloat = 20, clearGlass: Bool = false) -> some View {
    modifier(ControlSurface(cornerRadius: cornerRadius, clearGlass: clearGlass))
  }
}
