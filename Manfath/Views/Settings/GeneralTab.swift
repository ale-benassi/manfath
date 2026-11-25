import SwiftUI
import AppKit
import KeyboardShortcuts

struct GeneralTab: View {
    @Bindable var settings: SettingsStore

    /// The language code the bundle resolved at launch. Captured once
    /// so we can detect when the picker's value diverges and prompt
    /// the user to restart.
    private let launchLanguageCode: String =
        Bundle.main.preferredLocalizations.first ?? "en"

    private var needsRestart: Bool {
        let target: String? = switch settings.language {
        case .system:  nil
        case .english: "en"
        case .arabic:  "ar"
        }
        return target.map { $0 != launchLanguageCode } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(inset: 0) {
                VStack(spacing: 0) {
                    preferencePicker("Refresh", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    rowDivider

                    preferencePicker("Appearance", selection: $settings.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    rowDivider

                    preferencePicker("Menu bar badge", selection: $settings.badgeMode) {
                        ForEach(BadgeMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    rowDivider

                    preferencePicker("rowDisplay.title", selection: $settings.rowDisplay) {
                        ForEach(RowDisplay.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .help("rowDisplay.help")
                    rowDivider

                    preferencePicker("tunnelProvider.title", selection: $settings.tunnelProvider) {
                        ForEach(TunnelProviderChoice.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .help("tunnelProvider.help")
                    rowDivider

                    preferencePicker("Language", selection: $settings.language) {
                        ForEach(Language.allCases, id: \.self) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }

                    if needsRestart {
                        rowDivider
                        HStack(spacing: 8) {
                            Label("language.restartRequired", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(Theme.inkDim)
                            Spacer()
                            Button("language.restartNow") {
                                NSApp.sendAction(
                                    #selector(AppDelegate.relaunchApp(_:)),
                                    to: nil,
                                    from: nil
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }

            SettingsSection(title: "Shortcut", inset: 0) {
                KeyboardShortcuts.Recorder(
                    "Toggle popover",
                    name: .togglePopover
                )
            }

            SettingsSection(title: "Launch", inset: 0) {
                LabeledContent("Launch Manfath at login") {
                    Toggle(
                        "Launch Manfath at login",
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .hoverFeedback(outset: 2)
                }
            }
        }
        .labeledContentStyle(PreferenceRowStyle())
    }

    private var rowDivider: some View {
        SettingsDivider().padding(.horizontal, 12)
    }

    private func preferencePicker<Value: Hashable, Options: View>(
        _ title: LocalizedStringKey,
        selection: Binding<Value>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection, content: options)
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize(horizontal: true, vertical: false)
                .hoverFeedback(outset: 2)
        }
    }
}

private struct PreferenceRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
    }
}
