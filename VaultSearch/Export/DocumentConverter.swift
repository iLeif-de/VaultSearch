import AppKit
import Foundation

/// Converts Markdown into the export formats, with Pandoc when available,
/// otherwise with the HTML/AppKit pipeline built into macOS.
struct DocumentConverter {
    struct Options {
        var usePandoc: Bool
        var tools: ExternalTools
        /// "" = automatic, "builtin" = macOS rendering, otherwise an engine name.
        var pdfEngine: String
        var wordReference: URL?
        var odtReference: URL?
        var stylesheet: URL?
        var pandocPDFTemplate: URL?
    }

    static let builtinEngine = "builtin"

    let options: Options

    static var defaultStylesheetURL: URL? {
        Bundle.main.url(forResource: "ExportStyle", withExtension: "css")
    }

    private var stylesheetURL: URL? { options.stylesheet ?? Self.defaultStylesheetURL }

    private var pandoc: URL? { options.usePandoc ? options.tools.pandoc : nil }

    /// Engine used by Pandoc for PDF, nil means: render PDF with macOS.
    var resolvedPDFEngine: ExternalTools.PDFEngine? {
        guard pandoc != nil, options.pdfEngine != Self.builtinEngine else { return nil }
        if options.pdfEngine.isEmpty { return options.tools.pdfEngines.first }
        return options.tools.pdfEngines.first { $0.name == options.pdfEngine }
    }

    /// `markdown` must already be portable (see `ObsidianMarkdown.portable`).
    @MainActor
    func convert(markdown: String, title: String, format: ExportFormat, resourceFolders: [URL], to output: URL) async throws {
        if format == .markdown {
            try markdown.write(to: output, atomically: true, encoding: .utf8)
            return
        }
        if let pandoc {
            guard format == .pdf else {
                try await runPandoc(pandoc, markdown: markdown, title: title, format: format, engine: nil, resourceFolders: resourceFolders, output: output)
                return
            }
            if let engine = resolvedPDFEngine {
                // ==highlights== need the LaTeX package soul, which minimal TeX installs lack.
                let source = engine.isLaTeX
                    ? markdown.replacingOccurrences(of: #"==(.+?)=="#, with: "**$1**", options: .regularExpression)
                    : markdown
                do {
                    try await runPandoc(pandoc, markdown: source, title: title, format: .pdf, engine: engine, resourceFolders: resourceFolders, output: output)
                    return
                } catch {
                    // An explicitly chosen engine reports its error; the automatic choice falls back to macOS.
                    guard options.pdfEngine.isEmpty else { throw error }
                }
            }
            // Pandoc renders the HTML, macOS paginates it into a PDF.
            let html = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
            defer { try? FileManager.default.removeItem(at: html) }
            try await runPandoc(pandoc, markdown: markdown, title: title, format: .html, engine: nil, resourceFolders: resourceFolders, output: html)
            // AppKit drops <input> elements, so task checkboxes become symbols.
            let rendered = try String(contentsOf: html, encoding: .utf8)
                .replacingOccurrences(of: #"<input type="checkbox"[^>]*checked[^>]*>"#, with: "☑", options: .regularExpression)
                .replacingOccurrences(of: #"<input type="checkbox"[^>]*>"#, with: "☐", options: .regularExpression)
            try Self.renderPDF(html: rendered, baseURL: resourceFolders.first, to: output)
            return
        }

        guard !format.requiresPandoc else { throw ExportError.pandocRequired }
        let css = stylesheetURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let html = ObsidianMarkdown.htmlDocument(title: title, markdown: markdown, css: css)
        switch format {
        case .html:
            try html.write(to: output, atomically: true, encoding: .utf8)
        case .pdf:
            try Self.renderPDF(html: html, baseURL: resourceFolders.first, to: output)
        case .docx, .odt, .rtf:
            var attributed = try Self.attributedString(html: html, baseURL: resourceFolders.first)
            if format == .docx { attributed = Self.emphasizingHighlights(attributed) }
            let type: NSAttributedString.DocumentType = switch format {
            case .docx: .officeOpenXML
            case .odt: .openDocument
            default: .rtf
            }
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: type, .title: title]
            )
            try data.write(to: output)
        case .epub, .markdown:
            throw ExportError.pandocRequired
        }
    }

    // MARK: Pandoc

    private func runPandoc(_ pandoc: URL, markdown: String, title: String, format: ExportFormat,
                           engine: ExternalTools.PDFEngine?, resourceFolders: [URL], output: URL) async throws {
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
        try markdown.write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }

        let startsWithHeading = markdown.drop(while: \.isWhitespace).hasPrefix("# ")
        var arguments = [
            input.path,
            "--from", "markdown+mark+hard_line_breaks-yaml_metadata_block",
            "--standalone",
            "--resource-path", resourceFolders.map(\.path).joined(separator: ":"),
            "--metadata", startsWithHeading ? "pagetitle=\(title)" : "title=\(title)",
            "--output", output.path,
        ]
        if let language = Locale.current.language.languageCode?.identifier {
            arguments += ["--metadata", "lang=\(language)"]
        }
        if format != .pdf { arguments += ["--to", format.pandocWriter] }

        let css = stylesheetURL?.path
        switch format {
        case .html:
            arguments.append(options.tools.pandocMajorVersion >= 3 ? "--embed-resources" : "--self-contained")
            if let css { arguments += ["--css", css] }
        case .epub:
            if let css { arguments += ["--css", css] }
        case .docx:
            if let reference = options.wordReference { arguments += ["--reference-doc", reference.path] }
        case .odt:
            if let reference = options.odtReference { arguments += ["--reference-doc", reference.path] }
        case .pdf:
            guard let engine else { break }
            arguments += ["--pdf-engine", engine.url.path]
            if engine.isHTMLBased, let css { arguments += ["--css", css] }
            if engine.isLaTeX { arguments += ["--variable", "geometry:margin=2.2cm"] }
            if let template = options.pandocPDFTemplate {
                let ext = template.pathExtension.lowercased()
                let fits = (engine.isLaTeX && ["tex", "latex"].contains(ext))
                    || (engine.name == "typst" && ext == "typ")
                    || (engine.isHTMLBased && ext == "html")
                if fits { arguments += ["--template", template.path] }
            }
        case .rtf, .markdown:
            break
        }

        let workingDirectory = resourceFolders.first
        let result = try await Task.detached(priority: .userInitiated) {
            try ProcessRunner.run(pandoc, arguments, currentDirectory: workingDirectory)
        }.value
        guard result.status == 0 else {
            let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ExportError.pandocFailed(String(message.suffix(800)))
        }
    }

    /// Writes Pandoc's default reference document (docx/odt) for customising in Word or Pages.
    static func writeDefaultReference(pandoc: URL, fileExtension: String, to url: URL) async throws {
        let result = try await Task.detached {
            try ProcessRunner.run(pandoc, ["--output", url.path, "--print-default-data-file", "reference.\(fileExtension)"])
        }.value
        guard result.status == 0 else { throw ExportError.pandocFailed(result.errorOutput) }
    }

    // MARK: Built-in (AppKit)

    @MainActor
    static func attributedString(html: String, baseURL: URL?) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let baseURL { options[.baseURL] = baseURL }
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            throw ExportError.conversionFailed(String(localized: "The document could not be converted."))
        }
        return attributed
    }

    /// AppKit's Word writer drops background colours, so highlighted text (<mark>)
    /// is additionally set bold and underlined to stay visible.
    @MainActor
    static func emphasizingHighlights(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.backgroundColor, in: whole) { value, range, _ in
            guard value != nil else { return }
            result.enumerateAttribute(.font, in: range) { font, fontRange, _ in
                if let font = font as? NSFont {
                    result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: fontRange)
                }
            }
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: range)
            result.addAttribute(.underlineColor, value: NSColor(red: 1, green: 0.42, blue: 0.36, alpha: 1), range: range)
        }
        return result
    }

    /// Paginated A4/Letter PDF (from the default printer settings) via AppKit's print system.
    @MainActor
    static func renderPDF(html: String, baseURL: URL?, to output: URL) throws {
        let attributed = try attributedString(html: html, baseURL: baseURL)

        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        for margin in [\NSPrintInfo.topMargin, \.bottomMargin] { printInfo[keyPath: margin] = 56 }
        for margin in [\NSPrintInfo.leftMargin, \.rightMargin] { printInfo[keyPath: margin] = 62 }
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.textStorage?.setAttributedString(attributed)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw ExportError.conversionFailed(String(localized: "The PDF could not be created."))
        }
    }
}
