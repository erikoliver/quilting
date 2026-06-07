// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct Quilt: Identifiable, Hashable {
    var id: Int64
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
}

struct QuiltPhoto: Identifiable, Hashable {
    var id: Int64
    var quiltID: Int64
    var thumbnailData: Data?
    var mimeType: String
    var caption: String
    var sortOrder: Int
    var isCover: Bool
}

enum QuiltStatus: String, CaseIterable, Identifiable {
    case done = "1 - Done"
    case backFromLongarm = "2 - Back from Longarm"
    case atLongarm = "3 - At Longarm"
    case toLongarm = "4 - To Longarm"
    case inProgress = "5 - In Progress"

    var id: String { rawValue }
}
