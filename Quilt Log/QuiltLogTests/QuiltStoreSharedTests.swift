// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import XCTest
@testable import QuiltLog

@MainActor
final class QuiltStoreSharedTests: XCTestCase {
    func testCreatesSavesAndRenumbersQuilts() async throws {
        let store = try makeStore()

        let createdFirstID = await store.createQuilt()
        let createdSecondID = await store.createQuilt()
        let firstID = try XCTUnwrap(createdFirstID)
        let secondID = try XCTUnwrap(createdSecondID)
        XCTAssertEqual(store.quilts.map(\.sequenceNumber), [1, 2])

        var second = try XCTUnwrap(store.quilts.first { $0.id == secondID })
        second.sequenceNumber = 1
        second.quiltName = "Moved Quilt"
        await store.saveMakingSpace(for: second)

        XCTAssertEqual(store.quilts.map(\.id), [secondID, firstID])
        XCTAssertEqual(store.quilts.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(store.quilts.first?.quiltName, "Moved Quilt")
    }

    func testTemporaryPDFExportCreatesNonemptyFile() async throws {
        let store = try makeStore()
        let createdQuiltID = await store.createQuilt()
        let quiltID = try XCTUnwrap(createdQuiltID)

        var quilt = try XCTUnwrap(store.quilts.first { $0.id == quiltID })
        quilt.quiltName = "PDF Sample"
        quilt.patternName = "Cabin"
        quilt.status = QuiltStatus.done.rawValue
        let didSave = await store.save(quilt)
        XCTAssertTrue(didSave)

        let url = try store.temporaryPDFExportURL(for: .completeLog, ownerName: "Test Quilter")
        defer { try? FileManager.default.removeItem(at: url) }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(size.intValue, 0)
    }

    func testSavesAndSearchesStructuredDetailFields() async throws {
        let store = try makeStore()
        let createdQuiltID = await store.createQuilt()
        let quiltID = try XCTUnwrap(createdQuiltID)

        var quilt = try XCTUnwrap(store.quilts.first { $0.id == quiltID })
        quilt.startedDate = "2026-01-15"
        quilt.designerName = "Deb Tucker"
        quilt.fabricStore = "Needle & Thread"
        quilt.fabricLine = "Indelible Ink"
        quilt.quiltingCompletedDate = "2026-06-07"
        quilt.quilterName = "Longarm Studio"
        quilt.quiltingPatternName = "Baptist Fan"
        let didSave = await store.save(quilt)
        XCTAssertTrue(didSave)

        let saved = try XCTUnwrap(store.quilts.first { $0.id == quiltID })
        XCTAssertEqual(saved.designerName, "Deb Tucker")
        XCTAssertEqual(saved.fabricStore, "Needle & Thread")
        XCTAssertEqual(saved.quiltingPatternName, "Baptist Fan")

        store.searchText = "indelible"
        XCTAssertEqual(store.filteredQuilts.map(\.id), [quiltID])
    }

#if DEBUG && targetEnvironment(simulator)
    func testImportsBundledSampleDataOnSimulator() async throws {
        let store = try makeStore()

        await store.importBundledSampleData()

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.quilts.count, 18)
        XCTAssertEqual(Set(store.quilts.map(\.status)), [
            QuiltStatus.done.rawValue,
            QuiltStatus.backFromLongarm.rawValue,
            QuiltStatus.atLongarm.rawValue,
            QuiltStatus.toLongarm.rawValue,
        ])
        XCTAssertEqual(store.photosByQuiltID.values.reduce(0) { $0 + $1.count }, 18)
        XCTAssertTrue(store.quilts.contains { !$0.recipient.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.startedDate.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.designerName.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.fabricStore.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.fabricLine.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.quiltingCompletedDate.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.quilterName.isEmpty })
        XCTAssertTrue(store.quilts.contains { !$0.quiltingPatternName.isEmpty })
        for quilt in store.quilts where !quilt.quiltingCompletedDate.isEmpty {
            XCTAssertGreaterThanOrEqual(
                daysBetween(quilt.quiltDate, quilt.quiltingCompletedDate),
                3,
                "Quilting completed date should be at least three days after piecing completed date for \(quilt.quiltName)."
            )
        }
    }
#endif

    private func makeStore() throws -> QuiltStore {
        let schema = Schema([
            QuiltRecord.self,
            QuiltPhotoRecord.self,
            QuiltLogMetadata.self
        ])
        let configuration = ModelConfiguration(
            "QuiltStoreSharedTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return QuiltStore(modelContainer: container)
    }

#if DEBUG && targetEnvironment(simulator)
    private func daysBetween(_ start: String, _ end: String) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let startDate = formatter.date(from: start),
              let endDate = formatter.date(from: end),
              let days = Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day else {
            return Int.min
        }
        return days
    }
#endif
}
