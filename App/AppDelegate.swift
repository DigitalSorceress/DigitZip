import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = JobQueue()
    private var window: NSWindow?
    private var quitTimer: Timer?

    /// Stay alive this long after the last job so back-to-back extractions start instantly.
    private let idleQuitDelay: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.onIdle = { [weak self] in self?.scheduleQuitIfIdle() }
        JobQueue.requestNotificationPermission()

        // Opened directly (Finder, Spotlight, Xcode) rather than via a digitzip:// URL → show settings.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch { showSettings() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            quitTimer?.invalidate()
            switch DigitZipRequest(url: url) {
            case let .extract(mode, files):
                queue.enqueue(files.map { .extract(mode: mode, archive: $0) })
            case let .compress(format, files):
                queue.enqueue([.compress(format: format, items: files)])
            case .about:
                showAbout()
            case nil:
                log.error("Ignoring unrecognized URL")
            }
        }
        scheduleQuitIfIdle()
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

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: AboutInfo.panelOptions)
        scheduleQuitIfIdle()
    }

    /// Quits once nothing is happening: no extraction running and no window (settings,
    /// About, alerts) on screen. Re-checks rather than quitting out from under a window.
    private func scheduleQuitIfIdle() {
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: idleQuitDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.queue.isBusy || NSApp.windows.contains(where: \.isVisible) {
                    self.scheduleQuitIfIdle()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { self.scheduleQuitIfIdle() }
    }
}
