// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct QuiltLogApp: App {
    @StateObject private var store = QuiltStore()

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
                .frame(minWidth: 1080, minHeight: 680)
                .task {
                    await store.load()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Quilt") {
                    Task { _ = await store.createQuilt() }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Database...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.database]
                    panel.canCreateDirectories = true
                    panel.nameFieldStringValue = "Quilt Log.sqlite"

                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        try store.createDatabase(at: url)
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }

                Button("Open Database...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.database, .data]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false

                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        try store.openDatabase(at: url)
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Show Database in Finder") {
                    guard let databaseURL = store.databaseURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
                }
                .disabled(store.databaseURL == nil)

                Divider()

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
