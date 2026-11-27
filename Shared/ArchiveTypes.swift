import Foundation

/// What the user picked from the Finder menu.
enum ExtractMode: String {
    /// Extract into the folder that contains the archive.
    case here
    /// Extract into a new folder named after the archive.
    case toFolder = "folder"
}

/// Formats DigitZip can create.
enum ArchiveFormat: String, CaseIterable {
    case zip
    case sevenZip = "7z"

    var fileExtension: String { rawValue }
    var sevenZipTypeSwitch: String { "-t\(rawValue)" }
}

enum ArchiveTypes {
    /// Single-file compressions of a tarball; these are unpacked in one step (gz → tar → files).
    private static let tarballSuffixes = [
        ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz", ".tar.lzma", ".tar.z",
        ".tgz", ".tbz", ".tbz2", ".txz", ".tzst",
    ]

    /// Extensions DigitZip offers to extract. 7-Zip reads many more; these are the ones worth a menu item.
    private static let extensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "tzst",
        "lz", "lzma", "z", "cab", "iso", "arj", "lzh", "cpio", "rpm", "deb", "wim", "jar", "apk",
        "001",
    ]

    static func isArchive(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func isTarball(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return tarballSuffixes.contains { name.hasSuffix($0) }
    }

    /// The archive's name without its archive extension(s): "photos.tar.gz" → "photos",
    /// "backup.7z.001" → "backup", "movie.part1.rar" → "movie".
    static func baseName(_ url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if let suffix = tarballSuffixes.first(where: { lower.hasSuffix($0) }) {
            return nonEmpty(String(name.dropLast(suffix.count)), else: name)
        }
        var base = url.deletingPathExtension()
        if url.pathExtension == "001" { base = base.deletingPathExtension() }
        var result = base.lastPathComponent
        if let range = result.range(of: #"\.part0*1$"#, options: [.regularExpression, .caseInsensitive]) {
            result.removeSubrange(range)
        }
        return nonEmpty(result, else: name)
    }

    /// Name (without extension) for a new archive of `items`, 7-Zip style:
    /// one file → its name without extension ("report.txt" → "report"),
    /// one folder → its name, several items → the name of the folder they're in.
    static func newArchiveBaseName(for items: [URL]) -> String {
        guard let first = items.first else { return "Archive" }
        if items.count == 1 {
            let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? first.hasDirectoryPath
            let name = isFolder ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
            return nonEmpty(name, else: first.lastPathComponent)
        }
        let parent = first.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty || parent == "/" ? "Archive" : parent
    }

    private static func nonEmpty(_ value: String, else fallback: String) -> String {
        value.isEmpty ? fallback : value
    }
}

/// The `digitzip://` URLs the Finder extension uses to hand work to the app:
/// `digitzip://extract?mode=…&files=…`, `digitzip://compress?format=…&files=…`, `digitzip://about`.
/// Paths travel as base64url-encoded JSON so spaces, ampersands, etc. survive intact.
enum DigitZipRequest {
    case extract(mode: ExtractMode, files: [URL])
    case compress(format: ArchiveFormat, files: [URL])
    case about

    static let scheme = "digitzip"

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .about:
            components.host = "about"
        case let .extract(mode, files):
            guard let encoded = Self.encode(files) else { return nil }
            components.host = "extract"
            components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue),
                                     URLQueryItem(name: "files", value: encoded)]
        case let .compress(format, files):
            guard let encoded = Self.encode(files) else { return nil }
            components.host = "compress"
            components.queryItems = [URLQueryItem(name: "format", value: format.rawValue),
                                     URLQueryItem(name: "files", value: encoded)]
        }
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        switch url.host {
        case "about":
            self = .about
        case "extract":
            guard let mode = value("mode").flatMap(ExtractMode.init),
                  let files = value("files").flatMap(Self.decode) else { return nil }
            self = .extract(mode: mode, files: files)
        case "compress":
            guard let format = value("format").flatMap(ArchiveFormat.init),
                  let files = value("files").flatMap(Self.decode) else { return nil }
            self = .compress(format: format, files: files)
        default:
            return nil
        }
    }

    private static func encode(_ files: [URL]) -> String? {
        guard let json = try? JSONEncoder().encode(files.map(\.path)) else { return nil }
        return json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ encoded: String) -> [URL]? {
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return paths.map { URL(fileURLWithPath: $0) }
    }
}
