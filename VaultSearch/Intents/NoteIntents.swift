import AppIntents
import AppKit

// Actions for Siri, Shortcuts and Spotlight. They only read the vault;
// the one exception is "Save Results to Vault", which adds a new note, as the menu command does.
//
// Find, Show, Save and Export share the same search fields (see `NoteSearchIntent`):
// - Find returns the notes to the shortcut,
// - Show puts the search into the VaultSearch window,
// - Save and Export write the results to a note or a document.

// MARK: - Search fields

/// Where the search text is looked for.
enum SearchTextScope: String, AppEnum {
    case titleAndText, title, text

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Search In"
    static let caseDisplayRepresentations: [SearchTextScope: DisplayRepresentation] = [
        .titleAndText: "Title and Text",
        .title: "Title Only",
        .text: "Text Only",
    ]
}

/// How the search criteria are combined.
enum CriteriaMatch: String, AppEnum {
    case all, any

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Combine"
    static let caseDisplayRepresentations: [CriteriaMatch: DisplayRepresentation] = [
        .all: "All Criteria (AND)",
        .any: "Any Criterion (OR)",
    ]
}

/// An intent with the shared search fields. Each intent declares them as `@Parameter`s;
/// this protocol turns them into the query syntax of the search field.
protocol NoteSearchIntent: AppIntent {
    var text: String? { get }
    var scope: SearchTextScope { get }
    var tags: [String]? { get }
    var inlineTags: [String]? { get }
    var propertyName: String? { get }
    var propertyValue: String? { get }
    var match: CriteriaMatch { get }
}

extension NoteSearchIntent {
    /// The search as it would be typed into the search field.
    func searchQuery() throws -> String {
        try NoteSearchCriteria(
            text: text, scope: scope, tags: tags ?? [], inlineTags: inlineTags ?? [],
            propertyName: propertyName, propertyValue: propertyValue, match: match
        ).query
    }
}

/// Builds the query text from the separate search fields; kept apart from the intents so it can be tested.
struct NoteSearchCriteria {
    var text: String?
    var scope: SearchTextScope = .titleAndText
    var tags: [String] = []
    var inlineTags: [String] = []
    var propertyName: String?
    var propertyValue: String?
    var match: CriteriaMatch = .all

    var query: String {
        get throws {
            var criteria: [String] = []

            if let text = Self.trimmed(text) {
                switch scope {
                case .titleAndText:
                    // Passed on as typed, so the full search syntax works here too.
                    criteria.append(text)
                case .title, .text:
                    let prefix = scope == .title ? "intitle:" : "intext:"
                    criteria.append(SearchQuery.tokenize(text).map { token in
                        SearchQuery.orOperators.contains(token) || SearchQuery.andOperators.contains(token)
                            ? token : prefix + SearchSuggestion.quoted(token)
                    }.joined(separator: " "))
                }
            }
            criteria += tags.compactMap(Self.trimmed).map { "tag:" + SearchSuggestion.quoted($0) }
            criteria += inlineTags.compactMap(Self.trimmed).map { "contenttag:" + SearchSuggestion.quoted($0) }

            switch (Self.trimmed(propertyName), Self.trimmed(propertyValue)) {
            case (let name?, let value?):
                guard name.first?.isLetter == true,
                      name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                    throw VaultSearchIntentError.invalidProperty
                }
                criteria.append("\(name):" + SearchSuggestion.quoted(value))
            case (nil, nil):
                break
            default:
                throw VaultSearchIntentError.incompleteProperty
            }

            return criteria.joined(separator: match == .all ? " " : " OR ")
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Find and show

/// Returns the notes matching a search, for use in a shortcut or as an answer from Siri.
struct FindNotesIntent: NoteSearchIntent {
    static let title: LocalizedStringResource = "Find Notes"
    static let description = IntentDescription(
        "Returns the notes matching the search to the shortcut, e.g. to export them. Without any criteria, it returns the most recently changed notes.",
        categoryName: "Search"
    )

    @Parameter(title: "Search Text", description: "Words to look for. The syntax of the search field works too, e.g. “modified:last 7 days”.")
    var text: String?

    @Parameter(title: "Search In", default: .titleAndText)
    var scope: SearchTextScope

    @Parameter(title: "Tags", description: "Tags from the note properties (frontmatter). Also finds nested tags.")
    var tags: [String]?

    @Parameter(title: "Tags in Text", description: "#tags or [[links]] written in the note text.")
    var inlineTags: [String]?

    @Parameter(title: "Property", description: "Name of a frontmatter property, e.g. “status”.")
    var propertyName: String?

    @Parameter(title: "Property Value", description: "The property must contain this value, e.g. “active”.")
    var propertyValue: String?

    @Parameter(title: "Combine", default: .all)
    var match: CriteriaMatch

    @Parameter(title: "Maximum Results", default: 20, inclusiveRange: (1, 500))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find notes with \(\.$text)") {
            \.$scope
            \.$tags
            \.$inlineTags
            \.$propertyName
            \.$propertyValue
            \.$match
            \.$limit
        }
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<[NoteEntity]> & ProvidesDialog {
        try await model.requireVault()
        let found = await model.search.indexedResults(for: try searchQuery())
        let notes = found.prefix(limit).map(NoteEntity.init)
        let dialog: IntentDialog = found.isEmpty
            ? "No notes found."
            : "Found \(found.count) notes."
        return .result(value: Array(notes), dialog: dialog)
    }
}

/// Shows the results of a search in the VaultSearch window.
struct ShowInVaultSearchIntent: NoteSearchIntent {
    static let title: LocalizedStringResource = "Show in VaultSearch"
    static let description = IntentDescription(
        "Opens VaultSearch and shows the results of the search in the window.",
        categoryName: "Search"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Search Text", description: "Words to look for. The syntax of the search field works too, e.g. “modified:last 7 days”.")
    var text: String?

    @Parameter(title: "Search In", default: .titleAndText)
    var scope: SearchTextScope

    @Parameter(title: "Tags", description: "Tags from the note properties (frontmatter). Also finds nested tags.")
    var tags: [String]?

    @Parameter(title: "Tags in Text", description: "#tags or [[links]] written in the note text.")
    var inlineTags: [String]?

    @Parameter(title: "Property", description: "Name of a frontmatter property, e.g. “status”.")
    var propertyName: String?

    @Parameter(title: "Property Value", description: "The property must contain this value, e.g. “active”.")
    var propertyValue: String?

    @Parameter(title: "Combine", default: .all)
    var match: CriteriaMatch

    static var parameterSummary: some ParameterSummary {
        Summary("Show notes with \(\.$text) in VaultSearch") {
            \.$scope
            \.$tags
            \.$inlineTags
            \.$propertyName
            \.$propertyValue
            \.$match
        }
    }

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.requestSearch(try searchQuery())
        return .result()
    }
}

/// Siri's “search in VaultSearch”. Not listed in Shortcuts, where “Show in VaultSearch” offers the same with separate fields.
@AppIntent(schema: .system.searchInApp)
struct SearchInVaultSearchIntent {
    static let title: LocalizedStringResource = "Search in VaultSearch"
    static let description = IntentDescription("Shows the results of a search in the VaultSearch window.")
    static let searchScopes = [StringSearchScope.general]
    static let isDiscoverable = false

    @Parameter(title: "Search", description: "Search text, e.g. “tag:idea” or “modified:last 7 days”.")
    var criteria: StringSearchCriteria

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.requestSearch(criteria.term)
        return .result()
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
struct SaveResultsToVaultIntent: NoteSearchIntent {
    static let title: LocalizedStringResource = "Save Search Results to Vault"
    static let description = IntentDescription(
        "Saves the results of a search as a note in the export folder of the vault.",
        categoryName: "Export"
    )

    @Parameter(title: "Search Text", description: "Words to look for. The syntax of the search field works too, e.g. “modified:last 7 days”.")
    var text: String?

    @Parameter(title: "Search In", default: .titleAndText)
    var scope: SearchTextScope

    @Parameter(title: "Tags", description: "Tags from the note properties (frontmatter). Also finds nested tags.")
    var tags: [String]?

    @Parameter(title: "Tags in Text", description: "#tags or [[links]] written in the note text.")
    var inlineTags: [String]?

    @Parameter(title: "Property", description: "Name of a frontmatter property, e.g. “status”.")
    var propertyName: String?

    @Parameter(title: "Property Value", description: "The property must contain this value, e.g. “active”.")
    var propertyValue: String?

    @Parameter(title: "Combine", default: .all)
    var match: CriteriaMatch

    static var parameterSummary: some ParameterSummary {
        Summary("Save notes with \(\.$text) to the vault") {
            \.$scope
            \.$tags
            \.$inlineTags
            \.$propertyName
            \.$propertyValue
            \.$match
        }
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> & ProvidesDialog {
        try await model.requireVault()
        let snapshot = await model.snapshot(for: try searchQuery())
        guard !snapshot.files.isEmpty else { throw VaultSearchIntentError.noResults }
        let url = try await model.exporter.writeResultsToVault(snapshot)
        return .result(value: IntentFile(fileURL: url), dialog: "Saved \(snapshot.files.count) notes to “\(url.deletingPathExtension().lastPathComponent)”.")
    }
}

/// Exports the results of a search, e.g. as PDF, and hands the file on to the next action.
struct ExportResultsIntent: NoteSearchIntent {
    static let title: LocalizedStringResource = "Export Search Results"
    static let description = IntentDescription(
        "Exports the results of a search as a document. Pass the file on to “Save File” or “Share”.",
        categoryName: "Export"
    )

    @Parameter(title: "Format", default: .pdf)
    var format: ExportFormat

    @Parameter(title: "Search Text", description: "Words to look for. The syntax of the search field works too, e.g. “modified:last 7 days”.")
    var text: String?

    @Parameter(title: "Search In", default: .titleAndText)
    var scope: SearchTextScope

    @Parameter(title: "Tags", description: "Tags from the note properties (frontmatter). Also finds nested tags.")
    var tags: [String]?

    @Parameter(title: "Tags in Text", description: "#tags or [[links]] written in the note text.")
    var inlineTags: [String]?

    @Parameter(title: "Property", description: "Name of a frontmatter property, e.g. “status”.")
    var propertyName: String?

    @Parameter(title: "Property Value", description: "The property must contain this value, e.g. “active”.")
    var propertyValue: String?

    @Parameter(title: "Combine", default: .all)
    var match: CriteriaMatch

    static var parameterSummary: some ParameterSummary {
        Summary("Export notes with \(\.$text) as \(\.$format)") {
            \.$scope
            \.$tags
            \.$inlineTags
            \.$propertyName
            \.$propertyValue
            \.$match
        }
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> {
        try await model.requireVault()
        try await model.requireFormat(format)
        let query = try searchQuery()
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
    case incompleteProperty
    case invalidProperty

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noVault: "Choose a vault in VaultSearch first."
        case .noteNotFound: "The note is no longer in the vault."
        case .noResults: "The search found no notes."
        case .pandocRequired: "This format requires Pandoc. Install it with “brew install pandoc”."
        case .incompleteProperty: "Enter both a property and a value, or leave both empty."
        case .invalidProperty: "A property name may only contain letters, digits, “_” and “-”."
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
