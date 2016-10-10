import XCTest
import Foundation
#if USING_SQLCIPHER
    import GRDBCipher
#elseif USING_CUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

// A custom tokenizer that ignores some tokens
private final class StopWordsTokenizer : FTS5CustomTokenizer {
    static let name = "stopWords"
    
    let porter: FTS5Tokenizer
    let ignoredTokens: [String]
    
    init(db: Database, arguments: [String]) throws {
        // TODO: test wrapped tokenizer options
        porter = try db.makeTokenizer(.porter())
        // TODO: find a way to provide stop words through arguments
        ignoredTokens = ["bar"]
    }
    
    deinit {
        // TODO: test that deinit is called
    }
    
    func tokenize(_ context: UnsafeMutableRawPointer?, _ flags: FTS5TokenizeFlags, _ pText: UnsafePointer<Int8>?, _ nText: Int32, _ xToken: FTS5TokenCallback?) -> Int32 {
        
        // The way we implement stop words is by letting porter do its job, but
        // intercepting its tokens before they feed SQLite.
        //
        // The xToken callback is @convention(c). This requires a little setup
        // in order to transfer context.
        struct CustomContext {
            let ignoredTokens: [String]
            let context: UnsafeMutableRawPointer
            let xToken: FTS5TokenCallback
        }
        var customContext = CustomContext(ignoredTokens: ignoredTokens, context: context!, xToken: xToken!)
        return withUnsafeMutablePointer(to: &customContext) { customContextPointer in
            // Invoke portern, but intercept raw tokens
            return porter.tokenize(customContextPointer, flags, pText, nText) { (customContextPointer, flags, pToken, nToken, iStart, iEnd) in
                // Extract context
                let customContext = customContextPointer!.assumingMemoryBound(to: CustomContext.self).pointee
                
                // Extract token
                guard let token = pToken.flatMap({ String(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: Int(nToken), deallocator: .none), encoding: .utf8) }) else {
                    return 0 // SQLITE_OK
                }
                
                // Ignore stop words
                if customContext.ignoredTokens.contains(token) {
                    return 0 // SQLITE_OK
                }
                
                // Notify token
                return customContext.xToken(customContext.context, flags, pToken, nToken, iStart, iEnd)
            }
        }
    }
}

// A custom tokenizer that converts tokens to NFKC so that "fi" can match "ﬁ" (U+FB01: LATIN SMALL LIGATURE FI)
private final class NFKCTokenizer : FTS5CustomTokenizer {
    static let name = "nfkc"
    
    let unicode61: FTS5Tokenizer
    
    init(db: Database, arguments: [String]) throws {
        unicode61 = try db.makeTokenizer(.unicode61())
    }
    
    deinit {
        // TODO: test that deinit is called
    }
    
    func tokenize(_ context: UnsafeMutableRawPointer?, _ flags: FTS5TokenizeFlags, _ pText: UnsafePointer<Int8>?, _ nText: Int32, _ xToken: FTS5TokenCallback?) -> Int32 {
        
        // The way we implement NFKC conversion is by letting unicode61 do its
        // job, but intercepting its tokens before they feed SQLite.
        //
        // The xToken callback is @convention(c). This requires a little setup
        // in order to transfer context.
        struct CustomContext {
            let context: UnsafeMutableRawPointer
            let xToken: FTS5TokenCallback
        }
        var customContext = CustomContext(context: context!, xToken: xToken!)
        return withUnsafeMutablePointer(to: &customContext) { customContextPointer in
            // Invoke unicode61, but intercept raw tokens
            return unicode61.tokenize(customContextPointer, flags, pText, nText) { (customContextPointer, flags, pToken, nToken, iStart, iEnd) in
                // Extract context
                let customContext = customContextPointer!.assumingMemoryBound(to: CustomContext.self).pointee
                
                // Extract token
                guard let token = pToken.flatMap({ String(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: Int(nToken), deallocator: .none), encoding: .utf8) }) else {
                    return 0 // SQLITE_OK
                }
                
                // Convert to NFKC
                let nfkc = token.precomposedStringWithCompatibilityMapping
                
                // Notify NFKC token
                return ContiguousArray(nfkc.utf8).withUnsafeBufferPointer { buffer in
                    guard let addr = buffer.baseAddress else {
                        return 0 // SQLITE_OK
                    }
                    let pToken = UnsafeMutableRawPointer(mutating: addr).assumingMemoryBound(to: Int8.self)
                    let nToken = Int32(buffer.count)
                    return customContext.xToken(customContext.context, flags, pToken, nToken, iStart, iEnd)
                }
            }
        }
    }
}

// A custom tokenizer that defines synonyms
private final class SynonymsTokenizer : FTS5CustomTokenizer {
    static let name = "synonyms"

    let unicode61: FTS5Tokenizer
    let synonyms: [Set<String>]

    init(db: Database, arguments: [String]) throws {
        unicode61 = try db.makeTokenizer(.unicode61())
        synonyms = [["first", "1st"]]
    }

    deinit {
        // TODO: test taht deinit is called
    }

    func tokenize(_ context: UnsafeMutableRawPointer?, _ flags: FTS5TokenizeFlags, _ pText: UnsafePointer<Int8>?, _ nText: Int32, _ xToken: FTS5TokenCallback?) -> Int32 {
        // Don't look for synonyms when tokenizing queries, as advised by
        // https://www.sqlite.org/fts5.html#synonym_support
        if flags.contains(.query) {
            return unicode61.tokenize(context, flags, pText, nText, xToken)
        }
        
        // The way we implement synonyms support is by letting unicode61 do its
        // job, but intercepting its tokens before they feed SQLite.
        //
        // The xToken callback is @convention(c). This requires a little setup
        // in order to transfer context.
        struct CustomContext {
            let synonyms: [Set<String>]
            let context: UnsafeMutableRawPointer
            let xToken: FTS5TokenCallback
        }
        var customContext = CustomContext(synonyms: synonyms, context: context!, xToken: xToken!)

        return withUnsafeMutablePointer(to: &customContext) { customContextPointer in
            // Invoke unicode61, but intercept raw tokens
            return unicode61.tokenize(customContextPointer, flags, pText, nText) { (customContextPointer, flags, pToken, nToken, iStart, iEnd) in
                // Extract context
                let customContext = customContextPointer!.assumingMemoryBound(to: CustomContext.self).pointee
                
                // Extract token
                guard let token = pToken.flatMap({ String(data: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: $0), count: Int(nToken), deallocator: .none), encoding: .utf8) }) else {
                    return 0 // SQLITE_OK
                }
                
                guard let synonyms = customContext.synonyms.first(where: { $0.contains(token) }) else {
                    // No synonym
                    return customContext.xToken(customContext.context, flags, pToken, nToken, iStart, iEnd)
                }
                
                // Notify each synonym
                for (index, synonym) in synonyms.enumerated() {
                    let code = ContiguousArray(synonym.utf8).withUnsafeBufferPointer { buffer -> Int32 in
                        guard let addr = buffer.baseAddress else {
                            return 0 // SQLITE_OK
                        }
                        let pToken = UnsafeMutableRawPointer(mutating: addr).assumingMemoryBound(to: Int8.self)
                        let nToken = Int32(buffer.count)
                        // Set FTS5_TOKEN_COLOCATED for all but first token
                        let synonymFlags = (index == 0) ? flags : flags | 1 // FTS5_TOKEN_COLOCATED
                        return customContext.xToken(customContext.context, synonymFlags, pToken, nToken, iStart, iEnd)
                    }
                    if code != 0 { // SQLITE_OK
                        return code
                    }
                }
                return 0 // SQLITE_OK
            }
        }
    }
}

class FTS5CustomTokenizerTests: GRDBTestCase {
    
    func testStopWordsDatabaseQueue() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.add(tokenizer: StopWordsTokenizer.self)
            
            try dbQueue.inDatabase { db in
                try db.create(virtualTable: "documents", using: FTS5()) { t in
                    // TODO: improve this API
                    t.tokenizer = StopWordsTokenizer.tokenizer()
                    t.column("content")
                }
                
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["foo bar"])
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["foo baz"])
                
                // foo is not ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["foo"]), 2)
                // bar is ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["bar"]), 0)
                // bar is ignored in queries too: the "foo bar baz" phrase matches the "foo baz" content
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"foo bar baz\""]), 1)
            }
        }
    }
    
    func testStopWordsDatabasePool() {
        assertNoError {
            let dbPool = try makeDatabaseQueue()
            dbPool.add(tokenizer: StopWordsTokenizer.self)
            
            try dbPool.write { db in
                try db.create(virtualTable: "documents", using: FTS5()) { t in
                    t.tokenizer = StopWordsTokenizer.tokenizer(arguments: ["foo", "bar"])
                    t.column("content")
                }
                
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["foo bar"])
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["foo baz"])
                
                // foo is not ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["foo"]), 2)
                // bar is ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["bar"]), 0)
                // bar is ignored in queries too: the "foo bar baz" phrase matches the "foo baz" content
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"foo bar baz\""]), 1)
            }
            
            dbPool.read { db in
                // foo is not ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["foo"]), 2)
                // bar is ignored
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["bar"]), 0)
                // bar is ignored in queries too: the "foo bar baz" phrase matches the "foo baz" content
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"foo bar baz\""]), 1)
            }
        }
    }
    
    func testNFKCTokenizer() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.add(tokenizer: NFKCTokenizer.self)
            
            // Without NFKC conversion
            try dbQueue.inDatabase { db in
                try db.create(virtualTable: "documents", using: FTS5()) { t in
                    t.tokenizer = .unicode61()
                    t.column("content")
                }
                
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["aimé\u{FB01}"]) // U+FB01: LATIN SMALL LIGATURE FI
                
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["aimé\u{FB01}"]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["aimefi"]), 0)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["aim\u{00E9}fi"]), 0)
            }
            
            // With NFKC conversion
            try dbQueue.inDatabase { db in
                try db.create(virtualTable: "nkfcDocuments", using: FTS5()) { t in
                    t.tokenizer = NFKCTokenizer.tokenizer()
                    t.column("content")
                }
                
                try db.execute("INSERT INTO nkfcDocuments VALUES (?)", arguments: ["aimé\u{FB01}"]) // U+FB01: LATIN SMALL LIGATURE FI
                
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM nkfcDocuments WHERE nkfcDocuments MATCH ?", arguments: ["aimé\u{FB01}"]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM nkfcDocuments WHERE nkfcDocuments MATCH ?", arguments: ["aimefi"]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM nkfcDocuments WHERE nkfcDocuments MATCH ?", arguments: ["aim\u{00E9}fi"]), 1)
            }
        }
    }
    
    func testSynonymTokenizer() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            dbQueue.add(tokenizer: SynonymsTokenizer.self)
            
            try dbQueue.inDatabase { db in
                try db.create(virtualTable: "documents", using: FTS5()) { t in
                    t.tokenizer = SynonymsTokenizer.tokenizer()
                    t.column("content")
                }
                
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["first foo"])
                try db.execute("INSERT INTO documents VALUES (?)", arguments: ["1st bar"])
                
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["first"]), 2)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["1st"]), 2)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"first foo\""]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"1st foo\""]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"first bar\""]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["\"1st bar\""]), 1)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["fi*"]), 2)
                XCTAssertEqual(Int.fetchOne(db, "SELECT COUNT(*) FROM documents WHERE documents MATCH ?", arguments: ["1s*"]), 2)
            }
        }
    }
}
