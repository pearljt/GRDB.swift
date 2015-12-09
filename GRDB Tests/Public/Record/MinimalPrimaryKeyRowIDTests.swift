import XCTest
import GRDB

// MinimalRowID is the most tiny class with a RowID primary key which supports
// read and write operations of Record.
class MinimalRowID: Record {
    var id: Int64!
    
    override class func databaseTableName() -> String? {
        return "minimalRowIDs"
    }
    
    override var storedDatabaseDictionary: [String: DatabaseValueConvertible?] {
        return ["id": id]
    }
    
    override func updateFromRow(row: Row) {
        if let dbv = row["id"] { id = dbv.value() }
        super.updateFromRow(row) // Subclasses are required to call super.
    }
    
    static func setupInDatabase(db: Database) throws {
        try db.execute(
            "CREATE TABLE minimalRowIDs (id INTEGER PRIMARY KEY)")
    }
}

class MinimalPrimaryKeyRowIDTests: GRDBTestCase {
    
    override func setUp() {
        super.setUp()
        
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createMinimalRowID", MinimalRowID.setupInDatabase)
        assertNoError {
            try migrator.migrate(dbQueue)
        }
    }
    
    
    // MARK: - Insert
    
    func testInsertWithNilPrimaryKeyInsertsARowAndSetsPrimaryKey() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                XCTAssertTrue(record.id == nil)
                try record.insert(db)
                XCTAssertTrue(record.id != nil)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testInsertWithNotNilPrimaryKeyThatDoesNotMatchAnyRowInsertsARow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                record.id = 123456
                try record.insert(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testInsertWithNotNilPrimaryKeyThatMatchesARowThrowsDatabaseError() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                do {
                    try record.insert(db)
                    XCTFail("Expected DatabaseError")
                } catch is DatabaseError {
                    // Expected DatabaseError
                }
            }
        }
    }
    
    func testInsertAfterDeleteInsertsARow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.delete(db)
                try record.insert(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    
    // MARK: - Update
    
    func testUpdateWithNotNilPrimaryKeyThatDoesNotMatchAnyRowThrowsRecordNotFound() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                record.id = 123456
                do {
                    try record.update(db)
                    XCTFail("Expected PersistenceError.NotFound")
                } catch PersistenceError.NotFound {
                    // Expected PersistenceError.NotFound
                }
            }
        }
    }
    
    func testUpdateWithNotNilPrimaryKeyThatMatchesARowUpdatesThatRow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.update(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testUpdateAfterDeleteThrowsRecordNotFound() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.delete(db)
                do {
                    try record.update(db)
                    XCTFail("Expected PersistenceError.NotFound")
                } catch PersistenceError.NotFound {
                    // Expected PersistenceError.NotFound
                }
            }
        }
    }
    
    
    // MARK: - Save
    
    func testSaveWithNilPrimaryKeyInsertsARowAndSetsPrimaryKey() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                XCTAssertTrue(record.id == nil)
                try record.save(db)
                XCTAssertTrue(record.id != nil)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testSaveWithNotNilPrimaryKeyThatDoesNotMatchAnyRowInsertsARow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                record.id = 123456
                try record.save(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testSaveWithNotNilPrimaryKeyThatMatchesARowUpdatesThatRow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.save(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testSaveAfterDeleteInsertsARow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.delete(db)
                try record.save(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    
    // MARK: - Delete
    
    func testDeleteWithNotNilPrimaryKeyThatDoesNotMatchAnyRowDoesNothing() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                record.id = 123456
                let deleted = try record.delete(db)
                XCTAssertFalse(deleted)
            }
        }
    }
    
    func testDeleteWithNotNilPrimaryKeyThatMatchesARowDeletesThatRow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                let deleted = try record.delete(db)
                XCTAssertTrue(deleted)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])
                XCTAssertTrue(row == nil)
            }
        }
    }
    
    func testDeleteAfterDeleteDoesNothing() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                var deleted = try record.delete(db)
                XCTAssertTrue(deleted)
                deleted = try record.delete(db)
                XCTAssertFalse(deleted)
            }
        }
    }
    
    
    // MARK: - Reload
    
    func testReloadWithNotNilPrimaryKeyThatDoesNotMatchAnyRowThrowsRecordNotFound() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                record.id = 123456
                do {
                    try record.reload(db)
                    XCTFail("Expected PersistenceError.NotFound")
                } catch PersistenceError.NotFound {
                    // Expected PersistenceError.NotFound
                }
            }
        }
    }
    
    func testReloadWithNotNilPrimaryKeyThatMatchesARowFetchesThatRow() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.reload(db)
                
                let row = Row.fetchOne(db, "SELECT * FROM minimalRowIDs WHERE id = ?", arguments: [record.id])!
                for (key, value) in record.storedDatabaseDictionary {
                    if let dbv = row[key] {
                        XCTAssertEqual(dbv, value?.databaseValue ?? .Null)
                    } else {
                        XCTFail("Missing column \(key) in fetched row")
                    }
                }
            }
        }
    }
    
    func testReloadAfterDeleteThrowsRecordNotFound() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.delete(db)
                do {
                    try record.reload(db)
                    XCTFail("Expected PersistenceError.NotFound")
                } catch PersistenceError.NotFound {
                    // Expected PersistenceError.NotFound
                }
            }
        }
    }
    
    
    // MARK: - Fetch With Key
    
    func testFetchWithKeys() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record1 = MinimalRowID()
                try record1.insert(db)
                let record2 = MinimalRowID()
                try record2.insert(db)
                
                do {
                    let fetchedRecords = Array(MinimalRowID.fetch(db, keys: []))
                    XCTAssertEqual(fetchedRecords.count, 0)
                }
                
                do {
                    let fetchedRecords = Array(MinimalRowID.fetch(db, keys: [["id": record1.id], ["id": record2.id]]))
                    XCTAssertEqual(fetchedRecords.count, 2)
                    XCTAssertEqual(Set(fetchedRecords.map { $0.id }), Set([record1.id, record2.id]))
                }
                
                do {
                    let fetchedRecords = Array(MinimalRowID.fetch(db, keys: [["id": record1.id], ["id": nil]]))
                    XCTAssertEqual(fetchedRecords.count, 1)
                    XCTAssertEqual(fetchedRecords.first!.id, record1.id!)
                }
            }
        }
    }
    
    func testFetchAllWithKeys() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record1 = MinimalRowID()
                try record1.insert(db)
                let record2 = MinimalRowID()
                try record2.insert(db)
                
                do {
                    let fetchedRecords = MinimalRowID.fetchAll(db, keys: [])
                    XCTAssertEqual(fetchedRecords.count, 0)
                }
                
                do {
                    let fetchedRecords = MinimalRowID.fetchAll(db, keys: [["id": record1.id], ["id": record2.id]])
                    XCTAssertEqual(fetchedRecords.count, 2)
                    XCTAssertEqual(Set(fetchedRecords.map { $0.id }), Set([record1.id, record2.id]))
                }
                
                do {
                    let fetchedRecords = MinimalRowID.fetchAll(db, keys: [["id": record1.id], ["id": nil]])
                    XCTAssertEqual(fetchedRecords.count, 1)
                    XCTAssertEqual(fetchedRecords.first!.id, record1.id!)
                }
            }
        }
    }
    
    func testFetchOneWithKey() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                
                let fetchedRecord = MinimalRowID.fetchOne(db, key: ["id": record.id])!
                XCTAssertTrue(fetchedRecord.id == record.id)
            }
        }
    }
    
    
    // MARK: - Fetch With Primary Key
    
    func testFetchWithPrimaryKeys() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record1 = MinimalRowID()
                try record1.insert(db)
                let record2 = MinimalRowID()
                try record2.insert(db)
                
                do {
                    let ids: [Int64] = []
                    let fetchedRecords = Array(MinimalRowID.fetch(db, keys: ids))
                    XCTAssertEqual(fetchedRecords.count, 0)
                }
                
                do {
                    let ids = [record1.id!, record2.id!]
                    let fetchedRecords = Array(MinimalRowID.fetch(db, keys: ids))
                    XCTAssertEqual(fetchedRecords.count, 2)
                    XCTAssertEqual(Set(fetchedRecords.map { $0.id }), Set(ids))
                }
            }
        }
    }
    
    func testFetchAllWithPrimaryKeys() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record1 = MinimalRowID()
                try record1.insert(db)
                let record2 = MinimalRowID()
                try record2.insert(db)
                
                do {
                    let ids: [Int64] = []
                    let fetchedRecords = MinimalRowID.fetchAll(db, keys: ids)
                    XCTAssertEqual(fetchedRecords.count, 0)
                }
                
                do {
                    let ids = [record1.id!, record2.id!]
                    let fetchedRecords = MinimalRowID.fetchAll(db, keys: ids)
                    XCTAssertEqual(fetchedRecords.count, 2)
                    XCTAssertEqual(Set(fetchedRecords.map { $0.id }), Set(ids))
                }
            }
        }
    }
    
    func testFetchOneWithPrimaryKey() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                
                do {
                    let id: Int64? = nil
                    let fetchedRecord = MinimalRowID.fetchOne(db, key: id)
                    XCTAssertTrue(fetchedRecord == nil)
                }
                
                do {
                    let fetchedRecord = MinimalRowID.fetchOne(db, key: record.id)!
                    XCTAssertTrue(fetchedRecord.id == record.id)
                }
            }
        }
    }
    
    
    // MARK: - Exists
    
    func testExistsWithNotNilPrimaryKeyThatDoesNotMatchAnyRowReturnsFalse() {
        dbQueue.inDatabase { db in
            let record = MinimalRowID()
            record.id = 123456
            XCTAssertFalse(record.exists(db))
        }
    }
    
    func testExistsWithNotNilPrimaryKeyThatMatchesARowReturnsTrue() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                XCTAssertTrue(record.exists(db))
            }
        }
    }
    
    func testExistsAfterDeleteReturnsTrue() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let record = MinimalRowID()
                try record.insert(db)
                try record.delete(db)
                XCTAssertFalse(record.exists(db))
            }
        }
    }
}
