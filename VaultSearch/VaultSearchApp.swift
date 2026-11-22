//
//  VaultSearchApp.swift
//  VaultSearch
//
//  Created by Leif Jensen-Pistorius on 27.04.25.
//

import AppIntents
import SwiftUI

@main
struct VaultSearchApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        // App Intents (Siri, Shortcuts, Spotlight) get the shared model through `@Dependency`.
        AppDependencyManager.shared.add { await AppModel.shared }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.search)
                .environmentObject(model.exporter)
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            SidebarCommands()
            VaultSearchCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.search)
                .environmentObject(model.exporter)
        }

        Window("About VaultSearch", id: WindowID.about) {
            VaultSearchAboutView()
                .frame(width: 440, height: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        Window("Search Syntax", id: WindowID.syntax) {
            SearchSyntaxView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum WindowID {
    static let about = "about"
    static let syntax = "syntax"
}

struct VaultSearchCommands: Commands {
    let model: AppModel
    @FocusedValue(\.selectedNote) private var note
    @FocusedValue(\.focusSearch) private var focusSearch
    @FocusedValue(\.searchResults) private var results
    @FocusedValue(\.noteFind) private var noteFind
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About VaultSearch") { openWindow(id: WindowID.about) }
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Choose Vault…") { model.chooseVault() }
                .keyboardShortcut("o")
        }

        CommandGroup(replacing: .importExport) {
            ResultsExportItems(snapshot: results, exporter: model.exporter, showsShortcut: true)
            NoteExportMenu(file: note, exporter: model.exporter, highlightTerms: results?.highlightTerms ?? [])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search Vault") { focusSearch?() }
                .keyboardShortcut("f")
                .disabled(focusSearch == nil)
            Divider()
            Button("Find in Note") { noteFind?.focus() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(noteFind == nil)
            Button("Find Next") { noteFind?.next() }
                .keyboardShortcut("g")
                .disabled(noteFind == nil)
            Button("Find Previous") { noteFind?.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(noteFind == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Reindex Vault") { model.search.reindex() }
                .keyboardShortcut("r")
                .disabled(model.settings.vaultPath == nil)
            Divider()
        }

        CommandMenu("Note") {
            Group {
            Button("Open in Obsidian") { note.map(NoteActions.openInObsidian) }
                .keyboardShortcut(.return)
            Button("Open with Default App") { note.map(NoteActions.openWithDefaultApp) }
                .keyboardShortcut(.return, modifiers: [.command, .option])
            Button("Show in Finder") { note.map(NoteActions.showInFinder) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Copy Obsidian Link") { note.map(NoteActions.copyObsidianLink) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copy Path") { note.map(NoteActions.copyPath) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            }
            .disabled(note == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Search Syntax") { openWindow(id: WindowID.syntax) }
                .keyboardShortcut("?")
            if let url = URL(string: "https://github.com/iLeif-de/VaultSearch") {
                Link("VaultSearch on GitHub", destination: url)
            }
        }
    }
}
