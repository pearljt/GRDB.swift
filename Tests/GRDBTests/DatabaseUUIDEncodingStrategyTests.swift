import XCTest
import Foundation
@testable import GRDB

private protocol StrategyProvider {
    static var strategy: DatabaseUUIDEncodingStrategy { get }
}

private enum StrategyDeferredToUUID: StrategyProvider {
    static let strategy: DatabaseUUIDEncodingStrategy = .deferredToUUID
}

private enum StrategyUppercaseString: StrategyProvider {
    static let strategy: DatabaseUUIDEncodingStrategy = .uppercaseString
}

private enum StrategyLowercaseString: StrategyProvider {
    static let strategy: DatabaseUUIDEncodingStrategy = .lowercaseString
}

private struct RecordWithUUID<Strategy: StrategyProvider>: EncodableRecord, Encodable {
    static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { Strategy.strategy }
    var uuid: UUID
}

private struct RecordWithOptionalUUID<Strategy: StrategyProvider>: EncodableRecord, Encodable {
    static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy { Strategy.strategy }
    var uuid: UUID?
}

@available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6, *)
extension RecordWithUUID: Identifiable {
    var id: UUID { uuid }
}

class DatabaseUUIDEncodingStrategyTests: GRDBTestCase {
    private func test<T: EncodableRecord>(
        record: T,
        expectedStorage: DatabaseValue.Storage)
    {
        var container = PersistenceContainer()
        record.encode(to: &container)
        if let dbValue = container["uuid"]?.databaseValue {
            XCTAssertEqual(dbValue.storage, expectedStorage)
        } else {
            XCTAssertEqual(.null, expectedStorage)
        }
    }
    
    private func test<Strategy: StrategyProvider>(strategy: Strategy.Type, encodesUUID uuid: UUID, as value: DatabaseValueConvertible) {
        test(record: RecordWithUUID<Strategy>(uuid: uuid), expectedStorage: value.databaseValue.storage)
        test(record: RecordWithOptionalUUID<Strategy>(uuid: uuid), expectedStorage: value.databaseValue.storage)
    }
    
    private func testNullEncoding<Strategy: StrategyProvider>(strategy: Strategy.Type) {
        test(record: RecordWithOptionalUUID<Strategy>(uuid: nil), expectedStorage: .null)
    }
}

// MARK: - deferredToUUID

extension DatabaseUUIDEncodingStrategyTests {
    func testDeferredToUUID() {
        testNullEncoding(strategy: StrategyDeferredToUUID.self)
        
        test(
            strategy: StrategyDeferredToUUID.self,
            encodesUUID: UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
            as: "abcdefghijklmnop".data(using: .utf8)!)
    }
}

// MARK: - UppercaseString

extension DatabaseUUIDEncodingStrategyTests {
    func testUppercaseString() {
        testNullEncoding(strategy: StrategyUppercaseString.self)
        
        test(
            strategy: StrategyUppercaseString.self,
            encodesUUID: UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
            as: "61626364-6566-6768-696A-6B6C6D6E6F70")
        
        test(
            strategy: StrategyUppercaseString.self,
            encodesUUID: UUID(uuidString: "56e7d8d3-e9e4-48b6-968e-8d102833af00")!,
            as: "56E7D8D3-E9E4-48B6-968E-8D102833AF00")
        
        let uuid = UUID()
        test(
            strategy: StrategyUppercaseString.self,
            encodesUUID: uuid,
            as: uuid.uuidString.uppercased()) // Assert stable casing
    }
}

// MARK: - LowercaseString

extension DatabaseUUIDEncodingStrategyTests {
    func testLowercaseString() {
        testNullEncoding(strategy: StrategyLowercaseString.self)
        
        test(
            strategy: StrategyLowercaseString.self,
            encodesUUID: UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
            as: "61626364-6566-6768-696a-6b6c6d6e6f70")
        
        test(
            strategy: StrategyLowercaseString.self,
            encodesUUID: UUID(uuidString: "56e7d8d3-e9e4-48b6-968e-8d102833af00")!,
            as: "56e7d8d3-e9e4-48b6-968e-8d102833af00")
        
        let uuid = UUID()
        test(
            strategy: StrategyLowercaseString.self,
            encodesUUID: uuid,
            as: uuid.uuidString.lowercased()) // Assert stable casing
    }
}

// MARK: - Filter

extension DatabaseUUIDEncodingStrategyTests {
    func testFilterKey() throws {
        try makeDatabaseQueue().write { db in
            try db.create(table: "t") { $0.column("id").primaryKey() }
            let uuids = [
                UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
                UUID(uuidString: "56e7d8d3-e9e4-48b6-968e-8d102833af00")!,
            ]
            
            do {
                let request = Table<RecordWithUUID<StrategyDeferredToUUID>>("t").filter(key: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = x'6162636465666768696a6b6c6d6e6f70'
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyDeferredToUUID>>("t").filter(keys: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN (x'6162636465666768696a6b6c6d6e6f70', x'56e7d8d3e9e448b6968e8d102833af00')
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyUppercaseString>>("t").filter(key: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '61626364-6566-6768-696A-6B6C6D6E6F70'
                    """)
            }

            do {
                let request = Table<RecordWithUUID<StrategyUppercaseString>>("t").filter(keys: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('61626364-6566-6768-696A-6B6C6D6E6F70', '56E7D8D3-E9E4-48B6-968E-8D102833AF00')
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyLowercaseString>>("t").filter(key: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '61626364-6566-6768-696a-6b6c6d6e6f70'
                    """)
            }

            do {
                let request = Table<RecordWithUUID<StrategyLowercaseString>>("t").filter(keys: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('61626364-6566-6768-696a-6b6c6d6e6f70', '56e7d8d3-e9e4-48b6-968e-8d102833af00')
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
            let uuids = [
                UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
                UUID(uuidString: "56e7d8d3-e9e4-48b6-968e-8d102833af00")!,
            ]
            
            do {
                let request = Table<RecordWithUUID<StrategyDeferredToUUID>>("t").filter(id: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = x'6162636465666768696a6b6c6d6e6f70'
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyDeferredToUUID>>("t").filter(ids: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN (x'6162636465666768696a6b6c6d6e6f70', x'56e7d8d3e9e448b6968e8d102833af00')
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyUppercaseString>>("t").filter(id: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '61626364-6566-6768-696A-6B6C6D6E6F70'
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyUppercaseString>>("t").filter(ids: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('61626364-6566-6768-696A-6B6C6D6E6F70', '56E7D8D3-E9E4-48B6-968E-8D102833AF00')
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyLowercaseString>>("t").filter(id: uuids[0])
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" = '61626364-6566-6768-696a-6b6c6d6e6f70'
                    """)
            }
            
            do {
                let request = Table<RecordWithUUID<StrategyLowercaseString>>("t").filter(ids: uuids)
                try assertEqualSQL(db, request, """
                    SELECT * FROM "t" WHERE "id" IN ('61626364-6566-6768-696a-6b6c6d6e6f70', '56e7d8d3-e9e4-48b6-968e-8d102833af00')
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
            let uuids = [
                UUID(uuidString: "61626364-6566-6768-696A-6B6C6D6E6F70")!,
                UUID(uuidString: "56e7d8d3-e9e4-48b6-968e-8d102833af00")!,
            ]
            
            do {
                try Table<RecordWithUUID<StrategyDeferredToUUID>>("t").deleteOne(db, id: uuids[0])
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" = x'6162636465666768696a6b6c6d6e6f70'
                    """)
            }
            
            do {
                try Table<RecordWithUUID<StrategyDeferredToUUID>>("t").deleteAll(db, ids: uuids)
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" IN (x'6162636465666768696a6b6c6d6e6f70', x'56e7d8d3e9e448b6968e8d102833af00')
                    """)
            }
            
            do {
                try Table<RecordWithUUID<StrategyUppercaseString>>("t").deleteOne(db, id: uuids[0])
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" = '61626364-6566-6768-696A-6B6C6D6E6F70'
                    """)
            }
            
            do {
                try Table<RecordWithUUID<StrategyUppercaseString>>("t").deleteAll(db, ids: uuids)
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" IN ('61626364-6566-6768-696A-6B6C6D6E6F70', '56E7D8D3-E9E4-48B6-968E-8D102833AF00')
                    """)
            }
            
            do {
                try Table<RecordWithUUID<StrategyLowercaseString>>("t").deleteOne(db, id: uuids[0])
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" = '61626364-6566-6768-696a-6b6c6d6e6f70'
                    """)
            }
            
            do {
                try Table<RecordWithUUID<StrategyLowercaseString>>("t").deleteAll(db, ids: uuids)
                XCTAssertEqual(lastSQLQuery, """
                    DELETE FROM "t" WHERE "id" IN ('61626364-6566-6768-696a-6b6c6d6e6f70', '56e7d8d3-e9e4-48b6-968e-8d102833af00')
                    """)
            }
        }
    }
}
