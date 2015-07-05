//
// GRDB.swift
// https://github.com/groue/GRDB.swift
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import XCTest
import GRDB

class RowTests: GRDBTestCase {
    
    func testRowAsSequence() {
        assertNoError {
            let dbQueue = DatabaseQueue()
            try dbQueue.inTransaction { db in
                try db.execute("CREATE TABLE texts (a TEXT, b TEXT, c TEXT)")
                try db.execute("INSERT INTO texts (a,b,c) VALUES ('foo', 'bar', 'baz')")
                let row = db.fetchOneRow("SELECT * FROM texts")!
                
                var columnNames = [String]()
                var texts = [String]()
                for (columnName, sqliteValue) in row {
                    columnNames.append(columnName)
                    texts.append(sqliteValue.value()! as String)
                }
                
                XCTAssertEqual(columnNames, ["a", "b", "c"])
                XCTAssertEqual(texts, ["foo", "bar", "baz"])
                
                return .Rollback
            }
        }

    }
}
