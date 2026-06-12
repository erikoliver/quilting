// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import CloudKit
import Foundation

enum CloudKitDiagnosticProbe {
    private static let containerIdentifier = "iCloud.com.erikoliver.quiltlog"
    private static let sampleLimit = 25
    private static let maxZonesToSample = 4

    static func run(reason: String) {
        Task.detached(priority: .utility) {
            await runProbe(reason: reason)
        }
    }

    private static func runProbe(reason: String) async {
        let container = CKContainer(identifier: containerIdentifier)
        let database = container.privateCloudDatabase
        DiagnosticLog.record("cloudkit probe begin reason=\(reason) container=\(containerIdentifier)")

        do {
            let status = try await accountStatus(for: container)
            DiagnosticLog.record("cloudkit probe accountStatus=\(accountStatusName(status))")
        } catch {
            DiagnosticLog.record("cloudkit probe accountStatus failed", error: error)
        }

        do {
            let userRecordID = try await userRecordID(for: container)
            DiagnosticLog.record("cloudkit probe userRecordID=\(redactedRecordID(userRecordID))")
        } catch {
            DiagnosticLog.record("cloudkit probe userRecordID failed", error: error)
        }

        do {
            let zones = try await allRecordZones(in: database)
            DiagnosticLog.record("cloudkit probe zones count=\(zones.count)")
            for zone in zones {
                DiagnosticLog.record("cloudkit probe zone \(describe(zone))")
            }

            let changeFetchableZones = zones
                .filter { $0.capabilities.contains(.fetchChanges) }
                .prefix(maxZonesToSample)
            for zone in changeFetchableZones {
                await sampleZoneChanges(in: database, zoneID: zone.zoneID)
            }
            DiagnosticLog.record("cloudkit probe finished zonesSampled=\(changeFetchableZones.count)")
        } catch {
            DiagnosticLog.record("cloudkit probe zones failed", error: error)
        }
    }

    private static func sampleZoneChanges(in database: CKDatabase, zoneID: CKRecordZone.ID) async {
        do {
            let sample = try await fetchZoneChangeSample(in: database, zoneID: zoneID)
            DiagnosticLog.record(
                "cloudkit probe zoneChanges zone=\(describe(zoneID)) changed=\(describe(sample.changedByType)) deleted=\(describe(sample.deletedByType)) returned=\(sample.returned) moreComing=\(sample.moreComing)"
            )
        } catch {
            DiagnosticLog.record(
                "cloudkit probe zoneChanges failed zone=\(describe(zoneID))",
                error: error
            )
        }
    }

    private static func accountStatus(for container: CKContainer) async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private static func userRecordID(for container: CKContainer) async throws -> CKRecord.ID {
        try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let recordID {
                    continuation.resume(returning: recordID)
                } else {
                    continuation.resume(throwing: CloudKitDiagnosticProbeError.missingUserRecordID)
                }
            }
        }
    }

    private static func allRecordZones(in database: CKDatabase) async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { continuation in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: zones ?? [])
                }
            }
        }
    }

    private static func fetchZoneChangeSample(
        in database: CKDatabase,
        zoneID: CKRecordZone.ID
    ) async throws -> ZoneChangeSample {
        try await withCheckedThrowingContinuation { continuation in
            let accumulator = ZoneChangeSampleAccumulator()
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
                previousServerChangeToken: nil,
                resultsLimit: sampleLimit,
                desiredKeys: []
            )
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )

            operation.recordWasChangedBlock = { _, result in
                switch result {
                case let .success(record):
                    accumulator.recordChanged(recordType: record.recordType)
                case let .failure(error):
                    accumulator.record(error)
                }
            }
            operation.recordWithIDWasDeletedBlock = { _, recordType in
                accumulator.recordDeleted(recordType: recordType)
            }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case let .success(response):
                    accumulator.setMoreComing(response.moreComing)
                case let .failure(error):
                    accumulator.record(error)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    if let error = accumulator.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: accumulator.sample)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private static func describe(_ zone: CKRecordZone) -> String {
        "id=\(describe(zone.zoneID)) capabilities=\(describe(zone.capabilities))"
    }

    private static func describe(_ zoneID: CKRecordZone.ID) -> String {
        "name=\(zoneID.zoneName) owner=\(redacted(zoneID.ownerName))"
    }

    private static func describe(_ capabilities: CKRecordZone.Capabilities) -> String {
        var names: [String] = []
        if capabilities.contains(.atomic) {
            names.append("atomic")
        }
        if capabilities.contains(.fetchChanges) {
            names.append("fetchChanges")
        }
        if capabilities.contains(.sharing) {
            names.append("sharing")
        }
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    private static func describe(_ counts: [String: Int]) -> String {
        guard !counts.isEmpty else { return "none" }
        return counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }

    private static func accountStatusName(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .couldNotDetermine: "couldNotDetermine"
        case .noAccount: "noAccount"
        case .restricted: "restricted"
        case .temporarilyUnavailable: "temporarilyUnavailable"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    private static func redactedRecordID(_ recordID: CKRecord.ID) -> String {
        "recordNameHash=\(redacted(recordID.recordName)) zone={\(describe(recordID.zoneID))}"
    }

    private static func redacted(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct ZoneChangeSample {
    var changedByType: [String: Int]
    var deletedByType: [String: Int]
    var returned: Int
    var moreComing: Bool
}

private final class ZoneChangeSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var changedByType: [String: Int] = [:]
    private var deletedByType: [String: Int] = [:]
    private var returned = 0
    private var moreComing = false
    private(set) var error: Error?

    var sample: ZoneChangeSample {
        lock.lock()
        defer { lock.unlock() }
        return ZoneChangeSample(
            changedByType: changedByType,
            deletedByType: deletedByType,
            returned: returned,
            moreComing: moreComing
        )
    }

    func recordChanged(recordType: String) {
        lock.lock()
        changedByType[recordType, default: 0] += 1
        returned += 1
        lock.unlock()
    }

    func recordDeleted(recordType: String) {
        lock.lock()
        deletedByType[recordType, default: 0] += 1
        returned += 1
        lock.unlock()
    }

    func setMoreComing(_ value: Bool) {
        lock.lock()
        moreComing = value
        lock.unlock()
    }

    func record(_ newError: Error) {
        lock.lock()
        if error == nil {
            error = newError
        }
        lock.unlock()
    }
}

private enum CloudKitDiagnosticProbeError: LocalizedError {
    case missingUserRecordID

    var errorDescription: String? {
        switch self {
        case .missingUserRecordID:
            "CloudKit did not return a user record ID."
        }
    }
}
