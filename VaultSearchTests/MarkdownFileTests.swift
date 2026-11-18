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

    @Test func folderAndCreatedLabel() {
        #expect(makeNote("A", folder: "x/y").folder == "x/y")
        #expect(makeNote("A").folder.isEmpty)
        #expect(makeNote("A", frontmatter: ["erstellt": "2024-04-27"]).createdLabel == "2024-04-27")
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
