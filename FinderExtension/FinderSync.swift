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

        let submenu = NSMenu(title: "DigitZip")
        let folderTitle = archives.count == 1
            ? "Extract to “\(ArchiveTypes.baseName(archives[0]))/”"
            : "Extract Each to Its Own Folder"
        submenu.addItem(item("Extract Here", symbol: "archivebox", action: #selector(extractHere(_:))))
        submenu.addItem(item(folderTitle, symbol: "folder.badge.plus", action: #selector(extractToFolder(_:))))
        submenu.addItem(.separator())
        submenu.addItem(item("About DigitZip", symbol: "info.circle", action: #selector(showAbout(_:))))

        let root = NSMenuItem(title: "DigitZip", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
        root.submenu = submenu

        let menu = NSMenu(title: "")
        menu.addItem(root)
        return menu
    }

    private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func extractHere(_ sender: AnyObject?) {
        send(.here)
    }

    @objc private func extractToFolder(_ sender: AnyObject?) {
        send(.toFolder)
    }

    @objc private func showAbout(_ sender: AnyObject?) {
        open(.about, activate: true)
    }

    private func selectedArchives() -> [URL] {
        (FIFinderSyncController.default().selectedItemURLs() ?? []).filter(ArchiveTypes.isArchive)
    }

    private func send(_ mode: ExtractMode) {
        let files = selectedArchives()
        guard !files.isEmpty else { return }
        // Don't activate: keep Finder in front unless DigitZip needs to ask something.
        open(.extract(mode: mode, files: files), activate: false)
    }

    private func open(_ request: DigitZipRequest, activate: Bool) {
        guard let url = request.url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
