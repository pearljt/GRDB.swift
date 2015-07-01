//
//  SelectStatement.swift
//  GRDB
//
//  Created by Gwendal Roué on 30/06/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//

public class SelectStatement : Statement {
    public lazy var columnCount: Int = Int(sqlite3_column_count(self.cStatement))
    
    // Document the reset performed on each generation
    public var rows: AnySequence<Row> {
        return AnySequence {
            return self.rowGenerator()
        }
    }
    
    private func rowGenerator() -> AnyGenerator<Row> {
        try! reset()
        
        return anyGenerator { () -> Row? in
            let code = sqlite3_step(self.cStatement)
            switch code {
            case SQLITE_DONE:
                return nil
            case SQLITE_ROW:
                return Row(statement: self)
            default:
                try! Error.checkCResultCode(code, cConnection: self.database.cConnection)
                return nil
            }
        }
    }
}
