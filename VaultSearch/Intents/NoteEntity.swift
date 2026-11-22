import AppIntents
import CoreSpotlight
import Foundation

/// A note of the vault as Siri, Shortcuts and Spotlight see it.
///
/// It follows Apple's notes schema, so Siri understands requests such as
/// “show my notes about the budget meeting” without fixed phrases.
/// VaultSearch only reads the vault, so the schema's create/update intents are not offered.
@AppEntity(schema: .notes.note)
struct NoteEntity: IndexedEntity {
    static let defaultQuery = NoteEntityQuery()

    /// The absolute file path; stable across re-indexing, like `MarkdownFile.id`.
    let id: String

    var name: String
    var content: AttributedString?
    var creationDate: Date?
    var modificationDate: Date?
    var folder: NoteFolderEntity?
    /// Obsidian has no pinned notes; always false.
    var isPinned: Bool
    /// Attachments are not read; always empty.
    var attachments: [IntentFile]

    @Property(title: "Tags")
    var tags: [String]

    /// Frontmatter properties other than tags, as “key: value”.
    @Property(title: "Properties")
    var properties: [String]

    /// Folder inside the vault, empty for notes at the root; for filtering in Shortcuts.
    @Property(title: "Folder Path")
    var folderPath: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: folder.map { "\($0.path)" },
            image: .init(systemName: "doc.text")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = name
        attributes.textContent = content.map { String($0.characters) }
        attributes.contentCreationDate = creationDate
        attributes.contentModificationDate = modificationDate
        attributes.keywords = tags
        attributes.containerDisplayName = folder?.path
        return attributes
    }

    init(_ file: MarkdownFile) {
        id = file.path.path
        name = file.title
        // Without Obsidian syntax, so Siri and Spotlight see readable text.
        content = AttributedString(file.plain)
        creationDate = file.createdDate
        modificationDate = file.modifiedDate
        folder = file.folder.isEmpty ? nil : NoteFolderEntity(vault: file.vaultName, path: file.folder)
        isPinned = false
        attachments = []
        tags = file.tags
        properties = file.frontmatter
            .filter { $0.key.lowercased() != "tags" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(NoteValues.text($0.value))" }
        folderPath = file.folder
    }
}

/// Finds notes by id, by text, for suggestions and with the filter of the “Find Notes” action
/// that Shortcuts builds from `properties`. Waits for the index when the app was just started.
struct NoteEntityQuery: EntityStringQuery, EntityPropertyQuery, IndexedEntityQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        await model.search.waitUntilIndexed()
        return await MainActor.run {
            identifiers.compactMap { model.search.file(with: URL(fileURLWithPath: $0)) }.map(NoteEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [NoteEntity] {
        await model.search.indexedResults(for: string).prefix(50).map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        await model.search.indexedResults(for: "").prefix(20).map(NoteEntity.init)
    }

    // MARK: Find Notes (filter rows in Shortcuts)

    static let findIntentDescription: IntentDescription? = IntentDescription(
        "Finds notes of the vault with filters for name, text, tags, properties, folder and dates.",
        categoryName: "Search"
    )

    static let properties = QueryProperties {
        Property(\NoteEntity.$name) {
            ContainsComparator { value in NotePredicate { $0.title.localizedStandardContains(value) } }
            EqualToComparator { value in NotePredicate { $0.title.localizedCaseInsensitiveCompare(value) == .orderedSame } }
            HasPrefixComparator { value in NotePredicate { $0.title.lowercased().hasPrefix(value.lowercased()) } }
        }
        Property(\NoteEntity.$content) {
            ContainsComparator { (value: AttributedString) in let text = String(value.characters); return NotePredicate { $0.content.localizedStandardContains(text) } }
        }
        Property(\NoteEntity.$tags) {
            ContainsComparator { value in NotePredicate.tag(value) }
        }
        Property(\NoteEntity.$properties) {
            ContainsComparator { value in NotePredicate.property(value) }
        }
        Property(\NoteEntity.$folderPath) {
            EqualToComparator { value in NotePredicate.folder(value, includingSubfolders: false) }
            HasPrefixComparator { value in NotePredicate.folder(value, includingSubfolders: true) }
            ContainsComparator { value in NotePredicate { $0.folder.localizedStandardContains(value) } }
        }
        Property(\NoteEntity.$creationDate) {
            EqualToComparator { date in NotePredicate.day(\.createdDate) { day in date.map { day == Self.day($0) } ?? false } }
            LessThanComparator { date in NotePredicate.day(\.createdDate) { $0 < Self.day(date) } }
            GreaterThanComparator { date in NotePredicate.day(\.createdDate) { $0 > Self.day(date) } }
            IsBetweenComparator { from, to in NotePredicate.day(\.createdDate) { (Self.day(from)...Self.day(to)).contains($0) } }
        }
        Property(\NoteEntity.$modificationDate) {
            EqualToComparator { date in NotePredicate.day(\.modifiedDate) { day in date.map { day == Self.day($0) } ?? false } }
            LessThanComparator { date in NotePredicate.day(\.modifiedDate) { $0 < Self.day(date) } }
            GreaterThanComparator { date in NotePredicate.day(\.modifiedDate) { $0 > Self.day(date) } }
            IsBetweenComparator { from, to in NotePredicate.day(\.modifiedDate) { (Self.day(from)...Self.day(to)).contains($0) } }
        }
    }

    static let sortingOptions = SortingOptions {
        SortableBy(\NoteEntity.$name)
        SortableBy(\NoteEntity.$creationDate)
        SortableBy(\NoteEntity.$modificationDate)
    }

    private static func day(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    func entities(
        matching comparators: [NotePredicate], mode: ComparatorMode,
        sortedBy: [EntityQuerySort<NoteEntity>], limit: Int?
    ) async throws -> [NoteEntity] {
        await model.search.waitUntilIndexed()
        let files = await MainActor.run { model.search.files }
        var found = files.filter { file in
            switch mode {
            case .and: comparators.allSatisfy { $0.matches(file) }
            case .or: comparators.isEmpty || comparators.contains { $0.matches(file) }
            @unknown default: comparators.allSatisfy { $0.matches(file) }
            }
        }
        found.sort { lhs, rhs in
            for sort in sortedBy {
                let order: ComparisonResult
                switch sort.by {
                case \NoteEntity.$name: order = lhs.title.localizedStandardCompare(rhs.title)
                case \NoteEntity.$creationDate: order = Self.compare(lhs.createdDate, rhs.createdDate)
                default: order = Self.compare(lhs.modifiedDate, rhs.modifiedDate)
                }
                if order != .orderedSame {
                    return sort.order == .ascending ? order == .orderedAscending : order == .orderedDescending
                }
            }
            return lhs.modifiedDate > rhs.modifiedDate
        }
        return found.prefix(limit ?? found.count).map(NoteEntity.init)
    }

    private static func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    }

    // MARK: Spotlight

    func reindexEntities(for identifiers: [NoteEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        let notes = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(notes)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        await model.search.waitUntilIndexed()
        let notes = await MainActor.run { model.search.files.map(NoteEntity.init) }
        try await CSSearchableIndex.default().deleteAppEntities(ofType: NoteEntity.self)
        try await CSSearchableIndex.default().indexAppEntities(notes)
    }
}

/// One filter row of “Find Notes” (or one criterion of “Filter Notes”), as a test on a note.
struct NotePredicate {
    let matches: (MarkdownFile) -> Bool

    init(_ matches: @escaping (MarkdownFile) -> Bool) {
        self.matches = matches
    }

    /// Frontmatter tag at any level, like `tag:`.
    static func tag(_ tag: String) -> NotePredicate {
        NotePredicate { file in file.tags.contains { SearchQuery.tagScore(tag: $0, query: tag) > 0 } }
    }

    /// `key: value` checks one property, like `key:value`; anything else looks in all property values.
    static func property(_ text: String) -> NotePredicate {
        let parts = text.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty {
            return property(parts[0], value: parts[1])
        }
        let value = text.trimmingCharacters(in: .whitespaces)
        return NotePredicate { file in
            file.frontmatter.contains { $0.key.lowercased() != "tags" && NoteValues.text($0.value).localizedStandardContains(value) }
        }
    }

    /// The property `key` exists and contains `value`; an empty value only requires the property.
    static func property(_ key: String, value: String) -> NotePredicate {
        NotePredicate { file in
            guard let entry = file.frontmatter.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
                return false
            }
            return value.isEmpty || NoteValues.text(entry.value).localizedStandardContains(value)
        }
    }

    static func folder(_ folder: String, includingSubfolders: Bool) -> NotePredicate {
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
        return NotePredicate { file in
            file.folder.caseInsensitiveCompare(folder) == .orderedSame
                || (includingSubfolders && (folder.isEmpty || file.folder.lowercased().hasPrefix(folder.lowercased() + "/")))
        }
    }

    /// Compares the start of the day of a note date.
    static func day(_ keyPath: KeyPath<MarkdownFile, Date>, _ test: @escaping (Date) -> Bool) -> NotePredicate {
        NotePredicate { file in test(Calendar.current.startOfDay(for: file[keyPath: keyPath])) }
    }
}

/// Frontmatter values as text, and the values a vault uses, for menus in Shortcuts.
enum NoteValues {
    static func text(_ value: Any) -> String {
        (value as? [String])?.joined(separator: ", ") ?? String(describing: value)
    }

    /// Single values of a property; list properties contribute each item.
    static func values(_ value: Any) -> [String] {
        (value as? [String]) ?? [String(describing: value)]
    }
}

/// A folder inside the vault, as part of a note.
@AppEntity(schema: .notes.folder)
struct NoteFolderEntity {
    static let defaultQuery = NoteFolderQuery()

    /// `Vault/relative/path`, so folders of different vaults stay apart.
    let id: String

    var name: String
    var account: VaultEntity?
    var parentFolder: NoteFolderEntity?

    /// Path relative to the vault root, e.g. `Projects/2026`.
    @Property(title: "Path")
    var path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(path)", image: .init(systemName: "folder"))
    }

    init(vault: String, path: String) {
        id = "\(vault)/\(path)"
        self.path = path
        name = (path as NSString).lastPathComponent
        account = VaultEntity(name: vault)
        let parent = (path as NSString).deletingLastPathComponent
        parentFolder = parent.isEmpty ? nil : NoteFolderEntity(vault: vault, path: parent)
    }
}

struct NoteFolderQuery: EntityQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [NoteFolderEntity.ID]) async throws -> [NoteFolderEntity] {
        identifiers.compactMap { id in
            guard let slash = id.firstIndex(of: "/") else { return nil }
            return NoteFolderEntity(vault: String(id[..<slash]), path: String(id[id.index(after: slash)...]))
        }
    }

    func suggestedEntities() async throws -> [NoteFolderEntity] {
        await model.search.waitUntilIndexed()
        return await MainActor.run {
            let files = model.search.files
            guard let vault = files.first?.vaultName else { return [] }
            return Set(files.map(\.folder)).filter { !$0.isEmpty }.sorted().map { NoteFolderEntity(vault: vault, path: $0) }
        }
    }
}

/// The vault; the notes schema calls it an account.
@AppEntity(schema: .notes.account)
struct VaultEntity {
    static let defaultQuery = VaultQuery()

    var id: String { name }
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "archivebox"))
    }

    init(name: String) {
        self.name = name
    }
}

struct VaultQuery: EntityQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [VaultEntity.ID]) async throws -> [VaultEntity] {
        identifiers.map(VaultEntity.init)
    }

    func suggestedEntities() async throws -> [VaultEntity] {
        await MainActor.run { model.settings.vaultPath.map { [VaultEntity(name: $0.lastPathComponent)] } ?? [] }
    }
}
