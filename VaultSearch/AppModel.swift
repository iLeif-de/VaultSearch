import AppKit
import Combine
import CoreSpotlight
import SwiftUI

/// Shared state for all windows: settings plus the search index built from them.
/// There is exactly one, so windows, Siri, Shortcuts and AppleScript see the same index.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings = AppSettings()
    let search = SearchService()
    let exporter: ExportService
    /// A search handed over by Siri or Shortcuts; the window puts it into its search field.
    @Published var requestedSearch: String?
    private var cancellables: Set<AnyCancellable> = []
    private var spotlightTask: Task<Void, Never>?
    /// Modification dates of the notes last handed to Spotlight; nil until the first pass after launch.
    private var spotlightDates: [String: Date]?

    /// True while unit tests run inside the app; the vault is then left alone.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    private init() {
        exporter = ExportService(settings: settings)
        guard !Self.isRunningTests else { return }
        // The export folder holds result lists of earlier searches; it is never searched itself.
        settings.$vaultPath
            .combineLatest(settings.$excludedFolders, settings.$exportFolder)
            .sink { [weak self] vaultPath, excluded, exportFolder in
                MainActor.assumeIsolated {
                    let folder = exportFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
                    self?.search.configure(vaultURL: vaultPath, excludedFolders: folder.isEmpty ? excluded : excluded.union([folder]))
                }
            }
            .store(in: &cancellables)
        // `generation` changes after every index run, when `files` is already up to date.
        search.$generation
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateSpotlight() }
            }
            .store(in: &cancellables)
    }

    /// Hands new and changed notes to Spotlight and removes deleted ones, so Siri can find them.
    /// The first pass after launch replaces everything, because notes may have changed while the app was closed.
    private func updateSpotlight() {
        let files = search.files
        let previous = spotlightDates
        spotlightTask?.cancel()
        spotlightTask = Task {
            let current = Dictionary(files.map { ($0.path.path, $0.fileModifiedDate) }, uniquingKeysWith: { first, _ in first })
            let changed = await Task.detached(priority: .utility) {
                files.filter { previous?[$0.path.path] != $0.fileModifiedDate }.map(NoteEntity.init)
            }.value
            guard !Task.isCancelled else { return }
            let index = CSSearchableIndex.default()
            do {
                if let previous {
                    let removed = previous.keys.filter { current[$0] == nil }
                    if !removed.isEmpty { try await index.deleteAppEntities(identifiedBy: removed, ofType: NoteEntity.self) }
                } else {
                    try await index.deleteAppEntities(ofType: NoteEntity.self)
                }
                if !changed.isEmpty { try await index.indexAppEntities(changed) }
                spotlightDates = current
            } catch {
                // Start over with the next index run.
                spotlightDates = nil
            }
        }
    }

    func chooseExportFolder() {
        guard let vault = settings.vaultPath else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose a folder inside your vault for exported result lists.")
        panel.prompt = String(localized: "Choose")
        panel.directoryURL = vault.appendingPathComponent(settings.exportFolderPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let root = vault.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == root {
            settings.exportFolder = ""
        } else if path.hasPrefix(root + "/") {
            settings.exportFolder = String(path.dropFirst(root.count + 1))
        } else {
            NSSound.beep()
        }
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose the folder of your Obsidian vault.")
        panel.prompt = String(localized: "Choose Vault")
        panel.directoryURL = settings.vaultPath
        if panel.runModal() == .OK, let url = panel.url {
            settings.vaultPath = url
        }
    }

    func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose folders whose notes should not be searched.")
        panel.prompt = String(localized: "Exclude")
        panel.directoryURL = settings.vaultPath
        guard panel.runModal() == .OK else { return }

        let root = settings.vaultPath?.standardizedFileURL.path
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if let root, path.hasPrefix(root + "/") {
                settings.excludedFolders.insert(String(path.dropFirst(root.count + 1)))
            } else {
                settings.excludedFolders.insert(path)
            }
        }
    }
}

/// Actions on a single note, shared by menus, context menus and toolbars.
enum NoteActions {
    static func openInObsidian(_ file: MarkdownFile) {
        if let uri = file.obsidianURI { NSWorkspace.shared.open(uri) }
    }

    static func openWithDefaultApp(_ file: MarkdownFile) {
        NSWorkspace.shared.open(file.path)
    }

    static func showInFinder(_ file: MarkdownFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.path])
    }

    static func copyObsidianLink(_ file: MarkdownFile) {
        guard let uri = file.obsidianURI else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uri.absoluteString, forType: .string)
    }

    static func copyPath(_ file: MarkdownFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path.path, forType: .string)
    }
}

/// Menu items for a note; used in the context menu of the result list.
struct NoteMenuItems: View {
    let file: MarkdownFile
    var highlightTerms: [String] = []
    @EnvironmentObject private var exporter: ExportService

    var body: some View {
        Button("Open in Obsidian", systemImage: "arrow.up.forward.app") { NoteActions.openInObsidian(file) }
        Button("Open with Default App", systemImage: "doc") { NoteActions.openWithDefaultApp(file) }
        Button("Show in Finder", systemImage: "folder") { NoteActions.showInFinder(file) }
        Divider()
        Button("Copy Obsidian Link", systemImage: "link") { NoteActions.copyObsidianLink(file) }
        Button("Copy Path", systemImage: "doc.on.doc") { NoteActions.copyPath(file) }
        Divider()
        NoteExportMenu(file: file, exporter: exporter, highlightTerms: highlightTerms)
        ShareLink(item: file.path)
    }
}

/// "Export As" submenu for one note.
struct NoteExportMenu: View {
    let file: MarkdownFile?
    @ObservedObject var exporter: ExportService
    var highlightTerms: [String] = []
    var title: LocalizedStringKey = "Export Note As"

    var body: some View {
        Menu(title) {
            ForEach(ExportFormat.allCases) { format in
                Button(format.menuTitle) {
                    if let file { exporter.exportNote(file, as: format, highlightTerms: highlightTerms) }
                }
                .disabled(file == nil || !exporter.canExport(format))
            }
        }
        .disabled(file == nil)
    }
}

/// Menu items for exporting the current result list.
struct ResultsExportItems: View {
    let snapshot: ResultsSnapshot?
    @ObservedObject var exporter: ExportService
    /// Only the menu bar carries the shortcut; a second copy in the toolbar menu would clash.
    var showsShortcut = false

    var body: some View {
        Button("Save Results to Vault") {
            if let snapshot { exporter.saveResultsToVault(snapshot) }
        }
        .keyboardShortcut(showsShortcut ? KeyboardShortcut("e", modifiers: [.command, .shift]) : nil)
        .disabled(snapshot?.files.isEmpty ?? true)
        Menu("Export Results As") {
            ForEach(ExportFormat.allCases) { format in
                Button(format.menuTitle) {
                    if let snapshot { exporter.exportResults(snapshot, as: format) }
                }
                .disabled(!exporter.canExport(format))
            }
        }
        .disabled(snapshot?.files.isEmpty ?? true)
    }
}

// MARK: - Focused values for menu commands

/// Find-in-note commands of the preview (⌥⌘F, ⌘G, ⇧⌘G).
struct NoteFindActions {
    let focus: () -> Void
    let next: () -> Void
    let previous: () -> Void
}

struct FocusSearchAction {
    let perform: () -> Void
    func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var selectedNote: MarkdownFile?
    @Entry var focusSearch: FocusSearchAction?
    @Entry var searchResults: ResultsSnapshot?
    @Entry var noteFind: NoteFindActions?
}
