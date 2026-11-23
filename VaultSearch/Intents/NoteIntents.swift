import AppIntents
import AppKit

// Actions for Siri, Shortcuts and Spotlight. They only read the vault;
// the one exception is "Save Notes to Vault", which adds a new note, as the menu command does.
//
// - “Find Notes” is built by Shortcuts from `NoteEntityQuery` (filter rows, All/Any, sorting).
// - “Filter Notes” takes one criterion, chosen from menus filled from the vault.
//   Chaining several Filter actions combines criteria with AND.
// - Save, Export and Open take the notes those actions return.

// MARK: - Filter Notes

/// What “Filter Notes” looks at; the rest of the sentence follows from it.
enum FilterCriterion: String, AppEnum {
    case text, tag, inlineTag, property, folder, created, modified

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Criterion"
    static let caseDisplayRepresentations: [FilterCriterion: DisplayRepresentation] = [
        .text: "Text",
        .tag: "Tag",
        .inlineTag: "Tag in Text",
        .property: "Property",
        .folder: "Folder",
        .created: "Creation Date",
        .modified: "Modification Date",
    ]
}

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

/// Periods for the date criteria; the last four need a date.
enum FilterPeriod: String, AppEnum {
    case today, yesterday, thisWeek, lastWeek, last7Days, thisMonth, lastMonth, last30Days, thisYear, lastYear
    case onDay, since, before, between

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [FilterPeriod: DisplayRepresentation] = [
        .today: "Today",
        .yesterday: "Yesterday",
        .thisWeek: "This Week",
        .lastWeek: "Last Week",
        .last7Days: "In the Last 7 Days",
        .thisMonth: "This Month",
        .lastMonth: "Last Month",
        .last30Days: "In the Last 30 Days",
        .thisYear: "This Year",
        .lastYear: "Last Year",
        .onDay: "On",
        .since: "Since",
        .before: "Before",
        .between: "Between",
    ]

    var needsDate: Bool { [.onDay, .since, .before, .between].contains(self) }
}

/// Filters notes by one criterion. Without input notes it searches the whole vault.
struct FilterNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Filter Notes"
    static let description = IntentDescription(
        "Keeps the notes that match one criterion: text, tag, property, folder or date. Choose the values from menus filled from your vault. Without notes from a previous action, the whole vault is searched. Add another “Filter Notes” after it to combine criteria.",
        categoryName: "Search"
    )

    @Parameter(title: "Notes", description: "Notes from a previous action. Leave empty to search the whole vault.")
    var notes: [NoteEntity]?

    @Parameter(title: "Criterion", default: .tag)
    var criterion: FilterCriterion

    @Parameter(title: "Search Text", description: "The syntax of the search field works too.")
    var text: String?

    @Parameter(title: "Search In", default: .titleAndText)
    var scope: SearchTextScope

    @Parameter(title: "Tag", optionsProvider: TagOptions())
    var tag: String?

    @Parameter(title: "Tag in Text", optionsProvider: TagOptions())
    var inlineTag: String?

    @Parameter(title: "Property", optionsProvider: PropertyNameOptions())
    var propertyName: String?

    @Parameter(title: "Value", description: "Leave empty to find every note that has the property.", optionsProvider: PropertyValueOptions())
    var propertyValue: String?

    @Parameter(title: "Folder", description: "Includes its subfolders.", optionsProvider: FolderOptions())
    var folder: String?

    @Parameter(title: "Period", default: .last7Days)
    var period: FilterPeriod

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "End Date")
    var endDate: Date?

    static var parameterSummary: some ParameterSummary {
        Switch(\.$criterion) {
            Case(.text) {
                Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$text) in \(\.$scope)")
            }
            Case(.tag) {
                Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$tag)")
            }
            Case(.inlineTag) {
                Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$inlineTag)")
            }
            Case(.property) {
                Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$propertyName) with \(\.$propertyValue)")
            }
            Case(.folder) {
                Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$folder)")
            }
            DefaultCase {
                Switch(\.$period) {
                    Case(.between) {
                        Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$period) \(\.$date) and \(\.$endDate)")
                    }
                    Case(.onDay) {
                        Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$period) \(\.$date)")
                    }
                    Case(.since) {
                        Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$period) \(\.$date)")
                    }
                    Case(.before) {
                        Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$period) \(\.$date)")
                    }
                    DefaultCase {
                        Summary("Filter \(\.$notes) by \(\.$criterion) \(\.$period)")
                    }
                }
            }
        }
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<[NoteEntity]> {
        try await model.requireVault()
        let predicate = try NoteFilter(
            criterion: criterion, text: text, scope: scope, tag: tag, inlineTag: inlineTag,
            propertyName: propertyName, propertyValue: propertyValue, folder: folder,
            period: period, date: date, endDate: endDate
        ).predicate()

        await model.search.waitUntilIndexed()
        let files = await MainActor.run { model.search.files }
        let candidates: [MarkdownFile]
        if let notes, !notes.isEmpty {
            // Keep the order of the previous action, e.g. its sorting.
            let byPath = Dictionary(files.map { ($0.path.path, $0) }, uniquingKeysWith: { first, _ in first })
            candidates = notes.compactMap { byPath[$0.id] }
        } else {
            candidates = files.sorted { $0.modifiedDate > $1.modifiedDate }
        }
        return .result(value: candidates.filter(predicate.matches).map(NoteEntity.init))
    }
}

/// Turns the fields of “Filter Notes” into a test on a note; kept apart from the intent so it can be tested.
struct NoteFilter {
    var criterion: FilterCriterion
    var text: String? = nil
    var scope: SearchTextScope = .titleAndText
    var tag: String? = nil
    var inlineTag: String? = nil
    var propertyName: String? = nil
    var propertyValue: String? = nil
    var folder: String? = nil
    var period: FilterPeriod = .last7Days
    var date: Date? = nil
    var endDate: Date? = nil
    var now: Date = .now
    var calendar: Calendar = .current

    func predicate() throws -> NotePredicate {
        switch criterion {
        case .text:
            guard let text = Self.trimmed(text) else { throw VaultSearchIntentError.missingValue }
            return query(Self.scoped(text, scope))
        case .tag:
            guard let tag = Self.trimmed(tag) else { throw VaultSearchIntentError.missingValue }
            return NotePredicate.tag(tag)
        case .inlineTag:
            guard let tag = Self.trimmed(inlineTag) else { throw VaultSearchIntentError.missingValue }
            return query("contenttag:" + SearchSuggestion.quoted(tag))
        case .property:
            guard let name = Self.trimmed(propertyName) else { throw VaultSearchIntentError.missingValue }
            return NotePredicate.property(name, value: Self.trimmed(propertyValue) ?? "")
        case .folder:
            guard let folder = Self.trimmed(folder) else { throw VaultSearchIntentError.missingValue }
            return NotePredicate.folder(folder, includingSubfolders: true)
        case .created, .modified:
            let key = criterion == .created ? "created:" : "modified:"
            return query(try dateTerms().map { key + $0 }.joined(separator: " "))
        }
    }

    /// Values in the date syntax of the search field (always English, so the UI language does not matter).
    func dateTerms() throws -> [String] {
        func day(_ date: Date?) throws -> String {
            guard let date else { throw VaultSearchIntentError.missingValue }
            var calendar = self.calendar
            calendar.timeZone = .current
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        switch period {
        case .today: return ["today"]
        case .yesterday: return ["yesterday"]
        case .thisWeek: return ["this week"]
        case .lastWeek: return ["last week"]
        case .last7Days: return ["last 7 days"]
        case .thisMonth: return ["this month"]
        case .lastMonth: return ["last month"]
        case .last30Days: return ["last 30 days"]
        case .thisYear: return ["this year"]
        case .lastYear: return ["last year"]
        case .onDay: return [try day(date)]
        case .since: return [">=" + (try day(date))]
        case .before: return ["<" + (try day(date))]
        case .between:
            let (from, to) = (try day(date), try day(endDate))
            return from <= to ? [">=" + from, "<=" + to] : [">=" + to, "<=" + from]
        }
    }

    private func query(_ text: String) -> NotePredicate {
        let query = SearchQuery(text, now: now, calendar: calendar)
        return NotePredicate { query.matches($0) }
    }

    /// `intitle:` / `intext:` before every word; operators stay as they are.
    static func scoped(_ text: String, _ scope: SearchTextScope) -> String {
        guard scope != .titleAndText else { return text }
        let prefix = scope == .title ? "intitle:" : "intext:"
        return SearchQuery.tokenize(text).map { token in
            SearchQuery.orOperators.contains(token) || SearchQuery.andOperators.contains(token)
                ? token : prefix + SearchSuggestion.quoted(token)
        }.joined(separator: " ")
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: Menus filled from the vault

struct TagOptions: DynamicOptionsProvider {
    @Dependency private var model: AppModel

    func results() async throws -> [String] {
        await model.search.waitUntilIndexed()
        return await MainActor.run { model.search.knownTags.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    }
}

struct PropertyNameOptions: DynamicOptionsProvider {
    @Dependency private var model: AppModel

    func results() async throws -> [String] {
        await model.search.waitUntilIndexed()
        return await MainActor.run {
            var names: [String: String] = [:]  // lowercased → first spelling
            for file in model.search.files {
                for key in file.frontmatter.keys where key.lowercased() != "tags" {
                    names[key.lowercased()] = names[key.lowercased()] ?? key
                }
            }
            return names.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}

/// Values of the property chosen in the same action.
struct PropertyValueOptions: DynamicOptionsProvider {
    @Dependency private var model: AppModel
    @IntentParameterDependency<FilterNotesIntent>(\.$propertyName)
    private var filter

    func results() async throws -> [String] {
        guard let name = filter?.propertyName, !name.isEmpty else { return [] }
        await model.search.waitUntilIndexed()
        return await MainActor.run {
            var values = Set<String>()
            for file in model.search.files {
                guard let entry = file.frontmatter.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
                for value in NoteValues.values(entry.value) where !value.isEmpty { values.insert(value) }
            }
            return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(300).map { $0 }
        }
    }
}

struct FolderOptions: DynamicOptionsProvider {
    @Dependency private var model: AppModel

    func results() async throws -> [String] {
        await model.search.waitUntilIndexed()
        return await MainActor.run {
            var folders = Set<String>()
            for file in model.search.files where !file.folder.isEmpty {
                // Parent folders too, so “Projects” also offers notes in “Projects/2026”.
                var path = file.folder
                while !path.isEmpty {
                    folders.insert(path)
                    path = (path as NSString).deletingLastPathComponent
                }
            }
            return folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
}

// MARK: - Show in VaultSearch

/// Shows the results of a search in the VaultSearch window.
struct ShowInVaultSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Show in VaultSearch"
    static let description = IntentDescription(
        "Opens VaultSearch and shows the results of a search in the window.",
        categoryName: "Search"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Search Text", description: "The syntax of the search field works too, e.g. “tag:idea modified:last 7 days”.")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$text) in VaultSearch")
    }

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.requestSearch(text)
        return .result()
    }
}

/// Siri's “search in VaultSearch”. Not listed in Shortcuts, where “Show in VaultSearch” does the same.
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

// MARK: - Save and export

/// Saves a list of notes as a Markdown note in the export folder of the vault.
struct SaveResultsToVaultIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Note List to Vault"
    static let description = IntentDescription(
        "Saves the notes, e.g. from “Find Notes” or “Filter Notes”, as a list note in the export folder of the vault.",
        categoryName: "Export"
    )

    @Parameter(title: "Notes")
    var notes: [NoteEntity]

    @Parameter(title: "Title", description: "Heading of the list. Optional.")
    var listTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$notes) as list \(\.$listTitle) to the vault")
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> & ProvidesDialog {
        try await model.requireVault()
        let snapshot = try await model.snapshot(of: notes, title: listTitle)
        let url = try await model.exporter.writeResultsToVault(snapshot)
        return .result(value: IntentFile(fileURL: url), dialog: "Saved \(snapshot.files.count) notes to “\(url.deletingPathExtension().lastPathComponent)”.")
    }
}

/// Exports a list of notes, e.g. as PDF, and hands the file on to the next action.
struct ExportResultsIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Note List"
    static let description = IntentDescription(
        "Exports the notes, e.g. from “Find Notes” or “Filter Notes”, as one list document. Pass the file on to “Save File” or “Share”.",
        categoryName: "Export"
    )

    @Parameter(title: "Notes")
    var notes: [NoteEntity]

    @Parameter(title: "Format", default: .pdf)
    var format: ExportFormat

    @Parameter(title: "Title", description: "Heading of the list. Optional.")
    var listTitle: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$notes) as \(\.$format) list \(\.$listTitle)")
    }

    @Dependency private var model: AppModel

    func perform() async throws -> some ReturnsValue<IntentFile> {
        try await model.requireVault()
        try await model.requireFormat(format)
        let snapshot = try await model.snapshot(of: notes, title: listTitle)
        let output = try ExportService.temporaryOutput(name: snapshot.fileName, format: format)
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
    case missingValue

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noVault: "Choose a vault in VaultSearch first."
        case .noteNotFound: "The note is no longer in the vault."
        case .noResults: "There are no notes to save or export."
        case .pandocRequired: "This format requires Pandoc. Install it with “brew install pandoc”."
        case .missingValue: "Choose a value for the criterion."
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

    /// The notes handed over by a shortcut, in their order, as a list to save or export.
    func snapshot(of notes: [NoteEntity], title: String?) async throws -> ResultsSnapshot {
        await search.waitUntilIndexed()
        let byPath = Dictionary(search.files.map { ($0.path.path, $0) }, uniquingKeysWith: { first, _ in first })
        return try snapshot(files: notes.compactMap { byPath[$0.id] }, title: title)
    }

    /// A list of notes without a search, to save or export (Shortcuts, AppleScript).
    func snapshot(files: [MarkdownFile], title: String?) throws -> ResultsSnapshot {
        guard !files.isEmpty else { throw VaultSearchIntentError.noResults }
        let title = NoteFilter.trimmed(title) ?? String(localized: "Notes from Shortcuts")
        return ResultsSnapshot(query: "", files: files, highlightTerms: [], title: title)
    }
}
