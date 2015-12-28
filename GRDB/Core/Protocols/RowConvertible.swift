/// Types that adopt RowConvertible can be initialized from a database Row.
///
///     let row = Row.fetchOne(db, "SELECT ...")!
///     let person = Person(row)
///
/// The protocol comes with built-in methods that allow to fetch sequences,
/// arrays, or single values:
///
///     Person.fetch(db, "SELECT ...", arguments:...)    // DatabaseSequence<Person>
///     Person.fetchAll(db, "SELECT ...", arguments:...) // [Person]
///     Person.fetchOne(db, "SELECT ...", arguments:...) // Person?
///
///     let statement = db.selectStatement("SELECT ...")
///     Person.fetch(statement, arguments:...)           // DatabaseSequence<Person>
///     Person.fetchAll(statement, arguments:...)        // [Person]
///     Person.fetchOne(statement, arguments:...)        // Person?
///
/// RowConvertible is adopted by Record.
public protocol RowConvertible {
    
    /// Returns a value initialized from `row`.
    ///
    /// For performance reasons, the row argument may be reused between several
    /// instance initializations during the iteration of a fetch query. So if
    /// you want to keep the row for later use, make sure to store a copy:
    /// `result.row = row.copy()`.
    ///
    /// - parameter row: A Row.
    /// - returns: A value.
    static func fromRow(row: Row) -> Self
    
    /// Do not call this method directly.
    ///
    /// Types that adopt RowConvertible have an opportunity to complete their
    /// initialization.
    mutating func awakeFromFetch(row row: Row, database: Database)
}

extension RowConvertible {
    
    /// Default implementation, which does nothing.
    public func awakeFromFetch(row row: Row, database: Database) { }

    
    // MARK: - Fetching From SelectStatement
    
    /// Returns a sequence of values fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT * FROM persons")
    ///     let persons = Person.fetch(statement) // DatabaseSequence<Person>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let persons = Person.fetch(statement)
    ///     Array(persons).count // 3
    ///     db.execute("DELETE ...")
    ///     Array(persons).count // 2
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameter statement: The statement to run.
    /// - parameter arguments: Statement arguments.
    /// - returns: A sequence.
    public static func fetch(statement: SelectStatement, arguments: StatementArguments = StatementArguments.Default) -> DatabaseSequence<Self> {
        // Metal rows can be reused. And reusing them yields better performance.
        let row = Row(metalStatement: statement)
        return statement.fetch(arguments: arguments) {
            var value = fromRow(row)
            value.awakeFromFetch(row: row, database: statement.database)
            return value
        }
    }
    
    /// Returns an array of values fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT * FROM persons")
    ///     let persons = Person.fetchAll(statement) // [Person]
    ///
    /// - parameter statement: The statement to run.
    /// - parameter arguments: Statement arguments.
    /// - returns: An array.
    public static func fetchAll(statement: SelectStatement, arguments: StatementArguments = StatementArguments.Default) -> [Self] {
        return Array(fetch(statement, arguments: arguments))
    }
    
    /// Returns a single value fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT * FROM persons")
    ///     let persons = Person.fetchOne(statement) // Person?
    ///
    /// - parameter statement: The statement to run.
    /// - parameter arguments: Statement arguments.
    /// - returns: An optional value.
    public static func fetchOne(statement: SelectStatement, arguments: StatementArguments = StatementArguments.Default) -> Self? {
        var generator = fetch(statement, arguments: arguments).generate()
        return generator.next()
    }
    
    
    // MARK: - Fetching From Database
    
    /// Returns a sequence of values fetched from an SQL query.
    ///
    ///     let persons = Person.fetch(db, "SELECT * FROM persons") // DatabaseSequence<Person>
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let persons = Person.fetch(db, "SELECT * FROM persons")
    ///     Array(persons).count // 3
    ///     db.execute("DELETE ...")
    ///     Array(persons).count // 2
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements are undefined.
    ///
    /// - parameter db: A Database.
    /// - parameter sql: An SQL query.
    /// - parameter arguments: Statement arguments.
    /// - returns: A sequence.
    public static func fetch(db: Database, _ sql: String, arguments: StatementArguments = StatementArguments.Default) -> DatabaseSequence<Self> {
        return fetch(try! db.selectStatement(sql), arguments: arguments)
    }
    
    /// Returns an array of values fetched from an SQL query.
    ///
    ///     let persons = Person.fetchAll(db, "SELECT * FROM persons") // [Person]
    ///
    /// - parameter db: A Database.
    /// - parameter sql: An SQL query.
    /// - parameter arguments: Statement arguments.
    /// - returns: An array.
    public static func fetchAll(db: Database, _ sql: String, arguments: StatementArguments = StatementArguments.Default) -> [Self] {
        return fetchAll(try! db.selectStatement(sql), arguments: arguments)
    }
    
    /// Returns a single value fetched from an SQL query.
    ///
    ///     let person = Person.fetchOne(db, "SELECT * FROM persons") // Person?
    ///
    /// - parameter db: A Database.
    /// - parameter sql: An SQL query.
    /// - parameter arguments: Statement arguments.
    /// - returns: An optional value.
    public static func fetchOne(db: Database, _ sql: String, arguments: StatementArguments = StatementArguments.Default) -> Self? {
        return fetchOne(try! db.selectStatement(sql), arguments: arguments)
    }
}
