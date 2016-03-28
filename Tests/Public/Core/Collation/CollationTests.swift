import XCTest
import GRDB

class CollationTests: GRDBTestCase {
    
    func testDefaultCollations() {
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE strings (id INTEGER PRIMARY KEY, name TEXT)")
                try db.execute("INSERT INTO strings VALUES (1, '1')")
                try db.execute("INSERT INTO strings VALUES (2, '2')")
                try db.execute("INSERT INTO strings VALUES (3, '10')")
                try db.execute("INSERT INTO strings VALUES (4, 'a')")
                try db.execute("INSERT INTO strings VALUES (5, 'à')")
                try db.execute("INSERT INTO strings VALUES (6, 'A')")
                try db.execute("INSERT INTO strings VALUES (7, 'Z')")
                try db.execute("INSERT INTO strings VALUES (8, 'z')")
                
                XCTAssertEqual(
                    Int.fetchAll(db, "SELECT id FROM strings ORDER BY name COLLATE \(DatabaseCollation.unicodeCompare.name), id"),
                    [1,3,2,6,7,4,5,8])
                XCTAssertEqual(
                    Int.fetchAll(db, "SELECT id FROM strings ORDER BY name COLLATE \(DatabaseCollation.caseInsensitiveCompare.name), id"),
                    [1,3,2,4,6,5,7,8])
                XCTAssertEqual(
                    Int.fetchAll(db, "SELECT id FROM strings ORDER BY name COLLATE \(DatabaseCollation.localizedCaseInsensitiveCompare.name), id"),
                    [1,3,2,4,6,5,7,8])
                XCTAssertEqual(
                    Int.fetchAll(db, "SELECT id FROM strings ORDER BY name COLLATE \(DatabaseCollation.localizedCompare.name), id"),
                    [1,3,2,4,6,5,8,7])
                XCTAssertEqual(
                    Int.fetchAll(db, "SELECT id FROM strings ORDER BY name COLLATE \(DatabaseCollation.localizedStandardCompare.name), id"),
                    [1,2,3,4,6,5,8,7])
            }
        }
    }

    func testCollation() {
        assertNoError {
            let collation = DatabaseCollation("localized_standard") { (string1, string2) in
                let length1 = string1.utf8.count
                let length2 = string2.utf8.count
                if length1 == length2 {
                    return (string1 as NSString).compare(string2)
                } else if length1 < length2 {
                    return .OrderedAscending
                } else {
                    return .OrderedDescending
                }
            }
            dbQueue.addCollation(collation)
            
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE strings (id INTEGER PRIMARY KEY, name TEXT COLLATE LOCALIZED_STANDARD)")
                try db.execute("INSERT INTO strings VALUES (1, 'a')")
                try db.execute("INSERT INTO strings VALUES (2, 'aa')")
                try db.execute("INSERT INTO strings VALUES (3, 'aaa')")
                try db.execute("INSERT INTO strings VALUES (4, 'b')")
                try db.execute("INSERT INTO strings VALUES (5, 'bb')")
                try db.execute("INSERT INTO strings VALUES (6, 'bbb')")
                try db.execute("INSERT INTO strings VALUES (7, 'c')")
                try db.execute("INSERT INTO strings VALUES (8, 'cc')")
                try db.execute("INSERT INTO strings VALUES (9, 'ccc')")
                
                let ids = Int.fetchAll(db, "SELECT id FROM strings ORDER BY NAME")
                XCTAssertEqual(ids, [1,4,7,2,5,8,3,6,9])
            }
        }
    }
}
