//
//  StatementTests.swift
//  GRDB
//
//  Created by Gwendal Roué on 06/01/2016.
//  Copyright © 2016 Gwendal Roué. All rights reserved.
//

import XCTest
import GRDB

class StatementArgumentsTests: GRDBTestCase {

    override func setUp() {
        super.setUp()
        
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("createPersons") { db in
            try db.execute(
                "CREATE TABLE persons (" +
                    "id INTEGER PRIMARY KEY, " +
                    "firstName TEXT, " +
                    "lastName TEXT, " +
                    "age INT" +
                ")")
        }
        
        assertNoError {
            try migrator.migrate(dbQueue)
        }
    }
    
    func testPositionalStatementArgumentsValidation() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let statement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (?, ?)")
                
                do {
                    // Correct number of arguments
                    try statement.validateArguments(["foo", 1])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Two few arguments
                    try statement.validateArguments(["foo"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Two many arguments
                    try statement.validateArguments(["foo", 1, "bar"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([:])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Unmappable arguments
                    try statement.validateArguments(["firstName": "foo", "age": 1])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }
    
    func testPositionalStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments([name, age] as [DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (?, ?)")
                updateStatement.arguments = arguments
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = ? AND age = ?")
                selectStatement.arguments = arguments
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
    func testUnsafePositionalStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments([name, age] as [DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (?, ?)")
                updateStatement.unsafeSetArguments(arguments)
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = ? AND age = ?")
                selectStatement.unsafeSetArguments(arguments)
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
    func testNamedStatementArgumentsValidation() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let statement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (:firstName, :age)")
                
                do {
                    // Correct number of arguments
                    try statement.validateArguments(["foo", 1])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // All arguments are mapped
                    try statement.validateArguments(["firstName": "foo", "age": 1])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // All arguments are mapped
                    try statement.validateArguments(["firstName": "foo", "age": 1, "bar": "baz"])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments(["foo"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Too many arguments
                    try statement.validateArguments(["foo", 1, "baz"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([:])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments(["firstName": "foo"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }
    
    func testNamedStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments(["name": name, "age": age] as [String: DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (:name, :age)")
                updateStatement.arguments = arguments
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = :name AND age = :age")
                selectStatement.arguments = arguments
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
    func testUnsafeNamedStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments(["name": name, "age": age] as [String: DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, age) VALUES (:name, :age)")
                updateStatement.unsafeSetArguments(arguments)
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = :name AND age = :age")
                selectStatement.unsafeSetArguments(arguments)
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
    func testReusedNamedStatementArgumentsValidation() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let statement = try db.updateStatement("INSERT INTO persons (firstName, lastName, age) VALUES (:name, :name, :age)")
                
                do {
                    try statement.execute(arguments: ["name": "foo", "age": 1])
                    let row = Row.fetchOne(db, "SELECT * FROM persons")!
                    XCTAssertEqual(row.value(named: "firstName") as String, "foo")
                    XCTAssertEqual(row.value(named: "lastName") as String, "foo")
                    XCTAssertEqual(row.value(named: "age") as Int, 1)
                }
                
                do {
                    // Correct number of arguments
                    try statement.validateArguments(["foo", 1])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // All arguments are mapped
                    try statement.validateArguments(["name": "foo", "age": 1])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // All arguments are mapped
                    try statement.validateArguments(["name": "foo", "age": 1, "bar": "baz"])
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments(["foo"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Too many arguments
                    try statement.validateArguments(["foo", 1, "baz"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments([:])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                
                do {
                    // Missing arguments
                    try statement.validateArguments(["name": "foo"])
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    print(error)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    
    func testReusedNamedStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments(["name": name, "age": age] as [String: DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, lastName, age) VALUES (:name, :name, :age)")
                updateStatement.arguments = arguments
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = :name AND lastName = :name AND age = :age")
                selectStatement.arguments = arguments
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
    func testUnsafeReusedNamedStatementArguments() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let name = "Arthur"
                let age = 42
                let arguments = StatementArguments(["name": name, "age": age] as [String: DatabaseValueConvertible?])
                
                let updateStatement = try db.updateStatement("INSERT INTO persons (firstName, lastName, age) VALUES (:name, :name, :age)")
                updateStatement.unsafeSetArguments(arguments)
                try updateStatement.execute()
                
                let selectStatement = try db.selectStatement("SELECT * FROM persons WHERE firstName = :name AND lastName = :name AND age = :age")
                selectStatement.unsafeSetArguments(arguments)
                let row = Row.fetchOne(selectStatement)!
                
                XCTAssertEqual(row.value(named: "firstName") as String, name)
                XCTAssertEqual(row.value(named: "age") as Int, age)
            }
        }
    }
    
}
