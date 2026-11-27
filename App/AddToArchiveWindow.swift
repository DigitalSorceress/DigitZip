import AppKit
import SwiftUI

// The "Add to Archive…" dialog: 7-Zip's options window, Mac-style.

@MainActor
final class AddToArchiveModel: ObservableObject {
    let items: [URL]

    @Published var directory: URL {
        didSet { folderText = Self.displayPath(directory); folderProblem = nil; missingFolder = nil }
    }
    /// Set when the typed folder doesn't exist yet, so the dialog can offer to create it.
    @Published var missingFolder: URL?
    /// What's in the editable folder field; checked by `commitFolder()` on Return / leaving the field.
    @Published var folderText: String
    @Published var folderProblem: String?
    @Published var name: String
    @Published var settings: CompressionSettings {
        didSet {
            if settings.format != oldValue.format { swapExtension(from: oldValue.format, to: settings.format) }
            // Assigning to an @Published property inside its own didSet re-runs didSet, so only
            // assign when normalizing actually changes something; otherwise this recurses forever.
            var normalized = settings
            normalized.normalize()
            if normalized != settings { settings = normalized }
        }
    }
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var showPassword = false
    @Published var split = ""
    @Published var parameters = ""

    init(items: [URL]) {
        self.items = items
        let settings = CompressionSettings.load()
        self.settings = settings
        let directory = items.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        self.directory = directory
        folderText = Self.displayPath(directory)
        name = ArchiveTypes.newArchiveBaseName(for: items) + "." + settings.format.fileExtension
    }

    var archiveURL: URL { directory.appendingPathComponent(name) }

    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Validates the typed folder: expands "~", and accepts it only if it's an existing folder.
    /// A path that doesn't exist yet is remembered in `missingFolder` so the user can create it.
    func commitFolder() {
        missingFolder = nil
        let typed = folderText.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else {
            folderProblem = "Enter a folder to save the archive in."
            return
        }
        let expanded = (typed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            folderProblem = "Enter a full path, starting with “/” or “~”."
            return
        }
        let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) {
            if isFolder.boolValue {
                directory = url
            } else {
                folderProblem = "“\(typed)” is a file, not a folder."
            }
        } else {
            missingFolder = url
            folderProblem = "Create the folder or choose a different one."
        }
    }

    var archiveExists: Bool {
        let path = archiveURL.path
        return FileManager.default.fileExists(atPath: path) || FileManager.default.fileExists(atPath: path + ".001")
    }

    func createMissingFolder() {
        guard let folder = missingFolder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
        } catch {
            missingFolder = nil
            folderProblem = "Couldn't create “\(Self.displayPath(folder))”: \(error.localizedDescription)"
        }
    }

    /// Why Create is disabled, or nil when everything is valid.
    var problem: String? {
        if let folderProblem { return folderProblem }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a name for the archive." }
        if trimmed.contains("/") || trimmed.contains(":") { return "The name can't contain “/” or “:”." }
        if settings.supportsEncryption, !showPassword, password != confirmPassword {
            return "The passwords don't match."
        }
        if CompressionOptions.splitSize(from: split) == .invalid {
            return "Split size must be a whole number with an optional unit, like 100M or 4092M."
        }
        return nil
    }

    func makeJob() -> CustomCompression? {
        if folderText != Self.displayPath(directory) { commitFolder() }
        guard problem == nil else { return nil }
        var splitSize: String?
        if case let .size(size) = CompressionOptions.splitSize(from: split) { splitSize = size }
        return CustomCompression(
            items: items,
            archive: directory.appendingPathComponent(name.trimmingCharacters(in: .whitespaces)),
            settings: settings,
            password: settings.supportsEncryption ? password : "",
            splitSize: splitSize,
            extraParameters: CompressionOptions.parseParameters(parameters)
        )
    }

    func resetToDefaults() {
        settings = CompressionSettings()
    }

    /// Like 7-Zip: changing the format changes the name's extension, if it had the old one.
    private func swapExtension(from old: ArchiveFormat, to new: ArchiveFormat) {
        let oldSuffix = "." + old.fileExtension
        if name.lowercased().hasSuffix(oldSuffix) {
            name = String(name.dropLast(oldSuffix.count)) + "." + new.fileExtension
        }
    }
}

struct AddToArchiveView: View {
    @ObservedObject var model: AddToArchiveModel
    var onChooseFolder: () -> Void
    var onCancel: () -> Void
    var onCreate: () -> Void

    private let controlWidth: CGFloat = 170
    @FocusState private var folderFieldFocused: Bool
    @AppStorage("AddToArchiveShowAdvanced") private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            archiveSection
            HStack(alignment: .top, spacing: 28) {
                compressionColumn
                optionsColumn
            }
            footer
        }
        .padding(20)
        .fixedSize()
    }

    // MARK: Archive name and location

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Archive:")
                    TextField("Archive name", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text("In folder:")
                    TextField("Folder", text: $model.folderText)
                        .textFieldStyle(.roundedBorder)
                        .focused($folderFieldFocused)
                        .onSubmit { model.commitFolder() }
                        .onChange(of: folderFieldFocused) { _, focused in
                            if !focused { model.commitFolder() }
                        }
                    Button("…", action: onChooseFolder)
                        .help("Choose a folder")
                        .fixedSize()
                }
            }

            // Notes about the location, lined up under the text fields.
            Group {
                if let missing = model.missingFolder {
                    HStack {
                        Label("There's no folder at “\(AddToArchiveModel.displayPath(missing))”.",
                              systemImage: "questionmark.folder")
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Create Folder") { model.createMissingFolder() }
                            .controlSize(.small)
                    }
                } else if model.archiveExists, model.folderProblem == nil {
                    Label("“\(model.name)” already exists. It will be changed using “\(model.settings.updateMode.title)”.",
                          systemImage: "info.circle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .padding(.leading, 72)
        }
        .frame(width: 660, alignment: .leading)
    }

    // MARK: Left column: format and compression

    private var compressionColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("Archive format:") {
                    Picker("Archive format", selection: $model.settings.format) {
                        ForEach(ArchiveFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                row("Compression level:") {
                    Picker("Compression level", selection: $model.settings.level) {
                        ForEach(CompressionOptions.levels, id: \.value) { Text($0.title).tag($0.value) }
                    }
                }
                .disabled(!model.settings.supportsLevel)
                row("Split into volumes:") {
                    HStack(spacing: 4) {
                        TextField("Don't split", text: $model.split)
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(CompressionOptions.splitPresets, id: \.value) { preset in
                                Button(preset.note.isEmpty ? preset.value : "\(preset.value) – \(preset.note)") {
                                    model.split = preset.value
                                }
                            }
                            Divider()
                            Button("Don't Split") { model.split = "" }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showAdvanced.toggle() }
            } label: {
                Label("Advanced", systemImage: showAdvanced ? "chevron.down" : "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if showAdvanced {
                advancedGrid
            }
        }
        .frame(width: 330, alignment: .leading)
    }

    private var advancedGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            row("Compression method:") {
                Picker("Compression method", selection: methodBinding) {
                    ForEach(CompressionOptions.methods(for: model.settings.format), id: \.self) { Text($0).tag($0) }
                }
            }
            .disabled(CompressionOptions.methods(for: model.settings.format).isEmpty)
            row(model.settings.dictionaryKind == .ppmdMemory ? "Memory size:" : "Dictionary size:") {
                Picker("Dictionary size", selection: $model.settings.dictionary) {
                    Text("Auto").tag(String?.none)
                    ForEach(CompressionOptions.dictionarySizes, id: \.self) {
                        Text(CompressionOptions.sizeLabel($0)).tag(Optional($0))
                    }
                }
            }
            .disabled(model.settings.dictionaryKind == nil)
            row(isPPMdOrder ? "Model order:" : "Word size:") {
                Picker("Word size", selection: $model.settings.wordSize) {
                    Text("Auto").tag(Int?.none)
                    ForEach(wordSizes, id: \.self) { Text("\($0)").tag(Optional($0)) }
                }
            }
            .disabled(model.settings.wordKind == nil)
            row("Solid block size:") {
                Picker("Solid block size", selection: $model.settings.solidBlock) {
                    Text("Auto").tag(String?.none)
                    Text("Non-solid").tag(Optional("off"))
                    ForEach(CompressionOptions.solidBlockSizes, id: \.self) {
                        Text(CompressionOptions.sizeLabel($0)).tag(Optional($0))
                    }
                    Text("Solid").tag(Optional("on"))
                }
            }
            .disabled(!model.settings.supportsSolidBlocks)
            row("CPU threads:") {
                HStack {
                    Picker("CPU threads", selection: $model.settings.threads) {
                        Text("Auto").tag(Int?.none)
                        ForEach(1...CompressionOptions.cpuCount, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    Text("/ \(CompressionOptions.cpuCount)").foregroundStyle(.secondary)
                }
            }
            .disabled(!model.settings.supportsThreads)
            row("Parameters:") {
                TextField("Extra 7-Zip switches", text: $model.parameters)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: Right column: update, options, encryption

    private var optionsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("Update mode:", width: 190) {
                    Picker("Update mode", selection: $model.settings.updateMode) {
                        ForEach(UpdateMode.allCases) { Text($0.title).tag($0) }
                    }
                }
                row("Path mode:", width: 190) {
                    Picker("Path mode", selection: $model.settings.pathMode) {
                        ForEach(PathMode.allCases) { Text($0.title).tag($0) }
                    }
                }
            }

            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Leave out macOS junk (.DS_Store, ._ files)", isOn: $model.settings.excludeMacJunk)
                    Toggle("Move originals to Trash afterward", isOn: $model.settings.trashOriginals)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox("Encryption") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter password:")
                    passwordField($model.password)
                    if !model.showPassword {
                        Text("Reenter password:")
                        passwordField($model.confirmPassword)
                    }
                    Toggle("Show password", isOn: $model.showPassword)
                    HStack {
                        Text("Encryption method:")
                        if model.settings.format == .zip {
                            Picker("Encryption method", selection: $model.settings.zipEncryption) {
                                ForEach(ZipEncryption.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                        } else {
                            Text("AES-256").foregroundStyle(.secondary)
                        }
                    }
                    if model.settings.format == .zip {
                        Text(model.settings.zipEncryption == .aes256
                             ? "Strong, but macOS Archive Utility and Windows Explorer can't open it. Needs 7-Zip, Keka or similar."
                             : "Opens anywhere, but is weak protection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Encrypt file names", isOn: $model.settings.encryptFileNames)
                        .disabled(!model.settings.supportsFileNameEncryption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .disabled(!model.settings.supportsEncryption)
        }
        .frame(width: 300, alignment: .leading)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset to Defaults") { model.resetToDefaults() }
            if let problem = model.problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(model.archiveExists ? "Update" : "Create", action: onCreate)
                .keyboardShortcut(.defaultAction)
                .disabled(model.problem != nil)
        }
        .frame(width: 660)
    }

    // MARK: Helpers

    private func row(_ label: String, width: CGFloat? = nil, @ViewBuilder control: () -> some View) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.leading)
            control()
                .labelsHidden()
                .frame(width: width ?? controlWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func passwordField(_ text: Binding<String>) -> some View {
        if model.showPassword {
            TextField("", text: text).textFieldStyle(.roundedBorder)
        } else {
            SecureField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var methodBinding: Binding<String> {
        Binding(
            get: { model.settings.effectiveMethod ?? "" },
            set: { newValue in
                model.settings.method = newValue == CompressionOptions.defaultMethod(for: model.settings.format)
                    ? nil : newValue
            }
        )
    }

    private var isPPMdOrder: Bool {
        if case .ppmdOrder = model.settings.wordKind { return true }
        return false
    }

    private var wordSizes: [Int] {
        switch model.settings.wordKind {
        case let .fastBytes(max):
            CompressionOptions.fastBytes.filter { $0 <= max } + (max == 258 ? [258] : [])
        case .ppmdOrder:
            CompressionOptions.ppmdOrders
        case nil:
            []
        }
    }
}

/// Hosts one Add to Archive dialog. Several can be open at once.
@MainActor
final class AddToArchiveWindowController: NSWindowController, NSWindowDelegate {
    private let model: AddToArchiveModel
    private let onCreate: (CustomCompression) -> Void
    var onClose: (() -> Void)?

    init(items: [URL], onCreate: @escaping (CustomCompression) -> Void) {
        model = AddToArchiveModel(items: items)
        self.onCreate = onCreate
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Add to Archive"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: AddToArchiveView(
            model: model,
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onCancel: { [weak self] in self?.close() },
            onCreate: { [weak self] in self?.create() }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func create() {
        guard let job = model.makeJob() else { return }
        model.settings.save()
        close()
        onCreate(job)
    }

    private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.directory
        panel.prompt = "Choose"
        panel.message = "Choose where to save the archive"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.directory = url
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
