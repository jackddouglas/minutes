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

private struct PrimaryActionStyle: ButtonStyle {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  func makeBody(configuration: Configuration) -> some View {
    let dark = colorScheme == .dark
    configuration.label
      .fontWeight(.medium)
      .foregroundStyle(dark ? Color.black : Color.white)
      .padding(.horizontal, controlSize == .large ? 14 : 10)
      .padding(.vertical, controlSize == .large ? 9 : 5)
      .background(dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 8))
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
  }
}

extension View {
  /// A neutral primary action with an explicit adaptive label/fill pair.
  func primaryAction() -> some View {
    buttonStyle(PrimaryActionStyle())
  }

  func controlSurface(cornerRadius: CGFloat = 20, clearGlass: Bool = false) -> some View {
    modifier(ControlSurface(cornerRadius: cornerRadius, clearGlass: clearGlass))
  }
}
