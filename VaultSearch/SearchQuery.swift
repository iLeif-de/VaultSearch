import Foundation

/// Parses the search field text into terms and matches notes against them.
///
/// Terms separated by spaces must all match (AND). `OR` / `ODER` (upper case) separates
/// alternatives, like Obsidian: `meeting work OR tag:idea` = (meeting AND work) OR tag:idea.
/// `AND` / `UND` may be written explicitly.
///
/// - `word`, `"exact phrase"`: title or content contains the text
/// - `intitle:word` / `intext:word` (German: `imtitel:` / `imtext:`): only the title, only the content
/// - `tag:name`: frontmatter tag at any level of the hierarchy: `name`, `name/…`
///   and `…/name`; closer matches are ranked first (see `tagScore`)
/// - `contenttag:name`: `#name`, `#…/name` or `[[name]]` in the note body
/// - `created:` / `modified:` (German: `erstellt:` / `geändert:`) with `2025-04-28`,
///   `28.04.25`, `today`, `yesterday`, `this week|month|year`, `last week|month|year`,
///   `last 7 days` (German: `heute`, `gestern`, `diese Woche`, `letzte 7 Tage`, …)
///   and the operators `>=`, `>`, `<=`, `<`
/// - `property:value`: any other frontmatter property contains the value
struct SearchQuery {
    enum DateField { case created, modified }
    enum DateOperator { case on, onOrAfter, after, onOrBefore, before }

    enum Term {
        case text(String)
        case titleText(String)
        case bodyText(String)
        case tag(String)
        case contentTag(String)
        case property(key: String, value: String)
        /// `range` is nil when the date could not be parsed; such a term matches nothing.
        case date(DateField, DateOperator, ClosedRange<Date>?)
    }

    /// Alternatives (OR) of term groups (AND).
    let groups: [[Term]]
    private let calendar: Calendar

    static let orOperators: Set<String> = ["OR", "ODER", "|"]
    /// Keys with a meaning of their own; `key:value` with them is not a property search.
    static let operatorKeys: Set<String> = [
        "tag", "contenttag", "intitle", "intext", "imtitel", "imtext",
        "created", "erstellt", "modified", "geändert", "geaendert",
    ]
    static let andOperators: Set<String> = ["AND", "UND", "&"]

    init(_ text: String, now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        var groups: [[Term]] = [[]]
        for token in Self.tokenize(text) {
            if Self.orOperators.contains(token) {
                groups.append([])
            } else if Self.andOperators.contains(token) {
                continue
            } else if token.hasSuffix(":") && token.dropLast().allSatisfy(\.isLetter) {
                continue  // a bare `key:` is still being typed; ignoring it keeps the results stable
            } else {
                groups[groups.count - 1].append(Self.term(for: token, now: now, calendar: calendar))
            }
        }
        self.groups = groups.filter { !$0.isEmpty }
    }

    /// All terms of all alternatives.
    var terms: [Term] { groups.flatMap { $0 } }

    var isEmpty: Bool { groups.isEmpty }

    /// Plain text terms, used to highlight matches and to rank title hits.
    var textTerms: [String] {
        terms.compactMap {
            switch $0 {
            case .text(let text), .titleText(let text), .bodyText(let text): text
            default: nil
            }
        }
    }

    // MARK: Matching

    /// Matching notes, ranked by: closeness of tag matches, title hit, then most recently modified.
    func run(on files: [MarkdownFile]) -> [MarkdownFile] {
        let texts = textTerms
        let tagTerms = terms.compactMap { if case .tag(let tag) = $0 { tag } else { nil } }
        return files
            .filter(matches)
            .map { file -> (file: MarkdownFile, rank: [Int]) in
                let tagRank = tagTerms.reduce(0) { sum, query in
                    sum + (file.tags.map { Self.tagScore(tag: $0, query: query) }.max() ?? 0)
                }
                let titleHit = texts.contains { file.title.localizedStandardContains($0) } ? 1 : 0
                return (file, [tagRank, titleHit])
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank.lexicographicallyPrecedes(rhs.rank, by: >) }
                return lhs.file.modifiedDate > rhs.file.modifiedDate
            }
            .map(\.file)
    }

    /// How closely a (possibly nested) tag matches the searched tag; 0 means no match.
    /// - 3: the tag itself (`idea`)
    /// - 2: a child of it (`idea/later`)
    /// - 1: the searched tag deeper in the hierarchy (`project/idea`, `project/idea/later`)
    ///
    /// The query may itself be a path (`project/idea`).
    static func tagScore(tag: String, query: String) -> Int {
        let tag = tag.lowercased()
        let query = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/#"))
        guard !query.isEmpty else { return 0 }
        if tag == query { return 3 }
        if tag.hasPrefix(query + "/") { return 2 }
        if ("/" + tag + "/").contains("/" + query + "/") { return 1 }
        return 0
    }

    func matches(_ file: MarkdownFile) -> Bool {
        groups.contains { group in group.allSatisfy { matches(file, term: $0) } }
    }

    private func matches(_ file: MarkdownFile, term: Term) -> Bool {
            switch term {
            case .text(let text):
                return file.title.localizedStandardContains(text) || file.content.localizedStandardContains(text)
            case .titleText(let text):
                return file.title.localizedStandardContains(text)
            case .bodyText(let text):
                return file.content.localizedStandardContains(text)
            case .tag(let tag):
                return file.tags.contains { Self.tagScore(tag: $0, query: tag) > 0 }
            case .contentTag(let tag):
                return file.content.localizedStandardContains("[[\(tag)]]")
                    || file.content.range(of: Self.inlineTagPattern(tag), options: [.regularExpression, .caseInsensitive]) != nil
            case .property(let key, let value):
                guard let entry = file.frontmatter.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
                    return false
                }
                let stored = (entry.value as? [String])?.joined(separator: " ") ?? String(describing: entry.value)
                return stored.localizedStandardContains(value)
            case .date(let field, let op, let range):
                guard let range else { return false }
                let day = calendar.startOfDay(for: field == .created ? file.createdDate : file.modifiedDate)
                switch op {
                case .on: return range.contains(day)
                case .onOrAfter: return day >= range.lowerBound
                case .after: return day > range.upperBound
                case .onOrBefore: return day <= range.upperBound
                case .before: return day < range.lowerBound
                }
            }
    }

    /// `#tag`, `#tag/child` or `#parent/tag` in the text, but not `#tags`.
    private static func inlineTagPattern(_ tag: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: tag.trimmingCharacters(in: CharacterSet(charactersIn: "#/")))
        return #"(?<![\p{L}\p{N}_/-])#(?:[\p{L}\p{N}_-]+/)*"# + name + #"(?![\p{L}\p{N}_-])"#
    }

    // MARK: Parsing

    private static let relativeDateWords: Set<String> = [
        "day", "days", "week", "weeks", "month", "months", "year", "years",
        "tag", "tage", "tagen", "woche", "wochen", "monat", "monate", "monaten", "jahr", "jahre", "jahren",
    ]

    /// Words that start a multi-word relative date ("this week", "letzte 7 Tage").
    private static let relativeDateStarts: Set<String> = [
        "this", "last", "diese", "dieser", "dieses", "letzte", "letzter", "letztes", "letzten",
    ]

    /// German date words, mapped to the English canonical form.
    private static let germanDateWords: [String: String] = [
        "heute": "today", "gestern": "yesterday",
        "diese": "this", "dieser": "this", "dieses": "this",
        "letzte": "last", "letzter": "last", "letztes": "last", "letzten": "last",
        "tag": "day", "tage": "days", "tagen": "days",
        "woche": "week", "wochen": "weeks",
        "monat": "month", "monate": "months", "monaten": "months",
        "jahr": "year", "jahre": "years", "jahren": "years",
    ]

    /// Splits on whitespace outside quotes, strips the quotes and keeps
    /// multi-word dates such as `created:last 7 days` together.
    static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
            } else if character.isWhitespace && !inQuotes {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }

        var tokens: [String] = []
        var index = 0
        while index < words.count {
            var token = words[index]
            index += 1
            if let (_, value) = dateKey(of: token) {
                let lowered = value.lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "<>="))
                if relativeDateStarts.contains(lowered) {
                    while index < words.count,
                          relativeDateWords.contains(words[index].lowercased()) || Int(words[index]) != nil {
                        token += " " + words[index]
                        index += 1
                    }
                }
            }
            tokens.append(token)
        }
        return tokens
    }

    private static func dateKey(of token: String) -> (DateField, Substring)? {
        let lowered = token.lowercased()
        for (prefix, field) in [("created:", DateField.created), ("erstellt:", .created),
                                ("modified:", .modified), ("geändert:", .modified), ("geaendert:", .modified)]
        where lowered.hasPrefix(prefix) {
            return (field, token.dropFirst(prefix.count))
        }
        return nil
    }

    private static func term(for token: String, now: Date, calendar: Calendar) -> Term {
        let lowered = token.lowercased()
        if lowered.hasPrefix("tag:"), token.count > 4 {
            return .tag(String(token.dropFirst(4)).trimmingPrefix("#").description)
        }
        for (prefix, make) in [("intitle:", Term.titleText), ("imtitel:", Term.titleText),
                               ("intext:", Term.bodyText), ("imtext:", Term.bodyText)]
        where lowered.hasPrefix(prefix) && token.count > prefix.count {
            return make(String(token.dropFirst(prefix.count)))
        }
        if lowered.hasPrefix("contenttag:"), token.count > 11 {
            return .contentTag(String(token.dropFirst(11)).trimmingPrefix("#").description)
        }
        if let (field, value) = dateKey(of: token), !value.isEmpty {
            let (op, rest) = dateOperator(value)
            return .date(field, op, dateRange(String(rest).trimmingCharacters(in: .whitespaces), now: now, calendar: calendar))
        }
        if let colon = token.firstIndex(of: ":"), colon != token.startIndex {
            let key = token[..<colon]
            let value = token[token.index(after: colon)...]
            if !value.isEmpty, key.first?.isLetter == true,
               key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                return .property(key: String(key), value: String(value))
            }
        }
        return .text(token)
    }

    private static func dateOperator(_ value: Substring) -> (DateOperator, Substring) {
        if value.hasPrefix(">=") { return (.onOrAfter, value.dropFirst(2)) }
        if value.hasPrefix("<=") { return (.onOrBefore, value.dropFirst(2)) }
        if value.hasPrefix(">") { return (.after, value.dropFirst()) }
        if value.hasPrefix("<") { return (.before, value.dropFirst()) }
        return (.on, value)
    }

    /// Pattern → format. Picked by pattern because DateFormatter parses leniently
    /// (`yyyy-MM-dd` would accept `28.04.25` as year 28). `yy` also reads four-digit years.
    private static let dateFormats = [
        (#"^\d{4}-\d{1,2}-\d{1,2}$"#, "yyyy-MM-dd"),
        (#"^\d{1,2}\.\d{1,2}\.(\d{2}|\d{4})$"#, "dd.MM.yy"),
    ]

    /// Range of whole days (start of day for both bounds) described by `value`.
    static func dateRange(_ value: String, now: Date, calendar: Calendar) -> ClosedRange<Date>? {
        let today = calendar.startOfDay(for: now)
        func days(_ offset: Int, from date: Date = today) -> Date {
            calendar.date(byAdding: .day, value: offset, to: date)!
        }
        func period(_ component: Calendar.Component, containing date: Date) -> ClosedRange<Date>? {
            guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
            return interval.start...days(-1, from: interval.end)
        }
        func current(_ component: Calendar.Component) -> ClosedRange<Date>? {
            guard let interval = calendar.dateInterval(of: component, for: today) else { return nil }
            return interval.start...today
        }

        let lowered = value.lowercased().split(separator: " ")
            .map { germanDateWords[String($0)] ?? String($0) }
            .joined(separator: " ")
        switch lowered {
        case "today": return today...today
        case "yesterday": return days(-1)...days(-1)
        case "this week": return current(.weekOfYear)
        case "this month": return current(.month)
        case "this year": return current(.year)
        case "last week": return period(.weekOfYear, containing: days(-7))
        case "last month": return calendar.date(byAdding: .month, value: -1, to: today).flatMap { period(.month, containing: $0) }
        case "last year": return calendar.date(byAdding: .year, value: -1, to: today).flatMap { period(.year, containing: $0) }
        default: break
        }

        let parts = lowered.split(separator: " ")
        if parts.count == 3, parts[0] == "last", let count = Int(parts[1]), count > 0 {
            let start: Date?
            switch parts[2].hasSuffix("s") ? String(parts[2].dropLast()) : String(parts[2]) {
            case "day": start = days(-(count - 1))
            case "week": start = days(-(count * 7 - 1))
            case "month": start = calendar.date(byAdding: .month, value: -count, to: today)
            case "year": start = calendar.date(byAdding: .year, value: -count, to: today)
            default: start = nil
            }
            return start.map { $0...today }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (pattern, format) in dateFormats where value.range(of: pattern, options: .regularExpression) != nil {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                let day = calendar.startOfDay(for: date)
                return day...day
            }
        }
        return nil
    }
}
