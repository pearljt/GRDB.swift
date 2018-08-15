private struct PersistableRecordKeyedEncodingContainer<Key: CodingKey> : KeyedEncodingContainerProtocol {
    let encode: DatabaseValuePersistenceEncoder
    
    init(encode: @escaping DatabaseValuePersistenceEncoder) {
        self.encode = encode
    }
    
    /// The path of coding keys taken to get to this point in encoding.
    /// A `nil` value indicates an unkeyed container.
    var codingPath: [CodingKey] { return [] }
    
    /// Encodes the given value for the given key.
    ///
    /// - parameter value: The value to encode.
    /// - parameter key: The key to associate the value with.
    /// - throws: `EncodingError.invalidValue` if the given value is invalid in the current context for this format.
    mutating func encode(_ value: Bool, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Int, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Float, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: Double, forKey key: Key) throws { encode(value, key.stringValue) }
    mutating func encode(_ value: String, forKey key: Key) throws { encode(value, key.stringValue) }

    /// Encodes the given value for the given key.
    ///
    /// - parameter value: The value to encode.
    /// - parameter key: The key to associate the value with.
    /// - throws: `EncodingError.invalidValue` if the given value is invalid in the current context for this format.
    mutating func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        if let dbValueConvertible = value as? DatabaseValueConvertible {
            // Prefer DatabaseValueConvertible encoding over Decodable.
            // This allows us to encode Date as String, for example.
            encode(dbValueConvertible.databaseValue, key.stringValue)
        } else {
            do {
                try value.encode(to: DatabaseValueEncoder(key: key, encode: encode))
            } catch is JSONEncodingRequiredError {
                // Encode to JSON
                let encoder = JSONEncoder()
                if #available(watchOS 4.0, OSX 10.13, iOS 11.0, *) {
                    encoder.outputFormatting = .sortedKeys
                }
                let jsonData = try encoder.encode(value)
                
                // Store JSON String in the database for easier debugging and
                // database inspection. Thanks to SQLite weak typing, we won't
                // have any trouble decoding this string into data when we
                // eventually perform JSON decoding.
                // TODO: possible optimization: avoid this conversion to string, and store raw data bytes as an SQLite string
                let jsonString = String(data: jsonData, encoding: .utf8)! // json data is guaranteed to convert to String
                encode(jsonString, key.stringValue)
            }
        }
    }
    
    // Provide explicit encoding of optionals, because default implementation does not encode nil values.
    mutating func encodeNil(forKey key: Key) throws { encode(nil, key.stringValue) }
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    mutating func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T : Encodable { if let value = value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) } }
    
    /// Stores a keyed encoding container for the given key and returns it.
    ///
    /// - parameter keyType: The key type to use for the container.
    /// - parameter key: The key to encode the container for.
    /// - returns: A new keyed encoding container.
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        fatalError("Not implemented")
    }
    
    /// Stores an unkeyed encoding container for the given key and returns it.
    ///
    /// - parameter key: The key to encode the container for.
    /// - returns: A new unkeyed encoding container.
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("Not implemented")
    }
    
    /// Stores a new nested container for the default `super` key and returns a new `Encoder` instance for encoding `super` into that container.
    ///
    /// Equivalent to calling `superEncoder(forKey:)` with `Key(stringValue: "super", intValue: 0)`.
    ///
    /// - returns: A new `Encoder` to pass to `super.encode(to:)`.
    mutating func superEncoder() -> Encoder {
        fatalError("Not implemented")
    }
    
    /// Stores a new nested container for the given key and returns a new `Encoder` instance for encoding `super` into that container.
    ///
    /// - parameter key: The key to encode `super` for.
    /// - returns: A new `Encoder` to pass to `super.encode(to:)`.
    mutating func superEncoder(forKey key: Key) -> Encoder {
        fatalError("Not implemented")
    }
}

private struct DatabaseValueEncodingContainer : SingleValueEncodingContainer {
    var codingPath: [CodingKey] { return [key] }
    var key: CodingKey
    var encode: DatabaseValuePersistenceEncoder
    
    init(key: CodingKey, encode: @escaping DatabaseValuePersistenceEncoder) {
        self.key = key
        self.encode = encode
    }
    
    /// Encodes a null value.
    ///
    /// - throws: `EncodingError.invalidValue` if a null value is invalid in the current context for this format.
    /// - precondition: May not be called after a previous `self.encode(_:)` call.
    func encodeNil() throws { encode(nil, key.stringValue) }
    
    /// Encodes a single value of the given type.
    ///
    /// - parameter value: The value to encode.
    /// - throws: `EncodingError.invalidValue` if the given value is invalid in the current context for this format.
    /// - precondition: May not be called after a previous `self.encode(_:)` call.
    func encode(_ value: Bool) throws { encode(value, key.stringValue) }
    func encode(_ value: Int) throws { encode(value, key.stringValue) }
    func encode(_ value: Int8) throws { encode(value, key.stringValue) }
    func encode(_ value: Int16) throws { encode(value, key.stringValue) }
    func encode(_ value: Int32) throws { encode(value, key.stringValue) }
    func encode(_ value: Int64) throws { encode(value, key.stringValue) }
    func encode(_ value: UInt) throws { encode(value, key.stringValue) }
    func encode(_ value: UInt8) throws { encode(value, key.stringValue) }
    func encode(_ value: UInt16) throws { encode(value, key.stringValue) }
    func encode(_ value: UInt32) throws { encode(value, key.stringValue) }
    func encode(_ value: UInt64) throws { encode(value, key.stringValue) }
    func encode(_ value: Float) throws { encode(value, key.stringValue) }
    func encode(_ value: Double) throws { encode(value, key.stringValue) }
    func encode(_ value: String) throws { encode(value, key.stringValue) }
    
    /// Encodes a single value of the given type.
    ///
    /// - parameter value: The value to encode.
    /// - throws: `EncodingError.invalidValue` if the given value is invalid in the current context for this format.
    /// - precondition: May not be called after a previous `self.encode(_:)` call.
    func encode<T>(_ value: T) throws where T : Encodable {
        if let dbValueConvertible = value as? DatabaseValueConvertible {
            // Prefer DatabaseValueConvertible encoding over Decodable.
            // This allows us to encode Date as String, for example.
            encode(dbValueConvertible.databaseValue, key.stringValue)
        } else {
            do {
                try value.encode(to: DatabaseValueEncoder(key: key, encode: encode))
            } catch is JSONEncodingRequiredError {
                // Encode to JSON
                let encoder = JSONEncoder()
                if #available(watchOS 4.0, OSX 10.13, iOS 11.0, *) {
                    encoder.outputFormatting = .sortedKeys
                }
                let jsonData = try encoder.encode(value)
                
                // Store JSON String in the database for easier debugging and
                // database inspection. Thanks to SQLite weak typing, we won't
                // have any trouble decoding this string into data when we
                // eventually perform JSON decoding.
                // TODO: possible optimization: avoid this conversion to string, and store raw data bytes as an SQLite string
                let jsonString = String(data: jsonData, encoding: .utf8)! // json data is guaranteed to convert to String
                encode(jsonString, key.stringValue)
            }
        }
    }
}

private struct DatabaseValueEncoder: Encoder {
    var codingPath: [CodingKey] { return [key] }
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var key: CodingKey
    var encode: DatabaseValuePersistenceEncoder
    
    init(key: CodingKey, encode: @escaping DatabaseValuePersistenceEncoder) {
        self.key = key
        self.encode = encode
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        // Keyed values require JSON encoding.
        // But we can't throw JSONEncodingRequiredError right here, unfortunately.
        // So let's delegate JSONEncodingRequiredError throwing to a
        // dedicated container.
        return KeyedEncodingContainer(JSONEncodingRequiredKeyedContainer())
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        // Unkeyed values require JSON encoding.
        // But we can't throw JSONEncodingRequiredError right here, unfortunately.
        // So let's delegate JSONEncodingRequiredError throwing to a
        // dedicated container.
        return JSONEncodingRequiredUnkeyedContainer()
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return DatabaseValueEncodingContainer(key: key, encode: encode)
    }
}

private struct PersistableRecordEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var encode: DatabaseValuePersistenceEncoder
    
    init(encode: @escaping DatabaseValuePersistenceEncoder) {
        self.encode = encode
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        return KeyedEncodingContainer(PersistableRecordKeyedEncodingContainer<Key>(encode: encode))
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("unkeyed encoding is not supported")
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        fatalError("unkeyed encoding is not supported")
    }
}

private struct JSONEncodingRequiredEncoder: Encoder {
    var codingPath: [CodingKey] { return [] }
    var userInfo: [CodingUserInfoKey: Any] = [:]
    
    init() { }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(JSONEncodingRequiredKeyedContainer())
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return JSONEncodingRequiredUnkeyedContainer()
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return JSONEncodingRequiredSingleValueContainer()
    }
}

private struct JSONEncodingRequiredKeyedContainer<KeyType: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] { return [] }
    
    func encodeNil(forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Bool, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int8, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int16, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int32, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int64, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt8, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt16, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt32, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt64, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Float, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Double, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: String, forKey key: KeyType) throws { throw JSONEncodingRequiredError() }
    func encode<T>(_ value: T, forKey key: KeyType) throws where T : Encodable { throw JSONEncodingRequiredError() }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: KeyType) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return KeyedEncodingContainer(JSONEncodingRequiredKeyedContainer<NestedKey>())
    }
    
    func nestedUnkeyedContainer(forKey key: KeyType) -> UnkeyedEncodingContainer {
        return JSONEncodingRequiredUnkeyedContainer()
    }
    
    func superEncoder() -> Encoder {
        return JSONEncodingRequiredEncoder()
    }
    
    func superEncoder(forKey key: KeyType) -> Encoder {
        return JSONEncodingRequiredEncoder()
    }
}

private struct JSONEncodingRequiredUnkeyedContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] { return [] }
    var count: Int { return 0 }
    
    func encodeNil() throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Bool) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int8) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int16) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int32) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Int64) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt8) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt16) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt32) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: UInt64) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Float) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: Double) throws { throw JSONEncodingRequiredError() }
    func encode(_ value: String) throws { throw JSONEncodingRequiredError() }
    func encode<T>(_ value: T) throws where T : Encodable { throw JSONEncodingRequiredError() }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return KeyedEncodingContainer(JSONEncodingRequiredKeyedContainer<NestedKey>())
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        return self
    }
    
    func superEncoder() -> Encoder {
        return JSONEncodingRequiredEncoder()
    }
}

private struct JSONEncodingRequiredSingleValueContainer: SingleValueEncodingContainer {
    var codingPath: [CodingKey] { return [] }

    mutating func encodeNil() throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Bool) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: String) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Double) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Float) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Int) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Int8) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Int16) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Int32) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: Int64) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: UInt) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: UInt8) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: UInt16) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: UInt32) throws { throw JSONEncodingRequiredError() }
    mutating func encode(_ value: UInt64) throws { throw JSONEncodingRequiredError() }
    mutating func encode<T>(_ value: T) throws where T : Encodable { throw JSONEncodingRequiredError() }
}

/// The error that triggers JSON encoding
private struct JSONEncodingRequiredError: Error { }

private typealias DatabaseValuePersistenceEncoder = (_ value: DatabaseValueConvertible?, _ key: String) -> Void

extension MutablePersistableRecord where Self: Encodable {
    public func encode(to container: inout PersistenceContainer) {
        // The inout container parameter won't enter an escaping closure since
        // SE-0035: https://github.com/apple/swift-evolution/blob/master/proposals/0035-limit-inout-capture.md
        //
        // So let's use it in a non-escaping closure:
        func encode(_ encode: DatabaseValuePersistenceEncoder) {
            withoutActuallyEscaping(encode) { escapableEncode in
                let encoder = PersistableRecordEncoder(encode: escapableEncode)
                try! self.encode(to: encoder)
            }
        }
        encode { (value, key) in
            container[key] = value
        }
    }
}
