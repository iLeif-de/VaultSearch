import AppIntents

/// Ready-made shortcuts that appear in the Shortcuts app and in Spotlight without any setup.
struct VaultSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindNotesIntent(),
            phrases: [
                "Find notes in \(.applicationName)",
                "Search my vault with \(.applicationName)",
            ],
            shortTitle: "Find Notes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: [
                "Open \(\.$target) with \(.applicationName)",
                "Open a note with \(.applicationName)",
            ],
            shortTitle: "Open Note",
            systemImageName: "arrow.up.forward.app"
        )
        AppShortcut(
            intent: ExportNoteIntent(),
            phrases: [
                "Export \(\.$note) with \(.applicationName)",
                "Export a note with \(.applicationName)",
            ],
            shortTitle: "Export Note",
            systemImageName: "square.and.arrow.up"
        )
    }
}
