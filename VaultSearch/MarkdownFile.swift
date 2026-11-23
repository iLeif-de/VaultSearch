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
    /// Creation and modification date: the frontmatter value (`erstellt`/`created`,
    /// `geändert`/`modified`) when there is one, otherwise the date of the file.
    /// Display, search, sorting and Shortcuts all use these.
    let createdDate: Date
    let modifiedDate: Date
    /// Dates of the file itself, for change detection.
    let fileCreatedDate: Date
    let fileModifiedDate: Date
    /// Frontmatter keys whose dates were used above, nil when the file date is used.
    let createdDateKey: String?
    let modifiedDateKey: String?
    /// Both keys; the frontmatter rows of the preview leave them out.
    var dateKeys: Set<String> { Set([createdDateKey, modifiedDateKey].compactMap { $0 }) }
    let vaultName: String

    static let createdKeys = ["erstellt", "created"]
    static let modifiedKeys = ["geändert", "geaendert", "modified", "updated"]

    /// `createdDate` and `modifiedDate` are the dates of the file.
    init(path: URL, relativePath: String, content: String, frontmatter: [String: Any],
         tags: [String], createdDate: Date, modifiedDate: Date, vaultName: String) {
        self.path = path
        self.relativePath = relativePath
        self.title = path.deletingPathExtension().lastPathComponent
        self.content = content
        self.frontmatter = frontmatter
        self.tags = tags
        self.fileCreatedDate = createdDate
        self.fileModifiedDate = modifiedDate
        self.vaultName = vaultName

        func date(_ keys: [String], fallback: Date) -> (Date, String?) {
            for (key, value) in frontmatter where keys.contains(key.lowercased()) {
                guard let text = value as? String, let parsed = FrontmatterDate.parse(text, fileDate: fallback) else { continue }
                return (parsed, key)
            }
            return (fallback, nil)
        }
        (self.createdDate, self.createdDateKey) = date(Self.createdKeys, fallback: createdDate)
        (self.modifiedDate, self.modifiedDateKey) = date(Self.modifiedKeys, fallback: modifiedDate)
    }

    /// Folder inside the vault, empty for notes at the root.
    var folder: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// One row of the property box in the preview. Every value can carry a search.
    struct DisplayProperty: Identifiable {
        struct Value: Hashable {
            let text: String
            /// The search a click puts into the search field; nil when it cannot be written as a search.
            let query: String?
        }

        let key: String
        let values: [Value]
        var separator = ", "
        var id: String { key }

        /// A frontmatter property; each value searches for `key:value`.
        static func frontmatter(key: String, values: [String]) -> DisplayProperty {
            DisplayProperty(key: key, values: values.map { Value(text: $0, query: query(key: key, value: $0)) })
        }

        /// `key:value`, or nil when the key has spaces or other characters, or is an operator such as `tag`.
        static func query(key: String, value: String) -> String? {
            guard key.first?.isLetter == true,
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
                  !SearchQuery.operatorKeys.contains(key.lowercased()) else { return nil }
            return "\(key):" + SearchSuggestion.quoted(value.replacingOccurrences(of: "\"", with: ""))
        }
    }

    /// The rows of the property box: creation and modification date, the folder path, then the
    /// frontmatter. Dates and folders search with `erstellt:`, `geändert:` and `pfad:`.
    var previewProperties: [DisplayProperty] {
        func dateRow(_ field: SearchQuery.DateField, _ date: Date, frontmatterKey: String?) -> DisplayProperty {
            let searchKey = SearchSuggestion.dateKey(field)
            let day = FrontmatterDate.day(date)
            return DisplayProperty(key: frontmatterKey ?? String(searchKey.dropLast()),
                                   values: [.init(text: day, query: searchKey + day)])
        }
        var rows = [
            dateRow(.created, createdDate, frontmatterKey: createdDateKey),
            dateRow(.modified, modifiedDate, frontmatterKey: modifiedDateKey),
        ]
        if !folder.isEmpty {
            let parts = folder.split(separator: "/").map(String.init)
            let values = parts.indices.map { index in
                let prefix = parts[...index].joined(separator: "/")
                return DisplayProperty.Value(text: parts[index], query: SearchSuggestion.pathKey + SearchSuggestion.quoted(prefix))
            }
            rows.append(DisplayProperty(key: String(SearchSuggestion.pathKey.dropLast()), values: values, separator: " / "))
        }
        return rows + displayProperties
    }

    /// Frontmatter entries for the preview. Leaves out tags (shown as buttons), the dates and a
    /// folder property that only repeats the folder of the note; `previewProperties` shows those.
    var displayProperties: [DisplayProperty] {
        frontmatter
            .filter { entry in
                let key = entry.key.lowercased()
                if key == "tags" || dateKeys.contains(entry.key) { return false }
                if ["ordner", "folder"].contains(key), let value = entry.value as? String,
                   value.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) == folder {
                    return false
                }
                return true
            }
            .map { entry in
                let values = (entry.value as? [String]) ?? [String(describing: entry.value)]
                return DisplayProperty.frontmatter(key: entry.key, values: values.filter { !$0.isEmpty })
            }
            .filter { !$0.values.isEmpty }
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
        lhs.path == rhs.path && lhs.fileModifiedDate == rhs.fileModifiedDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(fileModifiedDate)
    }
}

/// Dates written in the frontmatter, e.g. `2026-09-14`, `2026-09-14T10:30` or `14.09.2026`.
enum FrontmatterDate {
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "dd.MM.yyyy HH:mm", "dd.MM.yyyy",
    ]

    private static let formatters: [DateFormatter] = formats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    /// `2026-09-14` in the local time zone, as shown in the preview and understood by the search.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Only these shapes are read; DateFormatter alone would also accept e.g. `14/09/2026`.
    private static let shapes = [
        #"^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?([+-]\d{2}:?\d{2}|Z)?)?$"#,
        #"^\d{1,2}\.\d{1,2}\.\d{4}( \d{1,2}:\d{2})?$"#,
    ]

    /// A value without time on the same day as `fileDate` returns `fileDate`, which is more precise.
    static func parse(_ text: String, fileDate: Date, calendar: Calendar = .current) -> Date? {
        let text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespaces))
        guard shapes.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) else { return nil }
        for (format, formatter) in zip(formats, formatters) {
            let formatter = formatter.timeZone == calendar.timeZone ? formatter : {
                let copy = formatter.copy() as! DateFormatter
                copy.timeZone = calendar.timeZone
                return copy
            }()
            guard let date = formatter.date(from: text) else { continue }
            if !format.contains("HH") && calendar.isDate(date, inSameDayAs: fileDate) { return fileDate }
            return date
        }
        return nil
    }
}
