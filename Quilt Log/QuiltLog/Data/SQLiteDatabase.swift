// Copyright 2026 Erik Oliver
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SQLite3

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .prepareFailed(let message), .stepFailed(let message), .bindFailed(let message):
            return message
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: URL, createIfNeeded: Bool = false) throws {
        let flags = createIfNeeded
            ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path.path, &db, flags, nil) != SQLITE_OK {
            throw SQLiteError.openFailed(Self.errorMessage(db))
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? Self.errorMessage(db)
            sqlite3_free(error)
            throw SQLiteError.stepFailed(message)
        }
    }

    func query<T>(_ sql: String, _ bind: ((OpaquePointer?) throws -> Void)? = nil, map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(Self.errorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        try bind?(statement)

        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try map(statement))
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw SQLiteError.stepFailed(Self.errorMessage(db))
            }
        }
    }

    func run(_ sql: String, _ bind: ((OpaquePointer?) throws -> Void)? = nil) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(Self.errorMessage(db))
        }
        defer { sqlite3_finalize(statement) }

        try bind?(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(Self.errorMessage(db))
        }
    }

    var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(db)
    }

    static func bindText(_ value: String?, to index: Int32, in statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bindFailed("Could not bind text value.")
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func bindData(_ value: Data?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        try value.withUnsafeBytes { bytes in
            guard sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), SQLITE_TRANSIENT) == SQLITE_OK else {
                throw SQLiteError.bindFailed("Could not bind binary value.")
            }
        }
    }

    static func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    static func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private static func errorMessage(_ db: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(db) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
