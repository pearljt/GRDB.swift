//
// GRDB.swift
// https://github.com/groue/GRDB.swift
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


/**
A Database connection.

You don't create a database directly. Instead, you use a DatabaseQueue:

    let dbQueue = DatabaseQueue(...)

    // The Database is the `db` in the closure:
    dbQueue.inDatabase { db in
        db.execute(...)
    }
*/
public final class Database {
    
    // MARK: - Configuration
    
    /// The database configuration
    public let configuration: Configuration
    
    
    // MARK: - Select Statements
    
    /**
    Returns a select statement that can be reused.
    
        let statement = db.selectStatement("SELECT * FROM persons WHERE id = ?")
    
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    - parameter unsafe:   TODO.
    
    - returns: A SelectStatement.
    */
    public func selectStatement(sql: String, bindings: Bindings? = nil, unsafe: Bool = false) throws -> SelectStatement {
        return try SelectStatement(database: self, sql: sql, bindings: bindings, unsafe: unsafe)
    }
    
    
    // MARK: - Update Statements
    
    /**
    Returns an update statement that can be reused.
    
        let statement = db.updateStatement("INSERT INTO persons (name) VALUES (?)")
    
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: An UpdateStatement.
    */
    public func updateStatement(sql: String, bindings: Bindings? = nil) throws -> UpdateStatement {
        return try UpdateStatement(database: self, sql: sql, bindings: bindings)
    }
    
    /**
    Executes an update statement.
    
        db.excute("INSERT INTO persons (name) VALUES (?)", bindings: ["Arthur"])
    
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    */
    public func execute(sql: String, bindings: Bindings? = nil) throws {
        return try updateStatement(sql, bindings: bindings).execute()
    }
    
    
    // MARK: - Transactions
    
    /// A SQLite transaction type. See https://www.sqlite.org/lang_transaction.html
    public enum TransactionType {
        case Deferred
        case Immediate
        case Exclusive
    }
    
    /// The end of a transaction: Commit, or Rollback
    public enum TransactionCompletion {
        case Commit
        case Rollback
    }
    
    /**
    Executes a block inside a SQLite transaction.
    
    If the block throws an error, the transaction is rollbacked and the error is
    rethrown.
    
    - parameter type:  The transaction type (default Exclusive)
                       See https://www.sqlite.org/lang_transaction.html
    - parameter block: A function that executes SQL statements and return either
                       .Commit or .Rollback.
    */
    public func inTransaction(type: TransactionType = .Exclusive, block: () throws -> TransactionCompletion) throws {
        var completion: TransactionCompletion = .Rollback
        var dbError: ErrorType? = nil
        
        try beginTransaction(type)
        
        do {
            completion = try block()
        } catch {
            completion = .Rollback
            dbError = error
        }
        
        do {
            switch completion {
            case .Commit:
                try commit()
            case .Rollback:
                try rollback()
            }
        } catch {
            if dbError == nil {
                dbError = error
            }
        }
        
        if let dbError = dbError {
            throw dbError
        }
    }
    
    
    // MARK: - Miscellaneous
    
    /// The last inserted Row ID
    public var lastInsertedRowID: Int64? {
        let rowid = sqlite3_last_insert_rowid(sqliteConnection)
        return rowid == 0 ? nil : rowid
    }
    
    /**
    Returns whether a table exists.
    
    - parameter tableName: A table name.
    - returns: true if the table exists.
    */
    public func tableExists(tableName: String) -> Bool {
        if let _ = fetchOneRow("SELECT [sql] FROM sqlite_master WHERE [type] = 'table' AND LOWER(name) = ?", bindings: [tableName.lowercaseString]) {
            return true
        } else {
            return false
        }
    }
    
    
    // MARK: - Non public
    
    let sqliteConnection = SQLiteConnection()
    
    init(path: String, configuration: Configuration) throws {
        self.configuration = configuration
        
        // See https://www.sqlite.org/c3ref/open.html
        let code = sqlite3_open_v2(path, &sqliteConnection, configuration.sqliteOpenFlags, nil)
        try SQLiteError.checkCResultCode(code, sqliteConnection: sqliteConnection)
        
        if configuration.foreignKeysEnabled {
            try execute("PRAGMA foreign_keys = ON")
        }
    }
    
    // Initializes an in-memory database
    convenience init(configuration: Configuration) {
        try! self.init(path: ":memory:", configuration: configuration)
    }
    
    deinit {
        if sqliteConnection != nil {
            sqlite3_close(sqliteConnection)
        }
    }
    
    private func beginTransaction(type: TransactionType = .Exclusive) throws {
        switch type {
        case .Deferred:
            try execute("BEGIN DEFERRED TRANSACTION")
        case .Immediate:
            try execute("BEGIN IMMEDIATE TRANSACTION")
        case .Exclusive:
            try execute("BEGIN EXCLUSIVE TRANSACTION")
        }
    }
    
    private func rollback() throws {
        try execute("ROLLBACK TRANSACTION")
    }
    
    private func commit() throws {
        try execute("COMMIT TRANSACTION")
    }
}

/**
Convenience function that calls fatalError in case of error

    let x = failOnError {
        ...
    }
*/
func failOnError<Result>(@noescape block: (Void) throws -> Result) -> Result {
    do {
        return try block()
    } catch let error as SQLiteError {
        fatalError(error.description)
    } catch {
        fatalError("error: \(error)")
    }
}


// MARK: - Feching Rows

/**
The Database methods that fetch rows.
*/
extension Database {
    
    /**
    Fetches a lazy sequence of rows.

        let rows = db.fetchRows("SELECT ...")

    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: A lazy sequence of rows.
    */
    public func fetchRows(sql: String, bindings: Bindings? = nil) -> AnySequence<Row> {
        return failOnError {
            let statement = try selectStatement(sql, bindings: bindings)
            return statement.fetchRows()
        }
    }
    
    /**
    Fetches an array of rows.
    
        let rows = db.fetchAllRows("SELECT ...")
    
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: An array of rows.
    */
    public func fetchAllRows(sql: String, bindings: Bindings? = nil) -> [Row] {
        return Array(fetchRows(sql, bindings: bindings))
    }
    
    /**
    Fetches a single row.
    
        let row = db.fetchOneRow("SELECT ...")
    
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: An optional row.
    */
    public func fetchOneRow(sql: String, bindings: Bindings? = nil) -> Row? {
        return fetchRows(sql, bindings: bindings).generate().next()
    }
}


// MARK: - Feching Values

/**
The Database methods that fetch values.
*/
extension Database {
    
    /**
    Fetches a lazy sequence of values.

        let names = db.fetch(String.self, "SELECT ...")

    - parameter type:     The type of fetched values. It must adopt SQLiteValueConvertible.
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: A lazy sequence of values.
    */
    public func fetch<Value: SQLiteValueConvertible>(type: Value.Type, _ sql: String, bindings: Bindings? = nil) -> AnySequence<Value?> {
        return failOnError {
            let statement = try selectStatement(sql, bindings: bindings)
            return statement.fetch(type)
        }
    }
    
    /**
    Fetches an array of values.

        let names = db.fetchAll(String.self, "SELECT ...")

    - parameter type:     The type of fetched values. It must adopt SQLiteValueConvertible.
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: An array of values.
    */
    public func fetchAll<Value: SQLiteValueConvertible>(type: Value.Type, _ sql: String, bindings: Bindings? = nil) -> [Value?] {
        return Array(fetch(type, sql, bindings: bindings))
    }
    
    
    /**
    Fetches a single value.

        let name = db.fetchOne(String.self, "SELECT ...")

    - parameter type:     The type of fetched values. It must adopt SQLiteValueConvertible.
    - parameter sql:      An SQL query.
    - parameter bindings: Optional bindings for query parameters.
    
    - returns: An optional value.
    */
    public func fetchOne<Value: SQLiteValueConvertible>(type: Value.Type, _ sql: String, bindings: Bindings? = nil) -> Value? {
        if let first = fetch(type, sql, bindings: bindings).generate().next() {
            // one row containing an optional value
            return first
        } else {
            // no row
            return nil
        }
    }
}

