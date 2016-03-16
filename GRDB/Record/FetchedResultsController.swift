//
//  FetchedResultsController.swift
//  GRDB
//
//  Created by Pascal Edmond on 09/12/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//
import UIKit

private enum Source<T> {
    case SQL(String, StatementArguments?)
    case FetchRequest(GRDB.FetchRequest<T>)
    
    func selectStatement(db: Database) throws -> SelectStatement {
        switch self {
        case .SQL(let sql, let arguments):
            let statement = try db.selectStatement(sql)
            if let arguments = arguments {
                try statement.validateArguments(arguments)
                statement.unsafeSetArguments(arguments)
            }
            return statement
        case .FetchRequest(let request):
            return try request.selectStatement(db)
        }
    }
}

private struct FetchedItem<T: RowConvertible> : RowConvertible, Equatable {
    let row: Row
    var object: T   // var because awakeFromFetch is mutating
    
    init(_ row: Row) {
        self.row = row.copy()
        self.object = T(row)
    }
    
    mutating func awakeFromFetch(row row: Row, database: Database) {
        // TOOD: If object is a Record, it will copy the row *again*. We should
        // avoid creating two distinct copied instances.
        object.awakeFromFetch(row: row, database: database)
    }
}

private func ==<T>(lhs: FetchedItem<T>, rhs: FetchedItem<T>) -> Bool {
    return lhs.row == rhs.row
}

public class FetchedResultsController<T: RowConvertible> {
    
    // MARK: - Initialization
    public convenience init(_ database: DatabaseWriter, _ sql: String, arguments: StatementArguments? = nil, identityComparator: ((T, T) -> Bool)? = nil) {
        let source: Source<T> = .SQL(sql, arguments)
        self.init(database: database, source: source, identityComparator: identityComparator)
    }
    
    public convenience init(_ database: DatabaseWriter, _ request: FetchRequest<T>, identityComparator: ((T, T) -> Bool)? = nil) {
        let source: Source<T> = .FetchRequest(request)
        self.init(database: database, source: source, identityComparator: identityComparator)
    }
    
    private init(database: DatabaseWriter, source: Source<T>, identityComparator: ((T, T) -> Bool)?) {
        self.source = source
        self.database = database
        if let identityComparator = identityComparator {
            self.identityComparator = identityComparator
        } else {
            self.identityComparator = { _ in false }
        }
        database.addTransactionObserver(self)
    }
    
    public func performFetch() {
        try! database.read { db in
            let statement = try self.source.selectStatement(db)
            self.observedTables = statement.sourceTables
            self.fetchedItems = FetchedItem<T>.fetchAll(statement)
        }
    }
    
    
    // MARK: - Configuration
    
    /// The source
    private let source: Source<T>
    
    private let identityComparator: (T, T) -> Bool
    
    /// The observed tables. Set in performFetch()
    private var observedTables: Set<String>? = nil
    
    /// True if databaseDidCommit(db) should compute changes
    private var fetchedItemsDidChange = false
    
    private var fetchedItems: [FetchedItem<T>]?

    /// The databaseWriter
    public let database: DatabaseWriter
    
    /// Delegate that is notified when the resultss set changes.
    weak public var delegate: FetchedResultsControllerDelegate?
    
    
    // MARK: - Accessing results

    /// Returns the results of the query.
    /// Returns nil if the performQuery: hasn't been called.
    public var fetchedObjects: [T]? {
        if let fetchedItems = fetchedItems {
            return fetchedItems.map { $0.object }
        }
        return nil
    }

    
    /// Returns the fetched object at a given indexPath.
    public func objectAtIndexPath(indexPath: NSIndexPath) -> T? {
        if let item = fetchedItems?[indexPath.indexAtPosition(1)] {
            return item.object
        } else {
            return nil
        }
    }
    
    /// Returns the indexPath of a given object.
    public func indexPathForResult(result: T) -> NSIndexPath? {
        // TODO
        fatalError("Not implemented")
    }
    
    
    // MARK: - Not public
    
    private static func computeChanges(fromRows s: [FetchedItem<T>], toRows t: [FetchedItem<T>], identityComparator: ((T, T) -> Bool)) -> [ItemChange<T>] {
        
        let m = s.count
        let n = t.count
        
        // Fill first row and column of insertions and deletions.
        
        var d: [[[ItemChange<T>]]] = Array(count: m + 1, repeatedValue: Array(count: n + 1, repeatedValue: []))
        
        var changes = [ItemChange<T>]()
        for (row, item) in s.enumerate() {
            let deletion = ItemChange.Deletion(item: item, indexPath: NSIndexPath(forRow: row, inSection: 0))
            changes.append(deletion)
            d[row + 1][0] = changes
        }
        
        changes.removeAll()
        for (col, item) in t.enumerate() {
            let insertion = ItemChange.Insertion(item: item, indexPath: NSIndexPath(forRow: col, inSection: 0))
            changes.append(insertion)
            d[0][col + 1] = changes
        }
        
        if m == 0 || n == 0 {
            // Pure deletions or insertions
            return d[m][n]
        }
        
        // Fill body of matrix.
        for tx in 0..<n {
            for sx in 0..<m {
                if s[sx] == t[tx] {
                    d[sx+1][tx+1] = d[sx][tx] // no operation
                } else {
                    var del = d[sx][tx+1]     // a deletion
                    var ins = d[sx+1][tx]     // an insertion
                    var sub = d[sx][tx]       // a substitution
                    
                    // Record operation.
                    let minimumCount = min(del.count, ins.count, sub.count)
                    if del.count == minimumCount {
                        let deletion = ItemChange.Deletion(item: s[sx], indexPath: NSIndexPath(forRow: sx, inSection: 0))
                        del.append(deletion)
                        d[sx+1][tx+1] = del
                    } else if ins.count == minimumCount {
                        let insertion = ItemChange.Insertion(item: t[tx], indexPath: NSIndexPath(forRow: tx, inSection: 0))
                        ins.append(insertion)
                        d[sx+1][tx+1] = ins
                    } else {
                        let deletion = ItemChange.Deletion(item: s[sx], indexPath: NSIndexPath(forRow: sx, inSection: 0))
                        let insertion = ItemChange.Insertion(item: t[tx], indexPath: NSIndexPath(forRow: tx, inSection: 0))
                        sub.append(deletion)
                        sub.append(insertion)
                        d[sx+1][tx+1] = sub
                    }
                }
            }
        }
        
        /// Returns the changes between two rows
        /// Precondition: both rows have the same columns
        func changedValues(from referenceRow: Row, to newRow: Row) -> [String: DatabaseValue] {
            var changedValues: [String: DatabaseValue] = [:]
            for (column, newValue) in newRow {
                let oldValue = referenceRow[column]!
                if newValue != oldValue {
                    changedValues[column] = oldValue
                }
            }
            return changedValues
        }

        
        /// Returns an array where deletion/insertion pairs of the same element are replaced by `.Move` change.
        func standardizeChanges(changes: [ItemChange<T>]) -> [ItemChange<T>] {
            
            /// Returns a potential .Move or .Update if *change* has a matching change in *changes*:
            /// If *change* is a deletion or an insertion, and there is a matching inverse
            /// insertion/deletion with the same value in *changes*, a corresponding .Move or .Update is returned.
            /// As a convenience, the index of the matched change is returned as well.
            func mergedChange(change: ItemChange<T>, inChanges changes: [ItemChange<T>]) -> (mergedChange: ItemChange<T>, obsoleteIndex: Int)? {
                let obsoleteIndex = changes.indexOf { earlierChange in
                    return earlierChange.isMoveCounterpart(change, identityComparator: identityComparator)
                }
                if let obsoleteIndex = obsoleteIndex {
                    switch (changes[obsoleteIndex], change) {
                    case (.Deletion(let oldItem, let oldIndexPath), .Insertion(let newItem, let newIndexPath)):
                        let rowChanges = changedValues(from: oldItem.row, to: newItem.row)
                        if oldIndexPath == newIndexPath {
                            return (ItemChange.Update(item: newItem, indexPath: oldIndexPath, changes: rowChanges), obsoleteIndex)
                        } else {
                            return (ItemChange.Move(item: newItem, indexPath: oldIndexPath, newIndexPath: newIndexPath, changes: rowChanges), obsoleteIndex)
                        }
                    case (.Insertion(let newItem, let newIndexPath), .Deletion(let oldItem, let oldIndexPath)):
                        let rowChanges = changedValues(from: oldItem.row, to: newItem.row)
                        if oldIndexPath == newIndexPath {
                            return (ItemChange.Update(item: newItem, indexPath: oldIndexPath, changes: rowChanges), obsoleteIndex)
                        } else {
                            return (ItemChange.Move(item: newItem, indexPath: oldIndexPath, newIndexPath: newIndexPath, changes: rowChanges), obsoleteIndex)
                        }
                    default:
                        break
                    }
                }
                return nil
            }
            
            // Updates must be pushed at the end
            var mergedChanges: [ItemChange<T>] = []
            var updateChanges: [ItemChange<T>] = []
            for change in changes {
                if let (mergedChange, obsoleteIndex) = mergedChange(change, inChanges: mergedChanges) {
                    mergedChanges.removeAtIndex(obsoleteIndex)
                    switch mergedChange {
                    case .Update:
                        updateChanges.append(mergedChange)
                    default:
                        mergedChanges.append(mergedChange)
                    }
                } else {
                    mergedChanges.append(change)
                }
            }
            return mergedChanges + updateChanges
        }
        
        return standardizeChanges(d[m][n])
    }
}

// MARK: - <TransactionObserverType>
extension FetchedResultsController : TransactionObserverType {
    public func databaseDidChangeWithEvent(event: DatabaseEvent) {
        if let observedTables = observedTables where observedTables.contains(event.tableName) {
            fetchedItemsDidChange = true
        }
    }
    
    public func databaseWillCommit() throws { }
    
    public func databaseDidRollback(db: Database) {
        fetchedItemsDidChange = false
    }
    
    public func databaseDidCommit(db: Database) {
        guard fetchedItemsDidChange else {
            return
        }
        
        let statement = try! source.selectStatement(db)
        let newItems = FetchedItem<T>.fetchAll(statement)
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            let oldItems = self.fetchedItems!
            let changes = FetchedResultsController.computeChanges(fromRows: oldItems, toRows: newItems, identityComparator: self.identityComparator)
            guard !changes.isEmpty else {
                return
            }

            dispatch_async(dispatch_get_main_queue()) {
                self.delegate?.controllerWillUpdate(self)
                
                // after controllerWillUpdate
                self.fetchedItems = newItems
                
                // notify all updates
                for change in changes {
                    self.delegate?.controller(self, didChangeObject: change.item.object, with: change.resultChange)
                }
                
                // done
                self.delegate?.controllerDidFinishUpdates(self)
            }
        }
    }
}


public protocol FetchedResultsControllerDelegate : class {
    func controllerWillUpdate<T>(controller: FetchedResultsController<T>)
    func controller<T>(controller: FetchedResultsController<T>, didChangeObject object:T, with change: ResultChange)
    func controllerDidFinishUpdates<T>(controller: FetchedResultsController<T>)
}


public extension FetchedResultsControllerDelegate {
    func controllerWillUpdate<T>(controller: FetchedResultsController<T>) {}
    func controller<T>(controller: FetchedResultsController<T>, didChangeObject object:T, with change: ResultChange) {}
    func controllerDidFinishUpdates<T>(controller: FetchedResultsController<T>) {}
}


private enum ItemChange<T: RowConvertible> {
    case Insertion(item: FetchedItem<T>, indexPath: NSIndexPath)
    case Deletion(item: FetchedItem<T>, indexPath: NSIndexPath)
    case Move(item: FetchedItem<T>, indexPath: NSIndexPath, newIndexPath: NSIndexPath, changes: [String: DatabaseValue])
    case Update(item: FetchedItem<T>, indexPath: NSIndexPath, changes: [String: DatabaseValue])
}

extension ItemChange {

    var item: FetchedItem<T> {
        switch self {
        case .Insertion(item: let item, indexPath: _):
            return item
        case .Deletion(item: let item, indexPath: _):
            return item
        case .Move(item: let item, indexPath: _, newIndexPath: _, changes: _):
            return item
        case .Update(item: let item, indexPath: _, changes: _):
            return item
        }
    }
    
    var resultChange: ResultChange {
        switch self {
        case .Insertion(item: _, indexPath: let indexPath):
            return .Insertion(indexPath: indexPath)
        case .Deletion(item: _, indexPath: let indexPath):
            return .Deletion(indexPath: indexPath)
        case .Move(item: _, indexPath: let indexPath, newIndexPath: let newIndexPath, changes: let changes):
            return .Move(indexPath: indexPath, newIndexPath: newIndexPath, changes: changes)
        case .Update(item: _, indexPath: let indexPath, changes: let changes):
            return .Update(indexPath: indexPath, changes: changes)
        }
    }
}

extension ItemChange {
    func isMoveCounterpart(otherChange: ItemChange<T>, identityComparator: (T, T) -> Bool) -> Bool {
        switch (self, otherChange) {
        case (.Deletion(let deletedItem, _), .Insertion(let insertedItem, _)):
            return identityComparator(deletedItem.object, insertedItem.object)
        case (.Insertion(let insertedItem, _), .Deletion(let deletedItem, _)):
            return identityComparator(deletedItem.object, insertedItem.object)
        default:
            return false
        }
    }
}

extension ItemChange: CustomStringConvertible {
    var description: String {
        switch self {
        case .Insertion(let item, let indexPath):
            return "INSERTED \(item) AT index \(indexPath.row)"
            
        case .Deletion(let item, let indexPath):
            return "DELETED \(item) FROM index \(indexPath.row)"
            
        case .Move(let item, let indexPath, let newIndexPath, changes: let changes):
            return "MOVED \(item) FROM index \(indexPath.row) TO index \(newIndexPath.row) WITH CHANGES: \(changes)"
            
        case .Update(let item, let indexPath, let changes):
            return "UPDATED \(item) AT index \(indexPath.row) WITH CHANGES: \(changes)"
        }
    }
}

public enum ResultChange {
    case Insertion(indexPath: NSIndexPath)
    case Deletion(indexPath: NSIndexPath)
    case Move(indexPath: NSIndexPath, newIndexPath: NSIndexPath, changes: [String: DatabaseValue])
    case Update(indexPath: NSIndexPath, changes: [String: DatabaseValue])
}


extension ResultChange: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Insertion(let indexPath):
            return "INSERTED AT index \(indexPath.row)"
            
        case .Deletion(let indexPath):
            return "DELETED FROM index \(indexPath.row)"
            
        case .Move(let indexPath, let newIndexPath, changes: let changes):
            return "MOVED FROM index \(indexPath.row) TO index \(newIndexPath.row) WITH CHANGES: \(changes)"
            
        case .Update(let indexPath, let changes):
            return "UPDATED AT index \(indexPath.row) WITH CHANGES: \(changes)"
        }
    }
}
