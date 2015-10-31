import Foundation

/// DatabaseCoder reads and stores objects that conform to NSCoding in
/// the database.
public struct DatabaseCoder: DatabaseValueConvertible {
    
    /// The object
    public let object: AnyObject
    
    /// Creates a DatabaseCoder from an object that conforms to NSCoding.
    ///
    /// The result is nil if and only if *object* is nil.
    ///
    /// - parameter object: An optional object.
    /// - returns: An optional DatabaseCoder.
    public init?(_ object: AnyObject?) {
        guard let object = object else {
            return nil
        }
        self.object = object
    }
    
    /// Returns a value that can be stored in the database.
    public var databaseValue: DatabaseValue {
        return DatabaseValue(data: NSKeyedArchiver.archivedDataWithRootObject(object))
    }
    
    /// Returns a DatabaseCoder if *databaseValue* contains an archived object.
    ///
    /// - parameter databaseValue: A DatabaseValue.
    /// - returns: An optional DatabaseCoder.
    public static func fromDatabaseValue(databaseValue: DatabaseValue) -> DatabaseCoder? {
        guard let data = NSData.fromDatabaseValue(databaseValue) else {
            return nil
        }
        return DatabaseCoder(NSKeyedUnarchiver.unarchiveObjectWithData(data))
    }
}
