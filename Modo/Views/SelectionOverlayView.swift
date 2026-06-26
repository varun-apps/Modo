import SwiftUI

/// The pill that appears next to a user's text selection. Clicking it asks
/// AppDelegate to open the main Modo popover anchored on the menu-bar icon.
struct SelectionOverlayView: View {
    var onActivate: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                Text("Modo")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.9))
            )
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Improve with Modo")
        .accessibilityHint("Opens Modo to rewrite the selected text.")
    }
}
