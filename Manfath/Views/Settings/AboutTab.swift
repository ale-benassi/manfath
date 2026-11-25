import SwiftUI

struct AboutTab: View {
    var body: some View {
        SettingsSection(inset: 16) {
            HStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Manfath")
                        .font(.system(size: 17, weight: .semibold))
                    Text(versionLine)
                        .font(Theme.monoSize(11))
                        .foregroundStyle(Theme.inkDim)
                    Text("A localhost port dashboard for developers.")
                        .font(.callout)
                        .foregroundStyle(Theme.inkDim)
                }
            }

            SettingsDivider().padding(.vertical, 6)

            Text("about.updateNote")
                .font(.callout)
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Source", destination: URL(string: "https://github.com/Dnymte/manfath")!)
                    .hoverFeedback(outset: 2)
                Link("Report an issue", destination: URL(string: "https://github.com/Dnymte/manfath/issues")!)
                    .hoverFeedback(outset: 2)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.amber)
            .padding(.top, 4)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "about.version \(version) \(build)")
    }
}
