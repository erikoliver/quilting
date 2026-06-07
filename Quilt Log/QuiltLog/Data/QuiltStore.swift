// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import CoreData
import Foundation
import ImageIO
import SQLite3
import SwiftData

struct CloudSyncStatus: Equatable {
    enum Phase: Equatable {
        case waiting
        case settingUp
        case importing
        case exporting
        case idle
        case failed
    }

    var phase: Phase = .waiting
    var message = "Cloud sync pending"
    var lastUpdated: Date?

    var systemImage: String {
        switch phase {
        case .waiting: "icloud"
        case .settingUp: "icloud"
        case .importing: "icloud.and.arrow.down"
        case .exporting: "icloud.and.arrow.up"
        case .idle: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }
}

struct MigrationProgress: Equatable {
    var completed: Int
    var total: Int
    var message: String

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

private enum BackupExportError: LocalizedError {
    case zipFailed(status: Int32, output: String)
    case unsupportedOnThisPlatform

    var errorDescription: String? {
        switch self {
        case let .zipFailed(status, output):
            let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "Could not create ZIP backup. The zip process exited with status \(status)."
            }
            return "Could not create ZIP backup. The zip process exited with status \(status): \(details)"
        case .unsupportedOnThisPlatform:
            return "This export is only available on Mac."
        }
    }
}

@MainActor
final class QuiltStore: ObservableObject {
    @Published var quilts: [Quilt] = []
    @Published var photosByQuiltID: [Int64: [QuiltPhoto]] = [:]
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published private(set) var databaseGeneration = 0
    @Published private(set) var databaseURL: URL?
    @Published private(set) var migrationProgress: MigrationProgress?
    @Published private(set) var cloudSyncStatus = CloudSyncStatus()

    private let context: ModelContext
    private var quiltUUIDByID: [Int64: String] = [:]
    private var photoUUIDByID: [Int64: String] = [:]
    private var cloudKitEventObserver: NSObjectProtocol?

    private static let thumbnailMaxSide: CGFloat = 240
    private static let thumbnailJPEGCompression: CGFloat = 0.64
    private static let applicationSupportFolderName = "Quilt Log"
    private static let legacyDatabaseFilename = "Quilt Log.sqlite"
    private static let migrationCompleteKey = "legacySQLiteMigrationComplete"
    private static let backupFormatVersion = 1

    init(modelContainer: ModelContainer) {
        context = ModelContext(modelContainer)
        observeCloudKitEvents()
    }

    deinit {
        if let cloudKitEventObserver {
            NotificationCenter.default.removeObserver(cloudKitEventObserver)
        }
    }

    var filteredQuilts: [Quilt] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return quilts }
        return quilts.filter {
            searchableText(for: $0).contains(needle)
        }
    }

    func load() async {
        do {
            databaseURL = try Self.legacyDatabaseURL()
            try await migrateLegacySQLiteIfNeeded()
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchQuilts() throws {
        let records = try sortedQuiltRecords()
        quiltUUIDByID = Dictionary(uniqueKeysWithValues: records.map { (Self.id(for: $0), $0.uuid) })
        quilts = records.map(Self.quiltDTO)
        try fetchPhotos()
        databaseGeneration += 1
    }

    @discardableResult
    func save(_ quilt: Quilt) async -> Bool {
        do {
            guard let record = try quiltRecord(for: quilt.id) else { return false }
            if let conflict = try sequenceConflict(for: quilt) {
                errorMessage = "Seq # \(quilt.sequenceNumber) is already used by “\(conflict.quiltName)”. Choose another sequence number before saving."
                return false
            }
            update(record, from: quilt)
            try context.save()
            try fetchQuilts()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sequenceConflict(for quilt: Quilt) throws -> Quilt? {
        try sortedQuiltRecords()
            .first { $0.sequenceNumber == quilt.sequenceNumber && Self.id(for: $0) != quilt.id }
            .map(Self.quiltDTO)
    }

    func saveMakingSpace(for quilt: Quilt) async {
        do {
            guard let record = try quiltRecord(for: quilt.id) else {
                errorMessage = "Could not find the quilt being edited."
                return
            }

            if record.sequenceNumber != quilt.sequenceNumber {
                try renumberAroundMove(quiltID: quilt.id, from: record.sequenceNumber, to: quilt.sequenceNumber)
            }
            update(record, from: quilt)
            try context.save()
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repairSequenceGaps() async {
        do {
            for (index, record) in try sortedQuiltRecords().enumerated() {
                record.sequenceNumber = index + 1
                record.updatedAt = Date()
            }
            try context.save()
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createQuilt() async -> Int64? {
        do {
            let nextSequence = (quilts.map(\.sequenceNumber).max() ?? 0) + 1
            let record = QuiltRecord(
                legacyID: try nextLegacyQuiltID(),
                sequenceNumber: nextSequence,
                quiltName: "Untitled Quilt"
            )
            context.insert(record)
            try context.save()
            try fetchQuilts()
            return Self.id(for: record)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteQuilt(id: Int64) async {
        do {
            guard let record = try quiltRecord(for: id) else { return }
            for photo in record.photos ?? [] {
                context.delete(photo)
            }
            context.delete(record)
            try context.save()
            await repairSequenceGaps()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhoto(to quilt: Quilt, from url: URL) async {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let mimeType = Self.mimeType(for: url)
            try addPhoto(to: quilt, data: data, mimeType: mimeType)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhoto(to quilt: Quilt, data: Data, mimeType: String) throws {
        guard let quiltRecord = try quiltRecord(for: quilt.id) else { return }
        let photos = sortedPhotos(for: quiltRecord)
        let isFirst = photos.isEmpty
        let photo = QuiltPhotoRecord(
            legacyID: try nextLegacyPhotoID(),
            mimeType: mimeType,
            sortOrder: (photos.map(\.sortOrder).max() ?? -1) + 1,
            isCover: isFirst,
            imageData: data,
            thumbnailData: Self.thumbnailJPEGData(for: data),
            quilt: quiltRecord
        )
        context.insert(photo)
        try context.save()
        try fetchPhotos()
    }

    func setCoverPhoto(_ photo: QuiltPhoto) async {
        do {
            guard let photoRecord = try photoRecord(for: photo.id),
                  let quiltRecord = photoRecord.quilt else { return }
            for sibling in sortedPhotos(for: quiltRecord) {
                sibling.isCover = sibling.uuid == photoRecord.uuid
            }
            try context.save()
            try fetchPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func movePhoto(_ photo: QuiltPhoto, by offset: Int) async {
        do {
            guard let photoRecord = try photoRecord(for: photo.id),
                  let quiltRecord = photoRecord.quilt else { return }
            var photos = sortedPhotos(for: quiltRecord)
            guard let currentIndex = photos.firstIndex(where: { $0.uuid == photoRecord.uuid }) else { return }
            let targetIndex = currentIndex + offset
            guard photos.indices.contains(targetIndex) else { return }
            photos.swapAt(currentIndex, targetIndex)
            for (index, photo) in photos.enumerated() {
                photo.sortOrder = index
            }
            try context.save()
            try fetchPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePhoto(_ photo: QuiltPhoto) async {
        do {
            guard let photoRecord = try photoRecord(for: photo.id),
                  let quiltRecord = photoRecord.quilt else { return }
            context.delete(photoRecord)
            try context.save()

            let remainingPhotos = sortedPhotos(for: quiltRecord)
            for (index, photo) in remainingPhotos.enumerated() {
                photo.sortOrder = index
            }
            if !remainingPhotos.isEmpty, !remainingPhotos.contains(where: \.isCover) {
                remainingPhotos[0].isCover = true
            }
            try context.save()
            try fetchPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFullLog(to url: URL, ownerName: String) {
        exportPDF(.completeLog, to: url, ownerName: ownerName)
    }

    func exportPDF(_ preset: PDFExportPreset, to url: URL, ownerName: String) {
        do {
#if os(macOS)
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
#endif
            try PDFExportService.export(
                preset: preset,
                ownerName: ownerName,
                quilts: filteredQuilts,
                photosByQuiltID: photosByQuiltID,
                to: url
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func temporaryPDFExportURL(for preset: PDFExportPreset, ownerName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiltLogPDFExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(preset.datedDefaultFilename)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try PDFExportService.export(
            preset: preset,
            ownerName: ownerName,
            quilts: filteredQuilts,
            photosByQuiltID: photosByQuiltID,
            to: url
        )
        return url
    }

    func exportJSONBackup(to url: URL) throws {
#if os(macOS)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiltLogBackup-\(UUID().uuidString)", isDirectory: true)
        let payloadDirectory = workingDirectory.appendingPathComponent("payload", isDirectory: true)
        let imagesDirectory = payloadDirectory.appendingPathComponent("images", isDirectory: true)
        let thumbnailsDirectory = payloadDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let backup = try backupManifest(
            imagesDirectory: imagesDirectory,
            thumbnailsDirectory: thumbnailsDirectory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: payloadDirectory.appendingPathComponent("manifest.json"))

        let stagedZipURL = workingDirectory.appendingPathComponent("Quilt Log Backup.zip")
        try zip(directory: payloadDirectory, to: stagedZipURL)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.copyItem(at: stagedZipURL, to: url)
#else
        throw BackupExportError.unsupportedOnThisPlatform
#endif
    }

    func importDatabase(from url: URL) async throws {
        try await importLegacySQLite(from: url)
    }

    func exportDatabase(to url: URL) throws {
        try exportJSONBackup(to: url)
    }

    func resetDatabase() throws {
        for photo in try context.fetch(FetchDescriptor<QuiltPhotoRecord>()) {
            context.delete(photo)
        }
        for quilt in try context.fetch(FetchDescriptor<QuiltRecord>()) {
            context.delete(quilt)
        }
        for metadata in try context.fetch(FetchDescriptor<QuiltLogMetadata>()) {
            context.delete(metadata)
        }
        try context.save()
        try fetchQuilts()
    }

    private func migrateLegacySQLiteIfNeeded() async throws {
        guard try sortedQuiltRecords().isEmpty else { return }
        guard try metadataValue(for: Self.migrationCompleteKey) != "true" else { return }
        let legacyURL = try Self.legacyDatabaseURL()
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        try await importLegacySQLite(from: legacyURL)
        try setMetadataValue("true", for: Self.migrationCompleteKey)
    }

    private func observeCloudKitEvents() {
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
                return
            }
            Task { @MainActor [weak self] in
                self?.updateCloudSyncStatus(from: event)
            }
        }
    }

    private func updateCloudSyncStatus(from event: NSPersistentCloudKitContainer.Event) {
        let phase: CloudSyncStatus.Phase
        let action: String
        switch event.type {
        case .setup:
            phase = .settingUp
            action = "Cloud sync setup"
        case .import:
            phase = .importing
            action = "Cloud import"
        case .export:
            phase = .exporting
            action = "Cloud export"
        @unknown default:
            phase = .waiting
            action = "Cloud sync"
        }

        if let error = event.error, !Self.isTransientCloudKitQueueError(error) {
            cloudSyncStatus = CloudSyncStatus(
                phase: .failed,
                message: "\(action) failed: \(error.localizedDescription)",
                lastUpdated: event.endDate ?? Date()
            )
        } else if Self.isTransientCloudKitQueueError(event.error) {
            cloudSyncStatus = CloudSyncStatus(
                phase: phase,
                message: "\(action) already in progress",
                lastUpdated: event.endDate ?? Date()
            )
        } else if event.endDate != nil {
            cloudSyncStatus = CloudSyncStatus(
                phase: .idle,
                message: "iCloud synchronized",
                lastUpdated: event.endDate
            )
            refreshAfterCloudKitImportIfNeeded(event)
        } else {
            cloudSyncStatus = CloudSyncStatus(
                phase: phase,
                message: "\(action) in progress",
                lastUpdated: event.startDate
            )
        }
    }

    private func refreshAfterCloudKitImportIfNeeded(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.type == .import else { return }
        do {
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func isTransientCloudKitQueueError(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == NSCocoaErrorDomain && error.code == 134417
    }

    private func importLegacySQLite(from url: URL) async throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        migrationProgress = MigrationProgress(completed: 0, total: 1, message: "Reading legacy SQLite library...")
        await Task.yield()

        let database = try SQLiteDatabase(path: url)
        try Self.validateLegacyDatabase(database)
        let quiltRows = try Self.legacyQuilts(from: database)
        let photoRows = try Self.legacyPhotos(from: database)
        let total = max(quiltRows.count + photoRows.count, 1)

        migrationProgress = MigrationProgress(completed: 0, total: total, message: "Preparing SwiftData library...")
        await Task.yield()
        var importedQuiltsByLegacyID: [Int64: QuiltRecord] = [:]

        for (index, row) in quiltRows.enumerated() {
            let record = QuiltRecord(
                legacyID: row.id,
                sequenceNumber: row.sequenceNumber,
                quiltName: row.quiltName,
                patternName: row.patternName,
                fabricReminder: row.fabricReminder,
                approxSize: row.approxSize,
                quiltDate: row.quiltDate,
                status: row.status,
                giftedAlready: row.giftedAlready,
                recipient: row.recipient,
                notes: row.notes,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
            context.insert(record)
            importedQuiltsByLegacyID[row.id] = record
            migrationProgress = MigrationProgress(
                completed: index + 1,
                total: total,
                message: "Imported quilt \(row.sequenceNumber): \(row.quiltName)"
            )
            await Task.yield()
        }
        try context.save()
        await Task.yield()

        for (index, row) in photoRows.enumerated() {
            guard let quiltRecord = importedQuiltsByLegacyID[row.quiltID] else { continue }
            let photo = QuiltPhotoRecord(
                legacyID: row.id,
                mimeType: row.mimeType,
                caption: row.caption,
                sortOrder: row.sortOrder,
                isCover: row.isCover,
                createdAt: row.createdAt,
                imageData: row.imageData,
                thumbnailData: row.thumbnailData,
                quilt: quiltRecord
            )
            context.insert(photo)
            migrationProgress = MigrationProgress(
                completed: quiltRows.count + index + 1,
                total: total,
                message: "Imported photo \(index + 1) of \(photoRows.count)"
            )
            if index.isMultiple(of: 10) {
                try context.save()
                await Task.yield()
            }
        }

        try context.save()
        migrationProgress = nil
        try fetchQuilts()
    }

    private func fetchPhotos() throws {
        let records = try context.fetch(FetchDescriptor<QuiltPhotoRecord>())
        photoUUIDByID = Dictionary(uniqueKeysWithValues: records.map { (Self.id(for: $0), $0.uuid) })
        let photos = records.compactMap(Self.photoDTO)
        photosByQuiltID = Dictionary(grouping: photos, by: \.quiltID).mapValues {
            $0.sorted { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
        }
    }

    private func searchableText(for quilt: Quilt) -> String {
        [
            String(quilt.sequenceNumber),
            quilt.quiltName,
            quilt.patternName,
            quilt.fabricReminder,
            quilt.approxSize,
            quilt.quiltDate,
            quilt.status,
            quilt.giftedAlready ? "gifted gifted already yes" : "not gifted no",
            quilt.recipient,
            quilt.notes
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func sortedQuiltRecords() throws -> [QuiltRecord] {
        var descriptor = FetchDescriptor<QuiltRecord>(
            sortBy: [
                SortDescriptor(\.sequenceNumber),
                SortDescriptor(\.quiltName)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.photos]
        return try context.fetch(descriptor)
    }

    private func sortedPhotos(for quilt: QuiltRecord) -> [QuiltPhotoRecord] {
        (quilt.photos ?? []).sorted {
            $0.sortOrder == $1.sortOrder ? $0.uuid < $1.uuid : $0.sortOrder < $1.sortOrder
        }
    }

    private func quiltRecord(for id: Int64) throws -> QuiltRecord? {
        if let uuid = quiltUUIDByID[id] {
            let descriptor = FetchDescriptor<QuiltRecord>(
                predicate: #Predicate { $0.uuid == uuid }
            )
            return try context.fetch(descriptor).first
        }
        return try sortedQuiltRecords().first { Self.id(for: $0) == id }
    }

    private func photoRecord(for id: Int64) throws -> QuiltPhotoRecord? {
        if let uuid = photoUUIDByID[id] {
            let descriptor = FetchDescriptor<QuiltPhotoRecord>(
                predicate: #Predicate { $0.uuid == uuid }
            )
            return try context.fetch(descriptor).first
        }
        return try context.fetch(FetchDescriptor<QuiltPhotoRecord>()).first { Self.id(for: $0) == id }
    }

    private func update(_ record: QuiltRecord, from quilt: Quilt) {
        record.sequenceNumber = quilt.sequenceNumber
        record.quiltName = quilt.quiltName
        record.patternName = quilt.patternName
        record.fabricReminder = quilt.fabricReminder
        record.approxSize = quilt.approxSize
        record.quiltDate = quilt.quiltDate
        record.status = quilt.status
        record.giftedAlready = quilt.giftedAlready
        record.recipient = quilt.recipient
        record.notes = quilt.notes
        record.updatedAt = Date()
    }

    private func renumberAroundMove(quiltID: Int64, from oldSequence: Int, to newSequence: Int) throws {
        let records = try sortedQuiltRecords()
        if newSequence < oldSequence {
            for record in records where Self.id(for: record) != quiltID
                && record.sequenceNumber >= newSequence
                && record.sequenceNumber < oldSequence {
                record.sequenceNumber += 1
                record.updatedAt = Date()
            }
        } else if newSequence > oldSequence {
            for record in records where Self.id(for: record) != quiltID
                && record.sequenceNumber > oldSequence
                && record.sequenceNumber <= newSequence {
                record.sequenceNumber -= 1
                record.updatedAt = Date()
            }
        }
    }

    private func nextLegacyQuiltID() throws -> Int64 {
        (try sortedQuiltRecords().map(\.legacyID).max() ?? 0) + 1
    }

    private func nextLegacyPhotoID() throws -> Int64 {
        (try context.fetch(FetchDescriptor<QuiltPhotoRecord>()).map(\.legacyID).max() ?? 0) + 1
    }

    private func metadataValue(for key: String) throws -> String? {
        let descriptor = FetchDescriptor<QuiltLogMetadata>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first?.value
    }

    private func setMetadataValue(_ value: String, for key: String) throws {
        let descriptor = FetchDescriptor<QuiltLogMetadata>(
            predicate: #Predicate { $0.key == key }
        )
        if let metadata = try context.fetch(descriptor).first {
            metadata.value = value
            metadata.updatedAt = Date()
        } else {
            context.insert(QuiltLogMetadata(key: key, value: value))
        }
        try context.save()
    }

    private func backupManifest(imagesDirectory: URL, thumbnailsDirectory: URL) throws -> QuiltLogBackup {
        let records = try sortedQuiltRecords()
        let quilts = try records.map { quilt -> QuiltBackup in
            let photos = try sortedPhotos(for: quilt).map { photo -> QuiltPhotoBackup in
                let imageFilename = try writeBackupImage(
                    data: photo.imageData,
                    uuid: photo.uuid,
                    mimeType: photo.mimeType,
                    directory: imagesDirectory
                )
                let thumbnailFilename = try writeBackupImage(
                    data: photo.thumbnailData,
                    uuid: photo.uuid,
                    mimeType: "image/jpeg",
                    directory: thumbnailsDirectory
                )
                return QuiltPhotoBackup(
                    uuid: photo.uuid,
                    legacyID: photo.legacyID,
                    mimeType: photo.mimeType,
                    caption: photo.caption,
                    sortOrder: photo.sortOrder,
                    isCover: photo.isCover,
                    createdAt: photo.createdAt,
                    imageFilename: imageFilename.map { "images/\($0)" },
                    thumbnailFilename: thumbnailFilename.map { "thumbnails/\($0)" }
                )
            }
            return QuiltBackup(
                uuid: quilt.uuid,
                legacyID: quilt.legacyID,
                sequenceNumber: quilt.sequenceNumber,
                quiltName: quilt.quiltName,
                patternName: quilt.patternName,
                fabricReminder: quilt.fabricReminder,
                approxSize: quilt.approxSize,
                quiltDate: quilt.quiltDate,
                status: quilt.status,
                giftedAlready: quilt.giftedAlready,
                recipient: quilt.recipient,
                notes: quilt.notes,
                createdAt: quilt.createdAt,
                updatedAt: quilt.updatedAt,
                photos: photos
            )
        }

        return QuiltLogBackup(
            formatVersion: Self.backupFormatVersion,
            exportedAt: Date(),
            syncBehavior: "SwiftData local-first store with private CloudKit sync; sequence numbers are app-level ordering values.",
            quilts: quilts
        )
    }

    private func writeBackupImage(data: Data?, uuid: String, mimeType: String, directory: URL) throws -> String? {
        guard let data else { return nil }
        let filename = "\(uuid).\(Self.fileExtension(for: mimeType))"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

#if os(macOS)
    private func zip(directory: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-qry", destination.path, "."]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BackupExportError.zipFailed(status: process.terminationStatus, output: output)
        }
    }
#endif

    private static func quiltDTO(from record: QuiltRecord) -> Quilt {
        Quilt(
            id: id(for: record),
            sequenceNumber: record.sequenceNumber,
            quiltName: record.quiltName,
            patternName: record.patternName,
            fabricReminder: record.fabricReminder,
            approxSize: record.approxSize,
            quiltDate: record.quiltDate,
            status: record.status,
            giftedAlready: record.giftedAlready,
            recipient: record.recipient,
            notes: record.notes
        )
    }

    private static func photoDTO(from record: QuiltPhotoRecord) -> QuiltPhoto? {
        guard let quilt = record.quilt else { return nil }
        return QuiltPhoto(
            id: id(for: record),
            quiltID: id(for: quilt),
            thumbnailData: record.thumbnailData,
            mimeType: record.mimeType,
            caption: record.caption,
            sortOrder: record.sortOrder,
            isCover: record.isCover
        )
    }

    private static func id(for record: QuiltRecord) -> Int64 {
        QuiltRecordID.numericID(for: record.uuid)
    }

    private static func id(for record: QuiltPhotoRecord) -> Int64 {
        QuiltRecordID.numericID(for: record.uuid)
    }

    private static func legacyDatabaseURL() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent(legacyDatabaseFilename, isDirectory: false)
    }

    private static func applicationSupportDirectory() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = directory.appendingPathComponent(applicationSupportFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }

    private static func validateLegacyDatabase(_ database: SQLiteDatabase) throws {
        let versions = try database.query(
            """
            SELECT value
            FROM schema_metadata
            WHERE key = 'schema_version'
            LIMIT 1
            """
        ) { statement in
            SQLiteDatabase.columnString(statement, 0)
        }

        guard versions.first == "1" else {
            throw SQLiteError.prepareFailed("The selected file is not a supported Quilt Log database.")
        }
    }

    private static func legacyQuilts(from database: SQLiteDatabase) throws -> [LegacyQuiltRow] {
        try database.query(
            """
            SELECT id, sequence_number, quilt_name, pattern_name, fabric_reminder, approx_size,
                   COALESCE(quilt_date, ''), status, gifted_already, recipient, notes,
                   created_at, updated_at
            FROM quilts
            ORDER BY sequence_number
            """
        ) { statement in
            LegacyQuiltRow(
                id: sqlite3_column_int64(statement, 0),
                sequenceNumber: Int(sqlite3_column_int(statement, 1)),
                quiltName: SQLiteDatabase.columnString(statement, 2),
                patternName: SQLiteDatabase.columnString(statement, 3),
                fabricReminder: SQLiteDatabase.columnString(statement, 4),
                approxSize: SQLiteDatabase.columnString(statement, 5),
                quiltDate: SQLiteDatabase.columnString(statement, 6),
                status: SQLiteDatabase.columnString(statement, 7),
                giftedAlready: sqlite3_column_int(statement, 8) == 1,
                recipient: SQLiteDatabase.columnString(statement, 9),
                notes: SQLiteDatabase.columnString(statement, 10),
                createdAt: parseSQLiteDate(SQLiteDatabase.columnString(statement, 11)),
                updatedAt: parseSQLiteDate(SQLiteDatabase.columnString(statement, 12))
            )
        }
    }

    private static func legacyPhotos(from database: SQLiteDatabase) throws -> [LegacyPhotoRow] {
        try database.query(
            """
            SELECT id, quilt_id, image_data, thumbnail_data, mime_type, caption, sort_order, is_cover, created_at
            FROM photos
            ORDER BY quilt_id, sort_order
            """
        ) { statement in
            LegacyPhotoRow(
                id: sqlite3_column_int64(statement, 0),
                quiltID: sqlite3_column_int64(statement, 1),
                imageData: SQLiteDatabase.columnData(statement, 2),
                thumbnailData: SQLiteDatabase.columnData(statement, 3),
                mimeType: SQLiteDatabase.columnString(statement, 4),
                caption: SQLiteDatabase.columnString(statement, 5),
                sortOrder: Int(sqlite3_column_int(statement, 6)),
                isCover: sqlite3_column_int(statement, 7) == 1,
                createdAt: parseSQLiteDate(SQLiteDatabase.columnString(statement, 8))
            )
        }
    }

    private static func parseSQLiteDate(_ value: String) -> Date {
        guard !value.isEmpty else { return Date() }
        if let date = sqliteDateFormatter.date(from: value) {
            return date
        }
        if let date = iso8601Formatter.date(from: value) {
            return date
        }
        return Date()
    }

    private static let sqliteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static func thumbnailJPEGData(for data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(thumbnailMaxSide)
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: thumbnailJPEGCompression
        ]
        CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        default: return "image/jpeg"
        }
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/tiff": return "tiff"
        default: return "jpg"
        }
    }
}

private struct LegacyQuiltRow {
    var id: Int64
    var sequenceNumber: Int
    var quiltName: String
    var patternName: String
    var fabricReminder: String
    var approxSize: String
    var quiltDate: String
    var status: String
    var giftedAlready: Bool
    var recipient: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}

private struct LegacyPhotoRow {
    var id: Int64
    var quiltID: Int64
    var imageData: Data?
    var thumbnailData: Data?
    var mimeType: String
    var caption: String
    var sortOrder: Int
    var isCover: Bool
    var createdAt: Date
}
