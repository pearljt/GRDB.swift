/// A FetchRequest built from raw SQL.
public struct SQLRequest<T> : FetchRequest {
    public typealias RowDecoder = T
    
    public var adapter: RowAdapter?
    public var sql: String { return sqlLiteral.sql }
    public var arguments: StatementArguments { return sqlLiteral.arguments }
    
    private var sqlLiteral: SQLLiteral
    private let cache: Cache?

    /// Creates a request from an SQL string, optional arguments, and
    /// optional row adapter.
    ///
    ///     let request = SQLRequest<String>(sql: """
    ///         SELECT name FROM player
    ///         """)
    ///     let request = SQLRequest<Player>(sql: """
    ///         SELECT * FROM player WHERE id = ?
    ///         """, arguments: [1])
    ///
    /// - parameters:
    ///     - sql: An SQL query.
    ///     - arguments: Statement arguments.
    ///     - adapter: Optional RowAdapter.
    ///     - cached: Defaults to false. If true, the request reuses a cached
    ///       prepared statement.
    /// - returns: A SQLRequest
    public init(sql: String, arguments: StatementArguments = StatementArguments(), adapter: RowAdapter? = nil, cached: Bool = false) {
        self.init(literal: SQLLiteral(sql: sql, arguments: arguments), adapter: adapter, fromCache: cached ? .public : nil)
    }
    
    /// Creates a request from an SQLLiteral, and optional row adapter.
    ///
    ///     let request = SQLRequest<String>(literal: SQLLiteral(sql: """
    ///         SELECT name FROM player
    ///         """))
    ///     let request = SQLRequest<Player>(literal: SQLLiteral(sql: """
    ///         SELECT * FROM player WHERE name = ?
    ///         """, arguments: ["O'Brien"]))
    ///
    /// With Swift 5, you can safely embed raw values in your SQL queries,
    /// without any risk of syntax errors or SQL injection:
    ///
    ///     let request = SQLRequest<Player>(literal: """
    ///         SELECT * FROM player WHERE name = \("O'brien")
    ///         """)
    ///
    /// - parameters:
    ///     - sqlLiteral: An SQLLiteral.
    ///     - adapter: Optional RowAdapter.
    ///     - cached: Defaults to false. If true, the request reuses a cached
    ///       prepared statement.
    /// - returns: A SQLRequest
    public init(literal sqlLiteral: SQLLiteral, adapter: RowAdapter? = nil, cached: Bool = false) {
        // TODO: make this optional arguments non optional
        self.init(literal: sqlLiteral, adapter: adapter, fromCache: cached ? .public : nil)
    }

    /// Creates an SQL request from any other fetch request.
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - request: A request.
    ///     - cached: Defaults to false. If true, the request reuses a cached
    ///       prepared statement.
    /// - returns: An SQLRequest
    public init<Request: FetchRequest>(_ db: Database, request: Request, cached: Bool = false) throws where Request.RowDecoder == RowDecoder {
        let (statement, adapter) = try request.prepare(db)
        self.init(literal: SQLLiteral(sql: statement.sql, arguments: statement.arguments), adapter: adapter, cached: cached)
    }
    
    /// Creates a request from an SQLLiteral, and optional row adapter.
    ///
    ///     let request = SQLRequest<String>(literal: SQLLiteral(sql: """
    ///         SELECT name FROM player
    ///         """))
    ///     let request = SQLRequest<Player>(literal: SQLLiteral(sql: """
    ///         SELECT * FROM player WHERE name = ?
    ///         """, arguments: ["O'Brien"]))
    ///
    /// With Swift 5, you can safely embed raw values in your SQL queries,
    /// without any risk of syntax errors or SQL injection:
    ///
    ///     let request = SQLRequest<Player>(literal: """
    ///         SELECT * FROM player WHERE name = \("O'brien")
    ///         """)
    ///
    /// - parameters:
    ///     - sqlLiteral: An SQLLiteral.
    ///     - adapter: Optional RowAdapter.
    ///     - cache: The eventual cache
    /// - returns: A SQLRequest
    init(literal sqlLiteral: SQLLiteral, adapter: RowAdapter? = nil, fromCache cache: Cache?) {
        self.sqlLiteral = sqlLiteral
        self.adapter = adapter
        self.cache = cache
    }
    
    /// A tuple that contains a prepared statement that is ready to be
    /// executed, and an eventual row adapter.
    ///
    /// - parameter db: A database connection.
    ///
    /// :nodoc:
    public func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        let statement: SelectStatement
        switch cache {
        case .none:
            statement = try db.makeSelectStatement(sqlLiteral.sql)
        case .public?:
            statement = try db.cachedSelectStatement(sqlLiteral.sql)
        case .internal?:
            statement = try db.internalCachedSelectStatement(sqlLiteral.sql)
        }
        try statement.setArgumentsWithValidation(sqlLiteral.arguments)
        return (statement, adapter)
    }
    
    /// There are two statement caches: one for statements generated by the
    /// user, and one for the statements generated by GRDB. Those are separated
    /// so that GRDB has no opportunity to inadvertently modify the arguments of
    /// user's cached statements.
    enum Cache {
        /// The public cache, for library user
        case `public`
        
        /// The internal cache, for grdb
        case `internal`
    }
}

#if swift(>=5.0)
extension SQLRequest: ExpressibleByStringInterpolation {
    /// :nodoc
    public init(unicodeScalarLiteral: String) {
        self.init(sql: unicodeScalarLiteral)
    }
    
    /// :nodoc:
    public init(extendedGraphemeClusterLiteral: String) {
        self.init(sql: extendedGraphemeClusterLiteral)
    }
    
    /// :nodoc:
    public init(stringLiteral: String) {
        self.init(sql: stringLiteral)
    }
    
    /// :nodoc:
    public init(stringInterpolation sqlInterpolation: SQLInterpolation) {
        self.init(literal: SQLLiteral(stringInterpolation: sqlInterpolation))
    }
}
#endif
