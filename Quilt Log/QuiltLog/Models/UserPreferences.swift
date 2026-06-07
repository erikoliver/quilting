// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation

@MainActor
final class UserPreferences: ObservableObject {
    @Published var exportOwnerName: String {
        didSet {
            defaults.set(exportOwnerName, forKey: Self.exportOwnerNameKey)
        }
    }

    private let defaults: UserDefaults
    private static let exportOwnerNameKey = "exportOwnerName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let storedName = defaults.string(forKey: Self.exportOwnerNameKey) {
            exportOwnerName = storedName
        } else {
            exportOwnerName = Self.systemUserName()
            defaults.set(exportOwnerName, forKey: Self.exportOwnerNameKey)
        }
    }

    func resetExportOwnerNameToSystemUser() {
        exportOwnerName = Self.systemUserName()
    }

    var exportOwnerNameForDisplay: String {
        let trimmedName = exportOwnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Quilt Log" : "\(trimmedName) Quilt Log"
    }

    private static func systemUserName() -> String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        return NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
