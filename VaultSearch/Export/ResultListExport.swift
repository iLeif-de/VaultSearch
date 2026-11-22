import Foundation

/// Builds the Markdown document for an exported result list.
enum ResultListExport {
    /// `forVault`: Obsidian wikilinks, embeds and frontmatter; otherwise portable Markdown.
    /// `heading` replaces “Search: query” for lists that do not come from a search.
    static func markdown(query: String, files: [MarkdownFile], highlightTerms: [String],
                         style: ResultPreviewStyle, forVault: Bool, highlight: Bool,
                         heading: String? = nil, date: Date = .now) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        var lines: [String] = []

        if forVault {
            lines += [
                "---",
                "type: vaultsearch-export",
                "query: \"\(trimmedQuery.replacingOccurrences(of: "\"", with: "\\\""))\"",
                "exported: \(format(date, "yyyy-MM-dd'T'HH:mm"))",
                "results: \(files.count)",
                "tags:",
                "  - vaultsearch",
                "---",
                "",
            ]
        }

        lines.append("# \(heading ?? title(for: trimmedQuery))")
        lines.append("")
        let count = files.count == 1 ? String(localized: "1 note") : String(localized: "\(files.count) notes")
        lines.append("*\(count) · \(date.formatted(date: .long, time: .shortened))*")
        if !trimmedQuery.isEmpty {
            lines.append("")
            lines.append("`\(trimmedQuery.replacingOccurrences(of: "`", with: "'"))`")
        }

        let effectiveStyle: ResultPreviewStyle = (style == .embed && !forVault) ? .excerpt : style
        for file in files {
            lines.append("")
            let linkTarget = (file.relativePath as NSString).deletingPathExtension
            if forVault {
                lines.append("## [[\(linkTarget)|\(file.title)]]")
            } else {
                lines.append("## \(file.title)")
            }

            var meta: [String] = []
            if !file.folder.isEmpty { meta.append(file.folder) }
            meta.append(file.modifiedDate.formatted(date: .abbreviated, time: .omitted))
            if !file.tags.isEmpty {
                // In the vault "#tag" stays clickable; elsewhere plain names read better.
                meta.append(file.tags.map { forVault ? "#\($0)" : $0 }.joined(separator: forVault ? " " : ", "))
            }
            lines.append("")
            lines.append(meta.joined(separator: " · "))

            switch effectiveStyle {
            case .excerpt:
                var snippet = file.snippet(around: highlightTerms)
                if highlight {
                    // Obsidian, Pandoc and the built-in conversion show ==text== highlighted.
                    snippet = ObsidianMarkdown.markMatches(snippet, terms: highlightTerms)
                }
                if !snippet.isEmpty {
                    lines.append("")
                    lines.append("> \(snippet)")
                }
            case .embed:
                lines.append("")
                lines.append("![[\(linkTarget)]]")
            case .linksOnly:
                break
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Fixed-format local date, independent of the user's locale.
    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    static func title(for query: String) -> String {
        query.isEmpty ? String(localized: "Recently Modified Notes") : String(localized: "Search: \(query)")
    }

    /// File name without extension, safe for Finder and Obsidian links.
    static func fileName(for query: String, date: Date = .now) -> String {
        let stamp = format(date, "yyyy-MM-dd HHmm")
        let cleaned = query
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|#^[]`"))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let label = cleaned.isEmpty ? String(localized: "Recent") : String(cleaned.prefix(60))
        return "VaultSearch \(stamp) – \(label)"
    }
}
