// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import Security
#endif

@main
struct QuiltLogApp: App {
    @StateObject private var runtime = QuiltRuntime()
    @StateObject private var preferences = UserPreferences()

    init() {
    }
    
    private static let backupFilenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    var body: some Scene {
        appWindow
#if os(macOS)
        Settings {
            PreferencesView()
                .environmentObject(preferences)
        }
#endif
    }

    private var appWindow: some Scene {
        WindowGroup {
            Group {
                if let store = runtime.store {
                    ContentView()
                        .environmentObject(store)
                        .environmentObject(preferences)
#if os(macOS)
                        .frame(minWidth: 1080, minHeight: 680)
#endif
                        .task {
                            await store.load()
                        }
                        .sheet(isPresented: Binding(
                            get: { store.migrationProgress != nil },
                            set: { _ in }
                        )) {
                            if let progress = store.migrationProgress {
                                MigrationProgressView(progress: progress)
                            }
                        }
                } else {
                    LaunchingLibraryView(errorMessage: runtime.launchError)
                        .task {
                            await runtime.prepareStore()
                        }
                }
            }
        }
#if os(macOS)
        .commands {
            appCommands
        }
#endif
    }
}

@MainActor
private final class QuiltRuntime: ObservableObject {
    @Published private(set) var store: QuiltStore?
    @Published private(set) var launchError: String?

    private var isPreparing = false
    private var modelContainer: ModelContainer?

    func prepareStore() async {
        guard store == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        let schema = Schema([
            QuiltRecord.self,
            QuiltPhotoRecord.self,
            QuiltLogMetadata.self
        ])
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let configuration: ModelConfiguration
        if isRunningTests {
            configuration = ModelConfiguration("QuiltLogTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if Self.hasCloudKitEntitlement {
            configuration = ModelConfiguration("QuiltLogCloud", schema: schema, cloudKitDatabase: .private("iCloud.com.erikoliver.quiltlog"))
        } else {
            configuration = ModelConfiguration("QuiltLogUnsigned", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            store = QuiltStore(modelContainer: container)
        } catch {
            launchError = "Could not open the quilt library: \(error.localizedDescription)"
        }
    }

    private static var hasCloudKitEntitlement: Bool {
#if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-services" as CFString,
                nil
              ) else {
            return false
        }
        let services = value as? [String] ?? []
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
#else
        return true
#endif
    }
}

private struct LaunchingLibraryView: View {
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gallery")
                        .font(.title.bold())
                    Text("Opening library")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 12) {
                if let errorMessage {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing iCloud library")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)

            Spacer()
        }
    }
}

#if os(macOS)
private extension QuiltLogApp {
    @CommandsBuilder
    var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Quilt") {
                guard let store = runtime.store else { return }
                Task { _ = await store.createQuilt() }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(runtime.store == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Import Legacy SQLite Library...") {
                guard let store = runtime.store else { return }
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.database, .data]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.title = "Import Legacy Quilt Log SQLite Library"
                panel.message = "Choose a legacy Quilt Log SQLite database to convert into the SwiftData library."
                panel.prompt = "Import"

                guard panel.runModal() == .OK, let url = panel.url else { return }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Import legacy SQLite library?"
                alert.informativeText = "Importing \"\(url.lastPathComponent)\" will add its records to the SwiftData library. Export a ZIP backup first if you want a checkpoint."
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    Task {
                        do {
                            try await store.importDatabase(from: url)
                        } catch {
                            store.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .disabled(runtime.store == nil)

            Button("Export JSON Backup ZIP...") {
                guard let store = runtime.store else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "\(Self.backupFilenameDateFormatter.string(from: Date())) Quilt Log Backup.zip"

                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try store.exportJSONBackup(to: url)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            .disabled(runtime.store == nil)

            Button("Show Legacy Data Folder in Finder") {
                guard let databaseURL = runtime.store?.databaseURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
            }
            .disabled(runtime.store?.databaseURL == nil)

            Divider()

            Button("New Empty Library...") {
                guard let store = runtime.store else { return }
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
            .disabled(runtime.store == nil)

            Button("Repair Numbering...") {
                guard let store = runtime.store else { return }
                let alert = NSAlert()
                alert.messageText = "Repair sequence numbering?"
                alert.informativeText = "This will renumber quilts sequentially from 1 in the current sequence order. Quilt records keep their database IDs."
                alert.addButton(withTitle: "Repair Numbering")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    Task { await store.repairSequenceGaps() }
                }
            }
            .disabled(runtime.store == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .focusQuiltSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }
}
#endif
