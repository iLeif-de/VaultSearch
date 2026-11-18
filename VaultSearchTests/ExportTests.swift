import Foundation
import Testing
@testable import VaultSearch

@Suite("Export: Obsidian Markdown")
struct ObsidianMarkdownTests {
    let noAttachments: (String) -> URL? = { _ in nil }

    @Test func linksBecomeText() {
        let result = ObsidianMarkdown.portable("See [[Notes/Budget|the budget]], [[Ideas]] and [[Plan#Goals]].", resolveAttachment: noAttachments)
        #expect(result == "See the budget, Ideas and Plan › Goals.")
    }

    @Test func commentsAreRemoved() {
        #expect(ObsidianMarkdown.portable("a %%secret\nmultiline%% b", resolveAttachment: noAttachments) == "a  b")
    }

    @Test func imageEmbedsAreResolved() {
        let image = URL(fileURLWithPath: "/Vault/Attachments/chart.png")
        let result = ObsidianMarkdown.portable("![[chart.png]]", resolveAttachment: { $0 == "chart.png" ? image : nil })
        #expect(result == "![](</Vault/Attachments/chart.png>)")
    }

    @Test func unresolvedAndNoteEmbedsBecomeItalicText() {
        #expect(ObsidianMarkdown.portable("![[Other Note]]", resolveAttachment: noAttachments) == "*Other Note*")
        #expect(ObsidianMarkdown.portable("![[missing.png]]", resolveAttachment: noAttachments) == "*missing*")
    }

    @Test func calloutsBecomeBoldLabels() {
        #expect(ObsidianMarkdown.portable("> [!warning]- Careful\n> text", resolveAttachment: noAttachments)
                == "> **Warning** Careful\n> text")
    }

    @Test func attachmentResolverSearchesTheWholeVault() throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        let image = try vault.write("Files/Images/Chart.PNG", "png")
        let resolve = ObsidianMarkdown.attachmentResolver(vault: vault.url, near: vault.url.appendingPathComponent("Notes"))
        #expect(resolve("chart.png")?.standardizedFileURL == image.standardizedFileURL)
        #expect(resolve("missing.png") == nil)
    }
}

@Suite("Export: marking matches")
struct MarkMatchesTests {
    @Test func marksAllCases() {
        #expect(ObsidianMarkdown.markMatches("Idea and IDEA", terms: ["idea"]) == "==Idea== and ==IDEA==")
    }

    @Test func leavesCodeLinksAndURLsAlone() {
        let input = "Idea [Idea-Link](https://x.y/idea) `idea()` https://idea.de [[Idea]] ==idea=="
        let expected = "==Idea== [==Idea==-Link](https://x.y/idea) `idea()` https://idea.de [[Idea]] ==idea=="
        #expect(ObsidianMarkdown.markMatches(input, terms: ["idea"]) == expected)
    }

    @Test func leavesCodeBlocksAlone() {
        let input = "idea\n```\nlet idea = 1\n```\nidea"
        #expect(ObsidianMarkdown.markMatches(input, terms: ["idea"]) == "==idea==\n```\nlet idea = 1\n```\n==idea==")
    }

    @Test func longerTermsWin() {
        #expect(ObsidianMarkdown.markMatches("battery pack", terms: ["battery", "battery pack"]) == "==battery pack==")
    }

    @Test func noTermsNoChange() {
        #expect(ObsidianMarkdown.markMatches("text", terms: [" ", ""]) == "text")
    }
}

@Suite("Export: built-in HTML")
struct MarkdownHTMLTests {
    @Test func blocks() {
        let html = ObsidianMarkdown.html(fromMarkdown: """
        # Title
        Para **bold** and *italic* and ==mark==.
        - [ ] open
        - [x] done
        1. first
        > quote
        | A | B |
        |---|---|
        | 1 | 2 |
        """)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
        #expect(html.contains("<mark>mark</mark>"))
        #expect(html.contains("<li>☐ open</li>"))
        #expect(html.contains("☑ <del>"))
        #expect(html.contains("<ol>\n<li>first</li>"))
        #expect(html.contains("<blockquote><p>quote</p></blockquote>"))
        #expect(html.contains("<th>A</th><th>B</th>"))
        #expect(html.contains("<td>1</td><td>2</td>"))
        #expect(!html.contains("---"))
    }

    @Test func escapesHTMLAndKeepsCodeLiteral() {
        let html = ObsidianMarkdown.html(fromMarkdown: "a <b> & `x **y**`\n```\n<tag>\n```")
        #expect(html.contains("a &lt;b&gt; &amp; <code>x **y**</code>"))
        #expect(html.contains("<pre><code>&lt;tag&gt;</code></pre>"))
    }

    @Test func documentAddsTitleOnlyWithoutHeading() {
        #expect(ObsidianMarkdown.htmlDocument(title: "T", markdown: "text", css: "").contains("<h1>T</h1>"))
        #expect(!ObsidianMarkdown.htmlDocument(title: "T", markdown: "# Own", css: "").contains("<h1>T</h1>"))
    }
}

@Suite("Export: result lists")
struct ResultListExportTests {
    let notes = [
        makeNote("Solar", folder: "Projects", content: "The battery is full.", tags: ["energy", "idea"]),
        makeNote("Root note", content: "Battery level"),
    ]

    @Test func vaultVersionUsesWikilinksAndHighlights() {
        let markdown = ResultListExport.markdown(
            query: "battery", files: notes, highlightTerms: ["battery"],
            style: .excerpt, forVault: true, highlight: true
        )
        #expect(markdown.hasPrefix("---\ntype: vaultsearch-export\nquery: \"battery\""))
        #expect(markdown.contains("results: 2"))
        #expect(markdown.contains("## [[Projects/Solar|Solar]]"))
        #expect(markdown.contains("## [[Root note|Root note]]"))
        #expect(markdown.contains("#energy #idea"))
        #expect(markdown.contains("> The ==battery== is full."))
    }

    @Test func fileVersionHasNoObsidianSyntax() {
        let markdown = ResultListExport.markdown(
            query: "battery", files: notes, highlightTerms: ["battery"],
            style: .embed, forVault: false, highlight: false
        )
        #expect(!markdown.contains("---\ntype"))
        #expect(!markdown.contains("[["))
        #expect(markdown.contains("## Solar"))
        #expect(markdown.contains("energy, idea"))
        // Embeds only work in Obsidian, so files fall back to excerpts.
        #expect(markdown.contains("> The battery is full."))
        #expect(!markdown.contains("=="))
    }

    @Test func embedAndLinksOnlyStyles() {
        let embed = ResultListExport.markdown(query: "", files: notes, highlightTerms: [], style: .embed, forVault: true, highlight: true)
        #expect(embed.contains("![[Projects/Solar]]"))
        let links = ResultListExport.markdown(query: "", files: notes, highlightTerms: [], style: .linksOnly, forVault: true, highlight: true)
        #expect(!links.contains(">"))
    }

    @Test func fileNameIsSafe() {
        let name = ResultListExport.fileName(for: #"tag:a/b "x" #y|z"#, date: TestClock.now)
        #expect(name.hasPrefix("VaultSearch "))
        for forbidden in ["/", ":", "\"", "#", "|"] {
            #expect(!name.contains(forbidden), "contains \(forbidden)")
        }
        #expect(name.hasSuffix("tag a b x y z"))
    }
}

@Suite("Export: tools and templates")
struct ExportToolTests {
    @Test func engineKinds() {
        let url = URL(fileURLWithPath: "/bin/true")
        #expect(ExternalTools.PDFEngine(name: "xelatex", url: url).isLaTeX)
        #expect(ExternalTools.PDFEngine(name: "tectonic", url: url).isLaTeX)
        #expect(ExternalTools.PDFEngine(name: "weasyprint", url: url).isHTMLBased)
        #expect(!ExternalTools.PDFEngine(name: "typst", url: url).isLaTeX)
    }

    @Test func pandocMajorVersion() {
        var tools = ExternalTools()
        tools.pandocVersion = "3.14"
        #expect(tools.pandocMajorVersion == 3)
        tools.pandocVersion = nil
        #expect(tools.pandocMajorVersion == 0)
    }

    @Test func searchPathsIncludeHomebrewAndTeX() {
        #expect(ExternalTools.searchPaths.contains("/opt/homebrew/bin"))
        #expect(ExternalTools.searchPaths.contains("/Library/TeX/texbin"))
        #expect(Set(ExternalTools.searchPaths).count == ExternalTools.searchPaths.count)
    }

    @Test func processRunnerCapturesOutputAndStatus() throws {
        let ok = try ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), ["hello"])
        #expect(ok.status == 0)
        #expect(String(data: ok.output, encoding: .utf8) == "hello\n")
        let failing = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo oops >&2; exit 3"])
        #expect(failing.status == 3)
        #expect(failing.errorOutput == "oops\n")
    }

    @MainActor
    @Test func builtInConversionWritesFiles() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let converter = DocumentConverter(options: .init(
            usePandoc: false, tools: ExternalTools(), pdfEngine: "",
            wordReference: nil, odtReference: nil, stylesheet: nil, pandocPDFTemplate: nil
        ))
        for format in [ExportFormat.html, .rtf, .docx, .odt, .pdf, .markdown] {
            let output = folder.url.appendingPathComponent("out.\(format.fileExtension)")
            try await converter.convert(markdown: "# Title\nSome ==text==.", title: "Title", format: format,
                                        resourceFolders: [folder.url], to: output)
            let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int ?? 0
            #expect(size > 0, "\(format.rawValue) is empty")
        }
        await #expect(throws: ExportError.self) {
            try await converter.convert(markdown: "x", title: "T", format: .epub, resourceFolders: [], to: folder.url.appendingPathComponent("x.epub"))
        }
    }
}

@Suite("Search suggestions")
struct SearchSuggestionTests {
    let tags = ["project/idea", "area/ideas", "idea", "identity", "misc"]

    @Test func tagsMatchAtAnyLevelPrefixFirst() {
        let titles = SearchSuggestion.suggestions(for: "tag:id", tags: tags, properties: []).map(\.title)
        #expect(titles == ["#idea", "#identity", "#project/idea", "#area/ideas"])
    }

    @Test func completionKeepsTheRestOfTheQuery() {
        let first = SearchSuggestion.suggestions(for: "budget tag:mi", tags: tags, properties: []).first
        #expect(first?.completion == "budget tag:misc ")
    }

    @Test func datePresetsInTheTypedLanguage() {
        let english = SearchSuggestion.suggestions(for: "created:last", tags: [], properties: []).map(\.completion)
        #expect(english.contains("created:last 7 days "))
        let german = SearchSuggestion.suggestions(for: "erstellt:letzte", tags: [], properties: []).map(\.completion)
        #expect(german.contains("erstellt:letzte 7 Tage "))
    }

    @Test func emptyWordSuggestsNothing() {
        #expect(SearchSuggestion.suggestions(for: "", tags: tags, properties: []).isEmpty)
        #expect(SearchSuggestion.suggestions(for: "budget ", tags: tags, properties: []).isEmpty)
    }

    @Test func quotesTagsWithSpaces() {
        #expect(SearchSuggestion.quoted("two words") == "\"two words\"")
        #expect(SearchSuggestion.quoted("one") == "one")
    }
}
