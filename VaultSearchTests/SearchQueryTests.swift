import Foundation
import Testing
@testable import VaultSearch

@Suite("Search: text, AND and OR")
struct SearchQueryTextTests {
    let notes = [
        makeNote("Budget Plan", content: "The Café costs a lot.", modified: "2026-11-10"),
        makeNote("Meeting", content: "Budget review with the team.", modified: "2026-11-12"),
        makeNote("Holiday", content: "Beach and sun.", modified: "2026-11-11"),
    ]

    @Test func tokenizeKeepsQuotedPhrasesAndRelativeDates() {
        #expect(SearchQuery.tokenize(#"budget "exact phrase" created:last 7 days modified:>=this week"#)
                == ["budget", "exact phrase", "created:last 7 days", "modified:>=this week"])
        #expect(SearchQuery.tokenize("erstellt:letzte 30 Tage idee") == ["erstellt:letzte 30 Tage", "idee"])
    }

    @Test func textIgnoresCaseAndAccents() {
        #expect(SearchQuery.test("cafe").titles(in: notes) == ["Budget Plan"])
        #expect(SearchQuery.test("CAFÉ").titles(in: notes) == ["Budget Plan"])
    }

    @Test func spacesMeanAnd() {
        #expect(SearchQuery.test("budget team").titles(in: notes) == ["Meeting"])
        #expect(SearchQuery.test("budget AND team").titles(in: notes) == ["Meeting"])
        #expect(SearchQuery.test("budget UND team").titles(in: notes) == ["Meeting"])
    }

    @Test func orSeparatesAlternatives() {
        #expect(Set(SearchQuery.test("beach OR team").titles(in: notes)) == ["Holiday", "Meeting"])
        #expect(Set(SearchQuery.test("beach ODER team").titles(in: notes)) == ["Holiday", "Meeting"])
    }

    @Test func orBindsLooserThanAnd() {
        // (budget AND team) OR beach
        #expect(Set(SearchQuery.test("budget team OR beach").titles(in: notes)) == ["Meeting", "Holiday"])
    }

    @Test func lowercaseOrIsAnOrdinaryWord() {
        #expect(SearchQuery.test("beach or team").titles(in: notes).isEmpty)
    }

    @Test func titleHitsRankFirstThenNewest() {
        // Both mention "budget"; the title hit wins over the newer note.
        #expect(SearchQuery.test("budget").titles(in: notes) == ["Budget Plan", "Meeting"])
    }

    @Test func bareKeyWhileTypingIsIgnored() {
        #expect(SearchQuery.test("budget tag:").titles(in: notes) == SearchQuery.test("budget").titles(in: notes))
        #expect(SearchQuery.test("tag:").isEmpty)
    }

    @Test func plainTextDoesNotSearchTags() {
        let tagged = [makeNote("Untitled", content: "nothing", tags: ["idea"])]
        #expect(SearchQuery.test("idea").titles(in: tagged).isEmpty)
        #expect(SearchQuery.test("idea OR tag:idea").titles(in: tagged) == ["Untitled"])
    }

    @Test func textTermsCollectAllGroups() {
        #expect(SearchQuery.test("budget tag:x OR beach").textTerms == ["budget", "beach"])
    }
}

@Suite("Search: hierarchical tags")
struct SearchQueryTagTests {
    let notes = [
        makeNote("Deep", tags: ["area/project/idea"], modified: "2026-11-09"),
        makeNote("Child", tags: ["idea/later"], modified: "2026-11-08"),
        makeNote("Exact", tags: ["idea"], modified: "2026-01-01"),
        makeNote("Nested", tags: ["project/idea"], modified: "2026-11-07"),
        makeNote("Plural", tags: ["ideas"], modified: "2026-11-06"),
        makeNote("Project", tags: ["project"], modified: "2026-11-05"),
    ]

    @Test(arguments: [
        ("idea", "idea", 3),
        ("Idea", "idea", 3),
        ("idea/later", "idea", 2),
        ("project/idea", "idea", 1),
        ("area/project/idea", "idea", 1),
        ("project/idea/later", "idea", 1),
        ("ideas", "idea", 0),
        ("project/ideas", "idea", 0),
        ("area/project/idea", "project/idea", 1),
        ("project/idea", "#project/idea", 3),
    ])
    func tagScore(tag: String, query: String, expected: Int) {
        #expect(SearchQuery.tagScore(tag: tag, query: query) == expected)
    }

    @Test func rankedByClosenessThenDate() {
        #expect(SearchQuery.test("tag:idea").titles(in: notes) == ["Exact", "Child", "Deep", "Nested"])
    }

    @Test func parentTagFindsChildrenAndDeeperPaths() {
        #expect(SearchQuery.test("tag:project").titles(in: notes) == ["Project", "Nested", "Deep"])
    }

    @Test func pathQuery() {
        #expect(SearchQuery.test("tag:project/idea").titles(in: notes) == ["Nested", "Deep"])
    }

    @Test func leadingHashIsOptional() {
        #expect(SearchQuery.test("tag:#idea").titles(in: notes) == SearchQuery.test("tag:idea").titles(in: notes))
    }

    @Test func contentTagsInText() {
        let texts = [
            makeNote("Inline", content: "Text with #project/idea inside"),
            makeNote("Link", content: "See [[idea]]."),
            makeNote("Plural", content: "Only #ideas here"),
            makeNote("Child", content: "#idea/later"),
        ]
        #expect(Set(SearchQuery.test("contenttag:idea").titles(in: texts)) == ["Inline", "Link", "Child"])
    }
}

@Suite("Search: properties")
struct SearchQueryPropertyTests {
    let notes = [
        makeNote("Active", frontmatter: ["status": "active"]),
        makeNote("Done", frontmatter: ["Status": "done"]),
        makeNote("None"),
    ]

    @Test func propertyContainsValue() {
        #expect(SearchQuery.test("status:act").titles(in: notes) == ["Active"])
    }

    @Test func keyIgnoresCase() {
        #expect(SearchQuery.test("STATUS:done").titles(in: notes) == ["Done"])
    }

    @Test func notesWithoutThePropertyDoNotMatch() {
        #expect(!SearchQuery.test("status:a").titles(in: notes).contains("None"))
    }
}

@Suite("Search: dates")
struct SearchQueryDateTests {
    let cal = TestClock.calendar
    let now = TestClock.now

    func range(_ value: String) -> ClosedRange<Date>? {
        SearchQuery.dateRange(value, now: now, calendar: cal)
    }

    func days(_ from: String, _ to: String) -> ClosedRange<Date> {
        TestClock.day(from)...TestClock.day(to)
    }

    @Test(arguments: [
        ("today", "2026-11-18", "2026-11-18"),
        ("yesterday", "2026-11-17", "2026-11-17"),
        ("this week", "2026-11-16", "2026-11-18"),
        ("this month", "2026-11-01", "2026-11-18"),
        ("this year", "2026-01-01", "2026-11-18"),
        ("last week", "2026-11-09", "2026-11-15"),
        ("last month", "2026-10-01", "2026-10-31"),
        ("last year", "2025-01-01", "2025-12-31"),
        ("last 7 days", "2026-11-12", "2026-11-18"),
        ("last 2 weeks", "2026-11-05", "2026-11-18"),
        ("last 3 months", "2026-08-18", "2026-11-18"),
        ("2025-04-28", "2025-04-28", "2025-04-28"),
        ("2025-4-8", "2025-04-08", "2025-04-08"),
        ("28.04.25", "2025-04-28", "2025-04-28"),
        ("28.04.2025", "2025-04-28", "2025-04-28"),
    ])
    func englishAndNumericDates(value: String, from: String, to: String) {
        #expect(range(value) == days(from, to))
    }

    @Test(arguments: [
        ("heute", "today"),
        ("gestern", "yesterday"),
        ("diese Woche", "this week"),
        ("dieser Monat", "this month"),
        ("dieses Jahr", "this year"),
        ("letzte Woche", "last week"),
        ("letzter Monat", "last month"),
        ("letztes Jahr", "last year"),
        ("letzte 7 Tage", "last 7 days"),
        ("letzte 2 Wochen", "last 2 weeks"),
    ])
    func germanDatesEqualEnglish(german: String, english: String) {
        #expect(range(german) != nil)
        #expect(range(german) == range(english))
    }

    @Test func invalidDatesMatchNothing() {
        #expect(range("someday") == nil)
        #expect(range("2025-13-45") == nil)
        #expect(SearchQuery.test("created:someday").titles(in: [makeNote("A")]).isEmpty)
    }

    @Test func operators() {
        let notes = [
            makeNote("Before", created: "2026-03-31"),
            makeNote("On", created: "2026-04-01"),
            makeNote("After", created: "2026-04-02"),
        ]
        #expect(Set(SearchQuery.test("created:>=2026-04-01").titles(in: notes)) == ["On", "After"])
        #expect(Set(SearchQuery.test("created:>2026-04-01").titles(in: notes)) == ["After"])
        #expect(Set(SearchQuery.test("created:<=2026-04-01").titles(in: notes)) == ["Before", "On"])
        #expect(Set(SearchQuery.test("created:<2026-04-01").titles(in: notes)) == ["Before"])
        #expect(Set(SearchQuery.test("created:2026-04-01").titles(in: notes)) == ["On"])
    }

    @Test func createdAndModifiedUseTheirOwnDates() {
        let note = makeNote("A", created: "2025-01-01", modified: "2026-11-18")
        #expect(SearchQuery.test("modified:today").titles(in: [note]) == ["A"])
        #expect(SearchQuery.test("created:today").titles(in: [note]).isEmpty)
        #expect(SearchQuery.test("erstellt:letztes Jahr").titles(in: [note]) == ["A"])
        #expect(SearchQuery.test("geändert:heute").titles(in: [note]) == ["A"])
        #expect(SearchQuery.test("geaendert:heute").titles(in: [note]) == ["A"])
    }
}
