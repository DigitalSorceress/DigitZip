import AppKit
import SwiftUI

// A small floating window showing the running job's progress, with Cancel.
// It only appears if a job takes longer than `showDelay`, so quick jobs never flash it.

@MainActor
final class ProgressModel: ObservableObject {
    @Published var title = ""
    @Published var item: String?
    /// nil until 7-Zip reports progress (shows an indeterminate bar).
    @Published var fraction: Double?
    /// "2 of 5" when several jobs are queued.
    @Published var position: String?
    @Published var isCanceling = false
}

struct JobProgressView: View {
    @ObservedObject var model: ProgressModel
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if let fraction = model.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(model.isCanceling ? "Canceling…" : (model.item ?? " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let fraction = model.fraction {
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if let position = model.position {
                    Text(position).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.position == nil ? "Cancel" : "Cancel All", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCanceling)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

@MainActor
final class ProgressPanelController {
    private let model = ProgressModel()
    private var panel: NSPanel?
    private var pendingShow: DispatchWorkItem?
    /// A job is running (between begin and end).
    private var isActive = false
    /// A prompt (password, overwrite, error) is on screen; keep the panel out of its way.
    private var isSuspended = false
    var onCancel: () -> Void = {}

    private let showDelay: TimeInterval = 0.6

    func begin(title: String, position: String?) {
        model.title = title
        model.position = position
        model.item = nil
        model.fraction = nil
        model.isCanceling = false
        isActive = true
        if panel?.isVisible != true { scheduleShow() }
    }

    func update(_ progress: SevenZipProgress) {
        guard isActive else { return }
        model.fraction = progress.fraction
        if let item = progress.item { model.item = item }
    }

    func markCanceling() {
        model.isCanceling = true
    }

    /// Hide while a prompt is showing; `resume()` brings the panel back if the job continues.
    func suspend() {
        isSuspended = true
        pendingShow?.cancel()
        panel?.orderOut(nil)
    }

    func resume() {
        isSuspended = false
        if isActive { scheduleShow() }
    }

    /// Called when the whole queue is done.
    func end() {
        isActive = false
        pendingShow?.cancel()
        panel?.orderOut(nil)
    }

    private func scheduleShow() {
        pendingShow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive, !self.isSuspended else { return }
            self.makePanelIfNeeded().orderFrontRegardless()
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        // Non-activating, so it can be clicked (Cancel) without pulling focus from Finder.
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "DigitZip"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = NSHostingController(
            rootView: JobProgressView(model: model, onCancel: { [weak self] in self?.onCancel() })
        )
        panel.center()
        self.panel = panel
        return panel
    }
}
