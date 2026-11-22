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

/// Every intent of the app. Shortcuts finds intents by type name at run time, but the
/// Release optimizer removes types that no code refers to; the action then fails with
/// “internal error” (“type … does not exist in the process’s memory space”).
/// `VaultSearchApp.init` refers to this list, which keeps all of them.
enum AppIntentTypes {
    static let all: [any AppIntent.Type] = [
        FindNotesIntent.self,
        ShowInVaultSearchIntent.self,
        SearchInVaultSearchIntent.self,
        OpenNoteIntent.self,
        SaveResultsToVaultIntent.self,
        ExportResultsIntent.self,
        ExportNoteIntent.self,
    ]

    static func keep() {
        precondition(all.count == 7, "Add new intents to AppIntentTypes.all")
    }
}
