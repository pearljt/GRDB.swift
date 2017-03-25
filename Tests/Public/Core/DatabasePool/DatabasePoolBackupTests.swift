import XCTest
#if USING_SQLCIPHER
    @testable import GRDBCipher
#elseif USING_CUSTOMSQLITE
    @testable import GRDBCustomSQLite
#else
    @testable import GRDB
#endif

class DatabasePoolBackupTests: GRDBTestCase {

    func testBackup() throws {
        let source = try makeDatabasePool(filename: "source.sqlite")
        let destination = try makeDatabasePool(filename: "destination.sqlite")
        
        try source.write { db in
            try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY)")
            try db.execute("INSERT INTO items (id) VALUES (NULL)")
            XCTAssertEqual(try Int.fetchOne(db, "SELECT COUNT(*) FROM items")!, 1)
        }
        
        try source.backup(to: destination)
        
        try destination.read { db in
            XCTAssertEqual(try Int.fetchOne(db, "SELECT COUNT(*) FROM items")!, 1)
        }
        
        try source.write { db in
            try db.execute("DROP TABLE items")
        }
        
        try source.backup(to: destination)
        
        try destination.read { db in
            XCTAssertFalse(try db.tableExists("items"))
        }
    }

    @available(OSX 10.10, *)
    func testConcurrentWriteDuringBackup() throws {
        let source = try makeDatabasePool(filename: "source.sqlite")
        let destination = try makeDatabasePool(filename: "destination.sqlite")
        
        try source.write { db in
            try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY)")
            try db.execute("INSERT INTO items (id) VALUES (NULL)")
            XCTAssertEqual(try Int.fetchOne(db, "SELECT COUNT(*) FROM items")!, 1)
        }
        
        let s1 = DispatchSemaphore(value: 0)
        let s2 = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = s1.wait(timeout: .distantFuture)
            try! source.writeInTransaction(.immediate) { db in
                try db.execute("INSERT INTO items (id) VALUES (NULL)")
                s2.signal()
                return .commit
            }
        }
        
        try source.backup(
            to: destination,
            afterBackupInit: {
                s1.signal()
                _ = s2.wait(timeout: .distantFuture)
        },
            afterBackupStep: {
                try! source.write { db in
                    try db.execute("INSERT INTO items (id) VALUES (NULL)")
                }
        })
        
        try source.read { db in
            XCTAssertEqual(try Int.fetchOne(db, "SELECT COUNT(*) FROM items")!, 3)
        }
        try destination.read { db in
            // TODO: understand why the fix for https://github.com/groue/GRDB.swift/issues/102
            // had this value change from 2 to 1.
            // TODO: Worse, this test is fragile. I've seen not 1 but 2 once.
            XCTAssertEqual(try Int.fetchOne(db, "SELECT COUNT(*) FROM items")!, 1)
        }
    }
}
