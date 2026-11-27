import AppKit
import UserNotifications

/// Extracts archives one at a time, asking the user only when it has to
/// (password, or files that already exist).
@MainActor
final class ExtractionQueue {
    private struct Job {
        let mode: ExtractMode
        let archive: URL
    }

    private enum Outcome {
        case extracted(archive: String, destination: String)
        case cancelled
        case failed(archive: String, message: String)
    }

    private var pending: [Job] = []
    private var outcomes: [Outcome] = []
    private(set) var isBusy = false
    var onIdle: (() -> Void)?

    /// Passed to 7zz when there's no password, so it fails cleanly instead of prompting on stdin.
    /// Harmless for archives that aren't encrypted.
    private let noPassword = "-pDIGITZIP-NO-PASSWORD"

    func enqueue(mode: ExtractMode, archives: [URL]) {
        pending += archives.map { Job(mode: mode, archive: $0) }
        guard !isBusy else { return }
        isBusy = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let outcome = await process(job)
            if case let .failed(archive, message) = outcome {
                showError(archive: archive, message: message)
            }
            outcomes.append(outcome)
        }
        await notifySuccesses()
        outcomes = []
        isBusy = false
        onIdle?()
    }

    // MARK: - One archive

    private func process(_ job: Job) async -> Outcome {
        let archive = job.archive
        let name = archive.lastPathComponent
        let parent = archive.deletingLastPathComponent()
        let isTarball = ArchiveTypes.isTarball(archive)

        do {
            // 1. Look inside: find out whether it needs a password and what it will create.
            var password: String?
            var listing = try await list(archive, isTarball: isTarball, password: nil)
            if listing == nil || listing!.hasEncryptedEntries {
                guard let entered = try await askForWorkingPassword(archive) else { return .cancelled }
                password = entered
                listing = try await list(archive, isTarball: isTarball, password: entered)
            }
            guard let listing else { return .failed(archive: name, message: "Couldn't read the archive.") }

            // 2. Decide where it goes and how to handle existing files.
            let destination: URL
            var overwriteSwitch = "-aoa" // overwrite (only matters for Extract Here)
            switch job.mode {
            case .toFolder:
                destination = uniqueFolder(in: parent, named: ArchiveTypes.baseName(archive))
            case .here:
                destination = parent
                let conflicts = listing.topLevelNames.filter {
                    FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path)
                }
                if !conflicts.isEmpty {
                    switch askAboutConflicts(archive: name, conflicts: conflicts) {
                    case .keepBoth: overwriteSwitch = "-aou" // auto-rename extracted copies
                    case .replace: overwriteSwitch = "-aoa"
                    case .skip: overwriteSwitch = "-aos"
                    case .cancel: return .cancelled
                    }
                }
            }

            // 3. Extract.
            let passwordSwitch = password.map { "-p\($0)" } ?? noPassword
            let extractOptions = ["-o\(destination.path)", overwriteSwitch, "-y", "-bd", "-xr!__MACOSX", "-xr!._*"]
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
                if job.mode == .toFolder { try? FileManager.default.removeItem(at: destination) }
                return .failed(archive: name, message: result.errorSummary)
            }
            let shownDestination = job.mode == .toFolder ? "“\(destination.lastPathComponent)/”" : "this folder"
            return .extracted(archive: name, destination: shownDestination)
        } catch {
            return .failed(archive: name, message: error.localizedDescription)
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

    private func uniqueFolder(in directory: URL, named name: String) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(number)", isDirectory: true)
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

    private func showError(archive: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't extract “\(archive)”"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private func notifySuccesses() async {
        let extracted = outcomes.compactMap { outcome -> (String, String)? in
            if case let .extracted(archive, destination) = outcome { return (archive, destination) }
            return nil
        }
        guard !extracted.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }

        let content = UNMutableNotificationContent()
        if extracted.count == 1 {
            content.title = "Extracted “\(extracted[0].0)”"
            content.body = "Into \(extracted[0].1)"
        } else {
            content.title = "Extracted \(extracted.count) archives"
            content.body = extracted.map(\.0).joined(separator: ", ")
        }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
