import Foundation

/// Completions shown below the search field while typing.
struct SearchSuggestion: Identifiable {
    let title: String
    let detail: String?
    let systemImage: String
    /// The full search text after choosing this suggestion.
    let completion: String

    var id: String { completion }

    static let datePresets = [
        "today", "yesterday", "this week", "this month", "this year",
        "last week", "last month", "last 7 days", "last 30 days",
    ]

    private static let germanPresets: [String: String] = [
        "today": "heute", "yesterday": "gestern",
        "this week": "diese Woche", "this month": "dieser Monat", "this year": "dieses Jahr",
        "last week": "letzte Woche", "last month": "letzter Monat",
        "last 7 days": "letzte 7 Tage", "last 30 days": "letzte 30 Tage",
    ]

    /// True when the app runs with its German localization; search tokens are then written in German.
    static var usesGerman: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true
    }

    /// `pfad:` or `path:`, depending on the UI language.
    static var pathKey: String { usesGerman ? "pfad:" : "path:" }

    static func dateKey(_ field: SearchQuery.DateField) -> String {
        switch field {
        case .created: usesGerman ? "erstellt:" : "created:"
        case .modified: usesGerman ? "geändert:" : "modified:"
        }
    }

    /// A date filter token in the UI language, e.g. `created:last 7 days` or `erstellt:letzte 7 Tage`.
    static func dateToken(_ field: SearchQuery.DateField, _ preset: String) -> String {
        dateKey(field) + (usesGerman ? germanPresets[preset] ?? preset : preset)
    }

    static func quoted(_ value: String) -> String {
        value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
    }

    static func suggestions(for text: String, tags: [String], properties: [String]) -> [SearchSuggestion] {
        // Only the word currently being typed is completed.
        let head: Substring
        let current: Substring
        if let space = text.lastIndex(where: \.isWhitespace) {
            head = text[...space]
            current = text[text.index(after: space)...]
        } else {
            head = ""
            current = Substring(text)
        }
        let lowered = current.lowercased()
        guard !lowered.isEmpty else { return [] }

        func suggestion(_ token: String, title: String, detail: String? = nil, image: String) -> SearchSuggestion {
            SearchSuggestion(title: title, detail: detail, systemImage: image, completion: head + token)
        }

        if lowered.hasPrefix("tag:") {
            // Matches at any level of nested tags; tags starting with the input come first.
            let prefix = String(lowered.dropFirst(4).trimmingPrefix("#"))
            let ranked = tags.compactMap { tag -> (String, Int)? in
                let lowerTag = tag.lowercased()
                if prefix.isEmpty || lowerTag.hasPrefix(prefix) { return (tag, 0) }
                if lowerTag.split(separator: "/").dropFirst().contains(where: { $0.hasPrefix(prefix) }) { return (tag, 1) }
                return nil
            }
            return ranked
                .enumerated()
                .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                .prefix(8)
                .map { suggestion("tag:\(quoted($0.element.0)) ", title: "#\($0.element.0)", image: "number") }
        }

        let dateKeys: [(String, Bool, Bool)] = [  // key, isCreated, isGerman
            ("created:", true, false), ("modified:", false, false),
            ("erstellt:", true, true), ("geändert:", false, true), ("geaendert:", false, true),
        ]
        for (key, isCreated, isGerman) in dateKeys where lowered.hasPrefix(key) {
            let value = lowered.dropFirst(key.count)
            let presets = isGerman ? datePresets.compactMap { germanPresets[$0] } : datePresets
            let typedKey = String(current.prefix(key.count))
            return presets
                .filter { $0.lowercased().hasPrefix(value) && $0.lowercased() != value }
                .map { suggestion("\(typedKey)\($0) ", title: "\(typedKey)\($0)", image: isCreated ? "calendar" : "clock") }
        }

        let operators: [(token: String, detail: String, image: String)] = [
            ("tag:", String(localized: "Frontmatter tag"), "number"),
            (dateKey(.created), String(localized: "Creation date"), "calendar"),
            (dateKey(.modified), String(localized: "Last modified"), "clock"),
            ("contenttag:", String(localized: "#tag or [[link]] in the text"), "link"),
            (usesGerman ? "imtitel:" : "intitle:", String(localized: "Only in the title"), "textformat"),
            (usesGerman ? "imtext:" : "intext:", String(localized: "Only in the text"), "text.alignleft"),
            (pathKey, String(localized: "Folder and its subfolders"), "folder"),
        ] + properties.map { ("\($0.lowercased()):", String(localized: "Property"), "list.bullet.rectangle") }

        var seen = Set<String>()
        return operators
            .filter { $0.token.hasPrefix(lowered) && $0.token != lowered && seen.insert($0.token).inserted }
            .prefix(6)
            .map { suggestion($0.token, title: $0.token, detail: $0.detail, image: $0.image) }
    }
}
