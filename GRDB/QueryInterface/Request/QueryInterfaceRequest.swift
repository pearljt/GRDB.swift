// QueryInterfaceRequest is the type of requests generated by TableRecord:
//
//     struct Player: TableRecord { ... }
//     let playerRequest = Player.all() // QueryInterfaceRequest<Player>
//
// It wraps an SQLQuery, and has an attached type.
//
// The attached RowDecoder type helps decoding raw database values:
//
//     try dbQueue.read { db in
//         try playerRequest.fetchAll(db) // [Player]
//     }
//
// RowDecoder also helps the compiler validate associated requests:
//
//     playerRequest.including(required: Player.team) // OK
//     fruitRequest.including(required: Player.team)  // Does not compile

/// QueryInterfaceRequest is a request that generates SQL for you.
///
/// For example:
///
///     try dbQueue.read { db in
///         let request = Player
///             .filter(Column("score") > 1000)
///             .order(Column("name"))
///         let players = try request.fetchAll(db) // [Player]
///     }
///
/// See https://github.com/groue/GRDB.swift#the-query-interface
public struct QueryInterfaceRequest<RowDecoder> {
    var query: SQLQuery
}

extension QueryInterfaceRequest {
    init(relation: SQLRelation) {
        self.init(query: SQLQuery(relation: relation))
    }
}

extension QueryInterfaceRequest: Refinable { }

extension QueryInterfaceRequest: FetchRequest {
    public var sqlSubquery: SQLSubquery {
        .query(query)
    }
    
    public func fetchCount(_ db: Database) throws -> Int {
        try query.fetchCount(db)
    }
    
    public func makePreparedRequest(
        _ db: Database,
        forSingleResult singleResult: Bool = false)
    throws -> PreparedRequest
    {
        let generator = SQLQueryGenerator(query: query, forSingleResult: singleResult)
        var preparedRequest = try generator.makePreparedRequest(db)
        let associations = query.relation.prefetchedAssociations
        if associations.isEmpty == false {
            // Eager loading of prefetched associations
            preparedRequest = preparedRequest.with(\.supplementaryFetch) { [query] db, rows in
                try prefetch(db, associations: associations, from: query, into: rows)
            }
        }
        return preparedRequest
    }
}

// MARK: - Request Derivation

extension QueryInterfaceRequest: SelectionRequest {
    /// Creates a request which selects *selection promise*.
    ///
    ///     // SELECT id, email FROM player
    ///     var request = Player.all()
    ///     request = request.select { db in [Column("id"), Column("email")] }
    ///
    /// Any previous selection is replaced:
    ///
    ///     // SELECT email FROM player
    ///     request
    ///         .select { db in [Column("id")] }
    ///         .select { db in [Column("email")] }
    public func select(_ selection: @escaping (Database) throws -> [SQLSelectable]) -> QueryInterfaceRequest {
        map(\.query) { $0.select { try selection($0).map(\.sqlSelection) } }
    }
    
    /// Creates a request which selects *selection*, and fetches values of
    /// type *type*.
    ///
    ///     try dbQueue.read { db in
    ///         // SELECT max(score) FROM player
    ///         let request = Player.all().select([max(Column("score"))], as: Int.self)
    ///         let maxScore: Int? = try request.fetchOne(db)
    ///     }
    public func select<RowDecoder>(_ selection: [SQLSelectable], as type: RowDecoder.Type = RowDecoder.self)
    -> QueryInterfaceRequest<RowDecoder>
    {
        select(selection).asRequest(of: RowDecoder.self)
    }
    
    /// Creates a request which selects *selection*, and fetches values of
    /// type *type*.
    ///
    ///     try dbQueue.read { db in
    ///         // SELECT max(score) FROM player
    ///         let request = Player.all().select(max(Column("score")), as: Int.self)
    ///         let maxScore: Int? = try request.fetchOne(db)
    ///     }
    public func select<RowDecoder>(_ selection: SQLSelectable..., as type: RowDecoder.Type = RowDecoder.self)
    -> QueryInterfaceRequest<RowDecoder>
    {
        select(selection, as: type)
    }
    
    /// Creates a request which selects *sql*, and fetches values of
    /// type *type*.
    ///
    ///     try dbQueue.read { db in
    ///         // SELECT max(score) FROM player
    ///         let request = Player.all().select(sql: "max(score)", as: Int.self)
    ///         let maxScore: Int? = try request.fetchOne(db)
    ///     }
    public func select<RowDecoder>(
        sql: String,
        arguments: StatementArguments = StatementArguments(),
        as type: RowDecoder.Type = RowDecoder.self)
    -> QueryInterfaceRequest<RowDecoder>
    {
        select(literal: SQLLiteral(sql: sql, arguments: arguments), as: type)
    }
    
    /// Creates a request which selects an SQL *literal*, and fetches values of
    /// type *type*.
    ///
    ///     try dbQueue.read { db in
    ///         // SELECT IFNULL(name, 'Anonymous') FROM player WHERE id = 42
    ///         let request = Player.
    ///             .filter(primaryKey: 42)
    ///             .select(
    ///                 SQLLiteral(
    ///                     sql: "IFNULL(name, ?)",
    ///                     arguments: ["Anonymous"]),
    ///                 as: String.self)
    ///         let name: String? = try request.fetchOne(db)
    ///     }
    ///
    /// With Swift 5, you can safely embed raw values in your SQL queries,
    /// without any risk of syntax errors or SQL injection:
    ///
    ///     try dbQueue.read { db in
    ///         // SELECT IFNULL(name, 'Anonymous') FROM player WHERE id = 42
    ///         let request = Player.
    ///             .filter(primaryKey: 42)
    ///             .select(
    ///                 literal: "IFNULL(name, \("Anonymous"))",
    ///                 as: String.self)
    ///         let name: String? = try request.fetchOne(db)
    ///     }
    public func select<RowDecoder>(
        literal sqlLiteral: SQLLiteral,
        as type: RowDecoder.Type = RowDecoder.self)
    -> QueryInterfaceRequest<RowDecoder>
    {
        select(sqlLiteral.sqlSelection, as: type)
    }
    
    /// Creates a request which appends *selection promise*.
    ///
    ///     // SELECT id, email, name FROM player
    ///     var request = Player.all()
    ///     request = request
    ///         .select([Column("id"), Column("email")])
    ///         .annotated(with: { db in [Column("name")] })
    public func annotated(with selection: @escaping (Database) throws -> [SQLSelectable]) -> QueryInterfaceRequest {
        map(\.query) { $0.annotated { try selection($0).map(\.sqlSelection) } }
    }
}

extension QueryInterfaceRequest: FilteredRequest {
    /// Creates a request with the provided *predicate promise* added to the
    /// eventual set of already applied predicates.
    ///
    ///     // SELECT * FROM player WHERE 1
    ///     var request = Player.all()
    ///     request = request.filter { db in true }
    public func filter(_ predicate: @escaping (Database) throws -> SQLExpressible) -> QueryInterfaceRequest {
        map(\.query) { $0.filter { try predicate($0).sqlExpression } }
    }
}

extension QueryInterfaceRequest: OrderedRequest {
    /// Creates a request with the provided *orderings promise*.
    ///
    ///     // SELECT * FROM player ORDER BY name
    ///     var request = Player.all()
    ///     request = request.order { _ in [Column("name")] }
    ///
    /// Any previous ordering is replaced:
    ///
    ///     // SELECT * FROM player ORDER BY name
    ///     request
    ///         .order{ _ in [Column("email")] }
    ///         .reversed()
    ///         .order{ _ in [Column("name")] }
    public func order(_ orderings: @escaping (Database) throws -> [SQLOrderingTerm]) -> QueryInterfaceRequest {
        map(\.query) { $0.order { try orderings($0).map(\.sqlOrdering) } }
    }
    
    /// Creates a request that reverses applied orderings.
    ///
    ///     // SELECT * FROM player ORDER BY name DESC
    ///     var request = Player.all().order(Column("name"))
    ///     request = request.reversed()
    ///
    /// If no ordering was applied, the returned request is identical.
    ///
    ///     // SELECT * FROM player
    ///     var request = Player.all()
    ///     request = request.reversed()
    public func reversed() -> QueryInterfaceRequest {
        map(\.query) { $0.reversed() }
    }
    
    /// Creates a request without any ordering.
    ///
    ///     // SELECT * FROM player
    ///     var request = Player.all().order(Column("name"))
    ///     request = request.unordered()
    public func unordered() -> QueryInterfaceRequest {
        map(\.query) { $0.unordered() }
    }
}

extension QueryInterfaceRequest: AggregatingRequest {
    /// Creates a request grouped according to *expressions promise*.
    public func group(_ expressions: @escaping (Database) throws -> [SQLExpressible]) -> QueryInterfaceRequest {
        map(\.query) { $0.group { try expressions($0).map(\.sqlExpression) } }
    }
    
    /// Creates a request with the provided *predicate promise* added to the
    /// eventual set of already applied predicates.
    public func having(_ predicate: @escaping (Database) throws -> SQLExpressible) -> QueryInterfaceRequest {
        map(\.query) { $0.having { try predicate($0).sqlExpression } }
    }
}

/// :nodoc:
extension QueryInterfaceRequest: _JoinableRequest {
    /// :nodoc:
    public func _including(all association: _SQLAssociation) -> QueryInterfaceRequest {
        map(\.query) { $0._including(all: association) }
    }
    
    /// :nodoc:
    public func _including(optional association: _SQLAssociation) -> QueryInterfaceRequest {
        map(\.query) { $0._including(optional: association) }
    }
    
    /// :nodoc:
    public func _including(required association: _SQLAssociation) -> QueryInterfaceRequest {
        map(\.query) { $0._including(required: association) }
    }
    
    /// :nodoc:
    public func _joining(optional association: _SQLAssociation) -> QueryInterfaceRequest {
        map(\.query) { $0._joining(optional: association) }
    }
    
    /// :nodoc:
    public func _joining(required association: _SQLAssociation) -> QueryInterfaceRequest {
        map(\.query) { $0._joining(required: association) }
    }
}

extension QueryInterfaceRequest: JoinableRequest { }

extension QueryInterfaceRequest: TableRequest {
    /// :nodoc:
    public var databaseTableName: String {
        query.relation.source.tableName
    }
    
    /// Creates a request that allows you to define expressions that target
    /// a specific database table.
    ///
    /// In the example below, the "team.avgScore < player.score" condition in
    /// the ON clause could be not achieved without table aliases.
    ///
    ///     struct Player: TableRecord {
    ///         static let team = belongsTo(Team.self)
    ///     }
    ///
    ///     // SELECT player.*, team.*
    ///     // JOIN team ON ... AND team.avgScore < player.score
    ///     let playerAlias = TableAlias()
    ///     let request = Player
    ///         .all()
    ///         .aliased(playerAlias)
    ///         .including(required: Player.team.filter(Column("avgScore") < playerAlias[Column("score")])
    public func aliased(_ alias: TableAlias) -> QueryInterfaceRequest {
        map(\.query) { $0.qualified(with: alias) }
    }
}

extension QueryInterfaceRequest: DerivableRequest where RowDecoder: TableRecord { }

extension QueryInterfaceRequest {
    /// Creates a request which returns distinct rows.
    ///
    ///     // SELECT DISTINCT * FROM player
    ///     var request = Player.all()
    ///     request = request.distinct()
    ///
    ///     // SELECT DISTINCT name FROM player
    ///     var request = Player.select(Column("name"))
    ///     request = request.distinct()
    public func distinct() -> QueryInterfaceRequest {
        map(\.query) { $0.distinct() }
    }
    
    /// Creates a request which fetches *limit* rows, starting at *offset*.
    ///
    ///     // SELECT * FROM player LIMIT 1
    ///     var request = Player.all()
    ///     request = request.limit(1)
    ///
    /// Any previous limit is replaced.
    public func limit(_ limit: Int, offset: Int? = nil) -> QueryInterfaceRequest {
        map(\.query) { $0.limit(limit, offset: offset) }
    }
    
    /// Creates a request bound to type RowDecoder.
    ///
    /// The returned request can fetch if the type RowDecoder is fetchable (Row,
    /// value, record).
    ///
    ///     // Int?
    ///     let maxScore = try Player
    ///         .select(max(scoreColumn))
    ///         .asRequest(of: Int.self)    // <--
    ///         .fetchOne(db)
    ///
    /// - parameter type: The fetched type RowDecoder
    /// - returns: A request bound to type RowDecoder.
    public func asRequest<RowDecoder>(of type: RowDecoder.Type) -> QueryInterfaceRequest<RowDecoder> {
        QueryInterfaceRequest<RowDecoder>(query: query)
    }
}

// MARK: - Aggregates

extension QueryInterfaceRequest {
    
    private func annotated(with aggregate: AssociationAggregate<RowDecoder>) -> QueryInterfaceRequest {
        var request = self
        let expressionPromise = aggregate.prepare(&request)
        if let key = aggregate.key {
            return request.annotated(with: { db in try [expressionPromise.resolve(db).forKey(key)] })
        } else {
            return request.annotated(with: { db in try [expressionPromise.resolve(db)] })
        }
    }
    
    /// Creates a request which appends *aggregates* to the current selection.
    ///
    ///     // SELECT player.*, COUNT(DISTINCT book.id) AS bookCount
    ///     // FROM player LEFT JOIN book ...
    ///     var request = Player.all()
    ///     request = request.annotated(with: Player.books.count)
    public func annotated(with aggregates: AssociationAggregate<RowDecoder>...) -> QueryInterfaceRequest {
        annotated(with: aggregates)
    }
    
    /// Creates a request which appends *aggregates* to the current selection.
    ///
    ///     // SELECT player.*, COUNT(DISTINCT book.id) AS bookCount
    ///     // FROM player LEFT JOIN book ...
    ///     var request = Player.all()
    ///     request = request.annotated(with: [Player.books.count])
    public func annotated(with aggregates: [AssociationAggregate<RowDecoder>]) -> QueryInterfaceRequest {
        aggregates.reduce(self) { request, aggregate in
            request.annotated(with: aggregate)
        }
    }
    
    /// Creates a request which appends the provided aggregate *predicate* to
    /// the eventual set of already applied predicates.
    ///
    ///     // SELECT player.*
    ///     // FROM player LEFT JOIN book ...
    ///     // HAVING COUNT(DISTINCT book.id) = 0
    ///     var request = Player.all()
    ///     request = request.having(Player.books.isEmpty)
    public func having(_ predicate: AssociationAggregate<RowDecoder>) -> QueryInterfaceRequest {
        var request = self
        let expressionPromise = predicate.prepare(&request)
        return request.having(expressionPromise.resolve)
    }
}

// MARK: - Batch Delete

extension QueryInterfaceRequest where RowDecoder: MutablePersistableRecord {
    /// Deletes matching rows; returns the number of deleted rows.
    ///
    /// - parameter db: A database connection.
    /// - returns: The number of deleted rows
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    @discardableResult
    public func deleteAll(_ db: Database) throws -> Int {
        try SQLQueryGenerator(query: query).makeDeleteStatement(db).execute()
        return db.changesCount
    }
}

// MARK: - Batch Update

extension QueryInterfaceRequest where RowDecoder: MutablePersistableRecord {
    /// Updates matching rows; returns the number of updated rows.
    ///
    /// For example:
    ///
    ///     try dbQueue.write { db in
    ///         // UPDATE player SET score = 0
    ///         try Player.all().updateAll(db, [Column("score").set(to: 0)])
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution,
    ///   defaulting to the record's persistenceConflictPolicy.
    /// - parameter assignments: An array of column assignments.
    /// - returns: The number of updated rows.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    @discardableResult
    public func updateAll(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        _ assignments: [ColumnAssignment]) throws -> Int
    {
        let conflictResolution = conflictResolution ?? RowDecoder.persistenceConflictPolicy.conflictResolutionForUpdate
        guard let updateStatement = try SQLQueryGenerator(query: query).makeUpdateStatement(
                db,
                conflictResolution: conflictResolution,
                assignments: assignments) else
        {
            // database not hit
            return 0
        }
        try updateStatement.execute()
        return db.changesCount
    }
    
    /// Updates matching rows; returns the number of updated rows.
    ///
    /// For example:
    ///
    ///     try dbQueue.write { db in
    ///         // UPDATE player SET score = 0
    ///         try Player.all().updateAll(db, Column("score").set(to: 0))
    ///     }
    ///
    /// - parameter db: A database connection.
    /// - parameter conflictResolution: A policy for conflict resolution,
    ///   defaulting to the record's persistenceConflictPolicy.
    /// - parameter assignment: A column assignment.
    /// - parameter otherAssignments: Eventual other column assignments.
    /// - returns: The number of updated rows.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    @discardableResult
    public func updateAll(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil,
        _ assignment: ColumnAssignment,
        _ otherAssignments: ColumnAssignment...)
    throws -> Int
    {
        try updateAll(db, onConflict: conflictResolution, [assignment] + otherAssignments)
    }
}

// MARK: - ColumnAssignment

/// A ColumnAssignment can update rows in the database.
///
/// You create an assignment from a column and an assignment method or operator,
/// such as `set(to:)` or `+=`:
///
///     try dbQueue.write { db in
///         // UPDATE player SET score = 0
///         let assignment = Column("score").set(to: 0)
///         try Player.updateAll(db, assignment)
///     }
public struct ColumnAssignment {
    var column: ColumnExpression
    var value: SQLExpression
    
    func sql(_ context: SQLGenerationContext) throws -> String {
        try column.sqlExpression.sql(context) + " = " + value.sql(context)
    }
}

extension ColumnExpression {
    /// Creates an assignment to a value.
    ///
    ///     Column("valid").set(to: true)
    ///     Column("score").set(to: 0)
    ///     Column("score").set(to: nil)
    ///     Column("score").set(to: Column("score") + Column("bonus"))
    ///
    ///     try dbQueue.write { db in
    ///         // UPDATE player SET score = 0
    ///         try Player.updateAll(db, Column("score").set(to: 0))
    ///     }
    public func set(to value: SQLExpressible?) -> ColumnAssignment {
        ColumnAssignment(column: self, value: value?.sqlExpression ?? .null)
    }
}

/// Creates an assignment that adds a value
///
///     Column("score") += 1
///     Column("score") += Column("bonus")
///
///     try dbQueue.write { db in
///         // UPDATE player SET score = score + 1
///         try Player.updateAll(db, Column("score") += 1)
///     }
public func += (column: ColumnExpression, value: SQLExpressible) -> ColumnAssignment {
    column.set(to: column + value)
}

/// Creates an assignment that subtracts a value
///
///     Column("score") -= 1
///     Column("score") -= Column("bonus")
///
///     try dbQueue.write { db in
///         // UPDATE player SET score = score - 1
///         try Player.updateAll(db, Column("score") -= 1)
///     }
public func -= (column: ColumnExpression, value: SQLExpressible) -> ColumnAssignment {
    column.set(to: column - value)
}

/// Creates an assignment that multiplies by a value
///
///     Column("score") *= 2
///     Column("score") *= Column("factor")
///
///     try dbQueue.write { db in
///         // UPDATE player SET score = score * 2
///         try Player.updateAll(db, Column("score") *= 2)
///     }
public func *= (column: ColumnExpression, value: SQLExpressible) -> ColumnAssignment {
    column.set(to: column * value)
}

/// Creates an assignment that divides by a value
///
///     Column("score") /= 2
///     Column("score") /= Column("factor")
///
///     try dbQueue.write { db in
///         // UPDATE player SET score = score / 2
///         try Player.updateAll(db, Column("score") /= 2)
///     }
public func /= (column: ColumnExpression, value: SQLExpressible) -> ColumnAssignment {
    column.set(to: column / value)
}

// MARK: - Eager loading of hasMany associations

// CAUTION: Keep this code in sync with prefetchedRegion(_:_:)
/// Append rows from prefetched associations into the `originRows` argument.
///
/// - parameter db: A database connection.
/// - parameter associations: Prefetched associations.
/// - parameter originRows: The rows that need to be extended with prefetched rows.
/// - parameter originQuery: The query that was used to fetch `originRows`.
private func prefetch(
    _ db: Database,
    associations: [_SQLAssociation],
    from originQuery: SQLQuery,
    into originRows: [Row]) throws
{
    guard let firstOriginRow = originRows.first else {
        // No rows -> no prefetch
        return
    }
    
    for association in associations {
        switch association.pivot.condition {
        case .expression:
            // Likely a GRDB bug: such condition only exist for CTEs, which
            // are not prefetched with including(all:)
            fatalError("Not implemented: prefetch association without any foreign key")
            
        case let .foreignKey(pivotForeignKey):
            let originTable = originQuery.relation.source.tableName
            let pivotMapping = try pivotForeignKey.joinMapping(db, from: originTable)
            let pivotColumns = pivotMapping.map(\.right)
            let leftColumns = pivotMapping.map(\.left)
            
            // We want to avoid the "Expression tree is too large" SQLite error
            // when the foreign key contains several columns, and there are many
            // base rows that overflow SQLITE_LIMIT_EXPR_DEPTH:
            // https://github.com/groue/GRDB.swift/issues/871
            //
            //      -- May be too complex for the SQLite engine
            //      SELECT * FROM child
            //      WHERE (a = ? AND b = ?)
            //         OR (a = ? AND b = ?)
            //         OR ...
            //
            // Instead, we do not inject any value from the base rows in
            // the prefetch request. Instead, we directly inject the base
            // request as a common table expression (CTE):
            //
            //      WITH grdb_base AS (SELECT a, b FROM parent)
            //      SELECT * FROM child
            //      WHERE (a, b) IN grdb_base
            //
            // This technique works well, but there is one precondition: row
            // values must be available (https://www.sqlite.org/rowvalue.html).
            // This is the case of almost all our target platforms.
            //
            // Otherwise, we fallback to the `(a = ? AND b = ?) OR ...`
            // condition (the one that may fail if there are too many
            // base rows).
            let usesCommonTableExpression = pivotMapping.count > 1 && SQLExpression.rowValuesAreAvailable
            
            let prefetchRequest: QueryInterfaceRequest<Row>
            if usesCommonTableExpression {
                // HasMany: Author.including(all: Author.books)
                //
                //      WITH grdb_base AS (SELECT a, b FROM author)
                //      SELECT book.*, book.authorId AS grdb_authorId
                //      FROM book
                //      WHERE (book.a, book.b) IN grdb_base
                //
                // HasManyThrough: Citizen.including(all: Citizen.countries)
                //
                //      WITH grdb_base AS (SELECT a, b FROM citizen)
                //      SELECT country.*, passport.citizenId AS grdb_citizenId
                //      FROM country
                //      JOIN passport ON passport.countryCode = country.code
                //                    AND (passport.a, passport.b) IN grdb_base
                let originQuery = originQuery.map(\.relation) { baseRelation in
                    // Ordering and including(all:) children are
                    // useless, and we only need pivoting columns:
                    baseRelation
                        .unordered()
                        .removingChildrenForPrefetchedAssociations()
                        .selectOnly(leftColumns.map { SQLExpression.column($0).sqlSelection })
                }
                let originCTE = CommonTableExpression<Void>(
                    named: "grdb_base",
                    request: SQLSubquery.query(originQuery))
                let pivotRowValue = SQLExpression.rowValue(pivotColumns.map(SQLExpression.column))!
                let pivotFilter = originCTE.contains(pivotRowValue)
                
                prefetchRequest = makePrefetchRequest(
                    for: association,
                    filteringPivotWith: pivotFilter,
                    annotatedWith: pivotColumns)
                    .with(originCTE)
            } else {
                // HasMany: Author.including(all: Author.books)
                //
                //      SELECT *, authorId AS grdb_authorId
                //      FROM book
                //      WHERE authorId IN (1, 2, 3)
                //
                // HasManyThrough: Citizen.including(all: Citizen.countries)
                //
                //      SELECT country.*, passport.citizenId AS grdb_citizenId
                //      FROM country
                //      JOIN passport ON passport.countryCode = country.code
                //                    AND passport.citizenId IN (1, 2, 3)
                let pivotFilter = pivotMapping.joinExpression(leftRows: originRows)
                
                prefetchRequest = makePrefetchRequest(
                    for: association,
                    filteringPivotWith: pivotFilter,
                    annotatedWith: pivotColumns)
            }
            
            let prefetchedRows = try prefetchRequest.fetchAll(db)
            let prefetchedGroups = prefetchedRows.grouped(byDatabaseValuesOnColumns: pivotColumns.map { "grdb_\($0)" })
            let groupingIndexes = firstOriginRow.indexes(forColumns: leftColumns)
            
            for row in originRows {
                let groupingKey = groupingIndexes.map { row.impl.databaseValue(atUncheckedIndex: $0) }
                let prefetchedRows = prefetchedGroups[groupingKey, default: []]
                row.prefetchedRows.setRows(prefetchedRows, forKeyPath: association.keyPath)
            }
        }
    }
}

/// Returns a request for prefetched rows.
///
/// - parameter assocciation: The prefetched association.
/// - parameter pivotFilter: The expression that filters the pivot of
///   the association.
/// - parameter pivotColumns: The pivot columns that annotate the
///   returned request.
func makePrefetchRequest(
    for association: _SQLAssociation,
    filteringPivotWith pivotFilter: SQLExpression,
    annotatedWith pivotColumns: [String])
-> QueryInterfaceRequest<Row>
{
    // We annotate prefetched rows with pivot columns, so that we can
    // group them.
    //
    // Those pivot columns are necessary when we prefetch
    // indirect associations:
    //
    //      // SELECT country.*, passport.citizenId AS grdb_citizenId
    //      // --                ^ the necessary pivot column
    //      // FROM country
    //      // JOIN passport ON passport.countryCode = country.code
    //      //               AND passport.citizenId IN (1, 2, 3)
    //      Citizen.including(all: Citizen.countries)
    //
    // Those pivot columns are redundant when we prefetch direct
    // associations (maybe we'll remove this redundancy later):
    //
    //      // SELECT *, authorId AS grdb_authorId
    //      // --        ^ the redundant pivot column
    //      // FROM book
    //      // WHERE authorId IN (1, 2, 3)
    //      Author.including(all: Author.books)
    let pivotAlias = TableAlias()
    
    let prefetchRelation = association
        .map(\.pivot.relation, { $0.qualified(with: pivotAlias).filter(pivotFilter) })
        .destinationRelation()
        .annotated(with: pivotColumns.map { pivotAlias[$0].forKey("grdb_\($0)") })
    
    return QueryInterfaceRequest<Row>(relation: prefetchRelation)
}

// CAUTION: Keep this code in sync with prefetch(_:associations:in:)
/// Returns the region of prefetched associations
func prefetchedRegion(
    _ db: Database,
    associations: [_SQLAssociation],
    from originTable: String)
throws -> DatabaseRegion
{
    try associations.reduce(into: DatabaseRegion()) { (region, association) in
        switch association.pivot.condition {
        case .expression:
            // Likely a GRDB bug: such condition only exist for CTEs, which
            // are not prefetched with including(all:)
            fatalError("Not implemented: prefetch association without any foreign key")
            
        case let .foreignKey(pivotForeignKey):
            let pivotMapping = try pivotForeignKey.joinMapping(db, from: originTable)
            let prefetchRegion = try prefetchedRegion(db, association: association, pivotMapping: pivotMapping)
            region.formUnion(prefetchRegion)
        }
    }
}

// CAUTION: Keep this code in sync with prefetch(_:associations:in:)
func prefetchedRegion(
    _ db: Database,
    association: _SQLAssociation,
    pivotMapping: JoinMapping)
throws -> DatabaseRegion
{
    // Filter the pivot on a `DummyRow` in order to make sure all join
    // condition columns are made visible to SQLite, and present in the
    // selected region:
    //  ... JOIN right ON right.leftId = ?
    //                                   ^ content of the DummyRow
    let pivotFilter = pivotMapping.joinExpression(leftRows: [DummyRow()])
    
    let prefetchRelation = association
        .map(\.pivot.relation) { $0.filter(pivotFilter) }
        .destinationRelation()
    
    let prefetchQuery = SQLQuery(relation: prefetchRelation)
    
    return try SQLQueryGenerator(query: prefetchQuery)
        .makeSelectStatement(db)
        .databaseRegion // contains region of nested associations
}

extension Array where Element == Row {
    /// - precondition: Columns all exist in all rows. All rows have the same
    ///   columnns, in the same order.
    fileprivate func grouped(byDatabaseValuesOnColumns columns: [String]) -> [[DatabaseValue]: [Row]] {
        guard let firstRow = first else {
            return [:]
        }
        let indexes = firstRow.indexes(forColumns: columns)
        return Dictionary(grouping: self, by: { row in
            indexes.map { row.impl.databaseValue(atUncheckedIndex: $0) }
        })
    }
}

extension Row {
    /// - precondition: Columns all exist in the row.
    fileprivate func indexes(forColumns columns: [String]) -> [Int] {
        columns.map { column -> Int in
            guard let index = index(forColumn: column) else {
                fatalError("Column \(column) is not selected")
            }
            return index
        }
    }
}
