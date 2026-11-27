import Foundation

// The options in the Add to Archive… dialog, and how they map onto 7zz switches.
// Kept free of UI code so the switch-building can be tested on its own.

enum UpdateMode: String, Codable, CaseIterable, Identifiable {
    case addAndReplace, update, freshen, synchronize

    var id: Self { self }

    var title: String {
        switch self {
        case .addAndReplace: "Add and replace files"
        case .update: "Update and add files"
        case .freshen: "Freshen existing files"
        case .synchronize: "Synchronize files"
        }
    }

    var commandArguments: [String] {
        switch self {
        case .addAndReplace: ["a"]
        case .update: ["u"]
        case .freshen: ["u", "-ur0"] // don't add files that aren't already in the archive
        case .synchronize: ["u", "-uq0"] // remove archive entries that no longer exist on disk
        }
    }
}

enum PathMode: String, Codable, CaseIterable, Identifiable {
    case relative, full, absolute

    var id: Self { self }

    var title: String {
        switch self {
        case .relative: "Relative pathnames"
        case .full: "Full pathnames"
        case .absolute: "Absolute pathnames"
        }
    }

    var switches: [String] {
        switch self {
        case .relative: []
        case .full: ["-spf2"]
        case .absolute: ["-spf"]
        }
    }
}

enum ZipEncryption: String, Codable, CaseIterable, Identifiable {
    case zipCrypto = "ZipCrypto"
    case aes256 = "AES256"

    var id: Self { self }
    var title: String { self == .aes256 ? "AES-256" : "ZipCrypto" }
}

/// What the "Dictionary size" and "Word size" rows mean for the current format and method.
enum DictionaryKind { case dictionary, ppmdMemory }
enum WordKind { case fastBytes(max: Int), ppmdOrder }

enum CompressionOptions {
    static let levels: [(value: Int, title: String)] = [
        (0, "0 – Store"), (1, "1 – Fastest"), (3, "3 – Fast"),
        (5, "5 – Normal"), (7, "7 – Maximum"), (9, "9 – Ultra"),
    ]

    static func methods(for format: ArchiveFormat) -> [String] {
        switch format {
        case .sevenZip: ["LZMA2", "LZMA", "PPMd", "BZip2"]
        case .zip: ["Deflate", "Deflate64", "BZip2", "LZMA", "PPMd"]
        case .tar: []
        }
    }

    static func defaultMethod(for format: ArchiveFormat) -> String? {
        methods(for: format).first
    }

    static let dictionarySizes = ["1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m", "512m", "1024m"]
    static let fastBytes = [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 273]
    static let ppmdOrders = [2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32]
    static let solidBlockSizes = ["1m", "4m", "16m", "64m", "256m", "1g", "2g", "4g", "8g", "16g", "32g", "64g"]
    static let splitPresets: [(value: String, note: String)] = [
        ("10M", ""), ("100M", ""), ("1000M", ""), ("650M", "CD"), ("700M", "CD"),
        ("4092M", "FAT"), ("4480M", "DVD"), ("8128M", "DVD DL"), ("23040M", "Blu-ray"),
    ]
    static var cpuCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// "32m" → "32 MB", "1g" → "1 GB".
    static func sizeLabel(_ value: String) -> String {
        guard let unit = value.last, let number = Int(value.dropLast()) else { return value }
        switch unit {
        case "k": return "\(number) KB"
        case "m": return number >= 1024 && number % 1024 == 0 ? "\(number / 1024) GB" : "\(number) MB"
        case "g": return "\(number) GB"
        default: return value
        }
    }

    enum SplitSize: Equatable {
        case none
        case size(String) // a 7zz -v value, e.g. "100m"
        case invalid
    }

    /// Reads the "Split into volumes" field: "" → none, "100M" or "650M – CD" → "650m".
    /// Whole numbers with an optional b/k/m/g unit only ("4.7g" isn't accepted by 7zz).
    static func splitSize(from text: String) -> SplitSize {
        let token = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        if token.isEmpty { return .none }
        let lower = token.lowercased()
        guard lower.range(of: #"^[1-9][0-9]*[bkmg]?$"#, options: .regularExpression) != nil else { return .invalid }
        return .size(lower)
    }

    /// Splits the free-text "Parameters" field into arguments, honoring "double quotes".
    static func parseParameters(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if character.isWhitespace && !inQuotes {
                if hasToken { result.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { result.append(current) }
        return result
    }
}

/// The remembered part of the dialog (everything except name, location, password, split and parameters).
struct CompressionSettings: Codable, Equatable {
    var format: ArchiveFormat = .sevenZip
    var level = 5
    /// nil means the format's default method.
    var method: String?
    /// nil means "Auto" for the four rows below.
    var dictionary: String?
    var wordSize: Int?
    var solidBlock: String?
    var threads: Int?
    var updateMode: UpdateMode = .addAndReplace
    var pathMode: PathMode = .relative
    var excludeMacJunk = true
    var trashOriginals = false
    var zipEncryption: ZipEncryption = .zipCrypto
    var encryptFileNames = true

    var effectiveMethod: String? { method ?? CompressionOptions.defaultMethod(for: format) }

    var supportsLevel: Bool { format != .tar }
    var supportsSolidBlocks: Bool { format == .sevenZip }
    var supportsThreads: Bool { format != .tar }
    var supportsEncryption: Bool { format != .tar }
    var supportsFileNameEncryption: Bool { format == .sevenZip }

    var dictionaryKind: DictionaryKind? {
        switch (format, effectiveMethod) {
        case (.sevenZip, "LZMA2"), (.sevenZip, "LZMA"), (.zip, "LZMA"): .dictionary
        case (.sevenZip, "PPMd"): .ppmdMemory
        default: nil
        }
    }

    var wordKind: WordKind? {
        switch (format, effectiveMethod) {
        case (.sevenZip, "LZMA2"), (.sevenZip, "LZMA"), (.zip, "LZMA"): .fastBytes(max: 273)
        case (.zip, "Deflate"), (.zip, "Deflate64"): .fastBytes(max: 258)
        case (.sevenZip, "PPMd"): .ppmdOrder
        default: nil
        }
    }

    /// Clears choices that don't apply after the format or method changes.
    mutating func normalize() {
        if let method, !CompressionOptions.methods(for: format).contains(method) { self.method = nil }
        if dictionaryKind == nil { dictionary = nil }
        switch wordKind {
        case nil: wordSize = nil
        case let .fastBytes(max): if let size = wordSize, size > max || size < 8 { wordSize = nil }
        case .ppmdOrder: if let size = wordSize, !CompressionOptions.ppmdOrders.contains(size) { wordSize = nil }
        }
        if !supportsSolidBlocks { solidBlock = nil }
        if !supportsThreads { threads = nil }
    }

    /// Format, compression and path switches (not the command, password, split or file list).
    var switches: [String] {
        var switches = ["-t\(format.rawValue)"]
        if supportsLevel { switches.append("-mx=\(level)") }
        switch format {
        case .sevenZip:
            if method != nil || dictionary != nil || wordSize != nil, let method = effectiveMethod {
                let isPPMd = method == "PPMd"
                var spec = "-m0=\(method)"
                if let dictionary { spec += isPPMd ? ":mem=\(dictionary)" : ":d=\(dictionary)" }
                if let wordSize { spec += isPPMd ? ":o=\(wordSize)" : ":fb=\(wordSize)" }
                switches.append(spec)
            }
            if let solidBlock { switches.append("-ms=\(solidBlock)") }
        case .zip:
            if let method { switches.append("-mm=\(method)") }
            if let dictionary { switches.append("-md=\(dictionary)") }
            if let wordSize { switches.append("-mfb=\(wordSize)") }
        case .tar:
            break
        }
        if let threads { switches.append("-mmt=\(threads)") }
        switches += pathMode.switches
        if excludeMacJunk { switches += ["-xr!.DS_Store", "-xr!._*", "-xr!__MACOSX"] }
        return switches
    }

    private static let defaultsKey = "AddToArchiveSettings"

    static func load() -> CompressionSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(CompressionSettings.self, from: data)
        else { return CompressionSettings() }
        settings.normalize()
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// One "Add to Archive…" run: everything needed to build the 7zz command.
struct CustomCompression {
    let items: [URL]
    let archive: URL
    let settings: CompressionSettings
    let password: String
    /// Normalized split size for -v (e.g. "100m"), or nil for no splitting.
    let splitSize: String?
    let extraParameters: [String]

    var arguments: [String] {
        var arguments = settings.updateMode.commandArguments + ["-y", "-bd"] + settings.switches
        if settings.supportsEncryption, !password.isEmpty {
            arguments.append("-p\(password)")
            if settings.format == .zip { arguments.append("-mem=\(settings.zipEncryption.rawValue)") }
            if settings.supportsFileNameEncryption, settings.encryptFileNames { arguments.append("-mhe=on") }
        }
        if let splitSize { arguments.append("-v\(splitSize)") }
        arguments += extraParameters
        return arguments + ["--", archive.path] + items.map(\.path)
    }
}
