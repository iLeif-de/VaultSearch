import Foundation

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: Vault

    @Published var vaultPath: URL? {
        didSet { defaults.set(vaultPath?.path, forKey: "vaultPath") }
    }

    @Published var excludedFolders: Set<String> {
        didSet { defaults.set(Array(excludedFolders), forKey: "excludedFolders") }
    }

    // MARK: Export

    /// Folder inside the vault for exported result lists, relative to the vault root.
    @Published var exportFolder: String {
        didSet { defaults.set(exportFolder, forKey: "exportFolder") }
    }

    @Published var resultPreviewStyle: ResultPreviewStyle {
        didSet { defaults.set(resultPreviewStyle.rawValue, forKey: "resultPreviewStyle") }
    }

    @Published var openAfterExport: Bool {
        didSet { defaults.set(openAfterExport, forKey: "openAfterExport") }
    }

    /// Marks the search terms (==term==) in exported notes and result lists.
    @Published var highlightMatchesInExport: Bool {
        didSet { defaults.set(highlightMatchesInExport, forKey: "highlightMatchesInExport") }
    }

    /// Use Pandoc when it is installed; otherwise the built-in macOS conversion.
    @Published var usePandoc: Bool {
        didSet { defaults.set(usePandoc, forKey: "usePandoc") }
    }

    /// Name of the PDF engine for Pandoc; empty means automatic.
    @Published var pdfEngine: String {
        didSet { defaults.set(pdfEngine, forKey: "pdfEngine") }
    }

    /// Template file paths keyed by `ExportTemplate.rawValue`.
    @Published var exportTemplates: [String: String] {
        didSet { defaults.set(exportTemplates, forKey: "exportTemplates") }
    }

    init() {
        vaultPath = defaults.string(forKey: "vaultPath").map { URL(fileURLWithPath: $0) }
        excludedFolders = Set(defaults.stringArray(forKey: "excludedFolders") ?? [])
        exportFolder = defaults.string(forKey: "exportFolder") ?? "VaultSearch Exports"
        resultPreviewStyle = defaults.string(forKey: "resultPreviewStyle").flatMap(ResultPreviewStyle.init) ?? .excerpt
        openAfterExport = defaults.object(forKey: "openAfterExport") as? Bool ?? true
        highlightMatchesInExport = defaults.object(forKey: "highlightMatchesInExport") as? Bool ?? true
        usePandoc = defaults.object(forKey: "usePandoc") as? Bool ?? true
        pdfEngine = defaults.string(forKey: "pdfEngine") ?? ""
        exportTemplates = defaults.dictionary(forKey: "exportTemplates") as? [String: String] ?? [:]
    }

    /// Normalised export folder ("" when unset), without leading or trailing slashes.
    var exportFolderPath: String {
        exportFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ ").union(.whitespaces))
    }

    func template(_ template: ExportTemplate) -> URL? {
        guard let path = exportTemplates[template.rawValue], FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// How each hit is shown in an exported result list.
enum ResultPreviewStyle: String, CaseIterable, Identifiable {
    case excerpt
    case embed
    case linksOnly
    var id: Self { self }
}

/// Optional user templates for the export.
enum ExportTemplate: String, CaseIterable, Identifiable {
    case wordReference
    case odtReference
    case stylesheet
    case pandocPDFTemplate
    var id: Self { self }

    var allowedExtensions: [String] {
        switch self {
        case .wordReference: ["docx"]
        case .odtReference: ["odt"]
        case .stylesheet: ["css"]
        case .pandocPDFTemplate: ["tex", "latex", "typ", "html"]
        }
    }
}
