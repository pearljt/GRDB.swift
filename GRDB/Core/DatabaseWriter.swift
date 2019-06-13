import Dispatch

/// The protocol for all types that can update a database.
///
/// It is adopted by DatabaseQueue and DatabasePool.
///
/// The protocol comes with isolation guarantees that describe the behavior of
/// adopting types in a multithreaded application.
///
/// Types that adopt the protocol can in practice provide stronger guarantees.
/// For example, DatabaseQueue provides a stronger isolation level
/// than DatabasePool.
///
/// **Warning**: Isolation guarantees stand as long as there is no external
/// connection to the database. Should you have to cope with external
/// connections, protect yourself with transactions, and be ready to setup a
/// [busy handler](https://www.sqlite.org/c3ref/busy_handler.html).
public protocol DatabaseWriter : DatabaseReader {
    
    /// The database configuration
    var configuration: Configuration { get }
    
    // MARK: - Writing in Database
    
    /// Synchronously executes a block that takes a database connection, and
    /// returns its result.
    ///
    /// Eventual concurrent database updates are postponed until the block
    /// has executed.
    ///
    /// Eventual concurrent reads are guaranteed not to see any changes
    /// performed in the block until they are all saved in the database.
    ///
    /// The block may, or may not, be wrapped inside a transaction.
    ///
    /// This method is *not* reentrant.
    func write<T>(_ block: (Database) throws -> T) throws -> T
    
    /// Synchronously executes a block that takes a database connection, and
    /// returns its result.
    ///
    /// Eventual concurrent database updates are postponed until the block
    /// has executed.
    ///
    /// Eventual concurrent reads may see changes performed in the block before
    /// the block completes.
    ///
    /// The block is guaranteed to be executed outside of a transaction.
    ///
    /// This method is *not* reentrant.
    func writeWithoutTransaction<T>(_ block: (Database) throws -> T) rethrows -> T
    
    /// Synchronously executes a block that takes a database connection, and
    /// returns its result.
    ///
    /// Eventual concurrent database updates are postponed until the block
    /// has executed.
    ///
    /// Eventual concurrent reads may see changes performed in the block before
    /// the block completes.
    ///
    /// This method is reentrant. It should be avoided because it fosters
    /// dangerous concurrency practices.
    func unsafeReentrantWrite<T>(_ block: (Database) throws -> T) rethrows -> T
    
    /// Asynchronously executes a block that takes a database connection, and
    /// returns its result.
    ///
    /// Eventual concurrent reads may see changes performed in the block before
    /// the block completes.
    func asyncWriteWithoutTransaction(_ block: @escaping (Database) -> Void)

    // MARK: - Reading from Database
    
    /// Concurrently executes a read-only block that takes a
    /// database connection.
    ///
    /// This method must be called from a writing dispatch queue, outside of any
    /// transaction. You'll get a fatal error otherwise.
    ///
    /// The *block* argument is guaranteed to see the database in the last
    /// committed state at the moment this method is called. Eventual concurrent
    /// database updates are *not visible* inside the block.
    ///
    /// This method returns as soon as the isolation guarantees described above
    /// are established. To access the fetched results, you call the wait()
    /// method of the returned future, on any dispatch queue.
    ///
    /// In the example below, the number of players is fetched concurrently with
    /// the player insertion. Yet the future is guaranteed to return zero:
    ///
    ///     try writer.writeWithoutTransaction { db in
    ///         // Delete all players
    ///         try Player.deleteAll()
    ///
    ///         // Count players concurrently
    ///         let future = writer.concurrentRead { db in
    ///             return try Player.fetchCount()
    ///         }
    ///
    ///         // Insert a player
    ///         try Player(...).insert(db)
    ///
    ///         // Guaranteed to be zero
    ///         let count = try future.wait()
    ///     }
    func concurrentRead<T>(_ block: @escaping (Database) throws -> T) -> DatabaseFuture<T>
}

extension DatabaseWriter {
    
    // MARK: - Transaction Observers
    
    /// Add a transaction observer, so that it gets notified of
    /// database changes.
    ///
    /// To remove the observer, use `DatabaseReader.remove(transactionObserver:)`.
    ///
    /// - parameter transactionObserver: A transaction observer.
    /// - parameter extent: The duration of the observation. The default is
    ///   the observer lifetime (observation lasts until observer
    ///   is deallocated).
    public func add(transactionObserver: TransactionObserver, extent: Database.TransactionObservationExtent = .observerLifetime) {
        writeWithoutTransaction { $0.add(transactionObserver: transactionObserver, extent: extent) }
    }
    
    /// Default implementation for the DatabaseReader requirement.
    /// :nodoc:
    public func remove(transactionObserver: TransactionObserver) {
        writeWithoutTransaction { $0.remove(transactionObserver: transactionObserver) }
    }
    
    // MARK: - Erasing the content of the database
    
    /// Erases the content of the database.
    ///
    /// - precondition: database is not accessed concurrently during the
    ///   execution of this method.
    public func erase() throws {
        #if SQLITE_HAS_CODEC
        // SQLCipher does not support the backup API: https://discuss.zetetic.net/t/using-the-sqlite-online-backup-api/2631
        // So we'll drop all database objects one after the other.
        try writeWithoutTransaction { db in
            // Prevent foreign keys from messing with drop table statements
            let foreignKeysEnabled = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")!
            if foreignKeysEnabled {
                try db.execute(sql: "PRAGMA foreign_keys = OFF")
            }
            
            // Remove all database objects, one after the other
            do {
                try db.inTransaction {
                    while let row = try Row.fetchOne(db, sql: "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") {
                        let type: String = row["type"]
                        let name: String = row["name"]
                        try db.execute(sql: "DROP \(type) \(name.quotedDatabaseIdentifier)")
                    }
                    return .commit
                }
                
                // Restore foreign keys if needed
                if foreignKeysEnabled {
                    try db.execute(sql: "PRAGMA foreign_keys = ON")
                }
            } catch {
                // Restore foreign keys if needed
                if foreignKeysEnabled {
                    try? db.execute(sql: "PRAGMA foreign_keys = ON")
                }
                throw error
            }
        }
        #else
        try DatabaseQueue().backup(to: self)
        #endif
    }
    
    // MARK: - Claiming Disk Space
    
    /// Rebuilds the database file, repacking it into a minimal amount of
    /// disk space.
    ///
    /// See https://www.sqlite.org/lang_vacuum.html for more information.
    public func vacuum() throws {
        try writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }
    
    // MARK: - Value Observation
    
    /// Default implementation for the DatabaseReader requirement.
    /// :nodoc:
    public func add<Reducer: ValueReducer>(
        observation: ValueObservation<Reducer>,
        onError: @escaping (Error) -> Void,
        onChange: @escaping (Reducer.Value) -> Void)
        -> TransactionObserver
    {
        let requiresWriteAccess = observation.requiresWriteAccess
        let observer = ValueObserver<Reducer>(
            requiresWriteAccess: requiresWriteAccess,
            writer: self,
            reduceQueue: configuration.makeDispatchQueue(defaultLabel: "GRDB", purpose: "ValueObservation.reducer"),
            onError: onError,
            onChange: onChange)
        
        switch observation.scheduling {
        case .mainQueue:
            if DispatchQueue.isMain {
                // Use case: observation starts on the main queue and wants
                // a synchronous initial fetch. Typically, this helps avoiding
                // flashes of missing content.
                var startValue: Reducer.Value? = nil
                defer {
                    if let startValue = startValue {
                        onChange(startValue)
                    }
                }
                
                do {
                    try unsafeReentrantWrite { db in
                        let region = try observation.observedRegion(db)
                        var reducer = try observation.makeReducer(db)
                        
                        // Fetch initial value
                        if let value = try reducer.value(reducer.fetch(db, requiringWriteAccess: requiresWriteAccess)) {
                            startValue = value
                        }
                        
                        // Start observing the database
                        observer.region = region
                        observer.reducer = reducer
                        observer.notificationQueue = DispatchQueue.main
                        db.add(transactionObserver: observer, extent: .observerLifetime)
                    }
                } catch {
                    onError(error)
                }
            } else {
                // Use case: observation does not start on the main queue, but
                // has the default scheduling .mainQueue
                asyncWriteWithoutTransaction { db in
                    do {
                        let region = try observation.observedRegion(db)
                        var reducer = try observation.makeReducer(db)
                        
                        // Fetch initial value
                        if let value = try reducer.value(reducer.fetch(db, requiringWriteAccess: requiresWriteAccess)) {
                            DispatchQueue.main.async {
                                onChange(value)
                            }
                        }
                        
                        // Start observing the database
                        observer.region = region
                        observer.reducer = reducer
                        observer.notificationQueue = DispatchQueue.main
                        db.add(transactionObserver: observer, extent: .observerLifetime)
                    } catch {
                        DispatchQueue.main.async {
                            onError(error)
                        }
                    }
                }
            }
            
        case let .async(onQueue: queue, startImmediately: startImmediately):
            // Use case: observation must not block the target queue
            asyncWriteWithoutTransaction { db in
                do {
                    let region = try observation.observedRegion(db)
                    var reducer = try observation.makeReducer(db)
                    
                    // Fetch initial value
                    if startImmediately,
                        let value = try reducer.value(reducer.fetch(db, requiringWriteAccess: requiresWriteAccess))
                    {
                        queue.async {
                            onChange(value)
                        }
                    }
                    
                    // Start observing the database
                    observer.region = region
                    observer.reducer = reducer
                    observer.notificationQueue = queue
                    db.add(transactionObserver: observer, extent: .observerLifetime)
                } catch {
                    queue.async {
                        onError(error)
                    }
                }
            }
            
        case let .unsafe(startImmediately: startImmediately):
            if startImmediately {
                // Use case: third-party integration (RxSwift, Combine, ...) that
                // need a synchronous initial fetch.
                //
                // This is really super extra unsafe.
                //
                // If the observation is started on one dispatch queue, then
                // the onChange and onError callbacks must be asynchronously
                // dispatched on the *same* queue.
                //
                // A failure to follow this rule may mess with the ordering of
                // initial values.
                var startValue: Reducer.Value? = nil
                defer {
                    if let startValue = startValue {
                        onChange(startValue)
                    }
                }
                
                do {
                    try unsafeReentrantWrite { db in
                        let region = try observation.observedRegion(db)
                        var reducer = try observation.makeReducer(db)
                        
                        // Fetch initial value
                        if startImmediately,
                            let value = try reducer.value(reducer.fetch(db, requiringWriteAccess: requiresWriteAccess))
                        {
                            startValue = value
                        }
                        
                        // Start observing the database
                        observer.region = region
                        observer.reducer = reducer
                        observer.notificationQueue = nil
                        db.add(transactionObserver: observer, extent: .observerLifetime)
                    }
                } catch {
                    onError(error)
                }
            } else {
                // Use case: ?
                //
                // This is unsafe because no promise is made on the dispatch
                // queue on which the onChange and onError callbacks are called.
                asyncWriteWithoutTransaction { db in
                    do {
                        let region = try observation.observedRegion(db)
                        let reducer = try observation.makeReducer(db)
                        
                        // Start observing the database
                        observer.region = region
                        observer.reducer = reducer
                        observer.notificationQueue = nil
                        db.add(transactionObserver: observer, extent: .observerLifetime)
                    } catch {
                        onError(error)
                    }
                }
            }
        }
        
        // TODO
        //
        // We promise that observation stops when the returned observer is
        // deallocated. But the real observer may have not started observing
        // the database, because some observations start asynchronously.
        // Well... This forces us to return a "token" that cancels any
        // observation started asynchronously.
        //
        // We'll eventually return a proper Cancellable. In GRDB 5?
        return ValueObserverToken(writer: self, observer: observer)
    }
}

/// A future database value, returned by the DatabaseWriter.concurrentRead(_:)
/// method.
///
///     let futureCount: Future<Int> = try writer.writeWithoutTransaction { db in
///         try Player(...).insert()
///
///         // Count players concurrently
///         return writer.concurrentRead { db in
///             return try Player.fetchCount()
///         }
///     }
///
///     let count: Int = try futureCount.wait()
public class DatabaseFuture<Value> {
    private var consumed = false
    private let _wait: () throws -> Value
    
    init(_ wait: @escaping () throws -> Value) {
        _wait = wait
    }
    
    init(_ result: Result<Value>) {
        _wait = result.get
    }
    
    /// Blocks the current thread until the value is available, and returns it.
    ///
    /// It is a programmer error to call this method several times.
    ///
    /// - throws: Any error that prevented the value from becoming available.
    public func wait() throws -> Value {
        // Not thread-safe and quick and dirty.
        // Goal is that users learn not to call this method twice.
        GRDBPrecondition(consumed == false, "DatabaseFuture.wait() must be called only once")
        consumed = true
        return try _wait()
    }
}

/// A type-erased DatabaseWriter
///
/// Instances of AnyDatabaseWriter forward their methods to an arbitrary
/// underlying database writer.
public final class AnyDatabaseWriter : DatabaseWriter {
    private let base: DatabaseWriter
    
    /// Creates a database writer that wraps a base database writer.
    public init(_ base: DatabaseWriter) {
        self.base = base
    }
    
    public var configuration: Configuration {
        return base.configuration
    }
    
    // MARK: - Reading from Database
    
    /// :nodoc:
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        return try base.read(block)
    }
    
    /// :nodoc:
    public func unsafeRead<T>(_ block: (Database) throws -> T) throws -> T {
        return try base.unsafeRead(block)
    }
    
    /// :nodoc:
    public func unsafeReentrantRead<T>(_ block: (Database) throws -> T) throws -> T {
        return try base.unsafeReentrantRead(block)
    }
    
    /// :nodoc:
    public func concurrentRead<T>(_ block: @escaping (Database) throws -> T) -> DatabaseFuture<T> {
        return base.concurrentRead(block)
    }
    
    // MARK: - Writing in Database
    
    /// :nodoc:
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        return try base.write(block)
    }
    
    /// :nodoc:
    public func writeWithoutTransaction<T>(_ block: (Database) throws -> T) rethrows -> T {
        return try base.writeWithoutTransaction(block)
    }
    
    /// :nodoc:
    public func unsafeReentrantWrite<T>(_ block: (Database) throws -> T) rethrows -> T {
        return try base.unsafeReentrantWrite(block)
    }
    
    /// :nodoc:
    public func asyncWriteWithoutTransaction(_ block: @escaping (Database) -> Void) {
        base.asyncWriteWithoutTransaction(block)
    }

    // MARK: - Functions
    
    /// :nodoc:
    public func add(function: DatabaseFunction) {
        base.add(function: function)
    }
    
    /// :nodoc:
    public func remove(function: DatabaseFunction) {
        base.remove(function: function)
    }
    
    // MARK: - Collations
    
    /// :nodoc:
    public func add(collation: DatabaseCollation) {
        base.add(collation: collation)
    }
    
    /// :nodoc:
    public func remove(collation: DatabaseCollation) {
        base.remove(collation: collation)
    }
}
