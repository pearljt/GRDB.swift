/// Implementation details of `ValueReducer`.
///
/// :nodoc:
public protocol _ValueReducer {
    /// The type of fetched database values
    associatedtype Fetched
    
    /// The type of observed values
    associatedtype Value
    
    /// The tracked region
    var _trackingMode: _ValueReducerTrackingMode { get }
    
    /// Fetches database values upon changes in an observed database region.
    ///
    /// ValueReducer semantics require that this method does not depend on
    /// the state of the reducer.
    func _fetch(_ db: Database) throws -> Fetched
    
    /// Transforms a fetched value into an eventual observed value. Returns nil
    /// when observer should not be notified.
    ///
    /// This method runs in some unspecified dispatch queue.
    ///
    /// ValueReducer semantics require that the first invocation of this
    /// method returns a non-nil value:
    ///
    ///     let reducer = MyReducer()
    ///     reducer._value(...) // MUST NOT be nil
    ///     reducer._value(...) // MAY be nil
    ///     reducer._value(...) // MAY be nil
    mutating func _value(_ fetched: Fetched) -> Value?
}

/// Implementation details of `ValueReducer`.
///
/// :nodoc:
public enum _ValueReducerTrackingMode {
    /// The tracked region is constant and explicit.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is always the full player table
    ///     ValueObservation.trackingConstantRegion(Player.all()) { db in ... }
    case constantRegion([DatabaseRegionConvertible])
    
    /// The tracked region is constant and inferred from the fetched values.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is always the full player table
    ///     ValueObservation.trackingConstantRegion { db in Player.fetchAll(db) }
    case constantRegionRecordedFromSelection
    
    /// The tracked region is not constant, and inferred from the fetched values.
    ///
    /// Use case:
    ///
    ///     // Tracked Region is the one row of the table, and it changes on
    ///     // each fetch.
    ///     ValueObservation.tracking { db in
    ///         try Player.fetchOne(db, id: Int.random(in: 1.1000))
    ///     }
    case nonConstantRegionRecordedFromSelection
}

/// The `ValueReducer` protocol supports `ValueObservation`.
public protocol ValueReducer: _ValueReducer { }

extension ValueReducer {
    mutating func fetchAndReduce(_ db: Database) throws -> Value? {
        try _value(_fetch(db))
    }
}

/// A namespace for types related to the `ValueReducer` protocol.
public enum ValueReducers {
    // ValueReducers.Auto allows us to define ValueObservation factory methods.
    //
    // For example, ValueObservation.tracking(_:) is, practically,
    // ValueObservation<ValueReducers.Auto>.tracking(_:).
    /// :nodoc:
    public enum Auto: ValueReducer {
        /// :nodoc:
        public var _trackingMode: _ValueReducerTrackingMode { preconditionFailure() }
        /// :nodoc:
        public func _fetch(_ db: Database) throws -> Never { preconditionFailure() }
        /// :nodoc:
        public mutating func _value(_ fetched: Never) -> Never? { }
    }
}
