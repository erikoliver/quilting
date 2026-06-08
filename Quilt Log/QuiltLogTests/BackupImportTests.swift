// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import XCTest
@testable import QuiltLog

@MainActor
final class BackupImportTests: XCTestCase {
    func testImportsBackupIntoEmptyLibrary() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let backupURL = temporaryDirectory.appendingPathComponent("backup.zip")
        try makeBackup(
            at: backupURL,
            exportedAt: date("2026-06-07T12:00:00Z"),
            quilts: [
                backupQuilt(
                    uuid: "quilt-a",
                    sequenceNumber: 7,
                    quiltName: "Imported Quilt",
                    updatedAt: date("2026-06-07T12:30:00Z"),
                    photos: [
                        backupPhoto(uuid: "photo-a", caption: "Front", imageFilename: "images/photo-a.jpg")
                    ]
                )
            ],
            files: [
                "images/photo-a.jpg": Data([0x01, 0x02, 0x03])
            ],
            temporaryDirectory: temporaryDirectory
        )

        let store = try makeStore()
        let preflight = try store.preflightJSONBackupImport(from: backupURL)
        XCTAssertEqual(preflight.totalQuilts, 1)
        XCTAssertEqual(preflight.totalPhotos, 1)
        XCTAssertEqual(preflight.newQuilts, 1)
        XCTAssertEqual(preflight.overlappingQuilts, 0)

        try store.importJSONBackup(from: backupURL, resolution: .skipExisting)

        let quilt = try XCTUnwrap(store.quilts.first)
        XCTAssertEqual(store.quilts.count, 1)
        XCTAssertEqual(quilt.sequenceNumber, 1)
        XCTAssertEqual(quilt.quiltName, "Imported Quilt")

        let photos = try XCTUnwrap(store.photosByQuiltID[quilt.id])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].caption, "Front")
        XCTAssertEqual(photos[0].thumbnailData, nil)
    }

    func testSkipsOverlappingQuiltsAndImportsOnlyNewQuilts() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let originalBackupURL = temporaryDirectory.appendingPathComponent("original.zip")
        try makeBackup(
            at: originalBackupURL,
            exportedAt: date("2026-06-07T12:00:00Z"),
            quilts: [
                backupQuilt(uuid: "quilt-a", sequenceNumber: 1, quiltName: "Current Quilt")
            ],
            temporaryDirectory: temporaryDirectory
        )

        let importBackupURL = temporaryDirectory.appendingPathComponent("import.zip")
        try makeBackup(
            at: importBackupURL,
            exportedAt: date("2026-06-08T12:00:00Z"),
            quilts: [
                backupQuilt(uuid: "quilt-a", sequenceNumber: 1, quiltName: "Replacement Quilt"),
                backupQuilt(uuid: "quilt-b", sequenceNumber: 1, quiltName: "New Quilt")
            ],
            temporaryDirectory: temporaryDirectory
        )

        let store = try makeStore()
        try store.importJSONBackup(from: originalBackupURL, resolution: .skipExisting)

        let preflight = try store.preflightJSONBackupImport(from: importBackupURL)
        XCTAssertEqual(preflight.newQuilts, 1)
        XCTAssertEqual(preflight.overlappingQuilts, 1)

        try store.importJSONBackup(from: importBackupURL, resolution: .skipExisting)

        XCTAssertEqual(store.quilts.map(\.quiltName), ["Current Quilt", "New Quilt"])
        XCTAssertEqual(store.quilts.map(\.sequenceNumber), [1, 2])
    }

    func testReplacesOverlappingWholeQuiltAndKeepsCurrentSequenceNumber() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let originalBackupURL = temporaryDirectory.appendingPathComponent("original.zip")
        try makeBackup(
            at: originalBackupURL,
            exportedAt: date("2026-06-07T12:00:00Z"),
            quilts: [
                backupQuilt(
                    uuid: "quilt-a",
                    sequenceNumber: 4,
                    quiltName: "Current Quilt",
                    notes: "Old notes",
                    photos: [
                        backupPhoto(uuid: "photo-old", caption: "Old photo", imageFilename: "images/photo-old.jpg")
                    ]
                )
            ],
            files: [
                "images/photo-old.jpg": Data([0x01])
            ],
            temporaryDirectory: temporaryDirectory
        )

        let importBackupURL = temporaryDirectory.appendingPathComponent("import.zip")
        try makeBackup(
            at: importBackupURL,
            exportedAt: date("2026-06-08T12:00:00Z"),
            quilts: [
                backupQuilt(
                    uuid: "quilt-a",
                    sequenceNumber: 99,
                    quiltName: "Replacement Quilt",
                    notes: "New notes",
                    updatedAt: date("2026-06-08T13:00:00Z"),
                    photos: [
                        backupPhoto(uuid: "photo-new", caption: "New photo", imageFilename: "images/photo-new.jpg")
                    ]
                ),
                backupQuilt(uuid: "quilt-b", sequenceNumber: 99, quiltName: "New Quilt")
            ],
            files: [
                "images/photo-new.jpg": Data([0x02])
            ],
            temporaryDirectory: temporaryDirectory
        )

        let store = try makeStore()
        try store.importJSONBackup(from: originalBackupURL, resolution: .skipExisting)

        try store.importJSONBackup(from: importBackupURL, resolution: .replaceExisting)

        XCTAssertEqual(store.quilts.map(\.quiltName), ["Replacement Quilt", "New Quilt"])
        XCTAssertEqual(store.quilts.map(\.sequenceNumber), [1, 2])

        let replacedQuilt = try XCTUnwrap(store.quilts.first)
        XCTAssertEqual(replacedQuilt.notes, "New notes")

        let photos = try XCTUnwrap(store.photosByQuiltID[replacedQuilt.id])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0].caption, "New photo")
    }

    func testInvalidBackupFailsWithoutChangingLibrary() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let originalBackupURL = temporaryDirectory.appendingPathComponent("original.zip")
        try makeBackup(
            at: originalBackupURL,
            exportedAt: date("2026-06-07T12:00:00Z"),
            quilts: [
                backupQuilt(uuid: "quilt-a", sequenceNumber: 1, quiltName: "Current Quilt")
            ],
            temporaryDirectory: temporaryDirectory
        )

        let invalidBackupURL = temporaryDirectory.appendingPathComponent("invalid.zip")
        try makeBackup(
            at: invalidBackupURL,
            exportedAt: date("2026-06-08T12:00:00Z"),
            quilts: [
                backupQuilt(
                    uuid: "quilt-b",
                    sequenceNumber: 1,
                    quiltName: "Broken Quilt",
                    photos: [
                        backupPhoto(uuid: "photo-b", caption: "Missing", imageFilename: "images/missing.jpg")
                    ]
                )
            ],
            temporaryDirectory: temporaryDirectory
        )

        let store = try makeStore()
        try store.importJSONBackup(from: originalBackupURL, resolution: .skipExisting)

        XCTAssertThrowsError(try store.importJSONBackup(from: invalidBackupURL, resolution: .skipExisting))
        XCTAssertEqual(store.quilts.map(\.quiltName), ["Current Quilt"])
    }

    private func makeStore() throws -> QuiltStore {
        let schema = Schema([
            QuiltRecord.self,
            QuiltPhotoRecord.self,
            QuiltLogMetadata.self
        ])
        let configuration = ModelConfiguration(
            "BackupImportTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return QuiltStore(modelContainer: container)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBackup(
        at url: URL,
        exportedAt: Date,
        quilts: [QuiltBackup],
        files: [String: Data] = [:],
        temporaryDirectory: URL
    ) throws {
        let workingDirectory = temporaryDirectory
            .appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let manifest = QuiltLogBackup(
            formatVersion: 1,
            exportedAt: exportedAt,
            syncBehavior: "Test backup",
            quilts: quilts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: workingDirectory.appendingPathComponent("manifest.json"))

        for (relativePath, data) in files {
            let fileURL = workingDirectory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
        }

        try zip(directory: workingDirectory, to: url)
    }

    private func zip(directory: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-qry", destination.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func backupQuilt(
        uuid: String,
        sequenceNumber: Int,
        quiltName: String,
        notes: String = "",
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        photos: [QuiltPhotoBackup] = []
    ) -> QuiltBackup {
        QuiltBackup(
            uuid: uuid,
            legacyID: 0,
            sequenceNumber: sequenceNumber,
            quiltName: quiltName,
            patternName: "Pattern",
            fabricReminder: "Fabric",
            approxSize: "60 x 72",
            quiltDate: "2026-06-07",
            status: QuiltStatus.done.rawValue,
            giftedAlready: false,
            recipient: "",
            notes: notes,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: updatedAt,
            photos: photos
        )
    }

    private func backupPhoto(
        uuid: String,
        caption: String,
        imageFilename: String? = nil,
        thumbnailFilename: String? = nil
    ) -> QuiltPhotoBackup {
        QuiltPhotoBackup(
            uuid: uuid,
            legacyID: 0,
            mimeType: "image/jpeg",
            caption: caption,
            sortOrder: 0,
            isCover: true,
            createdAt: Date(timeIntervalSince1970: 0),
            imageFilename: imageFilename,
            thumbnailFilename: thumbnailFilename
        )
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
