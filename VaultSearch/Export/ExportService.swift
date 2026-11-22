import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// Snapshot of what the search window currently shows; published as a focused value
/// so menu commands can export it.
struct ResultsSnapshot {
    let query: String
    let files: [MarkdownFile]
    let highlightTerms: [String]
}

struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Runs exports: save panels, conversion, opening the result and error reporting.
/// The `write…` methods work without any window, for Siri, Shortcuts and AppleScript.
@MainActor
final class ExportService: ObservableObject {
    @Published private(set) var tools = ExternalTools()
    @Published private(set) var isDetectingTools = false
    @Published private(set) var isExporting = false
    @Published var alert: ExportAlert?

    private let settings: AppSettings
    private var toolsTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        toolsTask = Task { await detectTools() }
    }

    func detectTools() async {
        isDetectingTools = true
        tools = await Task.detached(priority: .utility) { ExternalTools.detect() }.value
        isDetectingTools = false
    }

    var isPandocActive: Bool { settings.usePandoc && tools.pandoc != nil }

    func canExport(_ format: ExportFormat) -> Bool {
        !format.requiresPandoc || isPandocActive
    }

    private var converter: DocumentConverter {
        DocumentConverter(options: .init(
            usePandoc: settings.usePandoc,
            tools: tools,
            pdfEngine: settings.pdfEngine,
            wordReference: settings.template(.wordReference),
            odtReference: settings.template(.odtReference),
            stylesheet: settings.template(.stylesheet),
            pandocPDFTemplate: settings.template(.pandocPDFTemplate)
        ))
    }

    /// Short description of how PDFs are made, for the settings.
    var pdfRouteDescription: String {
        if let engine = converter.resolvedPDFEngine { return "Pandoc + \(engine.name)" }
        return isPandocActive ? String(localized: "Pandoc + macOS") : String(localized: "macOS")
    }

    // MARK: Result lists

    /// Saves the result list into the vault, then opens it in Obsidian or reveals it in Finder.
    func saveResultsToVault(_ snapshot: ResultsSnapshot) {
        do {
            let url = try writeResultsToVault(snapshot)
            if settings.openAfterExport {
                openInObsidian(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            report(error)
        }
    }

    func exportResults(_ snapshot: ResultsSnapshot, as format: ExportFormat) {
        guard let output = savePanel(name: ResultListExport.fileName(for: snapshot.query), format: format,
                                     message: String(localized: "Export the result list.")) else { return }
        perform(format, output: output) { try await self.writeResults(snapshot, as: format, to: output) }
    }

    // MARK: Single notes

    /// `highlightTerms` are marked when “Highlight search matches” is on.
    func exportNote(_ file: MarkdownFile, as format: ExportFormat, highlightTerms: [String] = []) {
        guard let output = savePanel(name: file.title, format: format,
                                     message: String(localized: "Export “\(file.title)”.")) else { return }
        perform(format, output: output) { try await self.writeNote(file, as: format, highlightTerms: highlightTerms, to: output) }
    }

    // MARK: Writing without user interface
    // Used by the menu actions above and by Siri, Shortcuts and AppleScript.

    /// Writes the result list as Markdown into the export folder of the vault and returns the new file.
    @discardableResult
    func writeResultsToVault(_ snapshot: ResultsSnapshot) throws -> URL {
        guard let vault = settings.vaultPath else { throw ExportError.noVault }
        let folderPath = settings.exportFolderPath
        let folder = folderPath.isEmpty ? vault : vault.appendingPathComponent(folderPath, isDirectory: true)
        let baseName = ResultListExport.fileName(for: snapshot.query)
        var url = folder.appendingPathComponent(baseName).appendingPathExtension("md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension("md")
            counter += 1
        }

        let markdown = ResultListExport.markdown(
            query: snapshot.query, files: snapshot.files, highlightTerms: snapshot.highlightTerms,
            style: settings.resultPreviewStyle, forVault: true, highlight: settings.highlightMatchesInExport
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Converts the result list to `format` and writes it to `output`.
    func writeResults(_ snapshot: ResultsSnapshot, as format: ExportFormat, to output: URL) async throws {
        let title = ResultListExport.title(for: snapshot.query.trimmingCharacters(in: .whitespaces))
        let markdown = ResultListExport.markdown(
            query: snapshot.query, files: snapshot.files, highlightTerms: snapshot.highlightTerms,
            style: settings.resultPreviewStyle, forVault: false, highlight: settings.highlightMatchesInExport
        )
        // The list already starts with a heading, so the title is only document metadata.
        try await convert(markdown: markdown, title: title, format: format,
                          resources: [settings.vaultPath].compactMap { $0 }, output: output)
    }

    /// Converts one note to `format` and writes it to `output`; Markdown is copied unchanged.
    func writeNote(_ file: MarkdownFile, as format: ExportFormat, highlightTerms: [String] = [], to output: URL) async throws {
        if format == .markdown {
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try FileManager.default.copyItem(at: file.path, to: output)
            return
        }
        let folder = file.path.deletingLastPathComponent()
        let resolver = ObsidianMarkdown.attachmentResolver(vault: settings.vaultPath, near: folder)
        var markdown = ObsidianMarkdown.portable(file.content, resolveAttachment: resolver)
        if settings.highlightMatchesInExport {
            markdown = ObsidianMarkdown.markMatches(markdown, terms: highlightTerms)
        }
        try await convert(markdown: markdown, title: file.title, format: format,
                          resources: [folder, settings.vaultPath].compactMap { $0 }, output: output)
    }

    /// A fresh, empty location in the temporary folder, for exports handed on to Shortcuts.
    nonisolated static func temporaryOutput(name: String, format: ExportFormat) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultSearch Export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
    }

    /// Waits until the search for Pandoc and PDF engines has finished.
    func waitForTools() async {
        await toolsTask?.value
    }

    /// Opens a file inside the vault in Obsidian.
    func openInObsidian(_ url: URL) {
        guard let vault = settings.vaultPath else { return }
        let root = vault.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/"),
              let uri = MarkdownFile.obsidianURI(vaultName: vault.lastPathComponent,
                                                 relativePath: String(path.dropFirst(root.count + 1))) else { return }
        NSWorkspace.shared.open(uri)
    }

    // MARK: Templates

    func chooseTemplate(_ template: ExportTemplate) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = template.allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.template(template)?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportTemplates[template.rawValue] = url.path
        }
    }

    func clearTemplate(_ template: ExportTemplate) {
        settings.exportTemplates[template.rawValue] = nil
    }

    /// Why a template has no effect with the current settings; nil when it is used.
    func inactiveReason(for template: ExportTemplate) -> String? {
        switch template {
        case .stylesheet:
            return nil
        case .wordReference, .odtReference, .pandocPDFTemplate:
            if tools.pandoc == nil { return String(localized: "Not used: Pandoc is not installed.") }
            if !settings.usePandoc { return String(localized: "Not used: Pandoc is turned off.") }
            guard template == .pandocPDFTemplate else { return nil }
            guard let engine = converter.resolvedPDFEngine, engine.isLaTeX || engine.name == "typst" else {
                return String(localized: "Not used: the current PDF engine is not LaTeX or Typst.")
            }
            return nil
        }
    }

    /// Templates already reported as unused in this session, so the hint appears only once.
    private var reportedUnusedTemplates: Set<ExportTemplate> = []

    /// A chosen template that this export could not apply.
    private func unusedTemplate(for format: ExportFormat) -> (ExportTemplate, URL, String)? {
        let template: ExportTemplate
        switch format {
        case .docx: template = .wordReference
        case .odt: template = .odtReference
        case .pdf: template = .pandocPDFTemplate
        default: return nil
        }
        guard let url = settings.template(template), let reason = inactiveReason(for: template),
              !reportedUnusedTemplates.contains(template) else { return nil }
        return (template, url, reason)
    }

    func canCreateDefault(_ template: ExportTemplate) -> Bool {
        switch template {
        case .stylesheet: true
        case .wordReference, .odtReference: tools.pandoc != nil
        case .pandocPDFTemplate: false
        }
    }

    /// Saves a starting point for a template and selects it.
    func createDefaultTemplate(_ template: ExportTemplate) {
        let ext = template.allowedExtensions[0]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VaultSearch Template.\(ext)"
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.message = String(localized: "Save a copy of the default template to customise it.")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                switch template {
                case .stylesheet:
                    guard let source = DocumentConverter.defaultStylesheetURL else { return }
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    try FileManager.default.copyItem(at: source, to: url)
                case .wordReference, .odtReference:
                    guard let pandoc = tools.pandoc else { throw ExportError.pandocRequired }
                    try await DocumentConverter.writeDefaultReference(pandoc: pandoc, fileExtension: ext, to: url)
                case .pandocPDFTemplate:
                    return
                }
                settings.exportTemplates[template.rawValue] = url.path
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                report(error)
            }
        }
    }

    // MARK: Helpers

    private func savePanel(name: String, format: ExportFormat, message: String) -> URL? {
        // Checked before the panel, so nobody picks a location for an export that cannot run.
        guard canExport(format) else {
            report(ExportError.pandocRequired)
            return nil
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func convert(markdown: String, title: String, format: ExportFormat, resources: [URL], output: URL) async throws {
        guard canExport(format) else { throw ExportError.pandocRequired }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try await converter.convert(markdown: markdown, title: title, format: format, resourceFolders: resources, to: output)
    }

    /// Runs an export started from the menus: shows progress, opens the result and reports errors.
    private func perform(_ format: ExportFormat, output: URL, _ write: @escaping () async throws -> Void) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                try await write()
            } catch {
                report(error)
                return
            }
            finish(output)
            if let (template, url, reason) = unusedTemplate(for: format) {
                reportedUnusedTemplates.insert(template)
                alert = ExportAlert(
                    title: String(localized: "Template Not Used"),
                    message: String(localized: "The export was created, but “\(url.lastPathComponent)” was not applied. \(reason) You can change this in Settings ▸ Export.")
                )
            }
        }
    }

    private func finish(_ output: URL) {
        if settings.openAfterExport {
            NSWorkspace.shared.open(output)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([output])
        }
    }

    private func report(_ error: Error) {
        alert = ExportAlert(title: String(localized: "Export Failed"), message: error.localizedDescription)
    }
}
