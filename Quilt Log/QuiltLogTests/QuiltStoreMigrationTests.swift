// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SQLite3
import SwiftData
import XCTest
@testable import QuiltLog

#if os(macOS)
@MainActor
final class QuiltStoreMigrationTests: XCTestCase {
    func testImportsLegacySQLiteIntoSwiftDataAndExportsBackupZIP() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiltStoreMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let legacyURL = temporaryDirectory.appendingPathComponent("legacy.sqlite")
        try makeLegacyDatabase(at: legacyURL)

        let schema = Schema([
            QuiltRecord.self,
            QuiltPhotoRecord.self,
            QuiltLogMetadata.self
        ])
        let configuration = ModelConfiguration(
            "QuiltStoreMigrationTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = QuiltStore(modelContainer: container)

        try await store.importDatabase(from: legacyURL)

        let quilt = try XCTUnwrap(store.quilts.first)
        XCTAssertEqual(store.quilts.count, 1)
        XCTAssertEqual(quilt.sequenceNumber, 7)
        XCTAssertEqual(quilt.quiltName, "Migration Sample")
        XCTAssertEqual(quilt.patternName, "Cabin")
        XCTAssertEqual(quilt.status, QuiltStatus.done.rawValue)

        let photos = try XCTUnwrap(store.photosByQuiltID[quilt.id])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].caption, "Front")
        XCTAssertEqual(photos[0].sortOrder, 0)
        XCTAssertTrue(photos[0].isCover)

        let backupURL = temporaryDirectory.appendingPathComponent("backup.zip")
        try store.exportJSONBackup(to: backupURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        let backupSize = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(backupSize.intValue, 0)
    }

    private func makeLegacyDatabase(at url: URL) throws {
        let database = try SQLiteDatabase(path: url, createIfNeeded: true)
        try database.execute(
            """
            CREATE TABLE schema_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE quilts (
                id INTEGER PRIMARY KEY,
                sequence_number INTEGER NOT NULL,
                quilt_name TEXT NOT NULL DEFAULT '',
                pattern_name TEXT NOT NULL DEFAULT '',
                fabric_reminder TEXT NOT NULL DEFAULT '',
                approx_size TEXT NOT NULL DEFAULT '',
                quilt_date TEXT,
                status TEXT NOT NULL DEFAULT '',
                gifted_already INTEGER NOT NULL DEFAULT 0,
                recipient TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE photos (
                id INTEGER PRIMARY KEY,
                quilt_id INTEGER NOT NULL,
                image_data BLOB,
                thumbnail_data BLOB,
                mime_type TEXT NOT NULL DEFAULT 'image/jpeg',
                caption TEXT NOT NULL DEFAULT '',
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_cover INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                FOREIGN KEY(quilt_id) REFERENCES quilts(id) ON DELETE CASCADE
            )
            """
        )
        try database.run(
            """
            INSERT INTO schema_metadata (key, value)
            VALUES ('schema_version', '1')
            """
        )
        try database.run(
            """
            INSERT INTO quilts (
                id, sequence_number, quilt_name, pattern_name, fabric_reminder,
                approx_size, quilt_date, status, gifted_already, recipient, notes,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, 42)
            sqlite3_bind_int(statement, 2, 7)
            try SQLiteDatabase.bindText("Migration Sample", to: 3, in: statement)
            try SQLiteDatabase.bindText("Cabin", to: 4, in: statement)
            try SQLiteDatabase.bindText("Blue fabric", to: 5, in: statement)
            try SQLiteDatabase.bindText("60 x 72", to: 6, in: statement)
            try SQLiteDatabase.bindText("2026-06-07", to: 7, in: statement)
            try SQLiteDatabase.bindText(QuiltStatus.done.rawValue, to: 8, in: statement)
            sqlite3_bind_int(statement, 9, 1)
            try SQLiteDatabase.bindText("Dana", to: 10, in: statement)
            try SQLiteDatabase.bindText("Imported by migration test.", to: 11, in: statement)
            try SQLiteDatabase.bindText("2026-06-07 12:00:00", to: 12, in: statement)
            try SQLiteDatabase.bindText("2026-06-07 12:30:00", to: 13, in: statement)
        }
        try database.run(
            """
            INSERT INTO photos (
                id, quilt_id, image_data, thumbnail_data, mime_type, caption,
                sort_order, is_cover, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            sqlite3_bind_int64(statement, 1, 100)
            sqlite3_bind_int64(statement, 2, 42)
            try SQLiteDatabase.bindData(Data([0xFF, 0xD8, 0xFF, 0xD9]), to: 3, in: statement)
            try SQLiteDatabase.bindData(Data([0xFF, 0xD8, 0xFF, 0xD9]), to: 4, in: statement)
            try SQLiteDatabase.bindText("image/jpeg", to: 5, in: statement)
            try SQLiteDatabase.bindText("Front", to: 6, in: statement)
            sqlite3_bind_int(statement, 7, 0)
            sqlite3_bind_int(statement, 8, 1)
            try SQLiteDatabase.bindText("2026-06-07 12:45:00", to: 9, in: statement)
        }
    }
}
#endif
