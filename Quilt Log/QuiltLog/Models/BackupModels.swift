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
    var startedDate: String
    var designerName: String
    var patternName: String
    var fabricStore: String
    var fabricLine: String
    var fabricReminder: String
    var approxSize: String
    var quiltDate: String
    var quiltingCompletedDate: String
    var quilterName: String
    var quiltingPatternName: String
    var status: String
    var giftedAlready: Bool
    var recipient: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var photos: [QuiltPhotoBackup]

    init(
        uuid: String,
        legacyID: Int64,
        sequenceNumber: Int,
        quiltName: String,
        startedDate: String = "",
        designerName: String = "",
        patternName: String,
        fabricStore: String = "",
        fabricLine: String = "",
        fabricReminder: String,
        approxSize: String,
        quiltDate: String,
        quiltingCompletedDate: String = "",
        quilterName: String = "",
        quiltingPatternName: String = "",
        status: String,
        giftedAlready: Bool,
        recipient: String,
        notes: String,
        createdAt: Date,
        updatedAt: Date,
        photos: [QuiltPhotoBackup]
    ) {
        self.uuid = uuid
        self.legacyID = legacyID
        self.sequenceNumber = sequenceNumber
        self.quiltName = quiltName
        self.startedDate = startedDate
        self.designerName = designerName
        self.patternName = patternName
        self.fabricStore = fabricStore
        self.fabricLine = fabricLine
        self.fabricReminder = fabricReminder
        self.approxSize = approxSize
        self.quiltDate = quiltDate
        self.quiltingCompletedDate = quiltingCompletedDate
        self.quilterName = quilterName
        self.quiltingPatternName = quiltingPatternName
        self.status = status
        self.giftedAlready = giftedAlready
        self.recipient = recipient
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey {
        case uuid
        case legacyID
        case sequenceNumber
        case quiltName
        case startedDate
        case designerName
        case patternName
        case fabricStore
        case fabricLine
        case fabricReminder
        case approxSize
        case quiltDate
        case quiltingCompletedDate
        case quilterName
        case quiltingPatternName
        case status
        case giftedAlready
        case recipient
        case notes
        case createdAt
        case updatedAt
        case photos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        legacyID = try container.decode(Int64.self, forKey: .legacyID)
        sequenceNumber = try container.decode(Int.self, forKey: .sequenceNumber)
        quiltName = try container.decode(String.self, forKey: .quiltName)
        startedDate = try container.decodeIfPresent(String.self, forKey: .startedDate) ?? ""
        designerName = try container.decodeIfPresent(String.self, forKey: .designerName) ?? ""
        patternName = try container.decode(String.self, forKey: .patternName)
        fabricStore = try container.decodeIfPresent(String.self, forKey: .fabricStore) ?? ""
        fabricLine = try container.decodeIfPresent(String.self, forKey: .fabricLine) ?? ""
        fabricReminder = try container.decode(String.self, forKey: .fabricReminder)
        approxSize = try container.decode(String.self, forKey: .approxSize)
        quiltDate = try container.decode(String.self, forKey: .quiltDate)
        quiltingCompletedDate = try container.decodeIfPresent(String.self, forKey: .quiltingCompletedDate) ?? ""
        quilterName = try container.decodeIfPresent(String.self, forKey: .quilterName) ?? ""
        quiltingPatternName = try container.decodeIfPresent(String.self, forKey: .quiltingPatternName) ?? ""
        status = try container.decode(String.self, forKey: .status)
        giftedAlready = try container.decode(Bool.self, forKey: .giftedAlready)
        recipient = try container.decode(String.self, forKey: .recipient)
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        photos = try container.decode([QuiltPhotoBackup].self, forKey: .photos)
    }
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
