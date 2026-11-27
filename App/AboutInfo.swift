import AppKit

/// Content of the About panel (Finder: DigitZip ▸ About DigitZip, or the button in the settings window).
enum AboutInfo {
    static let author = "DigitalSorceress"
    static let authorURL = "https://digitalsorceress.com"
    /// Adds a "Source code" link to the About panel.
    static let repositoryURL: String? = "https://github.com/DigitalSorceress/DigitZip"

    static var panelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "DigitZip",
            .credits: credits,
        ]
    }

    private static var credits: NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 6

        let text = NSMutableAttributedString()
        func add(_ string: String, font: NSFont = body, link: String? = nil, color: NSColor = .labelColor) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: centered]
            if let link { attributes[.link] = URL(string: link) }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }

        add("7-Zip-style “Extract Here” and “Extract to folder” for the macOS Finder.\n")
        add("Created and maintained by ")
        add(author, font: bold, link: authorURL)
        add("\n")
        if let repositoryURL {
            add("Source code: ")
            add(repositoryURL.replacingOccurrences(of: "https://", with: ""), link: repositoryURL)
            add("\n")
        }
        add("Powered by the 7-Zip engine by Igor Pavlov · ")
        add("7-zip.org", link: "https://www.7-zip.org")
        add("\n7-Zip is licensed under the GNU LGPL with the unRAR restriction.\n", color: .secondaryLabelColor)
        add("DigitZip is an independent project, not affiliated with or endorsed by 7-Zip.", color: .secondaryLabelColor)
        return text
    }
}
