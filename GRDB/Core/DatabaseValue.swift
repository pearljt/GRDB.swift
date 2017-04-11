import Foundation

// MARK: - DatabaseValue

/// DatabaseValue is the intermediate type between SQLite and your values.
///
/// See https://www.sqlite.org/datatype3.html
public struct DatabaseValue {
    
    /// An SQLite storage (NULL, INTEGER, REAL, TEXT, BLOB).
    public enum Storage : Equatable {
        /// The NULL storage class.
        case null
        
        /// The INTEGER storage class, wrapping an Int64.
        case int64(Int64)
        
        /// The REAL storage class, wrapping a Double.
        case double(Double)
        
        /// The TEXT storage class, wrapping a String.
        case string(String)
        
        /// The BLOB storage class, wrapping Data.
        case blob(Data)
        
        /// Returns Int64, Double, String, Data or nil.
        public var value: DatabaseValueConvertible? {
            switch self {
            case .null:
                return nil
            case .int64(let int64):
                return int64
            case .double(let double):
                return double
            case .string(let string):
                return string
            case .blob(let data):
                return data
            }
        }
        
        /// Return true if the storages are identical.
        ///
        /// Unlike DatabaseValue equality that considers the integer 1 to be
        /// equal to the 1.0 double (as SQLite does), int64 and double storages
        /// are never equal.
        public static func == (_ lhs: Storage, _ rhs: Storage) -> Bool {
            switch (lhs, rhs) {
            case (.null, .null): return true
            case (.int64(let lhs), .int64(let rhs)): return lhs == rhs
            case (.double(let lhs), .double(let rhs)): return lhs == rhs
            case (.string(let lhs), .string(let rhs)): return lhs == rhs
            case (.blob(let lhs), .blob(let rhs)): return lhs == rhs
            default: return false
            }
        }
    }
    
    /// The SQLite storage
    public let storage: Storage
    
    /// The NULL DatabaseValue.
    public static let null = DatabaseValue(storage: .null)
    
    /// Creates a DatabaseValue from Any.
    ///
    /// The result is nil unless object adopts DatabaseValueConvertible.
    public init?(value: Any) {
        guard let convertible = value as? DatabaseValueConvertible else {
            return nil
        }
        self = convertible.databaseValue
    }
    
    
    // MARK: - Extracting Value
    
    /// Returns true if databaseValue is NULL.
    public var isNull: Bool {
        switch storage {
        case .null:
            return true
        default:
            return false
        }
    }
    
    
    // MARK: - Not Public
    
    init(storage: Storage) {
        // This initializer is not public because Storage is not a safe type:
        // one can create a Storage of zero-length Data, which is invalid
        // because SQLite can't store zero-length blobs.
        self.storage = storage
    }
    
    // SQLite function argument
    init(sqliteValue: SQLiteValue) {
        switch sqlite3_value_type(sqliteValue) {
        case SQLITE_NULL:
            storage = .null
        case SQLITE_INTEGER:
            storage = .int64(sqlite3_value_int64(sqliteValue))
        case SQLITE_FLOAT:
            storage = .double(sqlite3_value_double(sqliteValue))
        case SQLITE_TEXT:
            storage = .string(String(cString: sqlite3_value_text(sqliteValue)!))
        case SQLITE_BLOB:
            let bytes = unsafeBitCast(sqlite3_value_blob(sqliteValue), to: UnsafePointer<UInt8>.self)
            let count = Int(sqlite3_value_bytes(sqliteValue))
            storage = .blob(Data(bytes: bytes, count: count)) // copy bytes
        case let type:
            // Assume a GRDB bug: there is no point throwing any error.
            fatalError("Unexpected SQLite value type: \(type)")
        }
    }

    /// Returns a DatabaseValue initialized from a raw SQLite statement pointer.
    init(sqliteStatement: SQLiteStatement, index: Int32) {
        switch sqlite3_column_type(sqliteStatement, Int32(index)) {
        case SQLITE_NULL:
            storage = .null
        case SQLITE_INTEGER:
            storage = .int64(sqlite3_column_int64(sqliteStatement, Int32(index)))
        case SQLITE_FLOAT:
            storage = .double(sqlite3_column_double(sqliteStatement, Int32(index)))
        case SQLITE_TEXT:
            storage = .string(String(cString: sqlite3_column_text(sqliteStatement, Int32(index))))
        case SQLITE_BLOB:
            let bytes = unsafeBitCast(sqlite3_column_blob(sqliteStatement, Int32(index)), to: UnsafePointer<UInt8>.self)
            let count = Int(sqlite3_column_bytes(sqliteStatement, Int32(index)))
            storage = .blob(Data(bytes: bytes, count: count)) // copy bytes
        case let type:
            // Assume a GRDB bug: there is no point throwing any error.
            fatalError("Unexpected SQLite column type: \(type)")
        }
    }
}


// MARK: - Hashable & Equatable

/// DatabaseValue adopts Hashable.
extension DatabaseValue : Hashable {
    
    /// The hash value
    public var hashValue: Int {
        switch storage {
        case .null:
            return 0
        case .int64(let int64):
            // 1 == 1.0, hence 1 and 1.0 must have the same hash:
            return Double(int64).hashValue
        case .double(let double):
            return double.hashValue
        case .string(let string):
            return string.hashValue
        case .blob(let data):
            return data.hashValue
        }
    }
    
    /// Returns whether two DatabaseValues are equal.
    ///
    ///     1.databaseValue == "foo".databaseValue // false
    ///     1.databaseValue == 1.databaseValue     // true
    ///
    /// When comparing integers and doubles, the result is true if and only
    /// values are equal, and if converting one type to the other does
    /// not lose information:
    ///
    ///     1.databaseValue == 1.0.databaseValue   // true
    ///
    /// For a comparison that distinguishes integer and doubles, compare
    /// storages instead:
    ///
    ///     1.databaseValue.storage == 1.0.databaseValue.storage // false
    public static func == (lhs: DatabaseValue, rhs: DatabaseValue) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.null, .null):
            return true
        case (.int64(let lhs), .int64(let rhs)):
            return lhs == rhs
        case (.double(let lhs), .double(let rhs)):
            return lhs == rhs
        case (.int64(let lhs), .double(let rhs)):
            return int64EqualDouble(lhs, rhs)
        case (.double(let lhs), .int64(let rhs)):
            return int64EqualDouble(rhs, lhs)
        case (.string(let lhs), .string(let rhs)):
            return lhs == rhs
        case (.blob(let lhs), .blob(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

/// Returns true if i and d hold exactly the same value, and if converting one
/// type to the other does not lose any information.
private func int64EqualDouble(_ i: Int64, _ d: Double) -> Bool {
    // See http://stackoverflow.com/questions/33719132/how-to-test-for-lossless-double-integer-conversion/33784296#33784296
    return (d >= Double(Int64.min))
        && (d < Double(Int64.max))
        && (round(d) == d)
        && (i == Int64(d))
}


// MARK: - DatabaseValueConvertible

/// DatabaseValue adopts DatabaseValueConvertible.
extension DatabaseValue : DatabaseValueConvertible {
    /// Returns self
    public var databaseValue: DatabaseValue {
        return self
    }
    
    /// Returns `databaseValue`
    public static func fromDatabaseValue(_ databaseValue: DatabaseValue) -> DatabaseValue? {
        return databaseValue
    }
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    ///
    /// # Low Level Query Interface
    ///
    /// See SQLExpression.sqlExpression
    public var sqlExpression: SQLExpression {
        return self
    }
}


// MARK: - CustomStringConvertible

/// DatabaseValue adopts CustomStringConvertible.
extension DatabaseValue : CustomStringConvertible {
    /// A textual representation of `self`.
    public var description: String {
        switch storage {
        case .null:
            return "NULL"
        case .int64(let int64):
            return String(int64)
        case .double(let double):
            return String(double)
        case .string(let string):
            return String(reflecting: string)
        case .blob(let data):
            return data.description
        }
    }
}
