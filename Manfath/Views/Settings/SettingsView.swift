import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var selection: Pane = .general
    @FocusState private var focusedPane: Pane?

    private let topInset: CGFloat = 20

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case general
        case filters
        case about

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .general: return "settings.pane.general"
            case .filters: return "settings.pane.filters"
            case .about:   return "settings.pane.about"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .about:   return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            SettingsDivider(vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selection.label)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(minHeight: 32)
                        .accessibilityAddTraits(.isHeader)

                    paneContent
                }
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, topInset)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg1)
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.amberSoft)
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Pane.allCases) { pane in
                sidebarButton(for: pane)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, topInset)
        .frame(width: 192)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.bg2)
        .onMoveCommand { direction in
            guard let focusedPane, let index = Pane.allCases.firstIndex(of: focusedPane) else { return }
            let nextIndex: Int
            switch direction {
            case .up: nextIndex = index - 1
            case .down: nextIndex = index + 1
            default: return
            }
            guard Pane.allCases.indices.contains(nextIndex) else { return }
            let pane = Pane.allCases[nextIndex]
            selection = pane
            self.focusedPane = pane
        }
    }

    private func sidebarButton(for pane: Pane) -> some View {
        let isSelected = selection == pane
        let shape = RoundedRectangle(cornerRadius: 7)

        return Button {
            selection = pane
            if focusedPane != nil {
                focusedPane = pane
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(pane.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .foregroundStyle(isSelected ? Theme.amber : Theme.inkDim)
            .contentShape(shape)
            .background(isSelected ? Theme.amber.opacity(0.12) : .clear, in: shape)
            .hoverFeedback(radius: 7)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedPane, equals: pane)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selection {
        case .general: GeneralTab(settings: settings)
        case .filters: FiltersTab(settings: settings)
        case .about:   AboutTab()
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var subtitle: LocalizedStringKey? = nil
    var inset: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.inkDim)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(inset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct SettingsDivider: View {
    var vertical = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(vertical ? Theme.lineStrong : Theme.line)
            .frame(width: vertical ? 1 / displayScale : nil, height: vertical ? nil : 1 / displayScale)
            .accessibilityHidden(true)
    }
}
