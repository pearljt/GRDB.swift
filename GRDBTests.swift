//
//  GRDBTests.swift
//  GRDB
//
//  Created by Gwendal Roué on 01/07/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//

import XCTest
import GRDB

class GRDBTests: XCTestCase {
    var databasePath: String!
    var dbQueue: DatabaseQueue!
    
    override func setUp() {
        super.setUp()
        
        self.databasePath = "/tmp/GRDB.sqlite"
        do { try NSFileManager.defaultManager().removeItemAtPath(databasePath) } catch { }
        let configuration = DatabaseConfiguration(verbose: true)
        self.dbQueue = try! DatabaseQueue(path: databasePath, configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
        
        self.dbQueue = nil
        try! NSFileManager.defaultManager().removeItemAtPath(databasePath)
    }
    
    func assertNoError(@noescape test: (Void) throws -> Void) {
        do {
            try test()
        } catch let error as SQLiteError {
            if let sql = error.sql {
                if let message = error.message {
                    XCTFail("SQLite error code \(error.code) executing `\(sql)`: \(message)")
                } else {
                    XCTFail("SQLite error code \(error.code) executing `\(sql)`")
                }
            } else {
                if let message = error.message {
                    XCTFail("SQLite error code \(error.code): \(message)")
                } else {
                    XCTFail("SQLite error code \(error.code)")
                }
            }
        } catch {
            XCTFail("error: \(error)")
        }
    }
}
