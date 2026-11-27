import AppKit
import OSLog
import UserNotifications

let log = Logger(subsystem: "com.digitalsorceress.DigitZip", category: "jobs")

/// Runs extract and compress jobs one at a time, asking the user only when it has to
/// (password, or files that already exist).
@MainActor
final class JobQueue {
    enum Job {
        case extract(mode: ExtractMode, archive: URL)
        case compress(format: ArchiveFormat, items: [URL])

        var logDescription: String {
            switch self {
            case let .extract(mode, archive): "extract (\(mode.rawValue)) \(archive.lastPathComponent)"
            case let .compress(format, items): "compress \(items.count) item(s) to \(format.rawValue)"
            }
        }
    }

    private enum Outcome {
        /// `title` and `detail` are used for the notification, e.g. "Extracted “a.zip”" / "Into “a/”".
        case done(title: String, detail: String)
        case canceled
        /// `title` is the alert heading, e.g. "Couldn't extract “a.zip”".
        case failed(title: String, message: String)
    }

    private var pending: [Job] = []
    private var outcomes: [Outcome] = []
    private(set) var isBusy = false
    var onIdle: (() -> Void)?

    /// Passed to 7zz when there's no password, so it fails cleanly instead of prompting on stdin.
    /// Harmless for archives that aren't encrypted.
    private let noPassword = "-pDIGITZIP-NO-PASSWORD"

    func enqueue(_ jobs: [Job]) {
        log.info("Queued \(jobs.count) job(s), busy: \(self.isBusy)")
        pending += jobs
        guard !isBusy else { return }
        isBusy = true
        Task { await drain() }
    }

    private func drain() async {
        // Only ever awaits extraction work and the user's answers to prompts, never the
        // notification system, so a stuck notification request can't wedge the queue.
        while !pending.isEmpty {
            let job = pending.removeFirst()
            log.info("Starting \(job.logDescription, privacy: .public)")
            let outcome: Outcome
            switch job {
            case let .extract(mode, archive): outcome = await extract(archive, mode: mode)
            case let .compress(format, items): outcome = await compress(items, format: format)
            }
            switch outcome {
            case let .failed(title, message):
                log.error("\(title, privacy: .public): \(message, privacy: .public)")
                showError(title: title, message: message)
            case let .done(title, _):
                log.info("\(title, privacy: .public)")
            case .canceled:
                log.info("Canceled")
            }
            outcomes.append(outcome)
        }
        let finished = outcomes
        outcomes = []
        isBusy = false
        Task { await Self.notifySuccesses(finished) }
        onIdle?()
    }

    /// Ask for notification permission up front (at launch) so it never interrupts a job.
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            log.info("Notification permission granted: \(granted), error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Extract

    private func extract(_ archive: URL, mode: ExtractMode) async -> Outcome {
        let name = archive.lastPathComponent
        let failureTitle = "Couldn't extract “\(name)”"
        let parent = archive.deletingLastPathComponent()
        let isTarball = ArchiveTypes.isTarball(archive)

        do {
            // 1. Look inside: find out whether it needs a password and what it will create.
            var password: String?
            var listing = try await list(archive, isTarball: isTarball, password: nil)
            if listing == nil || listing!.hasEncryptedEntries {
                guard let entered = try await askForWorkingPassword(archive) else { return .canceled }
                password = entered
                listing = try await list(archive, isTarball: isTarball, password: entered)
            }
            guard let listing else { return .failed(title: failureTitle, message: "Couldn't read the archive.") }

            // 2. Decide where it goes and how to handle existing files.
            //    "Extract to folder" unpacks into a hidden staging folder first, then moves the
            //    result into place, so a half-finished folder never shows up in Finder.
            let extractInto: URL
            var overwriteSwitch = "-aoa" // overwrite (only matters for Extract Here)
            switch mode {
            case .toFolder:
                extractInto = parent.appendingPathComponent(".DigitZip-\(UUID().uuidString)", isDirectory: true)
            case .here:
                extractInto = parent
                let conflicts = listing.topLevelNames.filter {
                    FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
                }
                if !conflicts.isEmpty {
                    switch askAboutConflicts(archive: name, conflicts: conflicts) {
                    case .keepBoth: overwriteSwitch = "-aou" // auto-rename extracted copies
                    case .replace: overwriteSwitch = "-aoa"
                    case .skip: overwriteSwitch = "-aos"
                    case .cancel: return .canceled
                    }
                }
            }

            // 3. Extract.
            let passwordSwitch = password.map { "-p\($0)" } ?? noPassword
            let extractOptions = ["-o\(extractInto.path)", overwriteSwitch, "-y", "-bd", "-xr!__MACOSX", "-xr!._*"]
            let result: ProcessResult
            if isTarball {
                result = try await SevenZip.pipeline([
                    ["x", "-so", "-bd", passwordSwitch, "--", archive.path],
                    ["x", "-si", "-ttar"] + extractOptions,
                ])
            } else {
                result = try await SevenZip.run(["x", passwordSwitch] + extractOptions + ["--", archive.path])
            }

            guard result.succeeded else {
                if mode == .toFolder { try? FileManager.default.removeItem(at: extractInto) }
                return .failed(title: failureTitle, message: result.errorSummary)
            }

            // 4. For "Extract to folder", move the staged result into place.
            guard mode == .toFolder else {
                return .done(title: "Extracted “\(name)”", detail: "Into this folder")
            }
            let destination = uniqueFolder(in: parent, named: ArchiveTypes.baseName(archive))
            do {
                try moveStagedContents(from: extractInto, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: extractInto)
                throw error
            }
            return .done(title: "Extracted “\(name)”", detail: "Into “\(destination.lastPathComponent)/”")
        } catch {
            return .failed(title: failureTitle, message: error.localizedDescription)
        }
    }

    // MARK: - Compress

    /// Creates "name.zip" / "name.7z" next to the items. Like extraction, it writes to a hidden
    /// staging file and renames it into place, so a half-written archive never appears and
    /// an existing archive is never overwritten ("name 2.zip" instead).
    private func compress(_ items: [URL], format: ArchiveFormat) async -> Outcome {
        guard let first = items.first else { return .canceled }
        let parent = first.deletingLastPathComponent()
        let baseName = ArchiveTypes.newArchiveBaseName(for: items)
        let failureTitle = "Couldn't create “\(baseName).\(format.fileExtension)”"
        let staging = parent.appendingPathComponent(".DigitZip-\(UUID().uuidString).\(format.fileExtension)")

        do {
            let result = try await SevenZip.run(
                ["a", format.sevenZipTypeSwitch, "-y", "-bd", "-xr!.DS_Store", "-xr!._*", "-xr!__MACOSX",
                 "--", staging.path] + items.map(\.path)
            )
            guard result.succeeded else {
                try? FileManager.default.removeItem(at: staging)
                return .failed(title: failureTitle, message: result.errorSummary)
            }
            let destination = uniqueFile(in: parent, named: baseName, extension: format.fileExtension)
            try FileManager.default.moveItem(at: staging, to: destination)
            let detail = items.count == 1 ? "From “\(first.lastPathComponent)”" : "From \(items.count) items"
            return .done(title: "Created “\(destination.lastPathComponent)”", detail: detail)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            return .failed(title: failureTitle, message: error.localizedDescription)
        }
    }

    /// Lists the archive's contents. Returns nil if a password is needed to read it at all.
    private func list(_ archive: URL, isTarball: Bool, password: String?) async throws -> ArchiveListing? {
        let passwordSwitch = password.map { "-p\($0)" } ?? noPassword
        let result: ProcessResult
        if isTarball {
            result = try await SevenZip.pipeline([
                ["x", "-so", "-bd", passwordSwitch, "--", archive.path],
                ["l", "-si", "-ttar", "-slt", "-ba"],
            ])
        } else {
            result = try await SevenZip.run(["l", "-slt", "-ba", passwordSwitch, "--", archive.path])
        }
        if result.succeeded { return ArchiveListing(parsing: result.output) }
        if result.isPasswordError { return nil }
        throw DigitZipError.failed(result.errorSummary)
    }

    /// Prompts until the user enters a password that passes `7zz t`, or cancels.
    private func askForWorkingPassword(_ archive: URL) async throws -> String? {
        var message = "“\(archive.lastPathComponent)” is password-protected."
        while true {
            guard let password = promptForPassword(message: message) else { return nil }
            let test = try await SevenZip.run(["t", "-p\(password)", "-bd", "--", archive.path])
            if test.succeeded { return password }
            guard test.isPasswordError else { throw DigitZipError.failed(test.errorSummary) }
            message = "That password didn't work for “\(archive.lastPathComponent)”. Try again."
        }
    }

    /// Smart folder: if the archive held exactly one folder (e.g. "Holiday Photos/"), that folder
    /// *becomes* the destination instead of being nested inside another one with the same name.
    /// Otherwise (loose files, several items) the staging folder itself becomes the destination.
    private func moveStagedContents(from staging: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent != ".DS_Store" }
        let soleFolder = items.count == 1
            && (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if soleFolder {
            try fileManager.moveItem(at: items[0], to: destination)
            try fileManager.removeItem(at: staging)
            log.info("Smart folder: used the archive's single folder “\(items[0].lastPathComponent, privacy: .public)”")
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
    }

    private func uniqueFolder(in directory: URL, named name: String) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    private func uniqueFile(in directory: URL, named name: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(name).\(ext)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    // MARK: - Asking and telling the user

    private enum ConflictChoice { case keepBoth, replace, skip, cancel }

    private func askAboutConflicts(archive: String, conflicts: [String]) -> ConflictChoice {
        let shown = conflicts.prefix(5).map { "• \($0)" }.joined(separator: "\n")
        let more = conflicts.count > 5 ? "\n…and \(conflicts.count - 5) more" : ""
        let alert = NSAlert()
        alert.messageText = "Some items from “\(archive)” already exist here"
        alert.informativeText = shown + more
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Skip Existing")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return .cancel
        }
    }

    private func promptForPassword(message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Password Required"
        alert.informativeText = message
        alert.addButton(withTitle: "Extract")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private static func notifySuccesses(_ outcomes: [Outcome]) async {
        let finished = outcomes.compactMap { outcome -> (title: String, detail: String)? in
            if case let .done(title, detail) = outcome { return (title, detail) }
            return nil
        }
        guard !finished.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            log.info("Notifications not allowed (status \(settings.authorizationStatus.rawValue)); skipping")
            return
        }

        let content = UNMutableNotificationContent()
        if finished.count == 1 {
            content.title = finished[0].title
            content.body = finished[0].detail
        } else {
            content.title = "DigitZip finished \(finished.count) tasks"
            content.body = finished.map(\.title).joined(separator: "\n")
        }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
