import Foundation

/// What the user picked from the Finder menu.
enum ExtractMode: String {
    /// Extract into the folder that contains the archive.
    case here
    /// Extract into a new folder named after the archive.
    case toFolder = "folder"
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

    private static func nonEmpty(_ value: String, else fallback: String) -> String {
        value.isEmpty ? fallback : value
    }
}

/// The `digitzip://extract?...` URL the Finder extension uses to hand work to the app.
/// Paths travel as base64url-encoded JSON so spaces, ampersands, etc. survive intact.
enum DigitZipRequest {
    static let scheme = "digitzip"

    static func url(mode: ExtractMode, files: [URL]) -> URL? {
        guard let json = try? JSONEncoder().encode(files.map(\.path)) else { return nil }
        let encoded = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = scheme
        components.host = "extract"
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "files", value: encoded),
        ]
        return components.url
    }

    static func parse(_ url: URL) -> (mode: ExtractMode, files: [URL])? {
        guard url.scheme == scheme, url.host == "extract",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let mode = items.first(where: { $0.name == "mode" })?.value.flatMap(ExtractMode.init),
              var encoded = items.first(where: { $0.name == "files" })?.value
        else { return nil }
        encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return (mode, paths.map { URL(fileURLWithPath: $0) })
    }
}
