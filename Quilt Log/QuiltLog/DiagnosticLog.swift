// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import CloudKit
import Foundation

enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "com.erikoliver.quiltlog.diagnostic-log")

    static var fileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Quilt Log", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("quiltlog-diagnostics.log")
    }

    static func record(_ message: @autoclosure @escaping () -> String) {
        queue.async {
            write(message())
        }
    }

    static func record(_ message: String, error: Error) {
        record("\(message): \(describe(error))")
    }

    static func recordLaunch() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let identifier = bundle.bundleIdentifier ?? "unknown"
        let executable = bundle.executableURL?.path ?? "unknown"
        let container = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? "unknown"
        record("launch bundle=\(identifier) version=\(version) build=\(build) executable=\(executable) appSupport=\(container)")
    }

    static func describe(_ error: Error) -> String {
        describe(error as NSError, depth: 0)
    }

    private static func describe(_ error: NSError, depth: Int) -> String {
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]
        if let reason = nsError.localizedFailureReason {
            parts.append("reason=\(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion {
            parts.append("suggestion=\(suggestion)")
        }
        if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
            parts.append("debugDescription=\(debugDescription)")
        }
        if let cloudKitDescription = nsError.userInfo["CKErrorDescription"] as? String {
            parts.append("cloudKitDescription=\(cloudKitDescription)")
        }
        if let retryAfter = nsError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            parts.append("retryAfterSeconds=\(retryAfter)")
        }
        if let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            parts.append("partialErrors={\(describe(partialErrors, depth: depth + 1))}")
        }
        if depth < 2, let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying={\(describe(underlying, depth: depth + 1))}")
        }
        return parts.joined(separator: " ")
    }

    private static func describe(_ partialErrors: [AnyHashable: Error], depth: Int) -> String {
        let limit = 8
        let descriptions = partialErrors.prefix(limit).map { key, error in
            "\(redacted(String(describing: key)))={\(describe(error as NSError, depth: depth))}"
        }
        var parts = ["count=\(partialErrors.count)"]
        parts.append(contentsOf: descriptions)
        if partialErrors.count > limit {
            parts.append("omitted=\(partialErrors.count - limit)")
        }
        return parts.joined(separator: " ")
    }

    static func describe(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    private static func write(_ message: String) {
        do {
            let url = fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            let line = "\(Self.timestamp()) \(message)\n"
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // Diagnostics must never interfere with normal app behavior.
        }
    }

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    private static func redacted(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
