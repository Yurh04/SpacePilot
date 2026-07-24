import Foundation
import SQLite3

public struct SQLiteStoreError: Error, LocalizedError, Sendable {
    public let message: String
    public let resultCode: Int32?
    public let primaryCode: Int32?
    public let isConfirmedCorruption: Bool

    public init(message: String, resultCode: Int32? = nil, confirmedCorruption: Bool = false) {
        self.message = message
        self.resultCode = resultCode
        primaryCode = resultCode.map { $0 & 0xff }
        isConfirmedCorruption = confirmedCorruption
            || primaryCode == SQLITE_CORRUPT
            || primaryCode == SQLITE_NOTADB
    }

    public var errorDescription: String? { message }
}

final class SQLiteConnection {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let resultCode = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard resultCode == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite index"
            let extendedCode = handle.map(sqlite3_extended_errcode) ?? resultCode
            if let handle { sqlite3_close(handle) }
            throw SQLiteStoreError(message: message, resultCode: extendedCode)
        }
        database = handle
        sqlite3_extended_result_codes(handle, 1)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func execute(_ sql: String) throws {
        guard let database else { throw SQLiteStoreError(message: "SQLite index is closed") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let resultCode = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard resultCode == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError(
                message: message,
                resultCode: sqlite3_extended_errcode(database)
            )
        }
    }

    func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let database else { throw SQLiteStoreError(message: "SQLite index is closed") }
        var statement: OpaquePointer?
        let resultCode = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard resultCode == SQLITE_OK,
              let statement else {
            throw SQLiteStoreError(
                message: String(cString: sqlite3_errmsg(database)),
                resultCode: sqlite3_extended_errcode(database)
            )
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw currentError()
        }
    }

    func bind(_ value: Double, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw currentError() }
    }

    func bind(_ value: Int64, to index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else { throw currentError() }
    }

    func bind(_ value: Data, to index: Int32, in statement: OpaquePointer) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
        }
        guard result == SQLITE_OK else { throw currentError() }
    }

    func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    func reset(_ statement: OpaquePointer) throws {
        guard sqlite3_reset(statement) == SQLITE_OK,
              sqlite3_clear_bindings(statement) == SQLITE_OK else {
            throw currentError()
        }
    }

    func step(_ statement: OpaquePointer) throws -> Int32 {
        let resultCode = sqlite3_step(statement)
        guard resultCode == SQLITE_ROW || resultCode == SQLITE_DONE else {
            throw currentError()
        }
        return resultCode
    }

    func blob(at column: Int32, in statement: OpaquePointer) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func currentError() -> SQLiteStoreError {
        guard let database else { return SQLiteStoreError(message: "SQLite index is closed") }
        return SQLiteStoreError(
            message: String(cString: sqlite3_errmsg(database)),
            resultCode: sqlite3_extended_errcode(database)
        )
    }
}
