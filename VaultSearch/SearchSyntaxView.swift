import SwiftUI

/// Help window listing the search operators (Help ▸ Search Syntax, ⌘?).
struct SearchSyntaxView: View {
    private struct Entry: Identifiable {
        let syntax: String
        let meaning: LocalizedStringKey
        var id: String { syntax }
    }

    private let sections: [(title: LocalizedStringKey, entries: [Entry])] = [
        ("Text", [
            Entry(syntax: "meeting notes", meaning: "Notes containing both words in title, text or tags"),
            Entry(syntax: "\"meeting notes\"", meaning: "Exact phrase"),
            Entry(syntax: "idea OR tag:idea", meaning: "Either: OR / ODER separates alternatives (upper case)"),
        ]),
        ("Tags and Properties", [
            Entry(syntax: "tag:idea", meaning: "Frontmatter tag at any level: also finds idea/later and project/idea, closest first"),
            Entry(syntax: "contenttag:idea", meaning: "#idea, #project/idea or [[idea]] in the note text"),
            Entry(syntax: "status:active", meaning: "Any frontmatter property containing the value"),
        ]),
        ("Dates", [
            Entry(syntax: "created:2025-04-28", meaning: "Created on a day (also 28.04.25)"),
            Entry(syntax: "modified:>=2025-04-01", meaning: "Operators >=, >, <=, <"),
            Entry(syntax: "created:today", meaning: "today, yesterday"),
            Entry(syntax: "modified:this week", meaning: "this week, this month, this year"),
            Entry(syntax: "created:last month", meaning: "Previous week, month or year"),
            Entry(syntax: "modified:last 7 days", meaning: "Rolling period in days, weeks, months or years"),
            Entry(syntax: "erstellt:letzte 7 Tage", meaning: "German works too: erstellt:, geändert:, heute, gestern, diese Woche, letzter Monat"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                Section(section.title) {
                    ForEach(section.entries) { entry in
                        LabeledContent {
                            Text(entry.meaning)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text(entry.syntax)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section {
                Text("Terms separated by spaces must all match; OR separates alternatives, like in Obsidian: tag:project budget OR tag:idea.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }
}

#Preview {
    SearchSyntaxView()
}
