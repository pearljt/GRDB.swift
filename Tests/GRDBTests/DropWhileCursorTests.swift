import XCTest
#if GRDBCIPHER
    import GRDBCipher
#elseif GRDBCUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

private struct TestError : Error { }

class DropWhileCursorTests: GRDBTestCase {
    
    func testDropWhileCursorFromCursor() throws {
        let base = IteratorCursor([1, 2, 3, 1, 5])
        let cursor = base.drop(while: { $0 < 3 })
        try XCTAssertEqual(cursor.next()!, 3)
        try XCTAssertEqual(cursor.next()!, 1)
        try XCTAssertEqual(cursor.next()!, 5)
        XCTAssertTrue(try cursor.next() == nil) // end
        XCTAssertTrue(try cursor.next() == nil) // past the end
    }
    
    func testDropWhileCursorFromThrowingCursor() throws {
        var i = 0
        let base: AnyCursor<Int> = AnyCursor {
            guard i < 4 else { throw TestError() }
            defer { i += 1 }
            return i
        }

        let cursor = base.drop(while: { $0 < 3 })
        try XCTAssertEqual(cursor.next()!, 3)
        do {
            _ = try cursor.next()
            XCTFail()
        } catch is TestError {
        } catch {
            XCTFail()
        }
    }
}
