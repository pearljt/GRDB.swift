//
//  SQLite.swift
//  GRDB
//
//  Created by Gwendal Roué on 02/07/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//

typealias SQLiteConnection = COpaquePointer
typealias SQLiteStatement = COpaquePointer

public struct SQLiteError : ErrorType {
    public let _domain: String = "GRDB.SQLiteError"
    public let _code: Int
    
    public var code: Int { return _code }
    public let message: String?
    public let sql: String?
    
    init(code: Int32, message: String? = nil, sql: String? = nil) {
        self._code = Int(code)
        self.message = message
        self.sql = sql
    }
    
    init(code: Int32, sqliteConnection: SQLiteConnection, sql: String? = nil) {
        let message: String?
        let cString = sqlite3_errmsg(sqliteConnection)
        if cString == nil {
            message = nil
        } else {
            message = String.fromCString(cString)
        }
        self.init(code: code, message: message, sql: sql)
    }
    
    static func checkCResultCode(code: Int32, sqliteConnection: SQLiteConnection, sql: String? = nil) throws {
        if code != SQLITE_OK {
            throw SQLiteError(code: code, sqliteConnection: sqliteConnection, sql: sql)
        }
    }
}

extension SQLiteError: CustomStringConvertible {
    public var description: String {
        // How to write this with a switch?
        if let sql = sql {
            if let message = message {
                fatalError("SQLite error \(code) with statement `\(sql)`: \(message)")
            } else {
                fatalError("SQLite error \(code) with statement `\(sql)`")
            }
        } else {
            if let message = message {
                fatalError("SQLite error \(code): \(message)")
            } else {
                fatalError("SQLite error \(code)")
            }
        }
    }
}

public enum SQLiteValue {
    case Null
    case Integer(Int64)
    case Real(Double)
    case Text(String)
    case Blob(GRDB.Blob)
    
    public func value() -> SQLiteValueConvertible? {
        switch self {
        case .Null:
            return nil
        case .Integer(let int64):
            return int64
        case .Real(let double):
            return double
        case .Text(let string):
            return string
        case .Blob(let blob):
            return blob
        }
    }
    
    public func value<Value: SQLiteValueConvertible>() -> Value? {
        return Value(sqliteValue: self)
    }
}

public enum SQLiteStorageClass {
    case Null
    case Integer
    case Real
    case Text
    case Blob
}

extension SQLiteValue {
    public var storageClass: SQLiteStorageClass {
        switch self {
        case .Null:
            return .Null
        case .Integer:
            return .Integer
        case .Real:
            return .Real
        case .Text:
            return .Text
        case .Blob:
            return .Blob
        }
    }
}

