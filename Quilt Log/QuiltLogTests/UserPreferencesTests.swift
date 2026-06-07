// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import QuiltLog

@MainActor
final class UserPreferencesTests: XCTestCase {
    func testHideRecipientsOnScreenPersists() {
        let suiteName = "UserPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hideRecipientsOnScreen)

        preferences.hideRecipientsOnScreen = true

        let reloadedPreferences = UserPreferences(defaults: defaults)
        XCTAssertTrue(reloadedPreferences.hideRecipientsOnScreen)
    }

    func testContentViewPreferencesPersist() {
        let suiteName = "UserPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferences(defaults: defaults)
        XCTAssertEqual(preferences.contentDisplayMode, "list")
        XCTAssertEqual(preferences.contentSortOrder, "oldestFirst")
        XCTAssertEqual(preferences.contentGroupingMode, "status")
        XCTAssertEqual(preferences.contentAvailabilityFilter, "all")

        preferences.contentDisplayMode = "gallery"
        preferences.contentSortOrder = "newestFirst"
        preferences.contentGroupingMode = "availability"
        preferences.contentAvailabilityFilter = "status:5 - In Progress"

        let reloadedPreferences = UserPreferences(defaults: defaults)
        XCTAssertEqual(reloadedPreferences.contentDisplayMode, "gallery")
        XCTAssertEqual(reloadedPreferences.contentSortOrder, "newestFirst")
        XCTAssertEqual(reloadedPreferences.contentGroupingMode, "availability")
        XCTAssertEqual(reloadedPreferences.contentAvailabilityFilter, "status:5 - In Progress")
    }
}
