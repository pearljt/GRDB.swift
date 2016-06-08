#if !USING_BUILTIN_SQLITE
    #if os(OSX)
        import SQLiteMacOSX
    #elseif os(iOS)
        #if (arch(i386) || arch(x86_64))
            import SQLiteiPhoneSimulator
        #else
            import SQLiteiPhoneOS
        #endif
    #endif
#endif

/// StatementMapping is a type that supports the RowAdapter protocol.
public struct StatementMapping {
    public let columns: [(Int, String)]      // [(baseRowIndex, mappedColumn), ...]
    let lowercaseColumnIndexes: [String: Int]   // [mappedColumn: adaptedRowIndex]

    /// Creates a StatementMapping from an array of (index, name) pairs.
    ///
    /// - index is the index of a column in an original row
    /// - name is the name of the column in an adapted row
    ///
    /// For example, the following StatementMapping defines two columns, "foo"
    /// and "bar", that load from the original columns at indexes 0 and 1:
    ///
    ///     StatementMapping([(0, "foo"), (1, "bar")])
    ///
    /// Use it in your custom RowAdapter type:
    ///
    ///     // An adapter that turns any row to a row that contains a single
    ///     // column named "foo" whose value is the leftmost value of the
    ///     // original row.
    ///     struct FooBarAdapter : RowAdapter {
    ///         func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
    ///             return StatementMapping([(0, "foo"), (1, "bar")])
    ///         }
    ///     }
    ///
    ///     // <Row foo:1 bar: 2>
    ///     let row = Row.fetchOne(db, "SELECT 1, 2, 3", adapter: FooBarAdapter())!
    public init(columns: [(Int, String)]) {
        self.columns = columns
        self.lowercaseColumnIndexes = Dictionary(keyValueSequence: columns.enumerate().map { ($1.1.lowercaseString, $0) }.reverse())
    }

    var count: Int {
        return columns.count
    }

    func baseColumIndex(adaptedIndex index: Int) -> Int {
        return columns[index].0
    }

    func columnName(adaptedIndex index: Int) -> String {
        return columns[index].1
    }

    func adaptedIndexOfColumn(named name: String) -> Int? {
        if let index = lowercaseColumnIndexes[name] {
            return index
        }
        return lowercaseColumnIndexes[name.lowercaseString]
    }
}

extension StatementMapping : StatementAdapter {
    /// Part of the StatementMapping protocol; returns self.
    public var statementMapping: StatementMapping {
        return self
    }
    
    /// Part of the StatementMapping protocol; returns the empty dictionary.
    public var variants: [String: StatementAdapter] {
        return [:]
    }
}

struct VariantStatementAdapter : StatementAdapter {
    let mainAdapter: StatementAdapter
    let variants: [String: StatementAdapter]
    
    var statementMapping: StatementMapping {
        return mainAdapter.statementMapping
    }
}

public protocol StatementAdapter {
    var statementMapping: StatementMapping { get }
    
    /// Default implementation return the empty dictionary.
    var variants: [String: StatementAdapter] { get }
}

extension StatementAdapter {
    /// Default implementation return the empty dictionary.
    var variants: [String: StatementAdapter] { return [:] }
}

/// RowAdapter is a protocol that helps two incompatible row interfaces to work
/// together.
///
/// GRDB ships with three concrete types that adopt the RowAdapter protocol:
///
/// - ColumnMapping: renames row columns
/// - SuffixRowAdapter: hides the first columns of a row
/// - VariantAdapter: groups several adapters together, and defines named
///   row variants.
///
/// If the built-in adapters don't fit your needs, you can implement your own
/// type that adopts RowAdapter.
///
/// To use a row adapter, provide it to a method that fetches:
///
///     let adapter = SuffixRowAdapter(fromIndex: 1)
///     let sql = "SELECT 1 AS foo, 2 AS bar, 3 AS baz"
///     let row = Row.fetchOne(db, sql, adapter: adapter)!
///     row // <Row bar:2 baz: 3>
public protocol RowAdapter {
    
    /// You never call this method directly. It is called for you whenever an
    /// adapter has to be applied.
    ///
    /// The result is a value that adopts StatementAdapter, such as
    /// StatementMapping.
    ///
    /// For example:
    ///
    ///     // An adapter that turns any row to a row that contains a single
    ///     // column named "foo" whose value is the leftmost value of the
    ///     // original row.
    ///     struct FirstColumnAdapter : RowAdapter {
    ///         func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
    ///             return StatementMapping(columns: [(0, "foo")])
    ///         }
    ///     }
    ///
    ///     // <Row foo:1>
    ///     let row = Row.fetchOne(db, "SELECT 1, 2, 3", adapter: FirstColumnAdapter())!
    func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter
}

public struct ColumnMapping : RowAdapter {
    public let mapping: [String: String]
    
    public init(_ mapping: [String: String]) {
        self.mapping = mapping
    }
    
    public func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
        let columns = try mapping
            .map { (mappedColumn, baseColumn) -> (Int, String) in
                guard let index = statement.indexOfColumn(named: baseColumn) else {
                    throw DatabaseError(code: SQLITE_MISUSE, message: "Mapping references missing column \(baseColumn). Valid column names are: \(statement.columnNames.joinWithSeparator(", ")).")
                }
                return (index, mappedColumn)
            }
            .sort { return $0.0 < $1.0 }
        return StatementMapping(columns: columns)
    }
}

public struct SuffixRowAdapter : RowAdapter {
    public let index: Int
    
    public init(fromIndex index: Int) {
        self.index = index
    }

    public func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
        return StatementMapping(columns: statement.columnNames.suffixFrom(index).enumerate().map { ($0 + index, $1) })
    }
}

public struct VariantAdapter : RowAdapter {
    public let mainAdapter: RowAdapter
    public let variants: [String: RowAdapter]
    
    public init(_ mainAdapter: RowAdapter? = nil, variants: [String: RowAdapter]) {
        self.mainAdapter = mainAdapter ?? IdentityRowAdapter()
        self.variants = variants
    }

    public func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
        let mainStatementAdapter = try mainAdapter.statementAdapter(with: statement)
        var variantStatementAdapters = mainStatementAdapter.variants
        for (name, adapter) in variants {
            try variantStatementAdapters[name] = adapter.statementAdapter(with: statement)
        }
        return VariantStatementAdapter(
            mainAdapter: mainStatementAdapter,
            variants: variantStatementAdapters)
    }
}

struct IdentityRowAdapter : RowAdapter {
    func statementAdapter(with statement: SelectStatement) throws -> StatementAdapter {
        return StatementMapping(columns: Array(statement.columnNames.enumerate()))
    }
}

extension Row {
    /// Builds a row from a base row and a statement adapter
    convenience init(baseRow: Row, statementAdapter: StatementAdapter) {
        self.init(impl: AdapterRowImpl(baseRow: baseRow, statementAdapter: statementAdapter))
    }

    /// Returns self if adapter is nil
    func adaptedRow(adapter adapter: RowAdapter?, statement: SelectStatement) throws -> Row {
        guard let adapter = adapter else {
            return self
        }
        return try Row(baseRow: self, statementAdapter: adapter.statementAdapter(with: statement))
    }
}

struct AdapterRowImpl : RowImpl {

    let baseRow: Row
    let statementAdapter: StatementAdapter
    let statementMapping: StatementMapping

    init(baseRow: Row, statementAdapter: StatementAdapter) {
        self.baseRow = baseRow
        self.statementAdapter = statementAdapter
        self.statementMapping = statementAdapter.statementMapping
    }

    var count: Int {
        return statementMapping.count
    }

    func databaseValue(atIndex index: Int) -> DatabaseValue {
        return baseRow.databaseValue(atIndex: statementMapping.baseColumIndex(adaptedIndex: index))
    }

    func dataNoCopy(atIndex index:Int) -> NSData? {
        return baseRow.dataNoCopy(atIndex: statementMapping.baseColumIndex(adaptedIndex: index))
    }

    func columnName(atIndex index: Int) -> String {
        return statementMapping.columnName(adaptedIndex: index)
    }

    func indexOfColumn(named name: String) -> Int? {
        return statementMapping.adaptedIndexOfColumn(named: name)
    }

    func variant(named name: String) -> Row? {
        guard let statementAdapter = statementAdapter.variants[name] else {
            return nil
        }
        return Row(baseRow: baseRow, statementAdapter: statementAdapter)
    }
    
    var variantNames: Set<String> {
        return Set(statementAdapter.variants.keys)
    }
    
    func copy(row: Row) -> Row {
        return Row(baseRow: baseRow.copy(), statementAdapter: statementAdapter)
    }
}
