import SwiftUI

/// Compact action pill: just an icon at rest, slides out the label
/// on hover. Used for the open and tunnel row actions.
struct Pill: View {
    let icon: String
    let title: LocalizedStringKey
    let accent: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var showsLabel = false
    @State private var hoverDebounce: Task<Void, Never>?

    /// Activate-after delay — feels deliberate, ignores brief
    /// pass-throughs while you're aiming for an adjacent pill.
    private static let activateDelay: Duration = .milliseconds(220)

    var body: some View {
        let highlighted = isEnabled && isHovering
        let expanded = isEnabled && showsLabel
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 12, height: 12)

                if expanded {
                    Text(title)
                        .font(Theme.monoSize(11))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .foregroundStyle(highlighted ? accent : Theme.inkDim)
            .padding(.horizontal, expanded ? 7 : 5)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? accent.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(highlighted ? accent.opacity(0.5) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
            hoverDebounce?.cancel()
            if hover {
                hoverDebounce = Task { @MainActor in
                    try? await Task.sleep(for: Self.activateDelay)
                    if !Task.isCancelled { showsLabel = true }
                }
            } else {
                showsLabel = false
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: showsLabel)
        .help(title)
    }
}
