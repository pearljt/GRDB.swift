import XCTest
#if GRDBCUSTOMSQLITE
    import GRDBCustomSQLite
#else
    #if SWIFT_PACKAGE
        import CSQLite
    #else
        import SQLite3
    #endif
    import GRDB
#endif

class ValueObservationCountTests: GRDBTestCase {
    func testCount() throws {
        func test(writer: DatabaseWriter, observation: ValueObservation<ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Int>>>) throws {
            try writer.write { try $0.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT)") }
            
            let recorder = observation.record(in: writer)
            
            try writer.writeWithoutTransaction { db in
                try db.execute(sql: "INSERT INTO t DEFAULT VALUES") // +1
                try db.execute(sql: "UPDATE t SET id = id")         // =
                try db.execute(sql: "INSERT INTO t DEFAULT VALUES") // +1
                try db.inTransaction {                         // +1
                    try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
                    try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
                    try db.execute(sql: "DELETE FROM t WHERE id = 1")
                    return .commit
                }
                try db.execute(sql: "DELETE FROM t WHERE id = 2")   // -1
            }
            
            // We don't expect more than five values: [0, 1, 2, 3, 2]
            let expectedValues = [0, 1, 2, 3, 2]
            let values = try wait(for: recorder.prefix(expectedValues.count + 1).inverted, timeout: 0.5)
            let context = "\(type(of: writer)), \(observation.scheduling)"
            XCTAssert(!values.isEmpty, context)
            for count in 1...max(expectedValues.count, values.count) where count <= values.count {
                XCTAssertEqual(
                    expectedValues.suffix(count),
                    values.suffix(count),
                    context)
            }
        }
        
        struct T: TableRecord { }
        let observations = [
            T.all().observationForCount(),
            T.observationForCount()]
        
        for var observation in observations {
            let schedulings: [ValueObservationScheduling] = [
                .mainQueue,
                .async(onQueue: .main),
                .unsafe
            ]
            
            for scheduling in schedulings {
                observation.scheduling = scheduling
                
                try test(writer: DatabaseQueue(), observation: observation)
                try test(writer: makeDatabaseQueue(), observation: observation)
                try test(writer: makeDatabasePool(), observation: observation)
            }
        }
    }
}
