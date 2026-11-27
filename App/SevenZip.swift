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

/// A progress report parsed from 7zz's `-bsp2` output, e.g. " 32% 2 + photos/beach.jpg".
struct SevenZipProgress: Sendable {
    let fraction: Double
    let item: String?
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

    typealias ProgressHandler = @Sendable (SevenZipProgress) -> Void

    static func run(_ arguments: [String], onProgress: ProgressHandler? = nil) async throws -> ProcessResult {
        try await pipeline([arguments], progressStage: 0, onProgress: onProgress)
    }

    /// Runs several 7zz invocations with each one's stdout feeding the next one's stdin
    /// (used to unpack .tar.gz and friends in one go), off the main thread.
    ///
    /// - Progress: if `onProgress` is given, stage `progressStage` reports progress (called on a
    ///   background thread).
    /// - Cancellation: cancelling the calling Task stops 7zz (it exits cleanly on SIGTERM: an
    ///   archive being updated is left as it was, and a new one isn't left half-written) and this
    ///   throws `CancellationError`.
    static func pipeline(_ stages: [[String]], progressStage: Int = 0,
                         onProgress: ProgressHandler? = nil) async throws -> ProcessResult {
        guard let executable = executableURL else { throw DigitZipError.missingEngine }
        try Task.checkCancellation()
        let handle = RunningProcesses()
        let result = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try runBlocking(executable: executable, stages: stages, handle: handle,
                                progressStage: onProgress == nil ? nil : progressStage, onProgress: onProgress)
            }.value
        } onCancel: {
            handle.terminateAll()
        }
        if handle.wasTerminated { throw CancellationError() }
        return result
    }

    private static func runBlocking(executable: URL, stages: [[String]], handle: RunningProcesses,
                                    progressStage: Int?, onProgress: ProgressHandler?) throws -> ProcessResult {
        var processes: [Process] = []
        let errorPipes = stages.map { _ in Pipe() }
        let finalOutput = Pipe()
        var previousOutput: Pipe?

        for (index, var arguments) in stages.enumerated() {
            if index == progressStage {
                // -bd turns the progress indicator off; -bsp2 sends progress to stderr.
                arguments.removeAll { $0 == "-bd" }
                arguments.insert("-bsp2", at: min(1, arguments.count))
            }
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

        // Read every stderr pipe as data arrives, so a chatty process can't fill its pipe and
        // stall, and so progress can be reported live.
        var errorData = [Data](repeating: Data(), count: stages.count)
        let lock = NSLock()
        let group = DispatchGroup()
        var lastReported: (percent: Int, item: String?)?
        for (index, pipe) in errorPipes.enumerated() {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    fileHandle.readabilityHandler = nil
                    group.leave()
                    return
                }
                lock.lock()
                errorData[index].append(chunk)
                lock.unlock()
                guard index == progressStage, let onProgress,
                      let progress = parseProgress(String(decoding: chunk, as: UTF8.self)) else { return }
                let percent = Int(progress.fraction * 100)
                if lastReported?.percent != percent || lastReported?.item != progress.item {
                    lastReported = (percent, progress.item)
                    onProgress(progress)
                }
            }
        }

        do {
            for process in processes { try process.run() }
        } catch {
            processes.filter(\.isRunning).forEach { $0.terminate() }
            errorPipes.forEach { $0.fileHandleForWriting.closeFile() }
            throw error
        }
        handle.register(processes)

        let outputData = finalOutput.fileHandleForReading.readDataToEndOfFile()
        processes.forEach { $0.waitUntilExit() }
        group.wait()

        // The last stage's status matters most; an earlier stage failing is also a failure.
        let failing = processes.last(where: { $0.terminationStatus > 1 }) ?? processes[processes.count - 1]
        lock.lock()
        let errors = errorData.map { removeProgress(from: String(decoding: $0, as: UTF8.self)) }
        lock.unlock()
        return ProcessResult(
            status: failing.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self),
            errorOutput: errors.joined(separator: "\n")
        )
    }

    // MARK: Progress parsing

    /// Matches one progress segment: "32%", " 32% 2 + photos/beach.jpg", " 7% 1 - a.txt".
    private static let progressPattern = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,3})%(?:\s+\d+)?(?:\s+[+\-U=]?\s*(.*\S))?\s*$"#
    )

    /// The "scanning the disk" status 7zz shows before compressing: "0M Scan", "12M Scan /path/…".
    private static let scanPattern = try! NSRegularExpression(pattern: #"^\s*\d+M Scan\b"#)

    /// 7zz redraws its progress line with backspaces; split on those and take the newest segment.
    static func parseProgress(_ text: String) -> SevenZipProgress? {
        for segment in progressSegments(text).reversed() {
            let range = NSRange(segment.startIndex..., in: segment)
            guard let match = progressPattern.firstMatch(in: segment, range: range),
                  let percentRange = Range(match.range(at: 1), in: segment),
                  let percent = Int(segment[percentRange]) else { continue }
            let item = Range(match.range(at: 2), in: segment).map { String(segment[$0]) }
            return SevenZipProgress(fraction: min(Double(percent) / 100, 1), item: item)
        }
        return nil
    }

    /// Stderr with the progress redraws taken out, leaving only real messages.
    static func removeProgress(from text: String) -> String {
        progressSegments(text)
            .filter { segment in
                let trimmed = segment.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return false }
                let range = NSRange(segment.startIndex..., in: segment)
                return progressPattern.firstMatch(in: segment, range: range) == nil
                    && scanPattern.firstMatch(in: segment, range: range) == nil
            }
            .joined(separator: "\n")
    }

    private static func progressSegments(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: true) { $0 == "\u{8}" || $0 == "\r" || $0 == "\n" }.map(String.init)
    }
}

/// The 7zz processes of one run, so a cancel from another thread can stop them.
private final class RunningProcesses: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var terminateRequested = false

    var wasTerminated: Bool {
        lock.lock(); defer { lock.unlock() }
        return terminateRequested
    }

    func register(_ processes: [Process]) {
        lock.lock()
        self.processes = processes
        let alreadyRequested = terminateRequested
        lock.unlock()
        if alreadyRequested { processes.filter(\.isRunning).forEach { $0.terminate() } }
    }

    func terminateAll() {
        lock.lock()
        terminateRequested = true
        let running = processes
        lock.unlock()
        running.filter(\.isRunning).forEach { $0.terminate() }
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
