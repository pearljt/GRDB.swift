// MARK: - PreparedRequest

/// A PreparedRequest is a request that is ready to be executed.
public struct PreparedRequest {
    /// A prepared statement
    public var statement: SelectStatement
    
    /// An eventual adapter for rows fetched by the select statement
    public var adapter: RowAdapter?
    
    /// Support for eager loading of hasMany associations.
    var supplementaryFetch: (([Row]) throws -> Void)?
    
    /// Creates a PreparedRequest.
    ///
    /// - parameter statement: A prepared statement that is ready to
    ///   be executed.
    /// - parameter adapter: An eventual adapter for rows fetched by the
    ///   select statement.
    public init(
        statement: SelectStatement,
        adapter: RowAdapter? = nil)
    {
        self.init(statement: statement, adapter: adapter, supplementaryFetch: nil)
    }
    
    init(
        statement: SelectStatement,
        adapter: RowAdapter?,
        supplementaryFetch: (([Row]) throws -> Void)?)
    {
        self.statement = statement
        self.adapter = adapter
        self.supplementaryFetch = supplementaryFetch
    }
}

// MARK: - FetchRequest

/// The protocol for all requests that fetch database rows, and tell how those
/// rows should be interpreted.
///
///     struct Player: FetchableRecord { ... }
///     let request: ... // Some FetchRequest that fetches Player
///     try request.fetchCursor(db) // Cursor of Player
///     try request.fetchAll(db)    // [Player]
///     try request.fetchOne(db)    // Player?
public protocol FetchRequest: DatabaseRegionConvertible {
    /// The type that tells how fetched database rows should be interpreted.
    associatedtype RowDecoder
    
    /// Returns a PreparedRequest that is ready to be executed.
    ///
    /// - parameter db: A database connection.
    /// - parameter singleResult: A hint that a single result row will be
    ///   consumed. Implementations can optionally use this to optimize the
    ///   prepared statement.
    /// - returns: A prepared request.
    func makePreparedRequest(_ db: Database, forSingleResult singleResult: Bool) throws -> PreparedRequest
    
    /// Returns the number of rows fetched by the request.
    ///
    /// The default implementation builds a naive SQL query based on the
    /// statement returned by the `prepare` method:
    /// `SELECT COUNT(*) FROM (...)`.
    ///
    /// Adopting types can refine this method in order to use more
    /// efficient SQL.
    ///
    /// - parameter db: A database connection.
    func fetchCount(_ db: Database) throws -> Int
}

extension FetchRequest {
    
    /// Returns an adapted request.
    public func adapted(_ adapter: @escaping (Database) throws -> RowAdapter) -> AdaptedFetchRequest<Self> {
        AdaptedFetchRequest(self, adapter)
    }
    
    /// Returns the number of rows fetched by the request.
    ///
    /// This default implementation builds a naive SQL query based on the
    /// statement returned by the `prepare` method: `SELECT COUNT(*) FROM (...)`.
    ///
    /// - parameter db: A database connection.
    public func fetchCount(_ db: Database) throws -> Int {
        let request = try makePreparedRequest(db, forSingleResult: false)
        let sql = "SELECT COUNT(*) FROM (\(request.statement.sql))"
        return try Int.fetchOne(db, sql: sql, arguments: request.statement.arguments)!
    }
    
    /// Returns the database region that the request looks into.
    ///
    /// This default implementation returns a region built from the statement
    /// returned by the `prepare` method.
    ///
    /// - parameter db: A database connection.
    public func databaseRegion(_ db: Database) throws -> DatabaseRegion {
        let request = try makePreparedRequest(db, forSingleResult: false)
        return request.statement.selectedRegion
    }
}

// MARK: - AdaptedFetchRequest

/// An adapted request.
public struct AdaptedFetchRequest<Base: FetchRequest>: FetchRequest {
    public typealias RowDecoder = Base.RowDecoder
    
    private let base: Base
    private let adapter: (Database) throws -> RowAdapter
    
    /// Creates an adapted request from a base request and a closure that builds
    /// a row adapter from a database connection.
    init(_ base: Base, _ adapter: @escaping (Database) throws -> RowAdapter) {
        self.base = base
        self.adapter = adapter
    }
    
    /// :nodoc:
    public func makePreparedRequest(_ db: Database, forSingleResult singleResult: Bool) throws -> PreparedRequest {
        var request = try base.makePreparedRequest(db, forSingleResult: singleResult)
        if let baseAdapter = request.adapter {
            request.adapter = try ChainedAdapter(first: baseAdapter, second: adapter(db))
        } else {
            request.adapter = try adapter(db)
        }
        return request
    }
    
    /// :nodoc:
    public func fetchCount(_ db: Database) throws -> Int {
        try base.fetchCount(db)
    }
    
    /// :nodoc:
    public func databaseRegion(_ db: Database) throws -> DatabaseRegion {
        try base.databaseRegion(db)
    }
}

// MARK: - AnyFetchRequest

/// A type-erased FetchRequest.
///
/// An AnyFetchRequest forwards its operations to an underlying request,
/// hiding its specifics.
public struct AnyFetchRequest<RowDecoder>: FetchRequest {
    private let _preparedRequest: (Database, _ singleResult: Bool) throws -> PreparedRequest
    private let _fetchCount: (Database) throws -> Int
    private let _databaseRegion: (Database) throws -> DatabaseRegion
    
    /// Creates a request that wraps and forwards operations to `request`.
    public init<Request: FetchRequest>(_ request: Request) {
        _preparedRequest = request.makePreparedRequest
        _fetchCount = request.fetchCount
        _databaseRegion = request.databaseRegion
    }
    
    /// :nodoc:
    public func makePreparedRequest(_ db: Database, forSingleResult singleResult: Bool) throws -> PreparedRequest {
        try _preparedRequest(db, singleResult)
    }
    
    /// :nodoc:
    public func fetchCount(_ db: Database) throws -> Int {
        try _fetchCount(db)
    }
    
    /// :nodoc:
    public func databaseRegion(_ db: Database) throws -> DatabaseRegion {
        try _databaseRegion(db)
    }
}
