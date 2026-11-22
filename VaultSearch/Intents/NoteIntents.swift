import AppIntents
import AppKit

// Actions for Siri, Shortcuts and Spotlight. They only read the vault;
// the one exception is "Save Results to Vault", which adds a new note, as the menu command does.

// MARK: - Search

/// Shows the results of a search in the VaultSearch window.
@AppIntent(schema: .system.searchInApp)
struct SearchInVaultSearchIntent {
    static let title: LocalizedStringResource = "Search in VaultSearch"
    static let description = IntentDescription("Shows the results of a search in the VaultSearch window.")
    static let searchScopes = [StringSearchScope.general]

    @Parameter(title: "Search", description: "Search text, e.g. “tag:idea” or “modified:last 7 days”.")
    var criteria: StringSearchCriteria

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.requestSearch(criteria.term)
        return .result()
    }
}

/// Returns the notes matching a search, for use in a shortcut or as an answer from Siri.
struct FindNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Notes"
    static let description = IntentDescription(
        "Searches the vault and returns the matching notes. Uses the same search syntax as the search field.",
        categoryName: "Search"
    )

    @Parameter(title: "Search", description: "Search text, e.g. “tag:idea” or “modified:last 7 days”.")
    var query: String

    @Parameter(title: "Maximum Results", default: 20, inclusiveRange: (1, 500))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find notes matching \(\.$query)") {
            \.$limit
        }
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<[NoteEntity]> & ProvidesDialog {
        try await model.requireVault()
        let found = await model.search.indexedResults(for: query)
        let notes = found.prefix(limit).map(NoteEntity.init)
        let dialog: IntentDialog = found.isEmpty
            ? "No notes found."
            : "Found \(found.count) notes."
        return .result(value: Array(notes), dialog: dialog)
    }
}

// MARK: - Open

/// Opens a note in Obsidian; VaultSearch stays in the background.
@AppIntent(schema: .system.open)
struct OpenNoteIntent {
    static let title: LocalizedStringResource = "Open Note in Obsidian"
    static let description = IntentDescription("Opens a note of the vault in Obsidian.")
    static let openAppWhenRun = false

    @Parameter(title: "Note")
    var target: NoteEntity

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let file = model.search.file(with: URL(fileURLWithPath: target.id)) else {
            throw VaultSearchIntentError.noteNotFound
        }
        NoteActions.openInObsidian(file)
        return .result()
    }
}

// MARK: - Export

/// Saves the results of a search as a Markdown note in the export folder of the vault.
struct SaveResultsToVaultIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Search Results to Vault"
    static let description = IntentDescription(
        "Saves the results of a search as a note in the export folder of the vault.",
        categoryName: "Export"
    )

    @Parameter(title: "Search", description: "Search text, e.g. “tag:idea” or “modified:last 7 days”.")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save results of \(\.$query) to the vault")
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> & ProvidesDialog {
        try await model.requireVault()
        let snapshot = await model.snapshot(for: query)
        guard !snapshot.files.isEmpty else { throw VaultSearchIntentError.noResults }
        let url = try await model.exporter.writeResultsToVault(snapshot)
        return .result(value: IntentFile(fileURL: url), dialog: "Saved \(snapshot.files.count) notes to “\(url.deletingPathExtension().lastPathComponent)”.")
    }
}

/// Exports the results of a search, e.g. as PDF, and hands the file on to the next action.
struct ExportResultsIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Search Results"
    static let description = IntentDescription(
        "Exports the results of a search as a document. Pass the file on to “Save File” or “Share”.",
        categoryName: "Export"
    )

    @Parameter(title: "Search", description: "Search text, e.g. “tag:idea” or “modified:last 7 days”.")
    var query: String

    @Parameter(title: "Format", default: .pdf)
    var format: ExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export results of \(\.$query) as \(\.$format)")
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> {
        try await model.requireVault()
        try await model.requireFormat(format)
        let snapshot = await model.snapshot(for: query)
        guard !snapshot.files.isEmpty else { throw VaultSearchIntentError.noResults }
        let output = try ExportService.temporaryOutput(name: ResultListExport.fileName(for: query), format: format)
        try await model.exporter.writeResults(snapshot, as: format, to: output)
        return .result(value: IntentFile(fileURL: output, filename: output.lastPathComponent, type: format.contentType))
    }
}

/// Exports one note, e.g. as PDF or Word, and hands the file on to the next action.
struct ExportNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Note"
    static let description = IntentDescription(
        "Exports a note as a document. Pass the file on to “Save File” or “Share”.",
        categoryName: "Export"
    )

    @Parameter(title: "Note")
    var note: NoteEntity

    @Parameter(title: "Format", default: .pdf)
    var format: ExportFormat

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$note) as \(\.$format)")
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> {
        try await model.requireFormat(format)
        await model.search.waitUntilIndexed()
        guard let file = await model.search.file(with: URL(fileURLWithPath: note.id)) else {
            throw VaultSearchIntentError.noteNotFound
        }
        let output = try ExportService.temporaryOutput(name: file.title, format: format)
        try await model.exporter.writeNote(file, as: format, to: output)
        return .result(value: IntentFile(fileURL: output, filename: output.lastPathComponent, type: format.contentType))
    }
}

// MARK: - Support

extension ExportFormat: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static let caseDisplayRepresentations: [ExportFormat: DisplayRepresentation] = [
        .pdf: "PDF",
        .docx: "Word",
        .odt: "OpenDocument",
        .rtf: "Rich Text",
        .html: "HTML",
        .epub: "EPUB",
        .markdown: "Markdown",
    ]
}

enum VaultSearchIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noVault
    case noteNotFound
    case noResults
    case pandocRequired

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noVault: "Choose a vault in VaultSearch first."
        case .noteNotFound: "The note is no longer in the vault."
        case .noResults: "The search found no notes."
        case .pandocRequired: "This format requires Pandoc. Install it with “brew install pandoc”."
        }
    }
}

extension AppModel {
    /// Puts a search into the search field of the window and brings VaultSearch to the front.
    func requestSearch(_ text: String) {
        requestedSearch = text
        NSApplication.shared.activate()
    }

    func requireVault() throws {
        guard settings.vaultPath != nil else { throw VaultSearchIntentError.noVault }
    }

    func requireFormat(_ format: ExportFormat) async throws {
        await exporter.waitForTools()
        guard exporter.canExport(format) else { throw VaultSearchIntentError.pandocRequired }
    }

    /// The results of `query` as the window would show them.
    func snapshot(for query: String) async -> ResultsSnapshot {
        let files = await search.indexedResults(for: query)
        return ResultsSnapshot(query: query, files: files, highlightTerms: SearchQuery(query).textTerms)
    }
}
