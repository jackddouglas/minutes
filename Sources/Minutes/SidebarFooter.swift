import SwiftUI

struct SidebarFooter: ViewModifier {
  let meetingCount: Int
  let openSettings: () -> Void
  @State private var hasContentUnderFooter = false

  func body(content: Content) -> some View {
    let trackedContent =
      content
      .onScrollGeometryChange(for: Bool.self) { geometry in
        // The visible rectangle includes the footer's inset; only rows above it are unobscured.
        geometry.contentSize.height > geometry.visibleRect.maxY - geometry.contentInsets.bottom + 1
      } action: { _, hasContent in
        hasContentUnderFooter = hasContent
      }
    if #available(macOS 26.0, *) {
      // Keep the list identity and inset height stable while the bar background changes.
      trackedContent
        .safeAreaBar(edge: .bottom, spacing: 0) {
          if hasContentUnderFooter { footer }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if !hasContentUnderFooter { footer }
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    } else {
      trackedContent.safeAreaInset(edge: .bottom, spacing: 0) {
        footer.background {
          Rectangle().fill(.ultraThinMaterial).opacity(hasContentUnderFooter ? 1 : 0)
        }
      }
    }
  }

  private var footer: some View {
    HStack {
      Text("\(meetingCount) meetings").font(.caption).foregroundStyle(.secondary)
      Spacer()
      Button("Settings", systemImage: "gearshape", action: openSettings)
        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Settings")
    }.padding(14)
  }
}
