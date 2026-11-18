import Foundation

/// One indexed Markdown note of the vault.
struct MarkdownFile: Identifiable, Hashable {
    /// The file URL is stable across re-indexing, so selection survives a refresh.
    var id: URL { path }

    let path: URL
    /// Path relative to the vault root, e.g. `Projects/Idea.md`.
    let relativePath: String
    let title: String
    /// Note body without frontmatter.
    let content: String
    let frontmatter: [String: Any]
    let tags: [String]
    let createdDate: Date
    let modifiedDate: Date
    let vaultName: String

    init(path: URL, relativePath: String, content: String, frontmatter: [String: Any],
         tags: [String], createdDate: Date, modifiedDate: Date, vaultName: String) {
        self.path = path
        self.relativePath = relativePath
        self.title = path.deletingPathExtension().lastPathComponent
        self.content = content
        self.frontmatter = frontmatter
        self.tags = tags
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.vaultName = vaultName
    }

    /// Folder inside the vault, empty for notes at the root.
    var folder: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// Prefers an explicit `erstellt`/`created` frontmatter value over the file system date.
    var createdLabel: String {
        for key in ["erstellt", "created"] {
            if let value = frontmatter[key] as? String, !value.isEmpty { return value }
        }
        return createdDate.formatted(date: .abbreviated, time: .omitted)
    }

    /// Frontmatter entries suitable for display, excluding tags.
    var displayProperties: [(key: String, value: String)] {
        frontmatter
            .filter { $0.key.lowercased() != "tags" }
            .map { entry in
                let value: String
                if let list = entry.value as? [String] {
                    value = list.joined(separator: ", ")
                } else {
                    value = String(describing: entry.value)
                }
                return (entry.key, value)
            }
            .filter { !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    /// `obsidian://open?vault=…&file=…` for this note.
    var obsidianURI: URL? {
        Self.obsidianURI(vaultName: vaultName, relativePath: relativePath)
    }

    static func obsidianURI(vaultName: String, relativePath: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        let file = (relativePath as NSString).deletingPathExtension
        guard let vault = vaultName.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedFile = file.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "obsidian://open?vault=\(vault)&file=\(encodedFile)")
    }

    /// A one-paragraph excerpt around the first occurrence of one of `terms`.
    func snippet(around terms: [String], radius: Int = 80) -> String {
        let plain = self.plain
        for term in terms where !term.isEmpty {
            if let match = plain.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                let start = plain.index(match.lowerBound, offsetBy: -radius, limitedBy: plain.startIndex) ?? plain.startIndex
                let end = plain.index(match.upperBound, offsetBy: radius * 2, limitedBy: plain.endIndex) ?? plain.endIndex
                var excerpt = Self.flatten(plain[start..<end])
                if start > plain.startIndex { excerpt = "…" + excerpt }
                if end < plain.endIndex { excerpt += "…" }
                return excerpt
            }
        }
        return Self.flatten(plain.prefix(240))
    }

    /// The note text without Obsidian/Markdown syntax, for excerpts.
    var plain: String {
        var text = content
        let rules: [(String, String)] = [
            (#"%%[\s\S]*?%%"#, ""),
            (#"(?m)^\s*```.*$"#, ""),
            (#"!\[\[[^\]]*\]\]"#, ""),
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"\[\[[^\]|]+\|([^\]]*)\]\]"#, "$1"),
            (#"\[\[([^\]]+)\]\]"#, "$1"),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"(?m)^\s*>\s*\[!\w+\][+-]?"#, ""),
            (#"(?m)^(\s*[-*+]\s+)\[[ xX]\]\s*"#, "$1"),
            (#"(?m)^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#, ""),
            (#"\|"#, " "),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text
    }

    /// Single line without Markdown markup noise (headings, emphasis, highlights, code ticks).
    private static func flatten(_ text: Substring) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .filter { word in !(word.allSatisfy { $0 == "#" } || word == "-" || word == ">") }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\*\*|__|==|`|(?<![\w*])\*(?=\S)|(?<=\S)\*(?![\w*])"#, with: "", options: .regularExpression)
    }

    static func == (lhs: MarkdownFile, rhs: MarkdownFile) -> Bool {
        lhs.path == rhs.path && lhs.modifiedDate == rhs.modifiedDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(modifiedDate)
    }
}
