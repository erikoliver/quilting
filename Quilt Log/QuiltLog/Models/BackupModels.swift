// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct QuiltLogBackup: Codable {
    var formatVersion: Int
    var exportedAt: Date
    var syncBehavior: String
    var quilts: [QuiltBackup]
}

struct QuiltBackup: Codable {
    var uuid: String
    var legacyID: Int64
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
    var photos: [QuiltPhotoBackup]
}

struct QuiltPhotoBackup: Codable {
    var uuid: String
    var legacyID: Int64
    var mimeType: String
    var caption: String
    var sortOrder: Int
    var isCover: Bool
    var createdAt: Date
    var imageFilename: String?
    var thumbnailFilename: String?
}

