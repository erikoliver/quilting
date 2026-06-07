// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct QuiltLogApp: App {
    @StateObject private var store = QuiltStore()
    @StateObject private var preferences = UserPreferences()

    init() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(preferences)
                .frame(minWidth: 1080, minHeight: 680)
                .task {
                    await store.load()
                }
        }
        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Quilt") {
                    Task { _ = await store.createQuilt() }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Import SQLite Backup...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.database, .data]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.title = "Import Quilt Log SQLite Backup"
                    panel.message = "Choose a Quilt Log SQLite database to import. This will replace the current library."
                    panel.prompt = "Import"

                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Replace current Quilt Log library?"
                    alert.informativeText = "Importing \"\(url.lastPathComponent)\" will replace the app's current library. Export a backup first if you want to keep it."
                    alert.addButton(withTitle: "Import")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        do {
                            try store.importDatabase(from: url)
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Export SQLite Backup...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.database]
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = "Quilt Log.sqlite"

                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        try store.exportDatabase(to: url)
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }

                Button("Show Data Folder in Finder") {
                    guard let databaseURL = store.databaseURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                }
                .disabled(store.databaseURL == nil)

                Divider()

                Button("New Empty Library...") {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Create a new empty Quilt Log library?"
                    alert.informativeText = "This will replace the app's current library with an empty one. Export a backup first if you want to keep it."
                    alert.addButton(withTitle: "Create Empty Library")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        do {
                            try store.resetDatabase()
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Repair Numbering...") {
                    let alert = NSAlert()
                    alert.messageText = "Repair sequence numbering?"
                    alert.informativeText = "This will renumber quilts sequentially from 1 in the current sequence order. Quilt records keep their database IDs."
                    alert.addButton(withTitle: "Repair Numbering")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        Task { await store.repairSequenceGaps() }
                    }
                }
            }
            CommandGroup(after: .textEditing) {
                Button("Find") {
                    NotificationCenter.default.post(name: .focusQuiltSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
