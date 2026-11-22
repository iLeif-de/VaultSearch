import Foundation
import Testing
@testable import VaultSearch

// The export intents are not tested here: ExportService reads AppSettings,
// which writes to the real user defaults of the app.

@Suite("Siri and Shortcuts: notes")
struct NoteEntityTests {
    @Test func mapsNoteFields() {
        let note = makeNote("Budget", folder: "Projects/2026", content: "# Budget\nSee [[Plan]].", tags: ["finance"], vault: "Work")
        let entity = NoteEntity(note)
        #expect(entity.id == note.path.path)
        #expect(entity.name == "Budget")
        #expect(entity.tags == ["finance"])
        #expect(entity.isPinned == false)
        #expect(entity.attachments.isEmpty)
        #expect(entity.content.map { String($0.characters) } == note.plain)
    }

    @Test func folderChainEndsAtVaultRoot() throws {
        let entity = NoteEntity(makeNote("Budget", folder: "Projects/2026", vault: "Work"))
        let folder = try #require(entity.folder)
        #expect(folder.id == "Work/Projects/2026")
        #expect(folder.name == "2026")
        #expect(folder.account?.name == "Work")
        let parent = try #require(folder.parentFolder)
        #expect(parent.path == "Projects")
        #expect(parent.parentFolder == nil)
    }

    @Test func noteAtRootHasNoFolder() {
        #expect(NoteEntity(makeNote("Inbox")).folder == nil)
    }
}

@Suite("Siri and Shortcuts: support")
struct IntentSupportTests {
    @Test @MainActor func searchWaitsForIndex() async throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        try vault.write("Ideas/Garden.md", "---\ntags: [idea]\n---\nPlant tomatoes")
        try vault.write("Shopping.md", "Milk")

        let search = SearchService()
        search.configure(vaultURL: vault.url, excludedFolders: [])
        // Asked right away, as Siri does after starting the app.
        let found = await search.indexedResults(for: "tag:idea")
        #expect(found.map(\.title) == ["Garden"])
        #expect(!search.isIndexing)
    }

    @Test func temporaryOutputIsFreshEachTime() throws {
        let first = try ExportService.temporaryOutput(name: "Note", format: .pdf)
        let second = try ExportService.temporaryOutput(name: "Note", format: .pdf)
        #expect(first.lastPathComponent == "Note.pdf")
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path))
        try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
    }

    @Test func everyFormatHasAName() {
        for format in ExportFormat.allCases {
            #expect(ExportFormat.caseDisplayRepresentations[format] != nil)
        }
    }
}
