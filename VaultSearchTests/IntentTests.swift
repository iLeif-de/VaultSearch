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

@Suite("Siri and Shortcuts: Filter Notes")
struct NoteFilterTests {
    let notes = [
        makeNote("Budget 2026", folder: "Projects/2026", content: "Numbers", tags: ["finance"],
                 frontmatter: ["status": "active"], created: "2026-11-17", modified: "2026-11-18"),
        makeNote("Plan", folder: "Projects", content: "The budget is tight #todo", tags: ["project/idea"],
                 frontmatter: ["status": "done", "people": ["Anna", "Ben"]], created: "2026-10-01", modified: "2026-11-10"),
        makeNote("Ideas", content: "Nothing here", tags: ["idea"], created: "2025-05-01", modified: "2025-05-02"),
    ]

    func titles(_ filter: NoteFilter) throws -> [String] {
        var filter = filter
        filter.now = TestClock.now
        filter.calendar = TestClock.calendar
        let predicate = try filter.predicate()
        return notes.filter(predicate.matches).map(\.title)
    }

    @Test func text() throws {
        #expect(try titles(.init(criterion: .text, text: "budget")) == ["Budget 2026", "Plan"])
        #expect(try titles(.init(criterion: .text, text: "budget", scope: .title)) == ["Budget 2026"])
        #expect(try titles(.init(criterion: .text, text: "budget", scope: .text)) == ["Plan"])
    }

    @Test func tags() throws {
        #expect(try titles(.init(criterion: .tag, tag: "idea")) == ["Plan", "Ideas"])
        #expect(try titles(.init(criterion: .inlineTag, inlineTag: "todo")) == ["Plan"])
    }

    @Test func propertyWithAndWithoutValue() throws {
        #expect(try titles(.init(criterion: .property, propertyName: "Status", propertyValue: "active")) == ["Budget 2026"])
        #expect(try titles(.init(criterion: .property, propertyName: "status")) == ["Budget 2026", "Plan"])
        #expect(try titles(.init(criterion: .property, propertyName: "people", propertyValue: "Ben")) == ["Plan"])
    }

    @Test func folderIncludesSubfolders() throws {
        #expect(try titles(.init(criterion: .folder, folder: "Projects")) == ["Budget 2026", "Plan"])
        #expect(try titles(.init(criterion: .folder, folder: "Projects/2026/")) == ["Budget 2026"])
    }

    @Test func datePeriods() throws {
        #expect(try titles(.init(criterion: .modified, period: .last7Days)) == ["Budget 2026"])
        #expect(try titles(.init(criterion: .created, period: .thisYear)) == ["Budget 2026", "Plan"])
        #expect(try titles(.init(criterion: .created, period: .since, date: TestClock.date("2026-10-01"))) == ["Budget 2026", "Plan"])
        #expect(try titles(.init(criterion: .created, period: .before, date: TestClock.date("2026-10-01"))) == ["Ideas"])
        #expect(try titles(.init(criterion: .modified, period: .onDay, date: TestClock.date("2026-11-10"))) == ["Plan"])
        // Reversed dates are swapped.
        #expect(try titles(.init(criterion: .modified, period: .between,
                                 date: TestClock.date("2026-11-30"), endDate: TestClock.date("2026-11-01"))) == ["Budget 2026", "Plan"])
    }

    @Test func missingValuesAreReported() {
        #expect(throws: VaultSearchIntentError.self) { try NoteFilter(criterion: .tag, tag: " ").predicate() }
        #expect(throws: VaultSearchIntentError.self) { try NoteFilter(criterion: .property).predicate() }
        #expect(throws: VaultSearchIntentError.self) { try NoteFilter(criterion: .created, period: .between, date: .now).predicate() }
    }

    @Test func scopedTextKeepsOperators() {
        #expect(NoteFilter.scoped("a OR \"b c\"", .title) == "intitle:a OR intitle:\"b c\"")
        #expect(NoteFilter.scoped("a b", .titleAndText) == "a b")
    }
}

@Suite("Siri and Shortcuts: Find Notes filters")
struct NotePredicateTests {
    let notes = [
        makeNote("Budget", folder: "Projects/2026", tags: ["project/finance"], frontmatter: ["status": "active"]),
        makeNote("Plan", folder: "Projects", frontmatter: ["status": "done"]),
    ]

    func titles(_ predicate: NotePredicate) -> [String] { notes.filter(predicate.matches).map(\.title) }

    @Test func tagAtAnyLevel() {
        #expect(titles(.tag("finance")) == ["Budget"])
    }

    @Test func propertyAsKeyValueOrAnyValue() {
        #expect(titles(.property("status: done")) == ["Plan"])
        #expect(titles(.property("active")) == ["Budget"])
    }

    @Test func folderExactOrWithSubfolders() {
        #expect(titles(.folder("Projects", includingSubfolders: false)) == ["Plan"])
        #expect(titles(.folder("projects", includingSubfolders: true)) == ["Budget", "Plan"])
    }

    @Test func entityListsPropertiesAndFolder() {
        let entity = NoteEntity(notes[0])
        #expect(entity.properties == ["status: active"])
        #expect(entity.folderPath == "Projects/2026")
    }
}
