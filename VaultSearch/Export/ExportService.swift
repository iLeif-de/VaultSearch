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
@MainActor
final class ExportService: ObservableObject {
    @Published private(set) var tools = ExternalTools()
    @Published private(set) var isDetectingTools = false
    @Published private(set) var isExporting = false
    @Published var alert: ExportAlert?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        Task { await detectTools() }
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

    /// Writes the result list as Markdown into the export folder of the vault.
    func saveResultsToVault(_ snapshot: ResultsSnapshot) {
        guard let vault = settings.vaultPath else {
            report(ExportError.noVault)
            return
        }
        let folderPath = settings.exportFolderPath
        let folder = folderPath.isEmpty ? vault : vault.appendingPathComponent(folderPath, isDirectory: true)
        var name = ResultListExport.fileName(for: snapshot.query)
        var url = folder.appendingPathComponent(name).appendingPathExtension("md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "\(ResultListExport.fileName(for: snapshot.query)) \(counter)"
            url = folder.appendingPathComponent(name).appendingPathExtension("md")
            counter += 1
        }

        let markdown = ResultListExport.markdown(
            query: snapshot.query, files: snapshot.files, highlightTerms: snapshot.highlightTerms,
            style: settings.resultPreviewStyle, forVault: true, highlight: settings.highlightMatchesInExport
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            report(error)
            return
        }

        if settings.openAfterExport {
            let relative = folderPath.isEmpty ? name : "\(folderPath)/\(name)"
            if let uri = MarkdownFile.obsidianURI(vaultName: vault.lastPathComponent, relativePath: relative + ".md") {
                NSWorkspace.shared.open(uri)
            }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func exportResults(_ snapshot: ResultsSnapshot, as format: ExportFormat) {
        let title = ResultListExport.title(for: snapshot.query.trimmingCharacters(in: .whitespaces))
        guard let output = savePanel(name: ResultListExport.fileName(for: snapshot.query), format: format,
                                     message: String(localized: "Export the result list.")) else { return }
        let markdown = ResultListExport.markdown(
            query: snapshot.query, files: snapshot.files, highlightTerms: snapshot.highlightTerms,
            style: settings.resultPreviewStyle, forVault: false, highlight: settings.highlightMatchesInExport
        )
        // The list already starts with a heading, so the title is only document metadata.
        run(markdown: markdown, title: title, format: format, resources: [settings.vaultPath].compactMap { $0 }, output: output)
    }

    // MARK: Single notes

    /// `highlightTerms` are marked when “Highlight search matches” is on.
    func exportNote(_ file: MarkdownFile, as format: ExportFormat, highlightTerms: [String] = []) {
        guard let output = savePanel(name: file.title, format: format,
                                     message: String(localized: "Export “\(file.title)”.")) else { return }
        if format == .markdown {
            do {
                if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
                try FileManager.default.copyItem(at: file.path, to: output)
                finish(output)
            } catch {
                report(error)
            }
            return
        }
        let folder = file.path.deletingLastPathComponent()
        let resolver = ObsidianMarkdown.attachmentResolver(vault: settings.vaultPath, near: folder)
        var markdown = ObsidianMarkdown.portable(file.content, resolveAttachment: resolver)
        if settings.highlightMatchesInExport {
            markdown = ObsidianMarkdown.markMatches(markdown, terms: highlightTerms)
        }
        let resources = [folder, settings.vaultPath].compactMap { $0 }
        run(markdown: markdown, title: file.title, format: format, resources: resources, output: output)
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

    private func run(markdown: String, title: String, format: ExportFormat, resources: [URL], output: URL) {
        isExporting = true
        let converter = self.converter
        Task {
            defer { isExporting = false }
            do {
                if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
                try await converter.convert(markdown: markdown, title: title, format: format, resourceFolders: resources, to: output)
                finish(output)
                if let (template, url, reason) = unusedTemplate(for: format) {
                    reportedUnusedTemplates.insert(template)
                    alert = ExportAlert(
                        title: String(localized: "Template Not Used"),
                        message: String(localized: "The export was created, but “\(url.lastPathComponent)” was not applied. \(reason) You can change this in Settings ▸ Export.")
                    )
                }
            } catch {
                report(error)
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
