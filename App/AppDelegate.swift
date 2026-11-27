import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = ExtractionQueue()
    private var window: NSWindow?
    private var quitTimer: Timer?

    /// Stay alive this long after the last job so back-to-back extractions start instantly.
    private let idleQuitDelay: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.onIdle = { [weak self] in self?.scheduleQuitIfIdle() }
        ExtractionQueue.requestNotificationPermission()

        // Opened directly (Finder, Spotlight, Xcode) rather than via a digitzip:// URL → show settings.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch { showSettings() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = DigitZipRequest.parse(url) else {
                log.error("Ignoring unrecognised URL")
                continue
            }
            quitTimer?.invalidate()
            queue.enqueue(mode: request.mode, archives: request.files)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // the queue decides when to quit
    }

    private func showSettings() {
        quitTimer?.invalidate()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "DigitZip"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func scheduleQuitIfIdle() {
        quitTimer?.invalidate()
        guard window?.isVisible != true, !queue.isBusy else { return }
        quitTimer = Timer.scheduledTimer(withTimeInterval: idleQuitDelay, repeats: false) { _ in
            NSApp.terminate(nil)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.scheduleQuitIfIdle() }
    }
}
