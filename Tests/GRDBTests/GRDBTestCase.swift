import XCTest
@testable import GRDB

// Support for Database.logError
var lastResultCode: ResultCode? = nil
var lastMessage: String? = nil
var logErrorSetup: Void = {
    Database.logError = { (resultCode, message) in
        lastResultCode = resultCode
        lastMessage = message
    }
}()

class GRDBTestCase: XCTestCase {
    // The default configuration for tests
    var dbConfiguration: Configuration!
    
    // Builds a database queue based on dbConfiguration
    func makeDatabaseQueue(filename: String? = nil) throws -> DatabaseQueue {
        try makeDatabaseQueue(filename: filename, configuration: dbConfiguration)
    }
    
    // Builds a database queue
    func makeDatabaseQueue(filename: String? = nil, configuration: Configuration) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(atPath: dbDirectoryPath, withIntermediateDirectories: true, attributes: nil)
        let dbPath = (dbDirectoryPath as NSString).appendingPathComponent(filename ?? ProcessInfo.processInfo.globallyUniqueString)
        let dbQueue = try DatabaseQueue(path: dbPath, configuration: configuration)
        try setup(dbQueue)
        return dbQueue
    }
    
    // Builds a database pool based on dbConfiguration
    func makeDatabasePool(filename: String? = nil) throws -> DatabasePool {
        try makeDatabasePool(filename: filename, configuration: dbConfiguration)
    }
    
    // Builds a database pool
    func makeDatabasePool(filename: String? = nil, configuration: Configuration) throws -> DatabasePool {
        try FileManager.default.createDirectory(atPath: dbDirectoryPath, withIntermediateDirectories: true, attributes: nil)
        let dbPath = (dbDirectoryPath as NSString).appendingPathComponent(filename ?? ProcessInfo.processInfo.globallyUniqueString)
        let dbPool = try DatabasePool(path: dbPath, configuration: configuration)
        try setup(dbPool)
        return dbPool
    }
    
    // Subclasses can override
    // Default implementation is empty.
    func setup(_ dbWriter: DatabaseWriter) throws {
    }
    
    // The default path for database pool directory
    private var dbDirectoryPath: String!
    
    // Populated by default configuration
    var sqlQueries: [String]!   // TODO: protect against concurrent accesses
    
    // Populated by default configuration
    var lastSQLQuery: String! { sqlQueries.last! }
    
    override func setUp() {
        super.setUp()
        
        _ = logErrorSetup
        
        let dbPoolDirectoryName = "GRDBTestCase-\(ProcessInfo.processInfo.globallyUniqueString)"
        dbDirectoryPath = (NSTemporaryDirectory() as NSString).appendingPathComponent(dbPoolDirectoryName)
        do { try FileManager.default.removeItem(atPath: dbDirectoryPath) } catch { }
        
        dbConfiguration = Configuration()
        
        // Test that database are deallocated in a clean state
        dbConfiguration.SQLiteConnectionWillClose = { sqliteConnection in
            // https://www.sqlite.org/capi3ref.html#sqlite3_close:
            // > If sqlite3_close_v2() is called on a database connection that still
            // > has outstanding prepared statements, BLOB handles, and/or
            // > sqlite3_backup objects then it returns SQLITE_OK and the
            // > deallocation of resources is deferred until all prepared
            // > statements, BLOB handles, and sqlite3_backup objects are also
            // > destroyed.
            //
            // Let's assert that there is no longer any busy update statements.
            //
            // SQLite would allow that. But not GRDB, since all updates happen
            // in closures that retain database connections, preventing
            // Database.deinit to fire.
            //
            // What we gain from this test is a guarantee that database
            // deallocation implies that there is no pending lock in the
            // database.
            //
            // See:
            // - sqlite3_next_stmt https://www.sqlite.org/capi3ref.html#sqlite3_next_stmt
            // - sqlite3_stmt_busy https://www.sqlite.org/capi3ref.html#sqlite3_stmt_busy
            // - sqlite3_stmt_readonly https://www.sqlite.org/capi3ref.html#sqlite3_stmt_readonly
            var stmt: SQLiteStatement? = sqlite3_next_stmt(sqliteConnection, nil)
            while stmt != nil {
                XCTAssertTrue(sqlite3_stmt_readonly(stmt) != 0 || sqlite3_stmt_busy(stmt) == 0)
                stmt = sqlite3_next_stmt(sqliteConnection, stmt)
            }
        }
        
        dbConfiguration.trace = { [unowned self] sql in
            #warning("TODO: make it thread-safe")
            self.sqlQueries.append(sql)
        }
        
        #if GRDBCIPHER_USE_ENCRYPTION
        // Encrypt all databases by default.
        dbConfiguration.prepareDatabase = { db in
            try db.usePassphrase("secret")
        }
        #endif
        
        sqlQueries = []
    }
    
    override func tearDown() {
        super.tearDown()
        do { try FileManager.default.removeItem(atPath: dbDirectoryPath) } catch { }
    }
    
    func assertNoError(file: StaticString = #file, line: UInt = #line, _ test: () throws -> Void) {
        do {
            try test()
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
    
    func assertDidExecute(sql: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(sqlQueries.contains(sql), "Did not execute \(sql)", file: file, line: line)
    }
    
    func assert(_ record: EncodableRecord, isEncodedIn row: Row, file: StaticString = #file, line: UInt = #line) {
        let recordDict = record.databaseDictionary
        let rowDict = Dictionary(row, uniquingKeysWith: { (left, _) in left })
        XCTAssertEqual(recordDict, rowDict, file: file, line: line)
    }
    
    // Compare SQL strings (ignoring leading and trailing white space and semicolons.
    func assertEqualSQL(_ lhs: String, _ rhs: String, file: StaticString = #file, line: UInt = #line) {
        // Trim white space and ";"
        let cs = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";"))
        XCTAssertEqual(lhs.trimmingCharacters(in: cs), rhs.trimmingCharacters(in: cs), file: file, line: line)
    }
    
    // Compare SQL strings (ignoring leading and trailing white space and semicolons.
    func assertEqualSQL<Request: FetchRequest>(_ db: Database, _ request: Request, _ sql: String, file: StaticString = #file, line: UInt = #line) throws {
        try request.makeStatement(db).makeCursor().next()
        assertEqualSQL(lastSQLQuery, sql, file: file, line: line)
    }
    
    // Compare SQL strings (ignoring leading and trailing white space and semicolons.
    func assertEqualSQL<Request: FetchRequest>(_ databaseReader: DatabaseReader, _ request: Request, _ sql: String, file: StaticString = #file, line: UInt = #line) throws {
        try databaseReader.unsafeRead { db in
            try assertEqualSQL(db, request, sql, file: file, line: line)
        }
    }
    
    func sql<Request: FetchRequest>(_ databaseReader: DatabaseReader, _ request: Request) -> String {
        try! databaseReader.unsafeRead { db in
            try request.makeStatement(db).makeCursor().next()
            return lastSQLQuery
        }
    }
}

extension FetchRequest {
    /// Turn request into a statement
    func makeStatement(_ db: Database) throws -> SelectStatement {
        try makePreparedRequest(db, forSingleResult: false).statement
    }
    
    /// Turn request into SQL and arguments
    func build(_ db: Database) throws -> (sql: String, arguments: StatementArguments) {
        let statement = try makePreparedRequest(db, forSingleResult: false).statement
        return (sql: statement.sql, arguments: statement.arguments)
    }
}

/// A type-erased ValueReducer.
public struct AnyValueReducer<Fetched, Value>: _ValueReducer {
    private var _fetch: (Database) throws -> Fetched
    private var _value: (Fetched) -> Value?
    
    public var isSelectedRegionDeterministic: Bool { false }
    
    public init(
        fetch: @escaping (Database) throws -> Fetched,
        value: @escaping (Fetched) -> Value?)
    {
        self._fetch = fetch
        self._value = value
    }
    
    public func fetch(_ db: Database) throws -> Fetched {
        try _fetch(db)
    }
    
    public func value(_ fetched: Fetched) -> Value? {
        _value(fetched)
    }
}
