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
    }
}

/// Finds notes by id, by text and for suggestions. Waits for the index when the app was just started.
struct NoteEntityQuery: EntityStringQuery, IndexedEntityQuery {
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
