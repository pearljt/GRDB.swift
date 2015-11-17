import Foundation

/// Foundation support for DatabaseValue
extension DatabaseValue {
    
    /// Builds a DatabaseValue from AnyObject.
    ///
    /// The result is nil unless object adopts DatabaseValueConvertible (NSData,
    /// NSDate, NSNull, NSNumber, NSString, NSURL).
    ///
    /// - parameter object: An AnyObject.
    public init?(object: AnyObject) {
        guard let convertible = object as? DatabaseValueConvertible else {
            return nil
        }
        self.init(convertible.databaseValue)
    }
    
    /// Converts a DatabaseValue to AnyObject.
    ///
    /// - returns: NSNull, NSNumber, NSString, or NSData.
    public func toAnyObject() -> AnyObject {
        switch storage {
        case .Null:
            return NSNull()
        case .Int64(let int64):
            return NSNumber(longLong: int64)
        case .Double(let double):
            return NSNumber(double: double)
        case .String(let string):
            return string as NSString
        case .Blob(let data):
            return data
        }
    }
}
