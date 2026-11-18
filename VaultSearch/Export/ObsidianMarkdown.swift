import Foundation

/// Turns Obsidian-flavoured Markdown into portable Markdown and, for the
/// built-in conversion, into simple HTML.
enum ObsidianMarkdown {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tif", "tiff", "bmp"]

    /// Resolves `%%comments%%`, `![[embeds]]` and `[[wikilinks]]`.
    /// `==highlights==` stay, both Pandoc (`+mark`) and `html(fromMarkdown:)` understand them.
    static func portable(_ markdown: String, resolveAttachment: (String) -> URL?) -> String {
        var text = markdown.replacingOccurrences(of: #"%%[\s\S]*?%%"#, with: "", options: .regularExpression)

        text = replace(#"!\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]"#, in: text) { groups in
            let target = groups[1].trimmingCharacters(in: .whitespaces)
            let ext = (target as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext), let url = resolveAttachment(target) {
                let alt = groups.count > 2 && !groups[2].isEmpty && Int(groups[2]) == nil ? groups[2] : ""
                return "![\(alt)](<\(url.path)>)"
            }
            return "*\((target as NSString).deletingPathExtension)*"
        }

        text = replace(#"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]"#, in: text) { groups in
            if groups.count > 2, !groups[2].isEmpty { return groups[2] }
            let target = groups[1].replacingOccurrences(of: "#", with: " › ")
            return (target as NSString).lastPathComponent
        }

        // Callouts "> [!note] Title" → "> **Note** Title"
        text = replace(#"(?m)^(\s*>\s*)\[!(\w+)\][+-]?[ \t]*"#, in: text) { groups in
            "\(groups[1])**\(groups[2].capitalized)** "
        }
        return text
    }

    /// Wraps the search terms in `==…==`. Code, link targets, URLs, HTML tags and
    /// existing highlights stay untouched, so the Markdown keeps working.
    static func markMatches(_ markdown: String, terms: [String]) -> String {
        let terms = terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return markdown }
        let alternatives = terms.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let termRegex = try? NSRegularExpression(pattern: alternatives, options: [.caseInsensitive]),
              let protected = try? NSRegularExpression(pattern: #"`[^`]*`|\]\([^)]*\)|<[^>]*>|https?://\S+|==.+?==|\[\[[^\]]*\]\]"#)
        else { return markdown }

        var output: [String] = []
        var inCodeBlock = false
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCodeBlock.toggle() }
            if inCodeBlock || line.hasPrefix("    ") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                output.append(line)
                continue
            }
            let ns = line as NSString
            var result = ""
            var last = 0
            func markPlain(_ range: NSRange) {
                let plain = ns.substring(with: range)
                result += termRegex.stringByReplacingMatches(in: plain, range: NSRange(location: 0, length: (plain as NSString).length), withTemplate: "==$0==")
            }
            for match in protected.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                markPlain(NSRange(location: last, length: match.range.location - last))
                result += ns.substring(with: match.range)
                last = match.range.location + match.range.length
            }
            markPlain(NSRange(location: last, length: ns.length - last))
            output.append(result)
        }
        return output.joined(separator: "\n")
    }

    /// Finds attachments by file name anywhere in the vault (Obsidian's shortest-path links).
    static func attachmentResolver(vault: URL?, near folder: URL) -> (String) -> URL? {
        var index: [String: URL]?
        return { name in
            let direct = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            if let vault {
                let inVault = vault.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: inVault.path) { return inVault }
                if index == nil {
                    var built: [String: URL] = [:]
                    if let enumerator = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for case let url as URL in enumerator where url.pathExtension.lowercased() != "md" {
                            let key = url.lastPathComponent.lowercased()
                            if built[key] == nil { built[key] = url }
                        }
                    }
                    index = built
                }
                return index?[(name as NSString).lastPathComponent.lowercased()]
            }
            return nil
        }
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: Built-in Markdown → HTML

    /// Complete HTML document for the built-in conversion.
    static func htmlDocument(title: String, markdown: String, css: String) -> String {
        let body = html(fromMarkdown: markdown)
        let startsWithHeading = markdown.drop(while: \.isWhitespace).hasPrefix("# ")
        let heading = startsWithHeading ? "" : "<h1>\(escape(title))</h1>\n"
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>\(css)</style></head>
        <body>
        \(heading)\(body)
        </body></html>
        """
    }

    /// Block-level conversion: headings, paragraphs, lists, tasks, quotes, code, rules, tables.
    static func html(fromMarkdown markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listTag: String?
        var quote: [String] = []
        var code: [String]?
        var table: [[String]] = []

        func flushParagraph() {
            if !paragraph.isEmpty { html.append("<p>\(paragraph.map(inline).joined(separator: "<br>\n"))</p>") }
            paragraph = []
        }
        func flushList() {
            if let tag = listTag { html.append("</\(tag)>") }
            listTag = nil
        }
        func flushQuote() {
            if !quote.isEmpty { html.append("<blockquote><p>\(quote.map(inline).joined(separator: "<br>\n"))</p></blockquote>") }
            quote = []
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            var rows = ["<table>"]
            for (index, cells) in table.enumerated() {
                let tag = index == 0 ? "th" : "td"
                rows.append("<tr>" + cells.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>")
            }
            rows.append("</table>")
            html.append(rows.joined(separator: "\n"))
            table = []
        }
        func flushAll() { flushParagraph(); flushList(); flushQuote(); flushTable() }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if code != nil {
                if trimmed.hasPrefix("```") {
                    html.append("<pre><code>\(code!.map(escape).joined(separator: "\n"))</code></pre>")
                    code = nil
                } else {
                    code!.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") { flushAll(); code = []; continue }

            if trimmed.isEmpty { flushAll(); continue }

            if trimmed.hasPrefix("|") {
                flushParagraph(); flushList(); flushQuote()
                let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if !cells.allSatisfy({ $0.allSatisfy { "-:".contains($0) } && !$0.isEmpty }) { table.append(cells) }
                continue
            }
            flushTable()

            let level = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(level), trimmed.dropFirst(level).first == " " {
                flushAll()
                html.append("<h\(level)>\(inline(String(trimmed.dropFirst(level + 1))))</h\(level)>")
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll(); html.append("<hr>"); continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph(); flushList()
                let content = String(trimmed.dropFirst().drop(while: { $0 == " " }))
                // Obsidian callout header "[!note] Title"
                quote.append(content.replacingOccurrences(of: #"^\[!(\w+)\][+-]?\s*"#, with: "**$1** ", options: .regularExpression))
                continue
            }

            var item: (tag: String, text: String)?
            if let match = trimmed.range(of: #"^[-*+] "#, options: .regularExpression) {
                item = ("ul", String(trimmed[match.upperBound...]))
            } else if let match = trimmed.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                item = ("ol", String(trimmed[match.upperBound...]))
            }
            if let item {
                flushParagraph(); flushQuote()
                if listTag != item.tag { flushList(); html.append("<\(item.tag)>"); listTag = item.tag }
                var text = inline(item.text)
                let taskText = String(item.text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if item.text.hasPrefix("[ ] ") || item.text == "[ ]" {
                    text = "☐ " + inline(taskText)
                } else if item.text.lowercased().hasPrefix("[x]") {
                    text = "☑ <del>" + inline(taskText) + "</del>"
                }
                html.append("<li>\(text)</li>")
                continue
            }

            flushList(); flushQuote()
            paragraph.append(trimmed)
        }
        if let code { html.append("<pre><code>\(code.map(escape).joined(separator: "\n"))</code></pre>") }
        flushAll()
        return html.joined(separator: "\n")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func inline(_ text: String) -> String {
        // Protect code spans first, then escape and apply emphasis.
        var codes: [String] = []
        var working = replace("`([^`]+)`", in: text) { groups in
            codes.append("<code>\(escape(groups[1]))</code>")
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        working = replace(#"!\[([^\]]*)\]\(<?([^)>]+)>?\)"#, in: working) { groups in
            let source = groups[2].hasPrefix("/") ? URL(fileURLWithPath: groups[2]).absoluteString : groups[2]
            codes.append("<img src=\"\(escape(source))\" alt=\"\(escape(groups[1]))\">")
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        working = escape(working)
        let rules: [(String, String)] = [
            (#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>"),
            (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
            (#"__(.+?)__"#, "<strong>$1</strong>"),
            (#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, "<em>$1</em>"),
            (#"==(.+?)=="#, "<mark>$1</mark>"),
            (#"~~(.+?)~~"#, "<del>$1</del>"),
        ]
        for (pattern, template) in rules {
            working = working.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return replace("\u{1}(\\d+)\u{1}", in: working) { codes[Int($0[1]) ?? 0] }
    }
}
