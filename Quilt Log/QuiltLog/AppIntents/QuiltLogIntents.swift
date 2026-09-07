// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

enum QuiltIntentStatus: String, AppEnum, CaseIterable {
    case done
    case backFromLongarm
    case atLongarm
    case toLongarm
    case inProgress
    case notStarted

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Quilt Status")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .done: "Done",
        .backFromLongarm: "Back from Longarm",
        .atLongarm: "At Longarm",
        .toLongarm: "To Longarm",
        .inProgress: "In Progress",
        .notStarted: "Not Started"
    ]

    init?(quiltStatus: String) {
        guard let status = QuiltStatus(rawValue: quiltStatus) else { return nil }
        switch status {
        case .done: self = .done
        case .backFromLongarm: self = .backFromLongarm
        case .atLongarm: self = .atLongarm
        case .toLongarm: self = .toLongarm
        case .inProgress: self = .inProgress
        case .notStarted: self = .notStarted
        }
    }

    var quiltStatus: QuiltStatus {
        switch self {
        case .done: .done
        case .backFromLongarm: .backFromLongarm
        case .atLongarm: .atLongarm
        case .toLongarm: .toLongarm
        case .inProgress: .inProgress
        case .notStarted: .notStarted
        }
    }
}

struct QuiltEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Quilt",
        numericFormat: "\(placeholder: .int) quilts"
    )
    static let defaultQuery = QuiltEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Sequence Number")
    var sequenceNumber: Int

    @Property(title: "Status")
    var status: QuiltIntentStatus

    @Property(title: "Recipient")
    var recipient: String

    @Property(title: "Gifted")
    var isGifted: Bool

    // These fields enrich the on-device Spotlight record without making the
    // Shortcuts-facing display representation unwieldy.
    var searchableDescription: String
    var searchableKeywords: [String]
    var coverThumbnailData: Data?

    var displayRepresentation: DisplayRepresentation {
        let recipientDescription = recipient.isEmpty ? "No recipient" : "For \(recipient)"
        let image = coverThumbnailData.map {
            DisplayRepresentation.Image(data: $0, isTemplate: false, displayStyle: .default)
        } ?? DisplayRepresentation.Image(systemName: "square.grid.3x3.fill")
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "#\(sequenceNumber) · \(status.quiltStatus.rawValue) · \(recipientDescription)",
            image: image
        )
    }

    init(record: QuiltRecord) {
        id = record.uuid
        searchableDescription = [
            record.notes, record.patternName, record.designerName, record.fabricReminder,
            record.fabricLine, record.approxSize, record.quilterName, record.quiltingPatternName
        ].filter { !$0.isEmpty }.joined(separator: ". ")
        searchableKeywords = [
            record.status, record.patternName, record.designerName, record.fabricStore,
            record.fabricLine, record.recipient, record.quilterName
        ].filter { !$0.isEmpty }
        let sortedPhotos = (record.photos ?? []).sorted {
            if $0.isCover != $1.isCover { return $0.isCover }
            return $0.sortOrder < $1.sortOrder
        }
        coverThumbnailData = sortedPhotos.first?.thumbnailData
        name = record.quiltName
        sequenceNumber = record.sequenceNumber
        status = QuiltIntentStatus(quiltStatus: record.status) ?? .inProgress
        recipient = record.recipient
        isGifted = record.giftedAlready
    }
}

// IndexedEntity and indexAppEntities back-deploy to iOS 18/macOS 15. The
// availability boundary is important because Quilt Log still supports iOS 17
// and macOS 14.
@available(iOS 18.0, macOS 15.0, *)
extension QuiltEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = name
        attributes.contentDescription = searchableDescription
        attributes.keywords = searchableKeywords
        attributes.thumbnailData = coverThumbnailData
        return attributes
    }
}

struct QuiltEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [QuiltEntity.ID]) async throws -> [QuiltEntity] {
        try QuiltIntentRepository.entities(identifiers: Set(identifiers))
    }

    @MainActor
    func entities(matching string: String) async throws -> [QuiltEntity] {
        try QuiltIntentRepository.entities(matching: string)
    }

    @MainActor
    func suggestedEntities() async throws -> [QuiltEntity] {
        try QuiltIntentRepository.entities().prefix(20).map { $0 }
    }
}

struct FindQuiltsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Quilts"
    static let description = IntentDescription("Find quilts by name, notes, pattern, fabric, recipient, quilter, or status.")

    @Parameter(title: "Search", description: "Words to look for in the quilt log")
    var search: String?

    @Parameter(title: "Status")
    var status: QuiltIntentStatus?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[QuiltEntity]> & ProvidesDialog {
        let matches = try QuiltIntentRepository.entities(matching: search, status: status)
        let dialog: IntentDialog = matches.isEmpty
            ? "I couldn't find any matching quilts."
            : "I found \(matches.count) matching quilts."
        return .result(value: matches, dialog: dialog)
    }
}

struct GetQuiltDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Quilt Details"
    static let description = IntentDescription("Get a quilt's name, number, status, recipient, and gifted state for use in Shortcuts.")

    @Parameter(title: "Quilt")
    var quilt: QuiltEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QuiltEntity> & ProvidesDialog {
        let current = try QuiltIntentRepository.entity(identifier: quilt.id)
        return .result(
            value: current,
            dialog: "\(current.name) is \(current.status.quiltStatus.rawValue.lowercased())."
        )
    }
}

struct CreateQuiltIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Quilt"
    static let description = IntentDescription("Add a quilt to Quilt Log.")

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Status", default: .inProgress)
    var status: QuiltIntentStatus

    init() {}

    init(name: String, status: QuiltIntentStatus = .inProgress) {
        self.name = name
        self.status = status
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QuiltEntity> & ProvidesDialog {
        let created = try QuiltIntentRepository.create(name: name, status: status)
        return .result(value: created, dialog: "I added \(created.name) as quilt number \(created.sequenceNumber).")
    }
}

struct UpdateQuiltStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Update Quilt Status"
    static let description = IntentDescription("Change where a quilt is in your workflow.")

    @Parameter(title: "Quilt")
    var quilt: QuiltEntity

    @Parameter(title: "New Status")
    var status: QuiltIntentStatus

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QuiltEntity> & ProvidesDialog {
        let updated = try QuiltIntentRepository.updateStatus(identifier: quilt.id, status: status)
        return .result(value: updated, dialog: "\(updated.name) is now \(status.quiltStatus.rawValue.lowercased()).")
    }
}

struct MarkQuiltGiftedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Quilt Gifted"
    static let description = IntentDescription("Mark a quilt as gifted and optionally record its recipient.")

    @Parameter(title: "Quilt")
    var quilt: QuiltEntity

    @Parameter(title: "Recipient")
    var recipient: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QuiltEntity> & ProvidesDialog {
        let updated = try QuiltIntentRepository.markGifted(identifier: quilt.id, recipient: recipient)
        let recipientText = updated.recipient.isEmpty ? "" : " to \(updated.recipient)"
        return .result(value: updated, dialog: "I marked \(updated.name) as gifted\(recipientText).")
    }
}

struct QuiltLibrarySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Quilt Library"
    static let description = IntentDescription("Count all, active, completed, and gifted quilts in Quilt Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = try QuiltIntentRepository.summary()
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct QuiltLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindQuiltsIntent(),
            phrases: [
                "Find my quilts in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Find Quilts",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CreateQuiltIntent(name: "Untitled Quilt"),
            phrases: [
                "Start a new quilt in \(.applicationName)",
                "Add a quilt to \(.applicationName)"
            ],
            shortTitle: "Create Quilt",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: QuiltLibrarySummaryIntent(),
            phrases: [
                "Summarize my quilts in \(.applicationName)",
                "How many quilts are in \(.applicationName)"
            ],
            shortTitle: "Quilt Summary",
            systemImageName: "chart.bar"
        )
    }
}

private enum QuiltIntentError: LocalizedError {
    case libraryUnavailable
    case quiltNotFound

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable: "Quilt Log couldn't open the quilt library. Open the app once, then try again."
        case .quiltNotFound: "That quilt is no longer in the quilt library."
        }
    }
}

@MainActor
enum QuiltIntentRepository {
    private static var cachedContainer: ModelContainer?

    static func use(modelContainer: ModelContainer) {
        cachedContainer = modelContainer
    }

    static func entities(
        matching search: String? = nil,
        status: QuiltIntentStatus? = nil
    ) throws -> [QuiltEntity] {
        let needle = search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return try records().filter { record in
            let matchesStatus = status == nil || record.status == status?.quiltStatus.rawValue
            guard matchesStatus, !needle.isEmpty else { return matchesStatus }
            return searchableText(for: record).contains(needle)
        }.map(QuiltEntity.init)
    }

    static func entities(identifiers: Set<String>) throws -> [QuiltEntity] {
        try records().filter { identifiers.contains($0.uuid) }.map(QuiltEntity.init)
    }

    static func entity(identifier: String) throws -> QuiltEntity {
        guard let record = try record(identifier: identifier) else { throw QuiltIntentError.quiltNotFound }
        return QuiltEntity(record: record)
    }

    static func create(name: String, status: QuiltIntentStatus) throws -> QuiltEntity {
        let context = try modelContext()
        let existing = try fetchRecords(context: context)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = QuiltRecord(
            legacyID: (existing.map(\.legacyID).max() ?? 0) + 1,
            sequenceNumber: (existing.map(\.sequenceNumber).max() ?? 0) + 1,
            quiltName: trimmedName.isEmpty ? "Untitled Quilt" : trimmedName,
            status: status.quiltStatus.rawValue
        )
        context.insert(record)
        try context.save()
        let entity = QuiltEntity(record: record)
        QuiltSpotlightIndexer.index(entity)
        return entity
    }

    static func updateStatus(identifier: String, status: QuiltIntentStatus) throws -> QuiltEntity {
        let context = try modelContext()
        guard let record = try fetchRecords(context: context).first(where: { $0.uuid == identifier }) else {
            throw QuiltIntentError.quiltNotFound
        }
        record.status = status.quiltStatus.rawValue
        record.updatedAt = Date()
        try context.save()
        let entity = QuiltEntity(record: record)
        QuiltSpotlightIndexer.index(entity)
        return entity
    }

    static func markGifted(identifier: String, recipient: String?) throws -> QuiltEntity {
        let context = try modelContext()
        guard let record = try fetchRecords(context: context).first(where: { $0.uuid == identifier }) else {
            throw QuiltIntentError.quiltNotFound
        }
        record.giftedAlready = true
        if let recipient {
            let trimmedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRecipient.isEmpty {
                record.recipient = trimmedRecipient
            }
        }
        record.updatedAt = Date()
        try context.save()
        let entity = QuiltEntity(record: record)
        QuiltSpotlightIndexer.index(entity)
        return entity
    }

    static func summary() throws -> String {
        let records = try records()
        let completed = records.filter { $0.status == QuiltStatus.done.rawValue }.count
        let active = records.count - completed
        let gifted = records.filter(\.giftedAlready).count
        return "You have \(records.count) quilts: \(active) active, \(completed) completed, and \(gifted) gifted."
    }

    private static func record(identifier: String) throws -> QuiltRecord? {
        let context = try modelContext()
        return try fetchRecords(context: context).first { $0.uuid == identifier }
    }

    private static func records() throws -> [QuiltRecord] {
        try fetchRecords(context: modelContext())
    }

    private static func fetchRecords(context: ModelContext) throws -> [QuiltRecord] {
        var descriptor = FetchDescriptor<QuiltRecord>()
        descriptor.sortBy = [SortDescriptor(\.sequenceNumber)]
        return try context.fetch(descriptor)
    }

    private static func modelContext() throws -> ModelContext {
        if let cachedContainer {
            return ModelContext(cachedContainer)
        }
        let schema = Schema([QuiltRecord.self, QuiltPhotoRecord.self, QuiltLogMetadata.self])
        let configuration = ModelConfiguration(
            "QuiltLogCloud",
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.erikoliver.quiltlog")
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            cachedContainer = container
            return ModelContext(container)
        } catch {
            throw QuiltIntentError.libraryUnavailable
        }
    }

    private static func searchableText(for record: QuiltRecord) -> String {
        [
            record.quiltName, record.designerName, record.patternName, record.fabricStore,
            record.fabricLine, record.fabricReminder, record.approxSize, record.quilterName,
            record.quiltingPatternName, record.status, record.recipient, record.notes
        ].joined(separator: " ").lowercased()
    }
}

@MainActor
enum QuiltSpotlightIndexer {
    static func reindexAll() {
        guard !isRunningTests else { return }
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        Task {
            do {
                let entities = try QuiltIntentRepository.entities()
                let index = CSSearchableIndex.default()
                try await index.deleteAppEntities(ofType: QuiltEntity.self)
                if !entities.isEmpty {
                    try await index.indexAppEntities(entities)
                }
            } catch {
                DiagnosticLog.record("Spotlight quilt reindex failed", error: error)
            }
        }
    }

    static func index(_ entity: QuiltEntity) {
        guard !isRunningTests else { return }
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        Task {
            do {
                try await CSSearchableIndex.default().indexAppEntities([entity])
            } catch {
                DiagnosticLog.record("Spotlight quilt index update failed", error: error)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
