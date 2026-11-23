import Foundation
import Testing
@testable import VaultSearch

@Suite("Notes: links and excerpts")
struct MarkdownFileTests {
    @Test func obsidianURIEncodesVaultAndPath() throws {
        let note = makeNote("Plan & Budget", folder: "Projects/2026", vault: "My Vault")
        let uri = try #require(note.obsidianURI).absoluteString
        #expect(uri == "obsidian://open?vault=My%20Vault&file=Projects%2F2026%2FPlan%20%26%20Budget")
    }

    @Test func folderAndDateKeys() {
        #expect(makeNote("A", folder: "x/y").folder == "x/y")
        #expect(makeNote("A").folder.isEmpty)
        #expect(makeNote("A", frontmatter: ["erstellt": "2024-04-27"]).dateKeys == ["erstellt"])
    }

    @Test func plainTextRemovesObsidianSyntax() {
        let note = makeNote("A", content: """
        %%hidden%%
        ![[image.png]]
        See [[Target|the target]] and [[Other]] and [a link](https://x.y).
        > [!note] Callout
        - [ ] task
        | a | b |
        |---|---|
        """)
        let plain = note.plain
        #expect(!plain.contains("hidden"))
        #expect(!plain.contains("image.png"))
        #expect(plain.contains("See the target and Other and a link."))
        #expect(!plain.contains("[!note]"))
        #expect(!plain.contains("[ ]"))
        #expect(!plain.contains("---"))
    }

    @Test func snippetIsCentredOnTheMatch() {
        let filler = String(repeating: "word ", count: 60)
        let note = makeNote("A", content: filler + "the **Battery** level" + filler)
        let snippet = note.snippet(around: ["battery"])
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("the Battery level"))
    }

    @Test func snippetWithoutMatchShowsTheStart() {
        let note = makeNote("A", content: "# Heading\nFirst line")
        #expect(note.snippet(around: ["missing"]) == "Heading First line")
    }
}

@Suite("Highlighter")
struct HighlighterTests {
    @Test func rangesAreSortedAndDoNotOverlap() {
        let text = AttributedString("Idea, ideas and IDEA")
        let ranges = Highlighter.ranges(in: text, terms: ["idea", "ideas"])
        let found = ranges.map { String(text[$0].characters) }
        #expect(found == ["Idea", "idea", "IDEA"])
    }

    @Test func diacriticInsensitive() {
        let text = AttributedString("Café and cafe")
        #expect(Highlighter.ranges(in: text, terms: ["cafe"]).count == 2)
    }
}

@Suite("Notes: frontmatter dates and properties")
struct FrontmatterDisplayTests {
    @Test func frontmatterDatesWin() {
        let note = makeNote("A", frontmatter: ["erstellt": "2024-04-27", "modified": "2025-01-02T10:30"],
                            created: "2026-01-01", modified: "2026-01-01")
        let calendar = Calendar.current
        #expect(calendar.dateComponents([.year, .month, .day], from: note.createdDate) == DateComponents(year: 2024, month: 4, day: 27))
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: note.modifiedDate)
                == DateComponents(year: 2025, month: 1, day: 2, hour: 10, minute: 30))
        // The file dates stay available for change detection.
        #expect(note.fileCreatedDate == TestClock.date("2026-01-01", hour: 9))
    }

    @Test func unreadableDatesFallBackToTheFile() {
        let note = makeNote("A", frontmatter: ["erstellt": "sometime", "geändert": ["2024-01-01"]], modified: "2026-01-01")
        #expect(note.createdDate == note.fileCreatedDate)
        #expect(note.modifiedDate == note.fileModifiedDate)
        #expect(note.dateKeys.isEmpty)
    }

    @Test func dateFormats() {
        let file = Date(timeIntervalSince1970: 0)
        for text in ["2026-09-14", "\"2026-09-14\"", "14.09.2026", "2026-09-14 08:15", "2026-09-14T08:15:00", "2026-09-14T08:15:00+02:00"] {
            #expect(FrontmatterDate.parse(text, fileDate: file) != nil, "\(text)")
        }
        #expect(FrontmatterDate.parse("14/09/2026", fileDate: file) == nil)
    }

    @Test func sameDayKeepsTheFileTime() throws {
        let fileDate = TestClock.date("2026-11-18", hour: 15)
        let parsed = try #require(FrontmatterDate.parse("2026-11-18", fileDate: fileDate, calendar: TestClock.calendar))
        #expect(parsed == fileDate)
    }

    @Test func searchUsesFrontmatterDates() {
        let notes = [
            makeNote("Old", frontmatter: ["erstellt": "2020-05-01"], created: "2026-11-18"),
            makeNote("New", created: "2026-11-18"),
        ]
        #expect(SearchQuery.test("created:2026-11-18").titles(in: notes) == ["New"])
        #expect(SearchQuery.test("erstellt:<2021-01-01").titles(in: notes) == ["Old"])
    }

    @Test func previewHidesRepeatedProperties() {
        let note = makeNote("A", folder: "Projects/2026", frontmatter: [
            "erstellt": "2024-04-27", "geändert": "2024-05-01", "ordner": "Projects/2026/",
            "autor": "Leif", "aliases": ["One", "Two"], "leer": "",
        ])
        #expect(note.displayProperties.map(\.key) == ["aliases", "autor"])
        #expect(note.displayProperties.first?.values.map(\.text) == ["One", "Two"])
        // A folder property that differs from the real folder stays.
        #expect(makeNote("A", folder: "x", frontmatter: ["ordner": "y"]).displayProperties.map(\.key) == ["ordner"])
    }

    @Test func clickingAValueSearchesForIt() throws {
        let query = try #require(MarkdownFile.DisplayProperty.query(key: "autor", value: "Leif Jensen"))
        #expect(query == "autor:\"Leif Jensen\"")
        #expect(MarkdownFile.DisplayProperty.query(key: "my key", value: "x") == nil)
        #expect(MarkdownFile.DisplayProperty.query(key: "tag", value: "x") == nil)
        #expect(MarkdownFile.DisplayProperty.query(key: "pfad", value: "x") == nil)
        let note = makeNote("A", frontmatter: ["autor": "Leif Jensen"])
        #expect(SearchQuery.test(query).titles(in: [note]) == ["A"])
    }

    @Test func datesAndPathAreRowsWithSearches() throws {
        let note = makeNote("A", folder: "Projects/2026", frontmatter: ["erstellt": "2024-04-27", "autor": "Leif"], modified: "2026-11-10")
        let rows = note.previewProperties
        // Dates and folder first, then the frontmatter.
        #expect(rows.count == 4)
        #expect(rows[0].key == "erstellt")
        #expect(rows[0].values.map(\.text) == ["2024-04-27"])
        let createdQuery = try #require(rows[0].values.first?.query)
        #expect(createdQuery.hasSuffix(":2024-04-27"))
        #expect(rows[1].values.map(\.text) == [FrontmatterDate.day(note.modifiedDate)])
        #expect(rows[2].values.map(\.text) == ["Projects", "2026"])
        #expect(rows[2].separator == " / ")
        let pathQueries = rows[2].values.compactMap(\.query)
        #expect(pathQueries.count == 2)
        #expect(pathQueries[1].hasSuffix(":Projects/2026"))
        #expect(rows[3].key == "autor")
        // Both searches find the note again.
        #expect(SearchQuery(createdQuery).titles(in: [note]) == ["A"])  // the app searches in local time, like the preview
        #expect(SearchQuery.test(pathQueries[0]).titles(in: [note]) == ["A"])
    }

    @Test func noteAtTheRootHasNoPathRow() {
        #expect(makeNote("A").previewProperties.count == 2)
    }
}
