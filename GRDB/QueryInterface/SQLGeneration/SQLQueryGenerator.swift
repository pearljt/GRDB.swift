/// SQLQueryGenerator is able to generate an SQL SELECT query.
struct SQLQueryGenerator: Refinable {
    fileprivate private(set) var relation: SQLQualifiedRelation
    private let isDistinct: Bool
    private let groupPromise: DatabasePromise<[SQLExpression]>?
    private let havingExpressionsPromise: DatabasePromise<[SQLExpression]>
    private let limit: SQLLimit?
    
    init(_ query: SQLQuery) {
        // To generate SQL, we need a "qualified" relation, where all tables,
        // expressions, etc, are identified with table aliases.
        //
        // All those aliases let us disambiguate tables at the SQL level, and
        // prefix columns names. For example, the following request...
        //
        //      Book.filter(Column("kind") == Book.Kind.novel)
        //          .including(optional: Book.author)
        //          .including(optional: Book.translator)
        //          .annotated(with: Book.awards.count)
        //
        // ... generates the following SQL, where all identifiers are correctly
        // disambiguated and qualified:
        //
        //      SELECT book.*, person1.*, person2.*, COUNT(DISTINCT award.id)
        //      FROM book
        //      LEFT JOIN person person1 ON person1.id = book.authorId
        //      LEFT JOIN person person2 ON person2.id = book.translatorId
        //      LEFT JOIN award ON award.bookId = book.id
        //      GROUP BY book.id
        //      WHERE book.kind = 'novel'
        relation = SQLQualifiedRelation(query.relation)
        
        // Qualify group expressions and having clause with the relation alias.
        //
        // This turns `GROUP BY id` INTO `GROUP BY book.id`, and
        // `HAVING MAX(year) < 2000` INTO `HAVING MAX(book.year) < 2000`.
        let alias = relation.sourceAlias
        groupPromise = query.groupPromise?.map { $0.map { $0.qualifiedExpression(with: alias) } }
        havingExpressionsPromise = query.havingExpressionsPromise.map { $0.map { $0.qualifiedExpression(with: alias) } }
        
        // Preserve other flags
        isDistinct = query.isDistinct
        limit = query.limit
    }
    
    func sql(_ context: inout SQLGenerationContext) throws -> String {
        var sql = "SELECT"
        
        if isDistinct {
            sql += " DISTINCT"
        }
        
        let selection = try relation.selectionPromise.resolve(context.db)
        GRDBPrecondition(!selection.isEmpty, "Can't generate SQL with empty selection")
        sql += try " " + selection.map { try $0.resultColumnSQL(&context) }.joined(separator: ", ")
        
        sql += " FROM "
        sql += try relation.source.sql(&context)
        
        for (_, join) in relation.joins {
            sql += " "
            sql += try join.sql(&context, leftAlias: relation.sourceAlias)
        }
        
        let filters = try relation.filtersPromise.resolve(context.db)
        if filters.isEmpty == false {
            sql += " WHERE "
            sql += try filters.joined(operator: .and).expressionSQL(&context, wrappedInParenthesis: false)
        }
        
        if let groupExpressions = try groupPromise?.resolve(context.db), !groupExpressions.isEmpty {
            sql += " GROUP BY "
            sql += try groupExpressions
                .map { try $0.expressionSQL(&context, wrappedInParenthesis: false) }
                .joined(separator: ", ")
        }
        
        let havingExpressions = try havingExpressionsPromise.resolve(context.db)
        if havingExpressions.isEmpty == false {
            sql += " HAVING "
            sql += try havingExpressions.joined(operator: .and).expressionSQL(&context, wrappedInParenthesis: false)
        }
        
        let orderings = try relation.ordering.resolve(context.db)
        if !orderings.isEmpty {
            sql += " ORDER BY "
            sql += try orderings
                .map { try $0.orderingTermSQL(&context) }
                .joined(separator: ", ")
        }
        
        if let limit = limit {
            sql += " LIMIT "
            sql += limit.sql
        }
        
        return sql
    }
    
    func prepare(_ db: Database) throws -> (SelectStatement, RowAdapter?) {
        try (makeSelectStatement(db), rowAdapter(db))
    }
    
    private func optimizedSelectedRegion(_ db: Database, _ selectedRegion: DatabaseRegion) throws -> DatabaseRegion {
        // Can we intersect the region with rowIds?
        //
        // Give up unless request feeds from a single database table
        guard case .table(tableName: let tableName, alias: _) = relation.source else {
            // TODO: try harder
            return selectedRegion
        }
        
        // Give up unless primary key is rowId
        let primaryKeyInfo = try db.primaryKey(tableName)
        guard primaryKeyInfo.isRowID else {
            return selectedRegion
        }
        
        // The filters knows better
        let filters = try relation.filtersPromise.resolve(db)
        guard let rowIds = filters.joined(operator: .and).matchedRowIds(rowIdName: primaryKeyInfo.rowIDColumn) else {
            return selectedRegion
        }
        
        // Database regions are case-sensitive: use the canonical table name
        let canonicalTableName = try db.canonicalTableName(tableName)
        return selectedRegion.tableIntersection(canonicalTableName, rowIds: rowIds)
    }
    
    func makeDeleteStatement(_ db: Database) throws -> UpdateStatement {
        switch try grouping(db) {
        case .none:
            guard case .table = relation.source else {
                // Programmer error
                fatalError("Can't delete without any database table")
            }
            
            guard relation.joins.isEmpty else {
                return try makeTrivialDeleteStatement(db)
            }
            
            var context = SQLGenerationContext.queryContext(db, aliases: relation.allAliases)
            
            var sql = try "DELETE FROM " + relation.source.sql(&context)
            
            let filters = try relation.filtersPromise.resolve(db)
            if filters.isEmpty == false {
                sql += " WHERE "
                sql += try filters
                    .joined(operator: .and)
                    .expressionSQL(&context, wrappedInParenthesis: false)
            }
            
            if let limit = limit {
                let orderings = try relation.ordering.resolve(db)
                if !orderings.isEmpty {
                    sql += try " ORDER BY " + orderings.map { try $0.orderingTermSQL(&context) }.joined(separator: ", ")
                }
                sql += " LIMIT " + limit.sql
            }
            
            let statement = try db.makeUpdateStatement(sql: sql)
            statement.arguments = context.arguments
            return statement
            
        case .unique:
            return try makeTrivialDeleteStatement(db)
            
        case .nonUnique:
            // Programmer error
            fatalError("Can't delete query with GROUP BY clause")
        }
    }
    
    /// DELETE FROM table WHERE id IN (SELECT id FROM table ...)
    private func makeTrivialDeleteStatement(_ db: Database) throws -> UpdateStatement {
        guard case let .table(tableName: tableName, alias: _) = relation.source else {
            // Programmer error
            fatalError("Can't delete without any database table")
        }
        
        var context = SQLGenerationContext.queryContext(db, aliases: relation.allAliases)
        let primaryKey = try db.primaryKeyExpression(tableName)
        
        var sql = "DELETE FROM \(tableName.quotedDatabaseIdentifier) WHERE "
        sql += try primaryKey.expressionSQL(&context, wrappedInParenthesis: false)
        sql += " IN ("
        sql += try map(\.relation, { $0.selectOnly([primaryKey]) }).sql(&context)
        sql += ")"
        
        let statement = try db.makeUpdateStatement(sql: sql)
        statement.arguments = context.arguments
        return statement
    }
    
    /// Returns nil if assignments is empty
    func makeUpdateStatement(
        _ db: Database,
        conflictResolution: Database.ConflictResolution,
        assignments: [ColumnAssignment])
        throws -> UpdateStatement?
    {
        switch try grouping(db) {
        case .none:
            guard case .table = relation.source else {
                // Programmer error
                fatalError("Can't update without any database table")
            }
            
            guard relation.joins.isEmpty else {
                return try makeTrivialUpdateStatement(
                    db,
                    conflictResolution: conflictResolution,
                    assignments: assignments)
            }
            
            // Check for empty assignments after all programmer errors have
            // been checked.
            if assignments.isEmpty {
                return nil
            }
            
            var context = SQLGenerationContext.queryContext(db, aliases: relation.allAliases)
            
            var sql = "UPDATE "
            
            if conflictResolution != .abort {
                sql += "OR \(conflictResolution.rawValue) "
            }
            
            sql += try relation.source.sql(&context)
            
            let assignmentsSQL = try assignments
                .map { try $0.sql(&context) }
                .joined(separator: ", ")
            sql += " SET " + assignmentsSQL
            
            let filters = try relation.filtersPromise.resolve(db)
            if filters.isEmpty == false {
                sql += " WHERE "
                sql += try filters
                    .joined(operator: .and)
                    .expressionSQL(&context, wrappedInParenthesis: false)
            }
            
            if let limit = limit {
                let orderings = try relation.ordering.resolve(db)
                if !orderings.isEmpty {
                    sql += try " ORDER BY " + orderings.map { try $0.orderingTermSQL(&context) }.joined(separator: ", ")
                }
                sql += " LIMIT " + limit.sql
            }
            
            let statement = try db.makeUpdateStatement(sql: sql)
            statement.arguments = context.arguments
            return statement
            
        case .unique:
            return try makeTrivialUpdateStatement(db, conflictResolution: conflictResolution, assignments: assignments)
            
        case .nonUnique:
            // Programmer error
            fatalError("Can't update query with GROUP BY clause")
        }
    }
    
    /// UPDATE table SET ... WHERE id IN (SELECT id FROM table ...)
    /// Returns nil if assignments is empty
    private func makeTrivialUpdateStatement(
        _ db: Database,
        conflictResolution: Database.ConflictResolution,
        assignments: [ColumnAssignment])
        throws -> UpdateStatement?
    {
        guard case let .table(tableName: tableName, alias: _) = relation.source else {
            // Programmer error
            fatalError("Can't delete without any database table")
        }
        
        // Check for empty assignments after all programmer errors have
        // been checked.
        if assignments.isEmpty {
            return nil
        }
        
        var context = SQLGenerationContext.queryContext(db, aliases: relation.allAliases)
        let primaryKey = try db.primaryKeyExpression(tableName)
        
        // UPDATE table...
        var sql = "UPDATE "
        if conflictResolution != .abort {
            sql += "OR \(conflictResolution.rawValue) "
        }
        sql += tableName.quotedDatabaseIdentifier
        
        // SET column = value...
        let assignmentsSQL = try assignments
            .map { try $0.sql(&context) }
            .joined(separator: ", ")
        sql += " SET " + assignmentsSQL
        
        // WHERE id IN (SELECT id FROM ...)
        sql += " WHERE "
        sql += try primaryKey.expressionSQL(&context, wrappedInParenthesis: false)
        sql += " IN ("
        sql += try map(\.relation, { $0.selectOnly([primaryKey]) }).sql(&context)
        sql += ")"
        
        let statement = try db.makeUpdateStatement(sql: sql)
        statement.arguments = context.arguments
        return statement
    }
    
    /// Returns a select statement
    func makeSelectStatement(_ db: Database) throws -> SelectStatement {
        // Build an SQK generation context with all aliases found in the query,
        // so that we can disambiguate tables that are used several times with
        // SQL aliases.
        var context = SQLGenerationContext.queryContext(db, aliases: relation.allAliases)
        
        // Generate SQL
        let sql = try self.sql(&context)
        
        // Compile & set arguments
        let statement = try db.makeSelectStatement(sql: sql)
        statement.arguments = context.arguments
        
        // Optimize databaseRegion
        statement.selectedRegion = try optimizedSelectedRegion(db, statement.selectedRegion)
        return statement
    }
    
    /// Informs about the query grouping
    private enum GroupingInfo {
        /// No grouping at all: SELECT ... FROM player
        case none
        /// Grouped by unique key: SELECT ... FROM player GROUP BY id
        case unique
        /// Grouped by some non-unique columnns: SELECT ... FROM player GROUP BY teamId
        case nonUnique
    }
    
    /// Informs about the query grouping
    private func grouping(_ db: Database) throws -> GroupingInfo {
        // Empty group clause: no grouping
        // SELECT * FROM player
        guard let groupExpressions = try groupPromise?.resolve(db), groupExpressions.isEmpty == false else {
            return .none
        }
        
        // Grouping by something which is not a column: assume non
        // unique grouping.
        // SELECT * FROM player GROUP BY (score + bonus)
        let qualifiedColumns = groupExpressions.compactMap { $0 as? QualifiedColumn }
        if qualifiedColumns.count != groupExpressions.count {
            return .nonUnique
        }
        
        // Grouping something which is not a table: assume non unique grouping.
        guard case let .table(tableName: tableName, alias: alias) = relation.source else {
            return .nonUnique
        }
        
        // Grouping by some column(s) which do not come from the main table:
        // assume non unique grouping.
        // SELECT * FROM player JOIN team ... GROUP BY team.id
        guard qualifiedColumns.allSatisfy({ $0.alias == alias }) else {
            return .nonUnique
        }
        
        // Grouping by some column(s) which are unique
        // SELECT * FROM player GROUP BY id
        let columnNames = qualifiedColumns.map(\.name)
        if try db.table(tableName, hasUniqueKey: columnNames) {
            return .unique
        }
        
        // Grouping by some column(s) which are not unique
        // SELECT * FROM player GROUP BY score
        return .nonUnique
    }
    
    /// Returns the row adapter which presents the fetched rows according to the
    /// tree of joined relations.
    ///
    /// The adapter is nil for queries without any included relation,
    /// because the fetched rows don't need any processing:
    ///
    ///     // SELECT * FROM book
    ///     let request = Book.all()
    ///     for row in try Row.fetchAll(db, request) {
    ///         row // [id:1, title:"Moby-Dick"]
    ///         let book = Book(row: row)
    ///     }
    ///
    /// But as soon as the selection includes columns of a included relation,
    /// we need an adapter:
    ///
    ///     // SELECT book.*, author.* FROM book JOIN author ON author.id = book.authorId
    ///     let request = Book.including(required: Book.author)
    ///     for row in try Row.fetchAll(db, request) {
    ///         row // [id:1, title:"Moby-Dick"]
    ///         let book = Book(row: row)
    ///
    ///         row.scopes["author"] // [id:12, name:"Herman Melville"]
    ///         let author: Author = row["author"]
    ///     }
    private func rowAdapter(_ db: Database) throws -> RowAdapter? {
        try relation.rowAdapter(db, fromIndex: 0)?.adapter
    }
}

/// A "qualified" relation, where all tables are identified with a table alias.
///
///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
///            |        |        |         |            |
///            |        |        |         |            • ordering
///            |        |        |         • filterPromise
///            |        |        • joins
///            |        • source
///            • selectionPromise
private struct SQLQualifiedRelation {
    /// The source alias
    var sourceAlias: TableAlias { source.alias }
    
    /// All aliases, including aliases of joined relations
    var allAliases: [TableAlias] {
        joins.reduce(into: source.allAliases) {
            $0.append(contentsOf: $1.value.relation.allAliases)
        }
    }
    
    /// The source
    ///
    ///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
    ///                     |
    ///                     • source
    let source: SQLQualifiedSource
    
    /// The selection from source, not including selection of joined relations
    private var sourceSelectionPromise: DatabasePromise<[SQLSelectable]>
    
    /// The full selection, including selection of joined relations
    ///
    ///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
    ///            |
    ///            • selectionPromise
    var selectionPromise: DatabasePromise<[SQLSelectable]> {
        DatabasePromise { db in
            let selection = try self.sourceSelectionPromise.resolve(db)
            return try self.joins.values.reduce(into: selection) { selection, join in
                let joinedSelection = try join.relation.selectionPromise.resolve(db)
                selection.append(contentsOf: joinedSelection)
            }
        }
    }
    
    /// The filtering clause
    ///
    ///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
    ///                                        |
    ///                                        • filtersPromise
    let filtersPromise: DatabasePromise<[SQLExpression]>
    
    /// The ordering of source, not including ordering of joined relations
    private let sourceOrdering: SQLRelation.Ordering
    
    /// The full ordering, including orderings of joined relations
    ///
    ///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
    ///                                                     |
    ///                                                     • ordering
    var ordering: SQLRelation.Ordering {
        joins.reduce(sourceOrdering) {
            $0.appending($1.value.relation.ordering)
        }
    }
    
    /// The joins
    ///
    ///     SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...
    ///                              |
    ///                              • joins
    private(set) var joins: OrderedDictionary<String, SQLQualifiedJoin>
    
    init(_ relation: SQLRelation) {
        // Qualify the source, so that it be disambiguated with an SQL alias
        // if needed (when a select query uses the same table several times).
        // This disambiguation job will be actually performed by
        // SQLGenerationContext, when the SQLSelectQueryGenerator which owns
        // this SQLQualifiedRelation generates SQL.
        source = SQLQualifiedSource(relation.source)
        let sourceAlias = source.alias
        
        // Qualify all joins, selection, filter, and ordering, so that all
        // identifiers can be correctly disambiguated and qualified.
        joins = relation.children.compactMapValues { SQLQualifiedJoin($0) }
        sourceSelectionPromise = relation.selectionPromise.map { $0.map { $0.qualifiedSelectable(with: sourceAlias) } }
        filtersPromise = relation.filtersPromise.map { $0.map { $0.qualifiedExpression(with: sourceAlias) } }
        sourceOrdering = relation.ordering.qualified(with: sourceAlias)
    }
    
    /// See SQLQueryGenerator.rowAdapter(_:)
    ///
    /// - parameter db: A database connection.
    /// - parameter startIndex: The index of the leftmost selected column of
    ///   this relation in a full SQL query. `startIndex` is 0 for the relation
    ///   at the root of a SQLQueryGenerator (as opposed to the
    ///   joined relations).
    /// - returns: An optional tuple made of a RowAdapter and the index past the
    ///   rightmost selected column of this relation. Nil is returned if this
    ///   relations does not need any row adapter.
    func rowAdapter(_ db: Database, fromIndex startIndex: Int) throws -> (adapter: RowAdapter, endIndex: Int)? {
        // Root relation && no join => no need for any adapter
        if startIndex == 0 && joins.isEmpty {
            return nil
        }
        
        // The number of columns in source selection. Columns selected by joined
        // relations are appended after.
        let sourceSelectionWidth = try sourceSelectionPromise.resolve(db).reduce(0) {
            try $0 + $1.columnCount(db)
        }
        
        // Recursively build adapters for each joined relation with a selection.
        // Name them according to the join keys.
        var endIndex = startIndex + sourceSelectionWidth
        var scopes: [String: RowAdapter] = [:]
        for (key, join) in joins {
            if let (joinAdapter, joinEndIndex) = try join.relation.rowAdapter(db, fromIndex: endIndex) {
                scopes[key] = joinAdapter
                endIndex = joinEndIndex
            }
        }
        
        // (Root relation || empty selection) && no included relation => no need for any adapter
        if (startIndex == 0 || sourceSelectionWidth == 0) && scopes.isEmpty {
            return nil
        }
        
        // Build a RangeRowAdapter extended with the adapters of joined relations.
        //
        //      // SELECT book.*, author.* FROM book JOIN author ON author.id = book.authorId
        //      let request = Book.including(required: Book.author)
        //      for row in try Row.fetchAll(db, request) {
        //
        // The RangeRowAdapter hides the columns appended by joined relations:
        //
        //          row // [id:1, title:"Moby-Dick"]
        //          let book = Book(row: row)
        //
        // Scopes give access to those joined relations:
        //
        //          row.scopes["author"] // [id:12, name:"Herman Melville"]
        //          let author: Author = row["author"]
        //      }
        let rangeAdapter = RangeRowAdapter(startIndex ..< (startIndex + sourceSelectionWidth))
        let adapter = rangeAdapter.addingScopes(scopes)
        
        return (adapter: adapter, endIndex: endIndex)
    }
    
    /// Removes all selections from joins
    func selectOnly(_ selection: [SQLSelectable]) -> Self {
        let selectionPromise = DatabasePromise(value: selection.map { $0.qualifiedSelectable(with: sourceAlias) })
        return self
            .with(\.sourceSelectionPromise, selectionPromise)
            .map(\.joins, { $0.mapValues { $0.selectOnly([]) } })
    }
}

extension SQLQualifiedRelation: Refinable { }

/// A "qualified" source, where all tables are identified with a table alias.
private enum SQLQualifiedSource {
    case table(tableName: String, alias: TableAlias)
    indirect case query(SQLQueryGenerator)
    
    var alias: TableAlias {
        switch self {
        case .table(_, let alias):
            return alias
        case .query(let query):
            return query.relation.sourceAlias
        }
    }
    
    var allAliases: [TableAlias] {
        switch self {
        case .table(_, let alias):
            return [alias]
        case .query(let query):
            return query.relation.allAliases
        }
    }
    
    init(_ source: SQLSource) {
        switch source {
        case let .table(tableName, alias):
            let alias = alias ?? TableAlias(tableName: tableName)
            self = .table(tableName: tableName, alias: alias)
        case let .query(query):
            self = .query(SQLQueryGenerator(query))
        }
    }
    
    func sql(_ context: inout SQLGenerationContext) throws -> String {
        switch self {
        case let .table(tableName, alias):
            if let aliasName = context.aliasName(for: alias) {
                return "\(tableName.quotedDatabaseIdentifier) \(aliasName.quotedDatabaseIdentifier)"
            } else {
                return "\(tableName.quotedDatabaseIdentifier)"
            }
        case let .query(query):
            return try "(\(query.sql(&context)))"
        }
    }
}

/// A "qualified" join, where all tables are identified with a table alias.
private struct SQLQualifiedJoin: Refinable {
    enum Kind: String {
        case leftJoin = "LEFT JOIN"
        case innerJoin = "JOIN"
        
        init?(_ kind: SQLRelation.Child.Kind) {
            switch kind {
            case .oneRequired:
                self = .innerJoin
            case .oneOptional:
                self = .leftJoin
            case .allPrefetched, .allNotPrefetched:
                // Eager loading of to-many associations is not implemented with joins
                return nil
            }
        }
    }
    
    var kind: Kind
    var condition: SQLAssociationCondition
    var relation: SQLQualifiedRelation
    
    init?(_ child: SQLRelation.Child) {
        guard let kind = Kind(child.kind) else {
            return nil
        }
        self.kind = kind
        self.condition = child.condition
        self.relation = SQLQualifiedRelation(child.relation)
    }
    
    func sql(_ context: inout SQLGenerationContext, leftAlias: TableAlias) throws -> String {
        try sql(&context, leftAlias: leftAlias, allowingInnerJoin: true)
    }
    
    /// Removes all selections from joins
    func selectOnly(_ selection: [SQLSelectable]) -> SQLQualifiedJoin {
        map(\.relation) { $0.selectOnly(selection) }
    }
    
    private func sql(
        _ context: inout SQLGenerationContext,
        leftAlias: TableAlias,
        allowingInnerJoin allowsInnerJoin: Bool)
        throws -> String
    {
        var allowsInnerJoin = allowsInnerJoin
        
        switch self.kind {
        case .innerJoin:
            guard allowsInnerJoin else {
                // TODO: chainOptionalRequired
                //
                // When we eventually implement this, make sure we both support:
                // - joining(optional: assoc.joining(required: ...))
                // - having(assoc.joining(required: ...).isEmpty)
                fatalError("Not implemented: chaining a required association behind an optional association")
            }
        case .leftJoin:
            allowsInnerJoin = false
        }
        
        // JOIN table...
        var sql = try "\(kind.rawValue) \(relation.source.sql(&context))"
        let rightAlias = relation.sourceAlias
        
        // ... ON <join conditions> AND <other filters>
        var filters = try condition.expressions(context.db, leftAlias: leftAlias)
        filters += try relation.filtersPromise.resolve(context.db)
        if filters.isEmpty == false {
            let filterSQL = try filters
                .joined(operator: .and)
                .qualifiedExpression(with: rightAlias)
                .expressionSQL(&context, wrappedInParenthesis: false)
            sql += " ON \(filterSQL)"
        }
        
        for (_, join) in relation.joins {
            // Right becomes left as we dig further
            sql += try " \(join.sql(&context, leftAlias: rightAlias, allowingInnerJoin: allowsInnerJoin))"
        }
        
        return sql
    }
}
