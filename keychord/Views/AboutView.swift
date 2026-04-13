import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: KC.space24)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("keychord")
                .font(.title.weight(.bold))
                .padding(.top, KC.space12)

            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, KC.space4)
                .textSelection(.enabled)

            Spacer().frame(height: KC.space20)

            VStack(spacing: KC.space6) {
                Text("© 2026 yangflow")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: KC.space16)

            HStack(spacing: KC.space12) {
                Button {
                    if let url = URL(string: "https://github.com/yangflow/keychord") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "link")
                }

                Button {
                    UpdaterService.shared.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)

            Spacer().frame(height: KC.space24)
        }
        .frame(width: 280)
        .fixedSize()
    }
}
