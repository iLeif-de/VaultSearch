import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf, docx, odt, rtf, html, epub, markdown

    var id: Self { self }

    var menuTitle: String {
        switch self {
        case .pdf: String(localized: "PDF…")
        case .docx: String(localized: "Word Document…")
        case .odt: String(localized: "OpenDocument Text…")
        case .rtf: String(localized: "Rich Text…")
        case .html: String(localized: "Web Page…")
        case .epub: String(localized: "EPUB…")
        case .markdown: String(localized: "Markdown…")
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        default: rawValue
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .data
    }

    /// Formats the built-in macOS conversion cannot produce.
    var requiresPandoc: Bool { self == .epub }

    var pandocWriter: String {
        switch self {
        case .pdf, .html: "html"
        case .markdown: "markdown"
        default: rawValue
        }
    }
}

enum ExportError: LocalizedError {
    case pandocRequired
    case pandocFailed(String)
    case conversionFailed(String)
    case noVault

    var errorDescription: String? {
        switch self {
        case .pandocRequired:
            String(localized: "This format requires Pandoc. Install it with “brew install pandoc”.")
        case .pandocFailed(let message):
            String(localized: "Pandoc reported an error:\n\(message)")
        case .conversionFailed(let message):
            message
        case .noVault:
            String(localized: "Choose a vault first.")
        }
    }
}
