import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Manage the list of apps where Modo is turned OFF. Users add apps via a
/// native file picker (which yields the app's bundle identifier) and remove
/// them to re-enable Modo there.
struct PerAppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var disabled: [String] = Array(AppPolicy.shared.disabledBundleIDs).sorted()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Excluded Apps").font(.headline)
                Spacer()
                Button("Add App…") { addApp() }
            }

            Text("Modo won't read selections or show the bubble in these apps.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if disabled.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No apps excluded — Modo works everywhere.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                List {
                    ForEach(disabled, id: \.self) { bundleID in
                        HStack {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(displayName(for: bundleID))
                                Text(bundleID)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Re-enable") { remove(bundleID) }
                                .controlSize(.small)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        AppPolicy.shared.setEnabled(false, forBundleID: bundleID)
        refresh()
    }

    private func remove(_ bundleID: String) {
        AppPolicy.shared.setEnabled(true, forBundleID: bundleID)
        refresh()
    }

    private func refresh() {
        disabled = Array(AppPolicy.shared.disabledBundleIDs).sorted()
    }

    /// Best-effort friendly name for a bundle ID from the installed app, if it
    /// can be located; otherwise the bundle ID's last component.
    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}
