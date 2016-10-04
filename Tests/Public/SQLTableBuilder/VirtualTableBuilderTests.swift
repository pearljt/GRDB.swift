import XCTest
#if USING_SQLCIPHER
    import GRDBCipher
#elseif USING_CUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

private struct FTS3TokenizeModule : VirtualTableModule {
    let moduleName = "FTS3TOKENIZE"
    
    func makeTableDefinition() -> FTS3TokenizeTableDefinition {
        return FTS3TokenizeTableDefinition()
    }
    
    func moduleArguments(_ definition: FTS3TokenizeTableDefinition) -> [String] {
        guard let tokenizer = definition.tokenizer else {
            return []
        }
        return [tokenizer]
    }
}

private final class FTS3TokenizeTableDefinition : VirtualTableDefinition {
    var tokenizer: String?
}

class VirtualTableBuilderTests: GRDBTestCase {
    
    func testCustomVirtualTableModule() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            try dbQueue.inDatabase { db in
                try db.create(virtualTable: "test", using: FTS3TokenizeModule()) { t in
                    t.tokenizer = "simple"
                }
                XCTAssertEqual(lastSQLQuery, "CREATE VIRTUAL TABLE \"test\" USING FTS3TOKENIZE(simple)")
            }
        }
    }
}
