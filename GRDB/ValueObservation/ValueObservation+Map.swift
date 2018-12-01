extension ValueObservation where Reducer: ValueReducer {
    /// Returns a ValueObservation which notifies the results of calling the
    /// given transformation which each element notified by this
    /// value observation.
    public func map<T>(_ transform: @escaping (Reducer.Value) -> T)
        -> ValueObservation<MapValueReducer<Reducer, T>>
    {
        let makeReducer = self.makeReducer
        return ValueObservation<MapValueReducer<Reducer, T>>(
            tracking: observedRegion,
            reducer: { db in try makeReducer(db).map(transform) })
    }
}

extension ValueReducer {
    /// Returns a reducer which outputs the results of calling the given
    /// transformation which each element emitted by this reducer.
    public func map<T>(_ transform: @escaping (Value) -> T) -> MapValueReducer<Self, T> {
        return MapValueReducer(self, transform)
    }
}

/// A ValueReducer whose values consist of those in a Base ValueReducer passed
/// through a transform function.
///
/// See ValueReducer.map(_:)
///
/// :nodoc:
public struct MapValueReducer<Base: ValueReducer, T>: ValueReducer {
    private var base: Base
    private let transform: (Base.Value) -> T
    
    init(_ base: Base, _ transform: @escaping (Base.Value) -> T) {
        self.base = base
        self.transform = transform
    }
    
    public func fetch(_ db: Database) throws -> Base.Fetched {
        return try base.fetch(db)
    }
    
    public mutating func value(_ fetched: Base.Fetched) -> T? {
        guard let value = base.value(fetched) else { return nil }
        return transform(value)
    }
}
