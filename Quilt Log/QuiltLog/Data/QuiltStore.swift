// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import ImageIO
import SQLite3

@MainActor
final class QuiltStore: ObservableObject {
    @Published var quilts: [Quilt] = []
    @Published var photosByQuiltID: [Int64: [QuiltPhoto]] = [:]
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published private(set) var databaseGeneration = 0
    @Published private(set) var databaseURL: URL?

    private var database: SQLiteDatabase?
    private static let thumbnailMaxSide: CGFloat = 240
    private static let thumbnailJPEGCompression: CGFloat = 0.64
    private static let applicationSupportFolderName = "Quilt Log"
    private static let applicationDatabaseFilename = "Quilt Log.sqlite"
    private static let databaseBookmarkKey = "databaseBookmark"
    private static let legacyDatabasePathKey = "lastOpenedDatabasePath"

    private enum DatabaseCompatibility: Equatable {
        case quiltLog
        case sqliteButNotQuiltLog
        case notSQLite
    }

    var filteredQuilts: [Quilt] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return quilts }
        return quilts.filter {
            searchableText(for: $0).contains(needle)
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

    func load() async {
        do {
            try openApplicationDatabase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openApplicationDatabase() throws {
        let url = try Self.applicationDatabaseURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            if let legacyURL = try Self.bookmarkedDatabaseURL(),
               Self.databaseCompatibility(at: legacyURL) == .quiltLog {
                try Self.replaceApplicationDatabase(with: legacyURL)
                Self.clearSavedDatabaseBookmark()
            } else {
                try Self.createEmptyDatabase(at: url)
            }
        }
        try openOwnedDatabase(at: url)
    }

    private func openOwnedDatabase(at url: URL) throws {
        let openedDatabase = try SQLiteDatabase(path: url)
        try Self.validateQuiltLogDatabase(openedDatabase)
        database = openedDatabase
        databaseURL = url
        databaseGeneration += 1
        try fetchQuilts()
    }

    func importDatabase(from url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let importedDatabase = try SQLiteDatabase(path: url)
        try Self.validateQuiltLogDatabase(importedDatabase)
        database = nil
        databaseURL = nil
        do {
            try Self.replaceApplicationDatabase(with: url)
            try openOwnedDatabase(at: Self.applicationDatabaseURL())
        } catch {
            try? openOwnedDatabase(at: Self.applicationDatabaseURL())
            throw error
        }
    }

    func exportDatabase(to url: URL) throws {
        guard let database else { return }
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try database.backup(to: url)
    }

    func resetDatabase() throws {
        database = nil
        databaseURL = nil
        let url = try Self.applicationDatabaseURL()
        try Self.removeDatabaseFiles(at: url)
        try Self.createEmptyDatabase(at: url)
        try openOwnedDatabase(at: url)
    }

    func fetchQuilts() throws {
        guard let database else { return }
        quilts = try database.query(
            """
            SELECT id, sequence_number, quilt_name, pattern_name, fabric_reminder, approx_size,
                   COALESCE(quilt_date, ''), status, gifted_already, recipient, notes
            FROM quilts
            ORDER BY sequence_number
            """
        ) { statement in
            Quilt(
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
                notes: SQLiteDatabase.columnString(statement, 10)
            )
        }
        try fetchPhotos()
    }

    @discardableResult
    func save(_ quilt: Quilt) async -> Bool {
        do {
            guard let database else { return false }
            if let conflict = try sequenceConflict(for: quilt) {
                errorMessage = "Seq # \(quilt.sequenceNumber) is already used by “\(conflict.quiltName)”. Choose another sequence number before saving."
                return false
            }
            try database.run(
                """
                UPDATE quilts
                SET sequence_number = ?, quilt_name = ?, pattern_name = ?, fabric_reminder = ?,
                    approx_size = ?, quilt_date = ?, status = ?, gifted_already = ?,
                    recipient = ?, notes = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """
            ) { statement in
                sqlite3_bind_int(statement, 1, Int32(quilt.sequenceNumber))
                try SQLiteDatabase.bindText(quilt.quiltName, to: 2, in: statement)
                try SQLiteDatabase.bindText(quilt.patternName, to: 3, in: statement)
                try SQLiteDatabase.bindText(quilt.fabricReminder, to: 4, in: statement)
                try SQLiteDatabase.bindText(quilt.approxSize, to: 5, in: statement)
                try SQLiteDatabase.bindText(quilt.quiltDate.isEmpty ? nil : quilt.quiltDate, to: 6, in: statement)
                try SQLiteDatabase.bindText(quilt.status, to: 7, in: statement)
                sqlite3_bind_int(statement, 8, quilt.giftedAlready ? 1 : 0)
                try SQLiteDatabase.bindText(quilt.recipient, to: 9, in: statement)
                try SQLiteDatabase.bindText(quilt.notes, to: 10, in: statement)
                sqlite3_bind_int64(statement, 11, quilt.id)
            }
            try fetchQuilts()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sequenceConflict(for quilt: Quilt) throws -> Quilt? {
        guard let database else { return nil }
        return try database.query(
            """
            SELECT id, sequence_number, quilt_name, pattern_name, fabric_reminder, approx_size,
                   COALESCE(quilt_date, ''), status, gifted_already, recipient, notes
            FROM quilts
            WHERE sequence_number = ? AND id <> ?
            LIMIT 1
            """
        ) { statement in
            sqlite3_bind_int(statement, 1, Int32(quilt.sequenceNumber))
            sqlite3_bind_int64(statement, 2, quilt.id)
        } map: { statement in
            Quilt(
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
                notes: SQLiteDatabase.columnString(statement, 10)
            )
        }.first
    }

    func saveMakingSpace(for quilt: Quilt) async {
        do {
            guard database != nil else { return }
            guard let original = try fetchQuilt(withID: quilt.id) else {
                errorMessage = "Could not find the quilt being edited."
                return
            }

            if original.sequenceNumber != quilt.sequenceNumber {
                try renumberAroundMove(quiltID: quilt.id, from: original.sequenceNumber, to: quilt.sequenceNumber)
            }
            try updateQuiltFields(quilt)
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repairSequenceGaps() async {
        do {
            guard let database else { return }
            let ids = try database.query(
                """
                SELECT id
                FROM quilts
                ORDER BY sequence_number, id
                """
            ) { statement in
                sqlite3_column_int64(statement, 0)
            }

            let offset = 100_000
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for (index, id) in ids.enumerated() {
                    try database.run(
                        "UPDATE quilts SET sequence_number = ? WHERE id = ?"
                    ) { statement in
                        sqlite3_bind_int(statement, 1, Int32(offset + index + 1))
                        sqlite3_bind_int64(statement, 2, id)
                    }
                }
                try database.run(
                    "UPDATE quilts SET sequence_number = sequence_number - ?"
                ) { statement in
                    sqlite3_bind_int(statement, 1, Int32(offset))
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
            try fetchQuilts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchQuilt(withID id: Int64) throws -> Quilt? {
        guard let database else { return nil }
        return try database.query(
            """
            SELECT id, sequence_number, quilt_name, pattern_name, fabric_reminder, approx_size,
                   COALESCE(quilt_date, ''), status, gifted_already, recipient, notes
            FROM quilts
            WHERE id = ?
            LIMIT 1
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, id)
        } map: { statement in
            Quilt(
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
                notes: SQLiteDatabase.columnString(statement, 10)
            )
        }.first
    }

    private func renumberAroundMove(quiltID: Int64, from oldSequence: Int, to newSequence: Int) throws {
        guard let database else { return }
        let offset = 100_000

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            if newSequence < oldSequence {
                try database.run(
                    """
                    UPDATE quilts
                    SET sequence_number = sequence_number + ?
                    WHERE id <> ? AND sequence_number >= ? AND sequence_number < ?
                    """
                ) { statement in
                    sqlite3_bind_int(statement, 1, Int32(offset))
                    sqlite3_bind_int64(statement, 2, quiltID)
                    sqlite3_bind_int(statement, 3, Int32(newSequence))
                    sqlite3_bind_int(statement, 4, Int32(oldSequence))
                }
                try database.run(
                    """
                    UPDATE quilts
                    SET sequence_number = sequence_number - ?
                    WHERE sequence_number >= ? AND sequence_number < ?
                    """
                ) { statement in
                    sqlite3_bind_int(statement, 1, Int32(offset - 1))
                    sqlite3_bind_int(statement, 2, Int32(newSequence + offset))
                    sqlite3_bind_int(statement, 3, Int32(oldSequence + offset))
                }
            } else if newSequence > oldSequence {
                try database.run(
                    """
                    UPDATE quilts
                    SET sequence_number = sequence_number + ?
                    WHERE id <> ? AND sequence_number > ? AND sequence_number <= ?
                    """
                ) { statement in
                    sqlite3_bind_int(statement, 1, Int32(offset))
                    sqlite3_bind_int64(statement, 2, quiltID)
                    sqlite3_bind_int(statement, 3, Int32(oldSequence))
                    sqlite3_bind_int(statement, 4, Int32(newSequence))
                }
                try database.run(
                    """
                    UPDATE quilts
                    SET sequence_number = sequence_number - ?
                    WHERE sequence_number > ? AND sequence_number <= ?
                    """
                ) { statement in
                    sqlite3_bind_int(statement, 1, Int32(offset + 1))
                    sqlite3_bind_int(statement, 2, Int32(oldSequence + offset))
                    sqlite3_bind_int(statement, 3, Int32(newSequence + offset))
                }
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private func updateQuiltFields(_ quilt: Quilt) throws {
        guard let database else { return }
        try database.run(
            """
            UPDATE quilts
            SET sequence_number = ?, quilt_name = ?, pattern_name = ?, fabric_reminder = ?,
                approx_size = ?, quilt_date = ?, status = ?, gifted_already = ?,
                recipient = ?, notes = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """
        ) { statement in
            sqlite3_bind_int(statement, 1, Int32(quilt.sequenceNumber))
            try SQLiteDatabase.bindText(quilt.quiltName, to: 2, in: statement)
            try SQLiteDatabase.bindText(quilt.patternName, to: 3, in: statement)
            try SQLiteDatabase.bindText(quilt.fabricReminder, to: 4, in: statement)
            try SQLiteDatabase.bindText(quilt.approxSize, to: 5, in: statement)
            try SQLiteDatabase.bindText(quilt.quiltDate.isEmpty ? nil : quilt.quiltDate, to: 6, in: statement)
            try SQLiteDatabase.bindText(quilt.status, to: 7, in: statement)
            sqlite3_bind_int(statement, 8, quilt.giftedAlready ? 1 : 0)
            try SQLiteDatabase.bindText(quilt.recipient, to: 9, in: statement)
            try SQLiteDatabase.bindText(quilt.notes, to: 10, in: statement)
            sqlite3_bind_int64(statement, 11, quilt.id)
        }
    }

    func createQuilt() async -> Int64? {
        do {
            guard let database else { return nil }
            let nextSequence = (quilts.map(\.sequenceNumber).max() ?? 0) + 1
            try database.run(
                """
                INSERT INTO quilts(sequence_number, quilt_name, status)
                VALUES (?, 'Untitled Quilt', ?)
                """
            ) { statement in
                sqlite3_bind_int(statement, 1, Int32(nextSequence))
                try SQLiteDatabase.bindText(QuiltStatus.inProgress.rawValue, to: 2, in: statement)
            }
            let newID = database.lastInsertedRowID
            try fetchQuilts()
            return newID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteQuilt(id: Int64) async {
        do {
            guard let database else { return }
            try database.run("DELETE FROM quilts WHERE id = ?") { statement in
                sqlite3_bind_int64(statement, 1, id)
            }
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
        guard let database else { return }
        let thumbnail = Self.thumbnailJPEGData(for: data)
        let nextSort = (photosByQuiltID[quilt.id]?.map(\.sortOrder).max() ?? -1) + 1
        let isFirst = (photosByQuiltID[quilt.id] ?? []).isEmpty

        try database.run(
            """
            INSERT INTO photos(quilt_id, image_data, thumbnail_data, mime_type, caption, sort_order, is_cover)
            VALUES (?, ?, ?, ?, '', ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, quilt.id)
            try SQLiteDatabase.bindData(data, to: 2, in: statement)
            try SQLiteDatabase.bindData(thumbnail, to: 3, in: statement)
            try SQLiteDatabase.bindText(mimeType, to: 4, in: statement)
            sqlite3_bind_int(statement, 5, Int32(nextSort))
            sqlite3_bind_int(statement, 6, isFirst ? 1 : 0)
        }
        try fetchPhotos()
    }

    func setCoverPhoto(_ photo: QuiltPhoto) async {
        do {
            guard let database else { return }
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try database.run("UPDATE photos SET is_cover = 0 WHERE quilt_id = ?") { statement in
                    sqlite3_bind_int64(statement, 1, photo.quiltID)
                }
                try database.run("UPDATE photos SET is_cover = 1 WHERE id = ?") { statement in
                    sqlite3_bind_int64(statement, 1, photo.id)
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
            try fetchPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func movePhoto(_ photo: QuiltPhoto, by offset: Int) async {
        do {
            guard let database else { return }
            var photos = photosByQuiltID[photo.quiltID] ?? []
            photos.sort { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
            guard let currentIndex = photos.firstIndex(where: { $0.id == photo.id }) else { return }
            let targetIndex = currentIndex + offset
            guard photos.indices.contains(targetIndex) else { return }

            photos.swapAt(currentIndex, targetIndex)
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for (index, photo) in photos.enumerated() {
                    try database.run("UPDATE photos SET sort_order = ? WHERE id = ?") { statement in
                        sqlite3_bind_int(statement, 1, Int32(index))
                        sqlite3_bind_int64(statement, 2, photo.id)
                    }
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
            try fetchPhotos()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePhoto(_ photo: QuiltPhoto) async {
        do {
            guard let database else { return }
            try database.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try database.run("DELETE FROM photos WHERE id = ?") { statement in
                    sqlite3_bind_int64(statement, 1, photo.id)
                }
                let remainingIDs = try database.query(
                    "SELECT id FROM photos WHERE quilt_id = ? ORDER BY sort_order, id"
                ) { statement in
                    sqlite3_bind_int64(statement, 1, photo.quiltID)
                } map: { statement in
                    sqlite3_column_int64(statement, 0)
                }
                for (index, id) in remainingIDs.enumerated() {
                    try database.run("UPDATE photos SET sort_order = ? WHERE id = ?") { statement in
                        sqlite3_bind_int(statement, 1, Int32(index))
                        sqlite3_bind_int64(statement, 2, id)
                    }
                }
                if !remainingIDs.isEmpty {
                    let coverCount = try database.query(
                        "SELECT COUNT(*) FROM photos WHERE quilt_id = ? AND is_cover = 1"
                    ) { statement in
                        sqlite3_bind_int64(statement, 1, photo.quiltID)
                    } map: { statement in
                        Int(sqlite3_column_int(statement, 0))
                    }.first ?? 0

                    if coverCount == 0 {
                        try database.run("UPDATE photos SET is_cover = 1 WHERE id = ?") { statement in
                            sqlite3_bind_int64(statement, 1, remainingIDs[0])
                        }
                    }
                }
                try database.execute("COMMIT")
            } catch {
                try? database.execute("ROLLBACK")
                throw error
            }
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
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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

    private func fetchPhotos() throws {
        guard let database else { return }
        let photos = try database.query(
            """
            SELECT id, quilt_id, thumbnail_data, mime_type, caption, sort_order, is_cover
            FROM photos
            ORDER BY quilt_id, sort_order
            """
        ) { statement in
            QuiltPhoto(
                id: sqlite3_column_int64(statement, 0),
                quiltID: sqlite3_column_int64(statement, 1),
                thumbnailData: SQLiteDatabase.columnData(statement, 2),
                mimeType: SQLiteDatabase.columnString(statement, 3),
                caption: SQLiteDatabase.columnString(statement, 4),
                sortOrder: Int(sqlite3_column_int(statement, 5)),
                isCover: sqlite3_column_int(statement, 6) == 1
            )
        }
        photosByQuiltID = Dictionary(grouping: photos, by: \.quiltID)
    }

    private static func bookmarkedDatabaseURL() throws -> URL? {
        if let bookmark = UserDefaults.standard.data(forKey: databaseBookmarkKey) {
            var isStale = false
            return try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }

        if let path = UserDefaults.standard.string(forKey: legacyDatabasePathKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private static func clearSavedDatabaseBookmark() {
        UserDefaults.standard.removeObject(forKey: databaseBookmarkKey)
        UserDefaults.standard.removeObject(forKey: legacyDatabasePathKey)
    }

    private static func applicationDatabaseURL() throws -> URL {
        try applicationSupportDirectory()
            .appendingPathComponent(applicationDatabaseFilename, isDirectory: false)
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

    private static func databaseCompatibility(at url: URL) -> DatabaseCompatibility {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let database = try SQLiteDatabase(path: url)
            try validateQuiltLogDatabase(database)
            return .quiltLog
        } catch let error as SQLiteError {
            switch error {
            case .prepareFailed, .stepFailed:
                return .sqliteButNotQuiltLog
            case .openFailed, .bindFailed:
                return .notSQLite
            }
        } catch {
            return .notSQLite
        }
    }

    private static func validateQuiltLogDatabase(_ database: SQLiteDatabase) throws {
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

        _ = try database.query(
            """
            SELECT id, sequence_number, quilt_name, pattern_name, fabric_reminder, approx_size,
                   quilt_date, status, gifted_already, recipient, notes
            FROM quilts
            LIMIT 1
            """
        ) { _ in
            true
        }

        _ = try database.query(
            """
            SELECT id, quilt_id, thumbnail_data, mime_type, caption, sort_order, is_cover
            FROM photos
            LIMIT 1
            """
        ) { _ in
            true
        }
    }

    private static func replaceApplicationDatabase(with sourceURL: URL) throws {
        let destinationURL = try applicationDatabaseURL()
        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return
        }

        let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceDatabase = try SQLiteDatabase(path: sourceURL)
        try validateQuiltLogDatabase(sourceDatabase)

        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try? FileManager.default.removeItem(at: temporaryURL)
        try sourceDatabase.backup(to: temporaryURL)
        try removeDatabaseFiles(at: destinationURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }

    private static func removeDatabaseFiles(at url: URL) throws {
        let fileManager = FileManager.default
        let urls = [
            url,
            URL(fileURLWithPath: url.path + "-journal"),
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func createEmptyDatabase(at url: URL) throws {
        let database = try SQLiteDatabase(path: url, createIfNeeded: true)
        try database.execute(
            """
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS schema_metadata (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS quilts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sequence_number INTEGER NOT NULL UNIQUE,
              quilt_name TEXT NOT NULL,
              pattern_name TEXT NOT NULL DEFAULT '',
              fabric_reminder TEXT NOT NULL DEFAULT '',
              approx_size TEXT NOT NULL DEFAULT '',
              quilt_date TEXT,
              status TEXT NOT NULL,
              gifted_already INTEGER NOT NULL DEFAULT 0 CHECK (gifted_already IN (0, 1)),
              recipient TEXT NOT NULL DEFAULT '',
              notes TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS photos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              quilt_id INTEGER NOT NULL REFERENCES quilts(id) ON DELETE CASCADE,
              image_data BLOB NOT NULL,
              thumbnail_data BLOB,
              mime_type TEXT NOT NULL,
              caption TEXT NOT NULL DEFAULT '',
              sort_order INTEGER NOT NULL DEFAULT 0,
              is_cover INTEGER NOT NULL DEFAULT 0 CHECK (is_cover IN (0, 1)),
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_quilts_status_sequence ON quilts(status, sequence_number);
            CREATE INDEX IF NOT EXISTS idx_photos_quilt_sort ON photos(quilt_id, sort_order);
            INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', '1');
            """
        )
    }

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
}
