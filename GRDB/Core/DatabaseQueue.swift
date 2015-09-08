/**
A Database Queue serializes access to an SQLite database.
*/
public final class DatabaseQueue {
    
    // MARK: - Configuration
    
    /// The database configuration
    public var configuration: Configuration {
        return database.configuration
    }
    
    
    // MARK: - Initializers
    
    /**
    Opens the SQLite database at path *path*.
    
        let dbQueue = try DatabaseQueue(path: "/path/to/database.sqlite")
    
    Database connections get closed when the database queue gets deallocated.
    
    - parameter path: The path to the database file.
    - parameter configuration: A configuration
    - throws: A DatabaseError whenever a SQLite error occurs.
    */
    public convenience init(path: String, var configuration: Configuration = Configuration()) throws {
        // IMPLEMENTATION NOTE
        //
        // According to https://www.sqlite.org/threadsafe.html:
        //
        // > Multi-thread. In this mode, SQLite can be safely used by multiple
        // > threads provided that no single database connection is used
        // > simultaneously in two or more threads.
        // >
        // > Serialized. In serialized mode, SQLite can be safely used by
        // > multiple threads with no restriction.
        // >
        // > The default mode is serialized.
        //
        // Since our database connection is only used via our serial dispatch
        // queue, there is no purpose using the default serialized mode.
        configuration.threadingMode = .MultiThread
        try self.init(database: Database(path: path, configuration: configuration))
    }
    
    /**
    Opens an in-memory SQLite database.
    
        let dbQueue = DatabaseQueue()
    
    Database memory is released when the database queue gets deallocated.
    
    - parameter configuration: A configuration
    */
    public convenience init(var configuration: Configuration = Configuration()) {
        configuration.threadingMode = .MultiThread  // See IMPLEMENTATION NOTE in init(_:configuration:)
        self.init(database: Database(configuration: configuration))
    }
    
    
    // MARK: - Database access
    
    /**
    Executes a block in the database queue.
    
        dbQueue.inDatabase { db in
            db.fetch(...)
        }

    This method is not reentrant.
    
    - parameter block: A block that accesses the databse.
    - throws: The error thrown by the block.
    */
    public func inDatabase(block: (db: Database) throws -> Void) rethrows {
        try inQueue { try block(db: self.database) }
    }
    
    /**
    Executes a block in the database queue, and returns its result.
    
        let rows = dbQueue.inDatabase { db in
            db.fetch(...)
        }
    
    This method is not reentrant.
    
    - parameter block: A block that accesses the databse.
    - throws: The error thrown by the block.
    */
    public func inDatabase<R>(block: (db: Database) throws -> R) rethrows -> R {
        return try inQueue { return try block(db: self.database) }
    }
    
    /**
    Executes a block in the database queue, wrapped inside a transaction.
    
    If the block throws an error, the transaction is rollbacked and the error is
    rethrown.
    
        try dbQueue.inTransaction { db in
            db.execute(...)
            return .Commit
        }
    
    This method is not reentrant.
    
    - parameter type:  The transaction type (default Exclusive)
                       See https://www.sqlite.org/lang_transaction.html
    - parameter block: A block that executes SQL statements and return either
                       .Commit or .Rollback.
    - throws: The error thrown by the block.
    */
    public func inTransaction(type: Database.TransactionType = .Exclusive, block: (db: Database) throws -> Database.TransactionCompletion) rethrows {
        let database = self.database
        try inQueue {
            try self.database.inTransaction(type) {
                try block(db: database)
            }
        }
    }
    
    
    // MARK: - Not public
    
    /// The Database
    private var database: Database
    
    /// The dispatch queue
    private let queue: dispatch_queue_t
    
    /// The key for the dispatch queue specific that holds the DatabaseQueue
    /// identity. See databaseQueueID.
    static var databaseQueueIDKey = unsafeBitCast(DatabaseQueue.self, UnsafePointer<Void>.self)     // some unique pointer
    
    /// The value for the dispatch queue specific that holds the DatabaseQueue
    /// identity.
    ///
    /// It helps:
    /// - warning the user when he wraps calls to inDatabase() or
    ///   inTransaction(), which would create a deadlock
    /// - warning the user the he uses a statement outside of the database
    ///   queue.
    private lazy var databaseQueueID: DatabaseQueueID = { [unowned self] in
        unsafeBitCast(self, DatabaseQueueID.self)   // pointer to self
    }()
    
    init(database: Database) {
        queue = dispatch_queue_create("GRDB", nil)
        self.database = database
        dispatch_queue_set_specific(queue, DatabaseQueue.databaseQueueIDKey, databaseQueueID, nil)
    }
    
    func inQueue<R>(block: () throws -> R) rethrows -> R {
        if databaseQueueID == dispatch_get_specific(DatabaseQueue.databaseQueueIDKey) {
            return try block()
        } else {
            return try DatabaseQueue.dispatchSync(queue, block: block)
        }
    }
    
    // A function declared as rethrows that synchronously executes a throwing
    // block in a dispatch_queue.
    static func dispatchSync<R>(queue: dispatch_queue_t, block: () throws -> R) rethrows -> R {
        func dispatchSyncImpl(queue: dispatch_queue_t, block: () throws -> R, block2: (ErrorType) throws -> Void) rethrows -> R {
            var result: R? = nil
            var blockError: ErrorType? = nil
            dispatch_sync(queue) {
                do {
                    result = try block()
                } catch {
                    blockError = error
                }
            }
            if let blockError = blockError {
                try block2(blockError)
            }
            return result!
        }
        return try dispatchSyncImpl(queue, block: block, block2: { throw $0 })
    }
}

typealias DatabaseQueueID = UnsafeMutablePointer<Void>
