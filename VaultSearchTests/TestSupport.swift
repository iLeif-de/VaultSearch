import Foundation
@testable import VaultSearch

/// Fixed calendar and clock so date tests do not depend on the machine.
enum TestClock {
    /// Gregorian, UTC, weeks start on Monday.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday, 18 November 2026, 12:00 UTC.
    static let now = date("2026-11-18", hour: 12)

    static func date(_ day: String, hour: Int = 0) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    static func day(_ day: String) -> Date { date(day) }
}

/// Builds a note without touching the file system.
func makeNote(
    _ title: String,
    folder: String = "",
    content: String = "",
    tags: [String] = [],
    frontmatter: [String: Any] = [:],
    created: String = "2026-01-01",
    modified: String = "2026-01-01",
    vault: String = "Vault"
) -> MarkdownFile {
    let relativePath = folder.isEmpty ? "\(title).md" : "\(folder)/\(title).md"
    var frontmatter = frontmatter
    if !tags.isEmpty { frontmatter["tags"] = tags }
    return MarkdownFile(
        path: URL(fileURLWithPath: "/\(vault)/\(relativePath)"),
        relativePath: relativePath,
        content: content,
        frontmatter: frontmatter,
        tags: tags,
        createdDate: TestClock.date(created, hour: 9),
        modifiedDate: TestClock.date(modified, hour: 9),
        vaultName: vault
    )
}

extension SearchQuery {
    /// A query evaluated with the fixed test clock.
    static func test(_ text: String) -> SearchQuery {
        SearchQuery(text, now: TestClock.now, calendar: TestClock.calendar)
    }

    func titles(in files: [MarkdownFile]) -> [String] {
        run(on: files).map(\.title)
    }
}

/// A temporary folder that is removed again by `cleanUp()`.
struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("VaultSearchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ relativePath: String, _ text: String = "") throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}
