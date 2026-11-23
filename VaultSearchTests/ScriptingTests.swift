import AppKit
import Testing
@testable import VaultSearch

@Suite("AppleScript")
struct ScriptingTests {
    @Test func notePropertiesComeFromTheIndexedNote() {
        let note = ScriptableNote(makeNote("Plan", folder: "Projects/2026", content: "Text", tags: ["idea"],
                                           frontmatter: ["status": "active"], vault: "Vault"))
        #expect(note.name == "Plan")
        #expect(note.uniqueID == "/Vault/Projects/2026/Plan.md")
        #expect(note.folder == "Projects/2026")
        #expect(note.tags == ["idea"])
        #expect(note.content == "Text")
        #expect(note.obsidianURL.hasPrefix("obsidian://open?vault=Vault"))
    }

    @Test func frontmatterBecomesARecordWithUserFields() throws {
        let note = ScriptableNote(makeNote("A", tags: ["x"], frontmatter: ["status": "active", "people": ["Anna", "Ben"]]))
        let fields = try #require(note.frontmatter.forKeyword(0x7573_7266))  // usrf
        // Pairs of key and value, sorted by key; tags are left out.
        #expect(fields.numberOfItems == 4)
        #expect(fields.atIndex(1)?.stringValue == "people")
        #expect(fields.atIndex(2)?.numberOfItems == 2)
        #expect(fields.atIndex(3)?.stringValue == "status")
        #expect(fields.atIndex(4)?.stringValue == "active")
    }

    @Test func everyScriptingClassIsKept() {
        #expect(ScriptingSupport.classes.count == 7)
        #expect(NSClassFromString("VSScriptableNote") != nil)
        #expect(NSClassFromString("VSExportCommand") != nil)
    }
}
