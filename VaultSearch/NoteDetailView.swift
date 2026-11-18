import SwiftUI
import AppKit

/// Read-only preview of the selected note. Matches are highlighted, the view jumps to
/// the first one, and a find bar steps through them (⌘G / ⇧⌘G).
struct NoteDetailView: View {
    let file: MarkdownFile
    let highlightTerms: [String]
    var onSelectTag: (String) -> Void = { _ in }
    @EnvironmentObject private var exporter: ExportService

    @State private var lines: [AttributedString] = []
    @State private var findText = ""
    @State private var currentMatch = 0
    @State private var isFindBarVisible = false
    @FocusState private var isFindFocused: Bool

    private struct Match: Hashable {
        let line: Int
        let ordinal: Int
    }

    /// Text typed into the find bar takes precedence over the terms of the vault search.
    private var activeTerms: [String] {
        let typed = findText.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? highlightTerms : [typed]
    }

    private var matches: [Match] {
        let terms = activeTerms
        guard !terms.isEmpty else { return [] }
        return lines.indices.flatMap { index in
            Highlighter.ranges(in: lines[index], terms: terms).indices.map { Match(line: index, ordinal: $0) }
        }
    }

    var body: some View {
        let matches = self.matches
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 18)
                        .id(-1)
                    Divider()
                        .padding(.bottom, 18)
                    ForEach(lines.indices, id: \.self) { index in
                        Text(styledLine(index, matches: matches))
                            .font(.body)
                            .lineSpacing(4)
                            .padding(.vertical, 1.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isFindBarVisible || !highlightTerms.isEmpty {
                    findBar(matchCount: matches.count)
                }
            }
            .task(id: file) {
                lines = MarkdownPreview.lines(file.content)
                currentMatch = 0
                // Give the lazy stack a moment to lay out before jumping to the first match.
                try? await Task.sleep(for: .milliseconds(60))
                scrollToCurrent(proxy, anchorTop: true)
            }
            .onChange(of: activeTerms) {
                currentMatch = 0
                scrollToCurrent(proxy, anchorTop: true)
            }
            .onChange(of: currentMatch) {
                scrollToCurrent(proxy, anchorTop: false)
            }
        }
        .focusedSceneValue(\.noteFind, NoteFindActions(
            focus: { isFindBarVisible = true; isFindFocused = true },
            next: { step(1) },
            previous: { step(-1) }
        ))
        .navigationTitle(file.title)
        .navigationSubtitle(file.folder.isEmpty ? file.vaultName : file.folder)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NoteActions.showInFinder(file)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show in Finder (⌥⌘R)")

                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.menuTitle) { exporter.exportNote(file, as: format, highlightTerms: activeTerms) }
                            .disabled(!exporter.canExport(format))
                    }
                } label: {
                    Label("Export Note", systemImage: "doc.badge.arrow.up")
                }
                .help("Export this note as PDF, Word and more")
                .disabled(exporter.isExporting)

                ShareLink(item: file.path)
                    .help("Share note")

                Button {
                    NoteActions.openInObsidian(file)
                } label: {
                    Label("Open in Obsidian", systemImage: "arrow.up.forward.app")
                }
                .help("Open in Obsidian (⌘↩)")
            }
        }
    }

    // MARK: Find

    private func findBar(matchCount: Int) -> some View {
        HStack(spacing: 8) {
            TextField("Find in Note", text: $findText,
                      prompt: highlightTerms.isEmpty ? Text("Find in Note") : Text(verbatim: highlightTerms.joined(separator: " ")))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($isFindFocused)
                .onSubmit { step(1) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    step(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    closeFindBar()
                    return .handled
                }

            Group {
                if activeTerms.isEmpty {
                    Text(verbatim: "")
                } else if matchCount == 0 {
                    Text("No matches")
                } else {
                    Text("\(min(currentMatch, matchCount - 1) + 1) of \(matchCount)")
                }
            }
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityAddTraits(.updatesFrequently)

            ControlGroup {
                Button { step(-1) } label: { Label("Previous Match", systemImage: "chevron.up") }
                    .help("Previous match (⇧⌘G)")
                Button { step(1) } label: { Label("Next Match", systemImage: "chevron.down") }
                    .help("Next match (⌘G)")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
            .disabled(matchCount < 2)

            Spacer()

            Button("Done") { closeFindBar() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func step(_ delta: Int) {
        let count = matches.count
        guard count > 0 else { return }
        currentMatch = (currentMatch + delta + count) % count
    }

    private func closeFindBar() {
        findText = ""
        isFindFocused = false
        isFindBarVisible = false
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, anchorTop: Bool) {
        let matches = self.matches
        guard matches.indices.contains(currentMatch) else {
            if anchorTop { proxy.scrollTo(-1, anchor: .top) }
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(matches[currentMatch].line, anchor: .center)
        }
    }

    /// The line with all matches marked; the current one in the system find colour.
    private func styledLine(_ index: Int, matches: [Match]) -> AttributedString {
        var line = lines[index]
        let ranges = Highlighter.ranges(in: line, terms: activeTerms)
        guard !ranges.isEmpty else { return line }
        let current = matches.indices.contains(currentMatch) ? matches[currentMatch] : nil
        for (ordinal, range) in ranges.enumerated() {
            if current == Match(line: index, ordinal: ordinal) {
                line[range].backgroundColor = Color(nsColor: .findHighlightColor)
                line[range].foregroundColor = Color.black
            } else {
                line[range].backgroundColor = Color(nsColor: .findHighlightColor).opacity(0.35)
            }
        }
        return line
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.title)
                .font(.largeTitle.weight(.bold))
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !file.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(file.tags, id: \.self) { tag in
                        Button("#\(tag)") { onSelectTag(tag) }
                            .buttonStyle(TagButtonStyle())
                            .help("Search for notes tagged #\(tag)")
                    }
                }
            }

            let properties = file.displayProperties
            if !properties.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
                    ForEach(properties, id: \.key) { property in
                        GridRow {
                            Text(property.key)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(property.value)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder private var metadata: some View {
        Label("Created \(file.createdLabel)", systemImage: "calendar")
        Label {
            Text("Modified \(file.modifiedDate.formatted(.relative(presentation: .named)))")
        } icon: {
            Image(systemName: "clock")
        }
        Label(file.relativePath, systemImage: "doc.text")
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// Lightweight Markdown rendering for the preview: headings, lists, quotes,
/// code blocks and inline formatting. Not a full CommonMark renderer.
enum MarkdownPreview {
    /// One attributed string per source line, so the preview can scroll to a line.
    static func lines(_ markdown: String) -> [AttributedString] {
        var result: [AttributedString] = []
        var inCodeBlock = false

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            var output = AttributedString()
            defer { result.append(output.characters.isEmpty ? AttributedString(" ") : output) }

            if inCodeBlock {
                var code = AttributedString(line)
                code.font = .system(.body, design: .monospaced)
                code.foregroundColor = Color.secondary
                output.append(code)
                continue
            }

            let level = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(level), trimmed.dropFirst(level).first == " " {
                var heading = inline(String(trimmed.dropFirst(level + 1)))
                heading.font = [Font.title.bold(), .title2.bold(), .title3.bold(), .headline, .headline, .headline][level - 1]
                output.append(heading)
                continue
            }

            let indent = String(repeating: "    ", count: (line.prefix(while: { $0 == " " || $0 == "\t" }).count) / 2)
            if ["- [ ]", "- [x]", "- [X]"].contains(where: { trimmed == $0 || trimmed.hasPrefix($0 + " ") }) {
                let done = !trimmed.hasPrefix("- [ ]")
                output.append(AttributedString(indent + (done ? "☑︎  " : "☐  ")))
                var task = inline(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                if done {
                    task.strikethroughStyle = .single
                    task.foregroundColor = Color.secondary
                }
                output.append(task)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                output.append(AttributedString(indent + "•  "))
                output.append(inline(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix(">") {
                var text = String(trimmed.dropFirst().drop(while: { $0 == " " }))
                output.append(AttributedString("▎ "))
                // Callout header "[!note] Title" → bold "Note" label
                if let match = text.range(of: #"^\[!(\w+)\][+-]?\s*"#, options: .regularExpression) {
                    let kind = text[match].dropFirst(2).prefix(while: { $0 != "]" })
                    var label = AttributedString(kind.capitalized + " ")
                    label.font = Font.body.bold()
                    output.append(label)
                    text = String(text[match.upperBound...])
                }
                var quote = inline(text)
                quote.foregroundColor = Color.secondary
                output.append(quote)
            } else if trimmed == "---" || trimmed == "***" {
                var rule = AttributedString(String(repeating: "─", count: 24))
                rule.foregroundColor = Color.secondary
                output.append(rule)
            } else {
                output.append(inline(line))
            }
        }
        return result
    }

    private static func inline(_ text: String) -> AttributedString {
        // [[target|alias]] → alias, [[target]] → target; %%comments%% are hidden like in Obsidian.
        let prepared = text
            .replacingOccurrences(of: #"%%.*?%%"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"!?\[\[[^\]|]+\|([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"!?\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
    }
}

private struct TagButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(.tint)
            .background(.tint.opacity(configuration.isPressed ? 0.24 : 0.12), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Wraps its subviews onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, maxWidth: bounds.width)
        for (subview, origin) in zip(subviews, layout.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}
