import Cocoa
import FinderSync

/// Adds the DigitZip ▸ submenu to Finder's right-click menu: extract items for archives,
/// "Add to …" items for anything.
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
        let selection = selectedItems()
        guard !selection.isEmpty else { return nil }
        let archives = selection.filter(ArchiveTypes.isArchive)

        let submenu = NSMenu(title: "DigitZip")
        if !archives.isEmpty {
            let folderTitle = archives.count == 1
                ? "Extract to “\(ArchiveTypes.baseName(archives[0]))/”"
                : "Extract Each to Its Own Folder"
            submenu.addItem(item("Extract Here", symbol: "archivebox", action: #selector(extractHere(_:))))
            submenu.addItem(item(folderTitle, symbol: "folder.badge.plus", action: #selector(extractToFolder(_:))))
            submenu.addItem(.separator())
        }
        // "Add to …" for a single archive would read as "add into this archive" and is rarely
        // useful, so it's only offered for non-archives or multi-item selections.
        let isSingleArchive = selection.count == 1 && archives.count == 1
        if !isSingleArchive {
            let baseName = ArchiveTypes.newArchiveBaseName(for: selection)
            submenu.addItem(item("Add to “\(baseName).zip”", symbol: "doc.zipper", action: #selector(addToZip(_:))))
            submenu.addItem(item("Add to “\(baseName).7z”", symbol: "doc.zipper", action: #selector(addTo7z(_:))))
            submenu.addItem(.separator())
        }
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

    @objc private func addToZip(_ sender: AnyObject?) {
        compress(.zip)
    }

    @objc private func addTo7z(_ sender: AnyObject?) {
        compress(.sevenZip)
    }

    @objc private func showAbout(_ sender: AnyObject?) {
        open(.about, activate: true)
    }

    private func selectedItems() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private func compress(_ format: ArchiveFormat) {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        open(.compress(format: format, files: items), activate: false)
    }

    private func send(_ mode: ExtractMode) {
        let files = selectedItems().filter(ArchiveTypes.isArchive)
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
