import SwiftUI

/// One search hit in the sidebar list.
struct ResultRow: View {
    let file: MarkdownFile
    let highlightTerms: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(Highlighter.highlight(file.title, terms: highlightTerms) { $0.font = .headline.weight(.heavy) })
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(file.modifiedDate, format: .dateTime.day().month(.abbreviated).year(.twoDigits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Modified \(file.modifiedDate.formatted(date: .long, time: .omitted))"))
            }

            let snippet = file.snippet(around: highlightTerms)
            if !snippet.isEmpty {
                Text(Highlighter.highlight(snippet, terms: highlightTerms) {
                    $0.foregroundColor = Color.primary
                    $0.font = .callout.weight(.semibold)
                })
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }

            if !file.folder.isEmpty || !file.tags.isEmpty {
                HStack(spacing: 8) {
                    if !file.folder.isEmpty {
                        Label(file.folder, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    if !file.tags.isEmpty {
                        Text(file.tags.prefix(4).map { "#\($0)" }.joined(separator: " "))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Double-click to open in Obsidian"))
    }
}

/// Marks every case- and diacritic-insensitive occurrence of the terms.
enum Highlighter {
    static func highlight(_ text: String, terms: [String], style: (inout AttributedSubstring) -> Void) -> AttributedString {
        var attributed = AttributedString(text)
        apply(to: &attributed, terms: terms, style: style)
        return attributed
    }

    /// Non-overlapping occurrences of all terms, in reading order.
    static func ranges(in attributed: AttributedString, terms: [String]) -> [Range<AttributedString.Index>] {
        var found: [Range<AttributedString.Index>] = []
        for term in terms where !term.isEmpty {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                found.append(range)
                searchStart = range.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var result: [Range<AttributedString.Index>] = []
        for range in found where result.last.map({ range.lowerBound >= $0.upperBound }) ?? true {
            result.append(range)
        }
        return result
    }

    static func apply(to attributed: inout AttributedString, terms: [String], style: (inout AttributedSubstring) -> Void) {
        for term in terms where !term.isEmpty {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                style(&attributed[range])
                searchStart = range.upperBound
            }
        }
    }
}
