// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum PDFExportPreset: String, CaseIterable, Identifiable {
    case completeLog
    case availableToGift
    case visualCatalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completeLog: "Complete Log"
        case .availableToGift: "Available to Gift"
        case .visualCatalog: "Visual Catalog"
        }
    }

    var details: String {
        switch self {
        case .completeLog:
            "Compact table with quilt details and cover thumbnails."
        case .availableToGift:
            "Quilts not marked gifted, formatted for sharing."
        case .visualCatalog:
            "Nine cover images per page with sequence number, title, and availability."
        }
    }

    var defaultFilename: String {
        switch self {
        case .completeLog: "Quilt Log - Complete.pdf"
        case .availableToGift: "Quilt Log - Available to Gift.pdf"
        case .visualCatalog: "Quilt Log - Visual Catalog.pdf"
        }
    }

    var datedDefaultFilename: String {
        datedDefaultFilename(on: Date())
    }

    func datedDefaultFilename(on date: Date) -> String {
        "\(Self.filenameDateFormatter.string(from: date)) \(defaultFilename)"
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
