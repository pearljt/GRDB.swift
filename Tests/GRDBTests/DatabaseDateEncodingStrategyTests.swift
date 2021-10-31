import XCTest
import Foundation
@testable import GRDB

private protocol StrategyProvider {
    static var strategy: DatabaseDateEncodingStrategy { get }
}

private enum StrategyDeferredToDate: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .deferredToDate
}

private enum StrategyTimeIntervalSinceReferenceDate: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .timeIntervalSinceReferenceDate
}

private enum StrategyTimeIntervalSince1970: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .timeIntervalSince1970
}

private enum StrategySecondsSince1970: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .secondsSince1970
}

private enum StrategyMillisecondsSince1970: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .millisecondsSince1970
}

@available(macOS 10.12, watchOS 3.0, tvOS 10.0, *)
private enum StrategyIso8601: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .iso8601
}

private enum StrategyFormatted: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .formatted({
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
        }())
}

private enum StrategyCustom: StrategyProvider {
    static let strategy: DatabaseDateEncodingStrategy = .custom { _ in "custom" }
}

private struct RecordWithDate<Strategy: StrategyProvider>: EncodableRecord, Encodable {
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { Strategy.strategy }
    var date: Date
}

private struct RecordWithOptionalDate<Strategy: StrategyProvider>: EncodableRecord, Encodable {
    static var databaseDateEncodingStrategy: DatabaseDateEncodingStrategy { Strategy.strategy }
    var date: Date?
}

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6, *)
extension RecordWithDate: Identifiable {
    var id: Date { date }
}

class DatabaseDateEncodingStrategyTests: GRDBTestCase {
    let testedDates = [
        Date(timeIntervalSince1970: -987654.321),
        Date(timeIntervalSince1970: 123456.789),
        Date(timeIntervalSinceReferenceDate: 0),
        Date(timeIntervalSinceReferenceDate: 123456.789),
        ]
    
    private func test<T: EncodableRecord>(
        record: T,
        expectedStorage: DatabaseValue.Storage)
    {
        var container = PersistenceContainer()
        record.encode(to: &container)
        if let dbValue = container["date"]?.databaseValue {
            XCTAssertEqual(dbValue.storage, expectedStorage)
        } else {
            XCTAssertEqual(.null, expectedStorage)
        }
    }
    
    private func test<Strategy: StrategyProvider>(strategy: Strategy.Type, encodesDate date: Date, as value: DatabaseValueConvertible) {
        test(record: RecordWithDate<Strategy>(date: date), expectedStorage: value.databaseValue.storage)
        test(record: RecordWithOptionalDate<Strategy>(date: date), expectedStorage: value.databaseValue.storage)
    }
    
    private func testNullEncoding<Strategy: StrategyProvider>(strategy: Strategy.Type) {
        test(record: RecordWithOptionalDate<Strategy>(date: nil), expectedStorage: .null)
    }
}

// MARK: - deferredToDate

extension DatabaseDateEncodingStrategyTests {
    func testDeferredToDate() {
        testNullEncoding(strategy: StrategyDeferredToDate.self)
        
        for (date, value) in zip(testedDates, [
            "1969-12-20 13:39:05.679",
            "1970-01-02 10:17:36.789",
            "2001-01-01 00:00:00.000",
            "2001-01-02 10:17:36.789",
            ]) { test(strategy: StrategyDeferredToDate.self, encodesDate: date, as: value) }
    }
}

// MARK: - timeIntervalSinceReferenceDate

extension DatabaseDateEncodingStrategyTests {
    func testTimeIntervalSinceReferenceDate() {
        testNullEncoding(strategy: StrategyTimeIntervalSinceReferenceDate.self)
        
        for (date, value) in zip(testedDates, [
            -979294854.321,
            -978183743.211,
            0.0,
            123456.789,
            ]) { test(strategy: StrategyTimeIntervalSinceReferenceDate.self, encodesDate: date, as: value) }
    }
}

// MARK: - timeIntervalSince1970

extension DatabaseDateEncodingStrategyTests {
    func testTimeIntervalSince1970() {
        testNullEncoding(strategy: StrategyTimeIntervalSince1970.self)
        
        for (date, value) in zip(testedDates, [
            -987654.32099997997,
            123456.78900003433,
            978307200.0,
            978430656.789,
            ]) { test(strategy: StrategyTimeIntervalSince1970.self, encodesDate: date, as: value) }
    }
}

// MARK: - secondsSince1970

extension DatabaseDateEncodingStrategyTests {
    func testSecondsSince1970() {
        testNullEncoding(strategy: StrategySecondsSince1970.self)
        
        for (date, value) in zip(testedDates, [
            -987655,
            123456,
            978307200,
            978430656,
            ]) { test(strategy: StrategySecondsSince1970.self, encodesDate: date, as: value) }
    }
}

// MARK: - millisecondsSince1970

extension DatabaseDateEncodingStrategyTests {
    func testMillisecondsSince1970() {
        testNullEncoding(strategy: StrategyMillisecondsSince1970.self)
        
        for (date, value) in zip(testedDates, [
            -987654321,
            123456789,
            978307200000,
            978430656789,
            ] as [Int64]) { test(strategy: StrategyMillisecondsSince1970.self, encodesDate: date, as: value) }
    }
}

// MARK: - iso8601(ISO8601DateFormatter)

extension DatabaseDateEncodingStrategyTests {
    func testIso8601() throws {
        guard #available(macOS 10.12, watchOS 3.0, tvOS 10.0, *) else {
            throw XCTSkip("ISO8601DateFormatter is not available")
        }
        
        testNullEncoding(strategy: StrategyIso8601.self)
        
        for (date, value) in zip(testedDates, [
            "1969-12-20T13:39:05Z",
            "1970-01-02T10:17:36Z",
            "2001-01-01T00:00:00Z",
            "2001-01-02T10:17:36Z",
        ]) { test(strategy: StrategyIso8601.self, encodesDate: date, as: value) }
    }
}

// MARK: - formatted(DateFormatter)

extension DatabaseDateEncodingStrategyTests {
    func testFormatted() {
        testNullEncoding(strategy: StrategyFormatted.self)
        
        for (date, value) in zip(testedDates, [
            "Saturday, December 20, 1969 at 1:39:05 PM",
            "Friday, January 2, 1970 at 10:17:36 AM",
            "Monday, January 1, 2001 at 12:00:00 AM",
            "Tuesday, January 2, 2001 at 10:17:36 AM",
            ]) { test(strategy: StrategyFormatted.self, encodesDate: date, as: value) }
    }
}

// MARK: - custom((Date) -> DatabaseValueConvertible?)

extension DatabaseDateEncodingStrategyTests {
    func testCustom() {
        testNullEncoding(strategy: StrategyCustom.self)
        
        for (date, value) in zip(testedDates, [
            "custom",
            "custom",
            "custom",
            "custom",
            ]) { test(strategy: StrategyCustom.self, encodesDate: date, as: value) }
    }
}

// MARK: - Filter

extension DatabaseDateEncodingStrategyTests {
    func testFilterKey() throws {
        try makeDatabaseQueue().write { db in
            try db.create(table: "t") { $0.column("id").primaryKey() }
            
            do {
                let request = Table<RecordWithDate<StrategyDeferredToDate>>("t").filter(key: testedDates[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '1969-12-20 13:39:05.679'
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyDeferredToDate>>("t").filter(keys: testedDates)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('1969-12-20 13:39:05.679', '1970-01-02 10:17:36.789', '2001-01-01 00:00:00.000', '2001-01-02 10:17:36.789')
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").filter(key: testedDates[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = -979294854.321
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").filter(keys: testedDates)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN (-979294854.321, -978183743.211, 0.0, 123456.789)
                    """)
            }
        }
    }
    
    func testFilterID() throws {
        guard #available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6, *) else {
            throw XCTSkip("Identifiable not available")
        }
        
        try makeDatabaseQueue().write { db in
            try db.create(table: "t") { $0.column("id").primaryKey() }
            
            do {
                let request = Table<RecordWithDate<StrategyDeferredToDate>>("t").filter(id: testedDates[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '1969-12-20 13:39:05.679'
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyDeferredToDate>>("t").filter(ids: testedDates)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('1969-12-20 13:39:05.679', '1970-01-02 10:17:36.789', '2001-01-01 00:00:00.000', '2001-01-02 10:17:36.789')
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").filter(id: testedDates[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = -979294854.321
                    """)
            }
            
            do {
                let request = Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").filter(ids: testedDates)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN (-979294854.321, -978183743.211, 0.0, 123456.789)
                    """)
            }
        }
    }
    
    func testDeleteID() throws {
        guard #available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6, *) else {
            throw XCTSkip("Identifiable not available")
        }
        
        try makeDatabaseQueue().write { db in
            try db.create(table: "t") { $0.column("id").primaryKey() }
            
            do {
                try Table<RecordWithDate<StrategyDeferredToDate>>("t").deleteOne(db, id: testedDates[0])
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" = '1969-12-20 13:39:05.679'
                    """)
            }
            
            do {
                try Table<RecordWithDate<StrategyDeferredToDate>>("t").deleteAll(db, ids: testedDates)
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" IN ('1969-12-20 13:39:05.679', '1970-01-02 10:17:36.789', '2001-01-01 00:00:00.000', '2001-01-02 10:17:36.789')
                    """)
            }
            
            do {
                try Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").deleteOne(db, id: testedDates[0])
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" = -979294854.321
                    """)
            }
            
            do {
                try Table<RecordWithDate<StrategyTimeIntervalSinceReferenceDate>>("t").deleteAll(db, ids: testedDates)
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" IN (-979294854.321, -978183743.211, 0.0, 123456.789)
                    """)
            }
        }
    }
}
