// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

@Model
final class QuiltRecord {
    var uuid: String = UUID().uuidString
    var legacyID: Int64 = 0
    var sequenceNumber: Int = 0
    var quiltName: String = ""
    var startedDate: String = ""
    var designerName: String = ""
    var patternName: String = ""
    var fabricStore: String = ""
    var fabricLine: String = ""
    var fabricReminder: String = ""
    var approxSize: String = ""
    var quiltDate: String = ""
    var quiltingCompletedDate: String = ""
    var quilterName: String = ""
    var quiltingPatternName: String = ""
    var status: String = QuiltStatus.inProgress.rawValue
    var giftedAlready: Bool = false
    var recipient: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var photos: [QuiltPhotoRecord]? = []

    init(
        uuid: String = UUID().uuidString,
        legacyID: Int64 = 0,
        sequenceNumber: Int,
        quiltName: String,
        startedDate: String = "",
        designerName: String = "",
        patternName: String = "",
        fabricStore: String = "",
        fabricLine: String = "",
        fabricReminder: String = "",
        approxSize: String = "",
        quiltDate: String = "",
        quiltingCompletedDate: String = "",
        quilterName: String = "",
        quiltingPatternName: String = "",
        status: String = QuiltStatus.inProgress.rawValue,
        giftedAlready: Bool = false,
        recipient: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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
    }
}

@Model
final class QuiltPhotoRecord {
    var uuid: String = UUID().uuidString
    var legacyID: Int64 = 0
    var mimeType: String = "image/jpeg"
    var caption: String = ""
    var sortOrder: Int = 0
    var isCover: Bool = false
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var quilt: QuiltRecord?

    init(
        uuid: String = UUID().uuidString,
        legacyID: Int64 = 0,
        mimeType: String,
        caption: String = "",
        sortOrder: Int,
        isCover: Bool,
        createdAt: Date = Date(),
        imageData: Data?,
        thumbnailData: Data?,
        quilt: QuiltRecord?
    ) {
        self.uuid = uuid
        self.legacyID = legacyID
        self.mimeType = mimeType
        self.caption = caption
        self.sortOrder = sortOrder
        self.isCover = isCover
        self.createdAt = createdAt
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.quilt = quilt
    }
}

@Model
final class QuiltLogMetadata {
    var key: String = ""
    var value: String = ""
    var updatedAt: Date = Date()

    init(key: String, value: String, updatedAt: Date = Date()) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

enum QuiltRecordID {
    static func numericID(for uuid: String) -> Int64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in uuid.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int64(hash & 0x7fff_ffff_ffff_ffff)
    }
}
