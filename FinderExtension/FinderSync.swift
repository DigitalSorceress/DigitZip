import Cocoa
import FinderSync

/// Adds DigitZip's items to Finder's right-click menu for archive files.
///
/// The extension is sandboxed and can't write files itself, so it just tells
/// DigitZip.app what to extract via a `digitzip://` URL.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Watch every folder so the menu appears everywhere.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let archives = selectedArchives()
        guard !archives.isEmpty else { return nil }

        let menu = NSMenu(title: "")

        let here = NSMenuItem(title: "Extract Here", action: #selector(extractHere(_:)), keyEquivalent: "")
        here.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        menu.addItem(here)

        let folderTitle = archives.count == 1
            ? "Extract to “\(ArchiveTypes.baseName(archives[0]))/”"
            : "Extract Each to Its Own Folder"
        let toFolder = NSMenuItem(title: folderTitle, action: #selector(extractToFolder(_:)), keyEquivalent: "")
        toFolder.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        menu.addItem(toFolder)

        return menu
    }

    @objc private func extractHere(_ sender: AnyObject?) {
        send(.here)
    }

    @objc private func extractToFolder(_ sender: AnyObject?) {
        send(.toFolder)
    }

    private func selectedArchives() -> [URL] {
        (FIFinderSyncController.default().selectedItemURLs() ?? []).filter(ArchiveTypes.isArchive)
    }

    private func send(_ mode: ExtractMode) {
        let files = selectedArchives()
        guard !files.isEmpty, let url = DigitZipRequest.url(mode: mode, files: files) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // keep Finder in front unless DigitZip needs to ask something
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
