import Foundation

/// NSURL adopts DatabaseValueConvertible.
extension NSURL : DatabaseValueConvertible {
    
    /// Returns a value that can be stored in the database.
    /// (the URL's absoluteString).
    public var databaseValue: DatabaseValue {
        return DatabaseValue(absoluteString)
    }
    
    /// Returns an NSURL initialized from *databaseValue*, if possible.
    ///
    /// - parameter databaseValue: A DatabaseValue.
    /// - returns: An optional NSURL.
    public static func fromDatabaseValue(databaseValue: DatabaseValue) -> Self? {
        guard let string = String.fromDatabaseValue(databaseValue) else {
            return nil
        }
        return self.init(string: string)
    }
    
    public static func fromRow(row: Row) -> Self {
        // TODO: test
        guard let url = fromDatabaseValue(row.databaseValues.first!) else {
            fatalError("Could not convert \(row.databaseValues.first!) to NSURL.")
        }
        return url
    }
}
