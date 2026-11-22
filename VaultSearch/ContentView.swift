//
//  ContentView.swift
//  VaultSearch
//
//  Created by Leif Jensen-Pistorius on 27.04.25.
//

import AppIntents
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var search: SearchService
    @EnvironmentObject private var exporter: ExportService
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var results: [MarkdownFile] = []
    @State private var selection: MarkdownFile.ID?
    /// The query the current results belong to; a new query selects its top hit.
    @State private var resultsQuery: String?
    @State private var showingDateFilter = false
    @FocusState private var isSearchFocused: Bool

    private var query: SearchQuery { SearchQuery(searchText) }

    private var suggestions: [SearchSuggestion] {
        SearchSuggestion.suggestions(for: searchText, tags: search.knownTags, properties: search.knownProperties)
    }

    private var selectedFile: MarkdownFile? {
        results.first { $0.id == selection } ?? search.file(with: selection)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 560)
        } detail: {
            detail
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search notes, tag:, created:…"))
        .searchFocused($isSearchFocused)
        .searchSuggestions {
            ForEach(suggestions) { suggestion in
                SuggestionRow(suggestion: suggestion)
                    .searchCompletion(suggestion.completion)
            }
        }
        .onSubmit(of: .search) {
            if let first = results.first { selection = first.id }
        }
        .task(id: SearchKey(text: searchText, generation: search.generation)) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let found = await search.results(for: searchText)
            guard !Task.isCancelled else { return }
            results = found
            // A new query shows its top hit; a re-index keeps the note the user is reading.
            let isNewQuery = resultsQuery != searchText
            resultsQuery = searchText
            if isNewQuery || selection == nil || !found.contains(where: { $0.id == selection }) {
                selection = found.first?.id
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                exportMenu
                reindexButton
            }
        }
        .sheet(isPresented: $showingDateFilter) {
            DateFilterView { addFilter($0) }
        }
        .navigationTitle(settings.vaultPath?.lastPathComponent ?? "VaultSearch")
        .focusedSceneValue(\.selectedNote, selectedFile)
        .focusedSceneValue(\.focusSearch, FocusSearchAction { isSearchFocused = true })
        .focusedSceneValue(\.searchResults, resultsSnapshot)
        .alert(item: $exporter.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .task {
            if settings.vaultPath != nil { isSearchFocused = true }
            takeRequestedSearch()
        }
        .onChange(of: model.requestedSearch) { takeRequestedSearch() }
    }

    /// Takes over a search from Siri or Shortcuts; the first window to see it wins.
    private func takeRequestedSearch() {
        guard let text = model.requestedSearch else { return }
        model.requestedSearch = nil
        searchText = text
    }

    // MARK: Sidebar

    @ViewBuilder private var sidebar: some View {
        if settings.vaultPath == nil {
            ContentUnavailableView {
                Label("No Vault Selected", systemImage: "books.vertical")
            } description: {
                Text("Choose the folder of your Obsidian vault to start searching.")
            } actions: {
                Button("Choose Vault…") { model.chooseVault() }
                    .buttonStyle(.borderedProminent)
            }
        } else if search.files.isEmpty, search.isIndexing {
            IndexingView(progress: search.progress)
        } else if search.files.isEmpty, let error = search.indexError {
            ContentUnavailableView {
                Label("Vault Not Available", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Choose Vault…") { model.chooseVault() }
            }
        } else {
            resultList
        }
    }

    private var resultList: some View {
        List(selection: $selection) {
            Section {
                ForEach(results) { file in
                    ResultRow(file: file, highlightTerms: query.textTerms)
                        .tag(file.id)
                }
            } header: {
                searchText.isEmpty ? Text("Recently Modified") : Text("Top Hits")
            }
        }
        .contextMenu(forSelectionType: MarkdownFile.ID.self) { ids in
            if let file = search.file(with: ids.first) {
                NoteMenuItems(file: file, highlightTerms: query.textTerms)
            }
        } primaryAction: { ids in
            if let file = search.file(with: ids.first) {
                NoteActions.openInObsidian(file)
            }
        }
        .overlay {
            if results.isEmpty, !searchText.isEmpty, !search.isIndexing {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(
                resultCount: results.count, noteCount: search.files.count,
                isSearching: !searchText.isEmpty, isIndexing: search.isIndexing, progress: search.progress,
                isExporting: exporter.isExporting
            )
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let file = selectedFile {
            NoteDetailView(file: file, highlightTerms: query.textTerms) { tag in
                searchText = "tag:\(SearchSuggestion.quoted(tag))"
            }
            // Tells Siri which note is on screen, so “open this in Obsidian” works.
            .appEntityIdentifier(EntityIdentifier(for: NoteEntity.self, identifier: file.path.path))
        } else {
            ContentUnavailableView {
                Label("No Note Selected", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Select a result to preview it. Double-click it or press ⌘↩ to open it in Obsidian.")
            }
        }
    }

    // MARK: Toolbar

    private var filterMenu: some View {
        Menu {
            Section("Created") {
                filterButton("Today", SearchSuggestion.dateToken(.created, "today"))
                filterButton("This Week", SearchSuggestion.dateToken(.created, "this week"))
                filterButton("This Month", SearchSuggestion.dateToken(.created, "this month"))
                filterButton("Last 30 Days", SearchSuggestion.dateToken(.created, "last 30 days"))
            }
            Section("Modified") {
                filterButton("Today", SearchSuggestion.dateToken(.modified, "today"))
                filterButton("Last 7 Days", SearchSuggestion.dateToken(.modified, "last 7 days"))
                filterButton("This Month", SearchSuggestion.dateToken(.modified, "this month"))
            }
            Button("Custom Date Range…") { showingDateFilter = true }
                .keyboardShortcut("d")
            if !search.knownTags.isEmpty {
                Divider()
                Menu("Tag") {
                    ForEach(search.knownTags.prefix(40), id: \.self) { tag in
                        filterButton("#\(tag)", "tag:\(SearchSuggestion.quoted(tag))")
                    }
                }
            }
            Divider()
            Button("Clear Search") { searchText = "" }
                .disabled(searchText.isEmpty)
            Button("Search Syntax…") { openWindow(id: WindowID.syntax) }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Add a filter to the search")
        .disabled(settings.vaultPath == nil)
    }

    private var resultsSnapshot: ResultsSnapshot {
        ResultsSnapshot(query: searchText, files: results, highlightTerms: query.textTerms)
    }

    private var exportMenu: some View {
        Menu {
            ResultsExportItems(snapshot: resultsSnapshot, exporter: exporter)
            Divider()
            NoteExportMenu(file: selectedFile, exporter: exporter, highlightTerms: query.textTerms)
        } label: {
            Label("Export", systemImage: "square.and.arrow.down.on.square")
        }
        .help("Save the results to your vault or export them (⇧⌘E)")
        .disabled(settings.vaultPath == nil || exporter.isExporting)
    }

    private func filterButton(_ title: LocalizedStringKey, _ token: String) -> some View {
        Button(title) { addFilter(token) }
    }

    private var reindexButton: some View {
        Button {
            search.reindex()
        } label: {
            Label("Reindex Vault", systemImage: "arrow.clockwise")
        }
        .help("Read all notes of the vault again (⌘R)")
        .disabled(settings.vaultPath == nil || search.isIndexing)
    }

    private func addFilter(_ token: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        searchText = trimmed.isEmpty ? token : "\(trimmed) \(token)"
        isSearchFocused = true
    }
}

private struct SearchKey: Equatable {
    let text: String
    let generation: Int
}

// MARK: - Sidebar pieces

private struct SuggestionRow: View {
    let suggestion: SearchSuggestion

    var body: some View {
        HStack {
            Label(suggestion.title, systemImage: suggestion.systemImage)
            if let detail = suggestion.detail {
                Spacer()
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private struct IndexingView: View {
    let progress: SearchService.Progress?

    var body: some View {
        VStack(spacing: 12) {
            if let progress, progress.total > 0 {
                ProgressView(value: Double(progress.done), total: Double(progress.total))
                    .frame(maxWidth: 220)
                Text("Indexing \(progress.done) of \(progress.total) notes…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
                Text("Reading vault…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusBar: View {
    let resultCount: Int
    let noteCount: Int
    let isSearching: Bool
    let isIndexing: Bool
    let progress: SearchService.Progress?
    let isExporting: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isExporting {
                ProgressView().controlSize(.small)
                Text("Exporting…")
            } else if isIndexing {
                ProgressView().controlSize(.small)
                if let progress, progress.total > 0 {
                    Text("Updating index… \(progress.done) of \(progress.total)")
                } else {
                    Text("Updating index…")
                }
            } else if isSearching {
                Text("\(resultCount) of \(noteCount) notes")
            } else {
                Text("\(noteCount) notes")
            }
            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
