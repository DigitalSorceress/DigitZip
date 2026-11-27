import Combine
import FinderSync
import SwiftUI

/// Shown when DigitZip is opened directly: is everything switched on?
struct SettingsView: View {
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    private let engine = SevenZip.executableURL
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DigitZip").font(.title2.bold())
                    Text("Extract archives from Finder's right-click menu.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow(
                        ok: extensionEnabled,
                        title: "Finder extension",
                        detail: extensionEnabled
                            ? "On"
                            : "Off. Turn on DigitZip in System Settings to get the menu items."
                    )
                    if !extensionEnabled {
                        Button("Open Extension Settings…") {
                            FIFinderSyncController.showExtensionManagementInterface()
                        }
                        .padding(.leading, 26)
                    }
                    Divider()
                    statusRow(
                        ok: engine != nil,
                        title: "7-Zip engine",
                        detail: engine?.path ?? "Missing. Run: brew install sevenzip, then rebuild."
                    )
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Right-click an archive in Finder and choose **Extract Here** or **Extract to “name/”**.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 460)
        .onReceive(refresh) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }

    private func statusRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
