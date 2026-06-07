// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class UserPreferences: ObservableObject {
    @Published var exportOwnerName: String {
        didSet {
            defaults.set(exportOwnerName, forKey: Self.exportOwnerNameKey)
        }
    }

    @Published var hideRecipientsOnScreen: Bool {
        didSet {
            defaults.set(hideRecipientsOnScreen, forKey: Self.hideRecipientsOnScreenKey)
        }
    }

    @Published var contentDisplayMode: String {
        didSet {
            defaults.set(contentDisplayMode, forKey: Self.contentDisplayModeKey)
        }
    }

    @Published var contentSortOrder: String {
        didSet {
            defaults.set(contentSortOrder, forKey: Self.contentSortOrderKey)
        }
    }

    @Published var contentGroupingMode: String {
        didSet {
            defaults.set(contentGroupingMode, forKey: Self.contentGroupingModeKey)
        }
    }

    @Published var contentAvailabilityFilter: String {
        didSet {
            defaults.set(contentAvailabilityFilter, forKey: Self.contentAvailabilityFilterKey)
        }
    }

    private let defaults: UserDefaults
    private static let exportOwnerNameKey = "exportOwnerName"
    private static let hideRecipientsOnScreenKey = "hideRecipientsOnScreen"
    private static let contentDisplayModeKey = "contentDisplayMode"
    private static let contentSortOrderKey = "contentSortOrder"
    private static let contentGroupingModeKey = "contentGroupingMode"
    private static let contentAvailabilityFilterKey = "contentAvailabilityFilter"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideRecipientsOnScreen = defaults.bool(forKey: Self.hideRecipientsOnScreenKey)
        contentDisplayMode = defaults.string(forKey: Self.contentDisplayModeKey) ?? "list"
        contentSortOrder = defaults.string(forKey: Self.contentSortOrderKey) ?? "oldestFirst"
        contentGroupingMode = defaults.string(forKey: Self.contentGroupingModeKey) ?? "status"
        contentAvailabilityFilter = defaults.string(forKey: Self.contentAvailabilityFilterKey) ?? "all"
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
#if os(macOS)
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        return NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
#else
        return "Quilt Log"
#endif
    }
}
