import Foundation
import AppKit

/// Keeps an in-memory index of the vault and answers search queries.
@MainActor
final class SearchService: ObservableObject {
    struct Progress: Equatable {
        var done: Int
        var total: Int
    }

    @Published private(set) var files: [MarkdownFile] = []
    @Published private(set) var isIndexing = false
    @Published private(set) var progress: Progress?
    @Published private(set) var lastIndexed: Date?
    @Published private(set) var indexError: String?
    @Published private(set) var knownTags: [String] = []
    @Published private(set) var knownProperties: [String] = []
    /// Increments after every finished index run, so views can refresh results.
    @Published private(set) var generation = 0

    private(set) var vaultURL: URL?
    private var excludedFolders: Set<String> = []
    private var recentFiles: [MarkdownFile] = []
    private var signature: VaultScanner.Signature?
    private var indexTask: Task<Void, Never>?
    private var watchTimer: Timer?
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkForChanges() }
        }
    }

    func configure(vaultURL: URL?, excludedFolders: Set<String>) {
        guard vaultURL != self.vaultURL || excludedFolders != self.excludedFolders || signature == nil else { return }
        if vaultURL != self.vaultURL {
            files = []
            recentFiles = []
            knownTags = []
            knownProperties = []
            signature = nil
        }
        self.vaultURL = vaultURL
        self.excludedFolders = excludedFolders
        reindex()

        watchTimer?.invalidate()
        if vaultURL != nil {
            watchTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkForChanges() }
            }
        }
    }

    func reindex() {
        indexTask?.cancel()
        guard let vaultURL else {
            isIndexing = false
            progress = nil
            return
        }
        let excluded = excludedFolders
        isIndexing = true
        indexError = nil
        progress = nil

        indexTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                VaultScanner.index(vaultURL: vaultURL, excluded: excluded) { done, total in
                    Task { @MainActor in
                        guard let self, self.isIndexing else { return }
                        self.progress = Progress(done: done, total: total)
                    }
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(result)
        }
    }

    /// Results for the search field text; the most recently modified notes when it is empty.
    func results(for text: String) async -> [MarkdownFile] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recentFiles }
        let files = self.files
        return await Task.detached(priority: .userInitiated) {
            SearchQuery(trimmed).run(on: files)
        }.value
    }

    func file(with id: MarkdownFile.ID?) -> MarkdownFile? {
        guard let id else { return nil }
        return files.first { $0.id == id }
    }

    private func apply(_ result: VaultScanner.Result) {
        files = result.files
        recentFiles = Array(result.files.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(100))
        signature = result.signature
        indexError = result.error

        var tagCounts: [String: Int] = [:]
        var propertyCounts: [String: Int] = [:]
        for file in result.files {
            for tag in file.tags { tagCounts[tag, default: 0] += 1 }
            for key in file.frontmatter.keys where key.lowercased() != "tags" { propertyCounts[key, default: 0] += 1 }
        }
        knownTags = tagCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        knownProperties = propertyCounts.sorted { $0.value > $1.value }.prefix(20).map(\.key)

        isIndexing = false
        progress = nil
        lastIndexed = .now
        generation += 1
    }

    /// Cheap check (file list and modification dates only) that re-indexes when something changed.
    private func checkForChanges() {
        guard let vaultURL, !isIndexing, let current = signature else { return }
        let excluded = excludedFolders
        Task {
            let latest = await Task.detached(priority: .utility) {
                VaultScanner.Signature(VaultScanner.entries(in: vaultURL, excluded: excluded))
            }.value
            if latest != current && !isIndexing && vaultURL == self.vaultURL {
                reindex()
            }
        }
    }
}

/// File system work, runs off the main actor.
enum VaultScanner {
    struct Entry {
        let url: URL
        let relativePath: String
        let created: Date
        let modified: Date
    }

    struct Signature: Equatable {
        var count = 0
        var latest = Date.distantPast
        var pathsHash = 0

        init(_ entries: [Entry] = []) {
            var hasher = Hasher()
            for entry in entries {
                hasher.combine(entry.relativePath)
                latest = max(latest, entry.modified)
            }
            count = entries.count
            pathsHash = hasher.finalize()
        }
    }

    struct Result {
        var files: [MarkdownFile]
        var signature: Signature
        var error: String?
    }

    static func entries(in vaultURL: URL, excluded: Set<String>) -> [Entry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        let rootPath = vaultURL.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: vaultURL, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var entries: [Entry] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let absolute = url.standardizedFileURL.path
            let relative = absolute.hasPrefix(rootPath + "/")
                ? String(absolute.dropFirst(rootPath.count + 1))
                : url.lastPathComponent

            if values.isDirectory == true {
                if excluded.contains(relative) || excluded.contains(absolute) || excluded.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            entries.append(Entry(
                url: url, relativePath: relative,
                created: values.creationDate ?? .distantPast,
                modified: values.contentModificationDate ?? .distantPast
            ))
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    static func index(vaultURL: URL, excluded: Set<String>, progress: (Int, Int) -> Void) -> Result {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return Result(files: [], signature: Signature(), error: "The vault folder “\(vaultURL.lastPathComponent)” could not be found.")
        }

        let entries = entries(in: vaultURL, excluded: excluded)
        let vaultName = vaultURL.lastPathComponent
        var files: [MarkdownFile] = []
        files.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            if index % 25 == 0 { progress(index, entries.count) }
            guard let raw = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            let parsed = parse(raw)
            files.append(MarkdownFile(
                path: entry.url, relativePath: entry.relativePath, content: parsed.body,
                frontmatter: parsed.frontmatter, tags: parsed.tags,
                createdDate: entry.created, modifiedDate: entry.modified, vaultName: vaultName
            ))
        }
        return Result(files: files, signature: Signature(entries), error: nil)
    }

    /// Minimal YAML frontmatter reader: `key: value`, `key: [a, b]` and `- item` lists.
    static func parse(_ raw: String) -> (frontmatter: [String: Any], body: String, tags: [String]) {
        let lines = raw.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" })
        else { return ([:], raw, []) }

        var frontmatter: [String: Any] = [:]
        var tags: [String] = []
        var listKey: String?
        var listValues: [String] = []

        func clean<S: StringProtocol>(_ value: S) -> String {
            value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        func store(_ key: String, _ value: Any, tagValues: [String]) {
            frontmatter[key] = value
            if key.lowercased() == "tags" { tags += tagValues }
        }
        func flushList() {
            if let key = listKey { store(key, listValues, tagValues: listValues) }
            listKey = nil
            listValues = []
        }

        for line in lines[1..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if listKey != nil, trimmed.hasPrefix("-") {
                let item = clean(trimmed.dropFirst())
                if !item.isEmpty { listValues.append(item) }
                continue
            }
            guard let colon = line.firstIndex(of: ":"), line.first?.isWhitespace == false else { continue }
            flushList()
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                listKey = key
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                let items = value.dropFirst().dropLast().split(separator: ",").map(clean).filter { !$0.isEmpty }
                store(key, items, tagValues: items)
            } else {
                let items = value.split(whereSeparator: { $0 == "," || $0 == " " }).map(clean).filter { !$0.isEmpty }
                store(key, clean(value), tagValues: items)
            }
        }
        flushList()

        var seen = Set<String>()
        let uniqueTags = tags
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return (frontmatter, lines[(end + 1)...].joined(separator: "\n"), uniqueTags)
    }
}
