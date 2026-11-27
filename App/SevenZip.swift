import Foundation

struct ProcessResult {
    let status: Int32
    let output: String
    let errorOutput: String

    /// 7-Zip exit codes: 0 = OK, 1 = warnings (e.g. a locked file), 2+ = fatal.
    var succeeded: Bool { status == 0 || status == 1 }

    var isPasswordError: Bool {
        let text = errorOutput + output
        return text.contains("Wrong password") || text.contains("Cannot open encrypted archive") || text.contains("Can not open encrypted archive")
    }

    /// The most useful lines of 7-Zip's error output, for showing to the user.
    var errorSummary: String {
        let lines = (errorOutput + "\n" + output)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let errors = lines.filter { $0.localizedCaseInsensitiveContains("error") }
        let picked = errors.isEmpty ? Array(lines.suffix(3)) : Array(errors.prefix(5))
        return picked.isEmpty ? "7-Zip exited with code \(status)." : picked.joined(separator: "\n")
    }
}

enum DigitZipError: LocalizedError {
    case missingEngine
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingEngine: "The 7-Zip engine (7zz) is missing. Reinstall DigitZip, or run: brew install sevenzip"
        case let .failed(message): message
        }
    }
}

/// Thin wrapper around the bundled `7zz` command-line tool.
enum SevenZip {
    /// The bundled copy (Contents/MacOS/7zz), falling back to Homebrew during development.
    static var executableURL: URL? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "7zz") { return bundled }
        return ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func run(_ arguments: [String]) async throws -> ProcessResult {
        try await pipeline([arguments])
    }

    /// Runs several 7zz invocations with each one's stdout feeding the next one's stdin
    /// (used to unpack .tar.gz and friends in one go). Runs off the main thread.
    static func pipeline(_ stages: [[String]]) async throws -> ProcessResult {
        guard let executable = executableURL else { throw DigitZipError.missingEngine }
        return try await Task.detached(priority: .userInitiated) {
            try runBlocking(executable: executable, stages: stages)
        }.value
    }

    private static func runBlocking(executable: URL, stages: [[String]]) throws -> ProcessResult {
        var processes: [Process] = []
        let errorPipes = stages.map { _ in Pipe() }
        let finalOutput = Pipe()
        var previousOutput: Pipe?

        for (index, arguments) in stages.enumerated() {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            // Never let 7zz wait for keyboard input (e.g. a password prompt): give it no stdin.
            process.standardInput = previousOutput ?? FileHandle.nullDevice
            let output = index == stages.count - 1 ? finalOutput : Pipe()
            process.standardOutput = output
            process.standardError = errorPipes[index]
            previousOutput = output
            processes.append(process)
        }
        for process in processes { try process.run() }

        // Drain stderr concurrently so a chatty process can't fill its pipe and stall.
        var errorData = [Data](repeating: Data(), count: stages.count)
        let lock = NSLock()
        let group = DispatchGroup()
        for (index, pipe) in errorPipes.enumerated() {
            group.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock(); errorData[index] = data; lock.unlock()
                group.leave()
            }
        }
        let outputData = finalOutput.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        processes.forEach { $0.waitUntilExit() }

        // The last stage's status matters most; an earlier stage failing is also a failure.
        let failing = processes.last(where: { $0.terminationStatus > 1 }) ?? processes[processes.count - 1]
        return ProcessResult(
            status: failing.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            errorOutput: errorData.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        )
    }
}

/// What's inside an archive, from `7zz l -slt`.
struct ArchiveListing {
    var paths: [String] = []
    var hasEncryptedEntries = false

    init(parsing text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("Path = ") {
                paths.append(String(line.dropFirst("Path = ".count)))
            } else if line == "Encrypted = +" {
                hasEncryptedEntries = true
            }
        }
    }

    /// Top-level names the archive will create, e.g. ["docs", "readme.txt"].
    var topLevelNames: [String] {
        let names = paths.compactMap { $0.split(separator: "/").first.map(String.init) }
        return Array(Set(names)).filter { $0 != "__MACOSX" && !$0.hasPrefix("._") }.sorted()
    }
}
