// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import QuiltLog

final class PDFExportPresetTests: XCTestCase {
    func testDatedDefaultFilenameUsesNumericDatePrefix() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 12)))

        XCTAssertEqual(
            PDFExportPreset.completeLog.datedDefaultFilename(on: date),
            "20260607 Quilt Log - Complete.pdf"
        )
    }

    func testDatedDefaultFilenamesPreservePresetNames() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)))

        XCTAssertEqual(
            PDFExportPreset.completeLog.datedDefaultFilename(on: date),
            "20260102 Quilt Log - Complete.pdf"
        )
        XCTAssertEqual(
            PDFExportPreset.availableToGift.datedDefaultFilename(on: date),
            "20260102 Quilt Log - Available to Gift.pdf"
        )
        XCTAssertEqual(
            PDFExportPreset.visualCatalog.datedDefaultFilename(on: date),
            "20260102 Quilt Log - Visual Catalog.pdf"
        )
    }
}
