// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

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
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]
        if let reason = nsError.localizedFailureReason {
            parts.append("reason=\(reason)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying={domain=\(underlying.domain), code=\(underlying.code), description=\(underlying.localizedDescription)}")
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

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
