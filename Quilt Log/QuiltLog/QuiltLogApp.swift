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
#if os(macOS)
    @StateObject private var modifierKeys = ModifierKeyObserver()
#endif

    init() {
        DiagnosticLog.recordLaunch()
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
        DiagnosticLog.record("runtime prepareStore begin")
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
            DiagnosticLog.record("runtime configuration=tests cloudKit=none")
            configuration = ModelConfiguration("QuiltLogTests", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else if Self.hasCloudKitEntitlement {
            DiagnosticLog.record("runtime configuration=cloud container=iCloud.com.erikoliver.quiltlog")
#if os(macOS)
            CloudKitDiagnosticProbe.run(reason: "prepareStore")
#endif
            configuration = ModelConfiguration("QuiltLogCloud", schema: schema, cloudKitDatabase: .private("iCloud.com.erikoliver.quiltlog"))
        } else {
            DiagnosticLog.record("runtime configuration=unsigned cloudKit=none")
            configuration = ModelConfiguration("QuiltLogUnsigned", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            store = QuiltStore(modelContainer: container) { [weak self] in
                self?.retryCloudStore()
            }
            DiagnosticLog.record("runtime prepareStore succeeded")
        } catch {
            DiagnosticLog.record("runtime prepareStore failed", error: error)
            launchError = "Could not open the quilt library: \(error.localizedDescription)"
        }
    }

    private func retryCloudStore() {
        guard !isPreparing else {
            DiagnosticLog.record("runtime cloud retry ignored; prepare already in progress")
            return
        }
        DiagnosticLog.record("runtime cloud retry requested; reopening store")
        store = nil
        modelContainer = nil
        launchError = nil
        Task {
            await prepareStore()
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
            DiagnosticLog.record("runtime cloudKitEntitlement missing")
            return false
        }
        let services = value as? [String] ?? []
        let hasEntitlement = services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        DiagnosticLog.record("runtime cloudKitEntitlement services=\(services.joined(separator: ",")) enabled=\(hasEntitlement)")
        return hasEntitlement
#else
        DiagnosticLog.record("runtime cloudKitEntitlement assumed=true non-macOS")
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
@MainActor
private final class ModifierKeyObserver: ObservableObject {
    @Published private(set) var isOptionPressed = false

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pollTimer: Timer?

    init() {
        update(from: NSEvent.modifierFlags)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in
                self?.update(from: flags)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in
                self?.update(from: flags)
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard NSApp.isActive else { return }
                let flags = NSEvent.modifierFlags
                self?.update(from: flags)
            }
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        pollTimer?.invalidate()
    }

    private func update(from flags: NSEvent.ModifierFlags) {
        isOptionPressed = flags.intersection(.deviceIndependentFlagsMask).contains(.option)
    }
}

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
            Button("Import Backup...") {
                guard let store = runtime.store else { return }
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.zip]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.title = "Import Quilt Log Backup"
                panel.message = "Choose a Quilt Log ZIP backup."
                panel.prompt = "Import"

                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    let preflight = try store.preflightJSONBackupImport(from: url)
                    if preflight.hasOverlaps {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Import backup with matching quilts?"
                        alert.informativeText = Self.backupImportSummary(preflight)
                        alert.addButton(withTitle: "Skip Existing")
                        alert.addButton(withTitle: "Replace Existing")
                        alert.addButton(withTitle: "Cancel")

                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            try store.importJSONBackup(from: url, resolution: .skipExisting)
                        } else if response == .alertSecondButtonReturn {
                            try store.importJSONBackup(from: url, resolution: .replaceExisting)
                        }
                    } else {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.messageText = "Import Quilt Log backup?"
                        alert.informativeText = Self.backupImportSummary(preflight)
                        alert.addButton(withTitle: "Import")
                        alert.addButton(withTitle: "Cancel")

                        if alert.runModal() == .alertFirstButtonReturn {
                            try store.importJSONBackup(from: url, resolution: .skipExisting)
                        }
                    }
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            .disabled(runtime.store == nil)

            Button("Backup Locally...") {
                guard let store = runtime.store else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true
                panel.title = "Back Up Quilt Log Locally"
                panel.nameFieldStringValue = "\(Self.backupFilenameDateFormatter.string(from: Date())) Quilt Log Backup.zip"

                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try store.exportJSONBackup(to: url)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            .disabled(runtime.store == nil)

            if modifierKeys.isOptionPressed {
                Divider()

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

                Button("Show Library Folder in Finder") {
                    guard let libraryFolderURL = runtime.store?.libraryFolderURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([libraryFolderURL])
                }
                .disabled(runtime.store?.libraryFolderURL == nil)
            }

            Divider()

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

    private static func backupImportSummary(_ preflight: BackupImportPreflight) -> String {
        let exportedAt = DateFormatter.localizedString(
            from: preflight.exportedAt,
            dateStyle: .medium,
            timeStyle: .short
        )
        var lines = [
            "Backup exported: \(exportedAt)",
            "\(preflight.totalQuilts) quilts and \(preflight.totalPhotos) photos in the backup.",
            "\(preflight.newQuilts) quilts are new."
        ]
        if preflight.hasOverlaps {
            lines.append("\(preflight.overlappingQuilts) quilts already exist in this library.")
            lines.append("\(preflight.newerOverlappingQuilts) matching quilts have a newer backup update date.")
            lines.append("New quilts will be added with new sequence numbers. Replaced quilts keep their current sequence numbers.")
        } else {
            lines.append("No matching quilt UUIDs were found. Imported quilts will be added with new sequence numbers.")
        }
        return lines.joined(separator: "\n")
    }
}
#endif
