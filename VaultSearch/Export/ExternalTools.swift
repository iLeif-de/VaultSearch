import Foundation

/// Command line helpers (Pandoc and PDF engines) found on this Mac.
struct ExternalTools: Equatable {
    struct PDFEngine: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { name }
        /// HTML engines honour the CSS stylesheet; LaTeX/Typst engines use a Pandoc template.
        var isHTMLBased: Bool { ["weasyprint", "wkhtmltopdf", "prince"].contains(name) }
        var isLaTeX: Bool { name.hasSuffix("latex") || name == "tectonic" }
    }

    var pandoc: URL?
    var pandocVersion: String?
    var pdfEngines: [PDFEngine] = []

    var pandocMajorVersion: Int {
        pandocVersion.flatMap { Int($0.split(separator: ".").first ?? "") } ?? 0
    }

    /// Order of preference for the automatic PDF engine. Prince comes last because its
    /// free edition adds a watermark.
    static let knownEngines = ["weasyprint", "typst", "tectonic", "xelatex", "lualatex", "pdflatex", "wkhtmltopdf", "prince"]

    /// GUI apps do not inherit the shell PATH, so Homebrew and TeX locations are listed explicitly.
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fromEnvironment = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (["/opt/homebrew/bin", "/usr/local/bin", "/Library/TeX/texbin", "\(home)/.local/bin", "\(home)/.cargo/bin"]
                + fromEnvironment + ["/usr/bin", "/bin"])
            .filter { seen.insert($0).inserted }
    }

    static func find(_ name: String) -> URL? {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Blocking; call off the main actor.
    static func detect() -> ExternalTools {
        var tools = ExternalTools()
        tools.pandoc = find("pandoc")
        if let pandoc = tools.pandoc,
           let result = try? ProcessRunner.run(pandoc, ["--version"]),
           let firstLine = String(data: result.output, encoding: .utf8)?.split(separator: "\n").first {
            tools.pandocVersion = firstLine.split(separator: " ").last.map(String.init)
        }
        tools.pdfEngines = knownEngines.compactMap { name in find(name).map { PDFEngine(name: name, url: $0) } }
        return tools
    }
}

enum ProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let errorOutput: String
    }

    /// Runs a tool synchronously with the extended PATH. Call off the main actor.
    static func run(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ExternalTools.searchPaths.joined(separator: ":")
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        process.environment = environment

        // stderr goes to a file so a chatty tool cannot block on a full pipe.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("vaultsearch-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        return Result(status: process.terminationStatus, output: output, errorOutput: errorText)
    }
}
