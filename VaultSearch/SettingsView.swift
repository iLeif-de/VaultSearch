import SwiftUI

/// Content of the Settings window (⌘,).
struct SettingsView: View {
    private enum Tab: Hashable { case general, export }
    @State private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ExportSettingsView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                .tag(Tab.export)
        }
        .frame(width: 540)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var search: SearchService

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Folder") {
                    HStack {
                        if let url = settings.vaultPath {
                            Label(url.lastPathComponent, systemImage: "folder")
                                .help(url.path)
                        } else {
                            Text("None").foregroundStyle(.secondary)
                        }
                        Button("Choose…") { model.chooseVault() }
                    }
                }

                LabeledContent("Index") {
                    HStack {
                        Text(indexSummary)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Reindex Now") { search.reindex() }
                            .disabled(settings.vaultPath == nil || search.isIndexing)
                    }
                }
            }

            Section {
                if settings.excludedFolders.isEmpty {
                    Text("No folders excluded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedFolders.sorted(), id: \.self) { folder in
                    HStack {
                        Label(folder, systemImage: "folder.badge.minus")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder)
                        Spacer()
                        Button {
                            settings.excludedFolders.remove(folder)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove \(folder)"))
                        .help("Search this folder again")
                    }
                }
                Button("Add Folder…", systemImage: "plus") { model.addExcludedFolder() }
                    .disabled(settings.vaultPath == nil)
            } header: {
                Text("Excluded Folders")
            } footer: {
                Text("Notes in these folders are not searched. Hidden folders such as .obsidian and .trash and the export folder are always skipped.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }

    private var indexSummary: String {
        if search.isIndexing { return String(localized: "Indexing…") }
        guard let date = search.lastIndexed else { return String(localized: "Not indexed") }
        return String(localized: "\(search.files.count) notes · \(date.formatted(date: .omitted, time: .shortened))")
    }
}

private struct ExportSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var exporter: ExportService

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder in Vault") {
                    HStack {
                        TextField("Folder in Vault", text: $settings.exportFolder, prompt: Text("Vault root"))
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        Button("Choose…") { model.chooseExportFolder() }
                            .disabled(settings.vaultPath == nil)
                    }
                }
                Picker("Preview", selection: $settings.resultPreviewStyle) {
                    Text("Excerpt with Matches").tag(ResultPreviewStyle.excerpt)
                    Text("Embedded Note (Obsidian)").tag(ResultPreviewStyle.embed)
                    Text("Links Only").tag(ResultPreviewStyle.linksOnly)
                }
                Toggle("Open exported files", isOn: $settings.openAfterExport)
                Toggle("Highlight search matches", isOn: $settings.highlightMatchesInExport)
            } header: {
                Text("Result Lists")
            } footer: {
                Text("“Save Results to Vault” (⇧⌘E) writes a Markdown note with links to every hit. Embedded notes show the full note in Obsidian; other formats use the excerpt. Highlighting marks the search terms in result lists and exported notes.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Pandoc") {
                    if let version = exporter.tools.pandocVersion, let path = exporter.tools.pandoc?.path {
                        Text("\(version) · \(path)")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if exporter.isDetectingTools {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack {
                            Text("Not installed").foregroundStyle(.secondary)
                            Button("Copy Install Command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install pandoc", forType: .string)
                            }
                            .help("brew install pandoc")
                        }
                    }
                }
                Toggle("Use Pandoc for conversion", isOn: $settings.usePandoc)
                    .disabled(exporter.tools.pandoc == nil)

                Picker("PDF Engine", selection: $settings.pdfEngine) {
                    Text("Automatic").tag("")
                    Text("macOS (no Pandoc)").tag(DocumentConverter.builtinEngine)
                    if !exporter.tools.pdfEngines.isEmpty { Divider() }
                    ForEach(exporter.tools.pdfEngines) { engine in
                        (engine.name == "prince" ? Text("prince (watermark in free edition)") : Text(verbatim: engine.name)).tag(engine.name)
                    }
                }
                .disabled(!exporter.isPandocActive)

                LabeledContent("PDFs are made with") {
                    Text(exporter.pdfRouteDescription).foregroundStyle(.secondary)
                }

                Button("Check for Tools Again") {
                    Task { await exporter.detectTools() }
                }
                .disabled(exporter.isDetectingTools)
            } header: {
                Text("Conversion")
            } footer: {
                Text("Without Pandoc, VaultSearch converts with macOS: PDF, Word, OpenDocument, Rich Text and HTML. EPUB requires Pandoc. Install PDF engines such as typst, tectonic or weasyprint with Homebrew.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TemplateRow(title: "Word Reference", usage: "Word exports made with Pandoc.", template: .wordReference)
                TemplateRow(title: "OpenDocument Reference", usage: "OpenDocument exports made with Pandoc.", template: .odtReference)
                TemplateRow(title: "Stylesheet (CSS)", usage: "Every format without Pandoc. With Pandoc: HTML, EPUB and PDFs made with macOS or an HTML engine.", template: .stylesheet)
                TemplateRow(title: "Pandoc PDF Template", usage: "PDFs made with a LaTeX or Typst engine (.tex or .typ).", template: .pandocPDFTemplate)
            } header: {
                Text("Templates")
            } footer: {
Text("Reference documents define the paragraph and heading styles that Pandoc uses for Word and OpenDocument; edit the styles in Word or Pages, not the text. Without Pandoc every format is rendered from HTML, so only the stylesheet applies. “Create from Default…” saves a copy of the built-in template as a starting point and selects it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
    }
}

private struct TemplateRow: View {
    let title: LocalizedStringKey
    let usage: LocalizedStringKey
    let template: ExportTemplate
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var exporter: ExportService

    var body: some View {
        LabeledContent {
            controls
        } label: {
            Text(title)
            Text(usage)
            if let reason = exporter.inactiveReason(for: template) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var controls: some View {
            HStack(spacing: 8) {
                if let url = settings.template(template) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                    Button {
                        exporter.clearTemplate(template)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Use the default template"))
                    .help("Use the default template")
                } else {
                    Text("Default").foregroundStyle(.secondary)
                }
                Menu {
                    Button("Choose File…") { exporter.chooseTemplate(template) }
                    if exporter.canCreateDefault(template) {
                        Button("Create from Default…") { exporter.createDefaultTemplate(template) }
                    }
                    if let url = settings.template(template) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                } label: {
                    Text("Edit")
                }
                .fixedSize()
            }
    }
}
