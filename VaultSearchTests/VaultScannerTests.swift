import Foundation
import Testing
@testable import VaultSearch

@Suite("Indexing: frontmatter")
struct FrontmatterTests {
    @Test func listTagsAndValues() {
        let parsed = VaultScanner.parse("""
        ---
        tags:
          - project/alpha
          - "#finance"
        status: active
        title: 'Quoted'
        ---
        # Body
        Text
        """)
        #expect(parsed.tags == ["project/alpha", "finance"])
        #expect(parsed.frontmatter["status"] as? String == "active")
        #expect(parsed.frontmatter["title"] as? String == "Quoted")
        #expect(parsed.body == "# Body\nText")
    }

    @Test func inlineArrayAndCommaSeparatedTags() {
        #expect(VaultScanner.parse("---\ntags: [a, \"b c\", a]\n---\n").tags == ["a", "b c"])
        #expect(VaultScanner.parse("---\ntags: one, two\n---\n").tags == ["one", "two"])
        #expect(VaultScanner.parse("---\ntags: #single\n---\n").tags == ["single"])
    }

    @Test func otherListsAreKept() {
        let parsed = VaultScanner.parse("---\naliases:\n  - First\n  - Second\n---\nBody")
        #expect(parsed.frontmatter["aliases"] as? [String] == ["First", "Second"])
        #expect(parsed.tags.isEmpty)
    }

    @Test func noFrontmatter() {
        let parsed = VaultScanner.parse("Just text\n---\nmore")
        #expect(parsed.frontmatter.isEmpty)
        #expect(parsed.body == "Just text\n---\nmore")
    }

    @Test func unterminatedFrontmatterIsBody() {
        let parsed = VaultScanner.parse("---\nstatus: open\nno end")
        #expect(parsed.frontmatter.isEmpty)
        #expect(parsed.body.hasPrefix("---"))
    }
}

@Suite("Indexing: file system")
struct VaultScannerFileTests {
    @Test func skipsHiddenAndExcludedFoldersAndNonMarkdown() throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        try vault.write("Root.md", "root")
        try vault.write("Projects/Plan.md", "plan")
        try vault.write("Projects/Archive/Old.md", "old")
        try vault.write("Private/Secret.md", "secret")
        try vault.write(".obsidian/workspace.md", "hidden")
        try vault.write(".trash/Deleted.md", "deleted")
        try vault.write("Attachments/image.png", "png")

        let paths = VaultScanner.entries(in: vault.url, excluded: ["Private", "Projects/Archive"]).map(\.relativePath)
        #expect(paths == ["Projects/Plan.md", "Root.md"])
    }

    @Test func excludesByFolderNameAndAbsolutePath() throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        try vault.write("A/Templates/T.md")
        try vault.write("B/Note.md")
        let absoluteB = vault.url.appendingPathComponent("B").standardizedFileURL.path

        let paths = VaultScanner.entries(in: vault.url, excluded: ["Templates", absoluteB]).map(\.relativePath)
        #expect(paths.isEmpty)
    }

    @Test func indexReadsNotes() throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        try vault.write("Ideas/Solar.md", "---\ntags: [energy]\n---\nBattery storage")

        let result = VaultScanner.index(vaultURL: vault.url, excluded: []) { _, _ in }
        let note = try #require(result.files.first)
        #expect(result.error == nil)
        #expect(note.title == "Solar")
        #expect(note.relativePath == "Ideas/Solar.md")
        #expect(note.folder == "Ideas")
        #expect(note.tags == ["energy"])
        #expect(note.content == "Battery storage")
        #expect(note.vaultName == vault.url.lastPathComponent)
    }

    @Test func missingVaultReportsAnError() {
        let result = VaultScanner.index(vaultURL: URL(fileURLWithPath: "/does/not/exist-\(UUID())"), excluded: []) { _, _ in }
        #expect(result.files.isEmpty)
        #expect(result.error != nil)
    }

    @Test func signatureChangesWhenFilesChange() throws {
        let vault = try TemporaryFolder()
        defer { vault.cleanUp() }
        try vault.write("A.md", "a")
        let before = VaultScanner.Signature(VaultScanner.entries(in: vault.url, excluded: []))
        #expect(before == VaultScanner.Signature(VaultScanner.entries(in: vault.url, excluded: [])))

        try vault.write("B.md", "b")
        let after = VaultScanner.Signature(VaultScanner.entries(in: vault.url, excluded: []))
        #expect(before != after)
        #expect(after.count == 2)
    }
}
