import AppKit

// AppleScript support (Cocoa Scripting). The dictionary is `VaultSearch.sdef`; `Config/Info.plist`
// turns scripting on. Commands run on the main thread; the ones that wait for the index or an
// export suspend the Apple event and resume it when the work is done.
//
// Like the App Intents, these classes are only reached by name at run time. They are referenced
// in `ScriptingSupport.classes`, so the Release optimizer keeps them.

// MARK: - Application

/// Answers the application's scripting keys (`notes`, `vault path`, `indexing`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ScriptingSupport.keep()
    }

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        ["scriptNotes", "scriptVaultPath", "scriptIndexing"].contains(key)
    }

    @objc var scriptNotes: [ScriptableNote] {
        MainActor.assumeIsolated { ScriptingSupport.notes }
    }

    @objc(valueInScriptNotesWithUniqueID:)
    func valueInScriptNotes(withUniqueID id: String) -> ScriptableNote? {
        MainActor.assumeIsolated { ScriptingSupport.notes.first { $0.uniqueID == id } }
    }

    @objc(valueInScriptNotesWithName:)
    func valueInScriptNotes(withName name: String) -> ScriptableNote? {
        MainActor.assumeIsolated {
            ScriptingSupport.notes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    @objc var scriptVaultPath: String {
        MainActor.assumeIsolated { AppModel.shared.settings.vaultPath?.path ?? "" }
    }

    @objc var scriptIndexing: Bool {
        MainActor.assumeIsolated { AppModel.shared.search.isIndexing }
    }
}

@MainActor
enum ScriptingSupport {
    private static var cache: (generation: Int, notes: [ScriptableNote])?

    /// One scripting object per note, rebuilt after each index run.
    static var notes: [ScriptableNote] {
        let search = AppModel.shared.search
        if let cache, cache.generation == search.generation { return cache.notes }
        let notes = search.files.map(ScriptableNote.init)
        cache = (search.generation, notes)
        return notes
    }

    static func note(for file: MarkdownFile) -> ScriptableNote {
        notes.first { $0.uniqueID == file.path.path } ?? ScriptableNote(file)
    }

    nonisolated static let classes: [AnyClass] = [
        ScriptableNote.self, SearchCommand.self, ShowSearchCommand.self, OpenInObsidianCommand.self,
        ExportCommand.self, SaveToVaultCommand.self, ReindexCommand.self,
    ]

    nonisolated static func keep() {
        precondition(classes.count == 7, "Add new scripting classes to ScriptingSupport.classes")
    }
}

// MARK: - Note

@objc(VSScriptableNote)
final class ScriptableNote: NSObject {
    let file: MarkdownFile

    init(_ file: MarkdownFile) {
        self.file = file
    }

    @objc var uniqueID: String { file.path.path }
    @objc var name: String { file.title }
    @objc var path: String { file.path.path }
    @objc var folder: String { file.folder }
    @objc var tags: [String] { file.tags }
    @objc var creationDate: Date { file.createdDate }
    @objc var modificationDate: Date { file.modifiedDate }
    @objc var content: String { file.content }
    @objc var obsidianURL: String { file.obsidianURI?.absoluteString ?? "" }

    /// The frontmatter as an AppleScript record with the keys as user fields (`|status|`).
    @objc var frontmatter: NSAppleEventDescriptor {
        let fields = NSAppleEventDescriptor.list()
        for (key, value) in file.frontmatter.sorted(by: { $0.key < $1.key }) where key.lowercased() != "tags" {
            fields.insert(NSAppleEventDescriptor(string: key), at: 0)
            if let list = value as? [String] {
                let items = NSAppleEventDescriptor.list()
                for item in list { items.insert(NSAppleEventDescriptor(string: item), at: 0) }
                fields.insert(items, at: 0)
            } else {
                fields.insert(NSAppleEventDescriptor(string: String(describing: value)), at: 0)
            }
        }
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(fields, forKeyword: 0x7573_7266)  // keyASUserRecordFields, "usrf"
        return record
    }

    /// Never called: `VaultSearchCommand.execute()` handles the commands; see the sdef.
    @objc func handleScriptCommand(_ command: NSScriptCommand) -> Any? {
        nil
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let application = NSScriptClassDescription(for: NSApplication.self) else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: application, containerSpecifier: nil,
                                   key: "scriptNotes", uniqueID: uniqueID)
    }
}

// MARK: - Commands

class VaultSearchCommand: NSScriptCommand {
    /// Cocoa would send a command whose direct parameter is a note (`export note "Plan"`,
    /// `export every note whose …`) to the notes themselves. VaultSearch handles all its
    /// commands in one place instead, so a list stays one list.
    override func execute() -> Any? {
        performDefaultImplementation()
    }

    /// Runs `work` asynchronously; the script waits for its result or error.
    func suspend(_ work: @escaping @MainActor () async throws -> Any?) -> Any? {
        suspendExecution()
        Task { @MainActor in
            do {
                resumeExecution(withResult: try await work())
            } catch {
                scriptErrorNumber = errOSAGeneralError
                if let error = error as? CustomLocalizedStringResourceConvertible {
                    scriptErrorString = String(localized: error.localizedStringResource)
                } else {
                    scriptErrorString = error.localizedDescription
                }
                resumeExecution(withResult: nil)
            }
        }
        return nil
    }

    /// Notes from the direct parameter: a note, a list of notes or a specifier such as `every note whose …`.
    @MainActor
    func notesFromDirectParameter() -> [ScriptableNote] {
        func resolve(_ value: Any?) -> [ScriptableNote] {
            switch value {
            case let note as ScriptableNote: return [note]
            case let notes as [Any]: return notes.flatMap(resolve)
            case let specifier as NSScriptObjectSpecifier: return resolve(specifier.objectsByEvaluatingSpecifier)
            default: return []
            }
        }
        for source in [evaluatedReceivers, receiversSpecifier, directParameter] as [Any?] {
            let notes = resolve(source)
            if !notes.isEmpty { return notes }
        }
        return []
    }

    /// True when the direct parameter is a single note rather than a list.
    @MainActor
    var directParameterIsSingleNote: Bool {
        if directParameter is [Any] { return false }
        if let specifier = directParameter as? NSScriptObjectSpecifier {
            return !(specifier.objectsByEvaluatingSpecifier is [Any])
        }
        if let receivers = evaluatedReceivers ?? receiversSpecifier?.objectsByEvaluatingSpecifier {
            return !(receivers is [Any])
        }
        return directParameter is ScriptableNote
    }
}

@objc(VSSearchCommand)
final class SearchCommand: VaultSearchCommand {
    override func performDefaultImplementation() -> Any? {
        let text = directParameter as? String ?? ""
        let limit = (evaluatedArguments?["limit"] as? NSNumber)?.intValue
        return suspend {
            let model = AppModel.shared
            try model.requireVault()
            let found = await model.search.indexedResults(for: text)
            return Array(found.prefix(limit ?? found.count)).map(ScriptingSupport.note(for:))
        }
    }
}

@objc(VSShowSearchCommand)
final class ShowSearchCommand: VaultSearchCommand {
    override func performDefaultImplementation() -> Any? {
        let text = directParameter as? String ?? ""
        MainActor.assumeIsolated { AppModel.shared.requestSearch(text) }
        return nil
    }
}

@objc(VSOpenInObsidianCommand)
final class OpenInObsidianCommand: VaultSearchCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            for note in notesFromDirectParameter() { NoteActions.openInObsidian(note.file) }
        }
        return nil
    }
}

@objc(VSExportCommand)
final class ExportCommand: VaultSearchCommand {
    private static let formats: [FourCharCode: ExportFormat] = [
        "Fpdf": .pdf, "Fdoc": .docx, "Fodt": .odt, "Frtf": .rtf, "Fhtm": .html, "Fepb": .epub, "Fmd ": .markdown,
    ].reduce(into: [:]) { result, entry in result[FourCharCode(fourCharString: entry.key)] = entry.value }

    override func performDefaultImplementation() -> Any? {
        let code = (evaluatedArguments?["format"] as? NSNumber)?.uint32Value
        let format = code.flatMap { Self.formats[$0] } ?? .pdf
        let target = evaluatedArguments?["file"] as? URL
        let title = evaluatedArguments?["title"] as? String
        let (notes, single) = MainActor.assumeIsolated { (notesFromDirectParameter(), directParameterIsSingleNote) }
        return suspend {
            let model = AppModel.shared
            try model.requireVault()
            try await model.requireFormat(format)
            guard !notes.isEmpty else { throw VaultSearchIntentError.noResults }
            if single, let note = notes.first {
                let output = try target ?? ExportService.temporaryOutput(name: note.file.title, format: format)
                try await model.exporter.writeNote(note.file, as: format, to: output)
                return output
            }
            let snapshot = try model.snapshot(files: notes.map(\.file), title: title)
            let output = try target ?? ExportService.temporaryOutput(name: snapshot.fileName, format: format)
            try await model.exporter.writeResults(snapshot, as: format, to: output)
            return output
        }
    }
}

@objc(VSSaveToVaultCommand)
final class SaveToVaultCommand: VaultSearchCommand {
    override func performDefaultImplementation() -> Any? {
        let title = evaluatedArguments?["title"] as? String
        let notes = MainActor.assumeIsolated { notesFromDirectParameter() }
        return suspend {
            let model = AppModel.shared
            try model.requireVault()
            let snapshot = try model.snapshot(files: notes.map(\.file), title: title)
            return try model.exporter.writeResultsToVault(snapshot)
        }
    }
}

@objc(VSReindexCommand)
final class ReindexCommand: VaultSearchCommand {
    override func performDefaultImplementation() -> Any? {
        suspend {
            let model = AppModel.shared
            try model.requireVault()
            model.search.reindex()
            await model.search.waitUntilIndexed()
            return nil
        }
    }
}

private extension FourCharCode {
    init(fourCharString text: String) {
        self = text.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
