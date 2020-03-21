// Inspired by https://github.com/groue/CombineExpectations
import XCTest
#if GRDBCUSTOMSQLITE
import GRDBCustomSQLite
#else
import GRDB
#endif

// MARK: - ValueObservationRecorder

public class ValueObservationRecorder<Value> {
    private struct RecorderExpectation {
        var expectation: XCTestExpectation
        var remainingCount: Int? // nil for error expectation
    }
    
    /// The recorder state
    private struct State {
        var values: [Value]
        var error: Error?
        var recorderExpectation: RecorderExpectation?
        var observer: TransactionObserver?
    }
    
    private let lock = NSLock()
    private var state = State(values: [], recorderExpectation: nil, observer: nil)
    private var consumedCount = 0
    
    /// Internal for testability. Use ValueObservation.record(in:) instead.
    init() { }
    
    private func synchronized<T>(_ execute: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try execute()
    }
    
    // MARK: ValueObservation API
    
    // Internal for testability.
    func onChange(_ value: Value) {
        return synchronized {
            if state.error != nil {
                // This is possible with ValueObservation, but not supported by ValueObservationRecorder
                XCTFail("ValueObservationRecorder got unexpected value after error: \(String(reflecting: value))")
            }
            
            state.values.append(value)
            
            if let exp = state.recorderExpectation, let remainingCount = exp.remainingCount {
                assert(remainingCount > 0)
                exp.expectation.fulfill()
                if remainingCount > 1 {
                    state.recorderExpectation = RecorderExpectation(expectation: exp.expectation, remainingCount: remainingCount - 1)
                } else {
                    state.recorderExpectation = nil
                }
            }
        }
    }
    
    // Internal for testability.
    func onError(_ error: Error) {
        return synchronized {
            if state.error != nil {
                // This is possible with ValueObservation, but not supported by ValueObservationRecorder
                XCTFail("f got unexpected error after error: \(String(describing: error))")
            }
            
            if let exp = state.recorderExpectation {
                exp.expectation.fulfill(count: exp.remainingCount ?? 1)
                state.recorderExpectation = nil
            }
            state.error = error
        }
    }
    
    // MARK: ValueObservationExpectation API
    
    func fulfillOnValue(_ expectation: XCTestExpectation, includingConsumed: Bool) {
        synchronized {
            preconditionCanFulfillExpectation()
            
            let expectedFulfillmentCount = expectation.expectedFulfillmentCount
            
            if state.error != nil {
                expectation.fulfill(count: expectedFulfillmentCount)
                return
            }
            
            let values = state.values
            let maxFulfillmentCount = includingConsumed
                ? values.count
                : values.count - consumedCount
            let fulfillmentCount = min(expectedFulfillmentCount, maxFulfillmentCount)
            expectation.fulfill(count: fulfillmentCount)
            
            let remainingCount = expectedFulfillmentCount - fulfillmentCount
            if remainingCount > 0 {
                state.recorderExpectation = RecorderExpectation(expectation: expectation, remainingCount: remainingCount)
            } else {
                state.recorderExpectation = nil
            }
        }
    }
    
    func fulfillOnError(_ expectation: XCTestExpectation) {
        synchronized {
            preconditionCanFulfillExpectation()
            
            if state.error != nil {
                expectation.fulfill()
                return
            }
            
            state.recorderExpectation = RecorderExpectation(expectation: expectation, remainingCount: nil)
        }
    }
    
    /// Returns a value based on the recorded state.
    ///
    /// - parameter value: A function which returns the value, given the
    ///   recorded state.
    /// - parameter values: All recorded values.
    /// - parameter remainingValues: The values that were not consumed yet.
    /// - parameter consume: A function which consumes values.
    /// - parameter count: The number of consumed values.
    /// - returns: The value
    func value<T>(_ value: (
        _ values: [Value],
        _ error: Error?,
        _ remainingValues: ArraySlice<Value>,
        _ consume: (_ count: Int) -> ()) throws -> T)
        rethrows -> T
    {
        try synchronized {
            let values = state.values
            let remainingValues = values[consumedCount...]
            return try value(values, state.error, remainingValues, { count in
                precondition(count >= 0)
                precondition(count <= remainingValues.count)
                consumedCount += count
            })
        }
    }
    
    /// Checks that recorder can fulfill an expectation.
    ///
    /// The reason this method exists is that a recorder can fulfill a single
    /// expectation at a given time. It is a programmer error to wait for two
    /// expectations concurrently.
    ///
    /// This method MUST be called within a synchronized block.
    private func preconditionCanFulfillExpectation() {
        if let exp = state.recorderExpectation {
            // We are already waiting for an expectation! Is it a programmer
            // error? Recorder drops references to non-inverted expectations
            // when they are fulfilled. But inverted expectations are not
            // fulfilled, and thus not dropped. We can't quite know if an
            // inverted expectations has expired yet, so just let it go.
            precondition(exp.expectation.isInverted, "Already waiting for an expectation")
        }
    }
    
    fileprivate func receive(_ observer: TransactionObserver) {
        synchronized {
            if state.observer != nil {
                XCTFail("ValueObservationRecorder is already observing")
            }
            state.observer = observer
        }
    }
}

// MARK: - ValueObservationRecorder + Expectations

extension ValueObservationRecorder {
    public func failure() -> ValueObservationExpectations.Failure<Value> {
        ValueObservationExpectations.Failure(recorder: self)
    }
    
    public func next() -> ValueObservationExpectations.NextOne<Value> {
        ValueObservationExpectations.NextOne(recorder: self)
    }
    
    public func next(_ count: Int) -> ValueObservationExpectations.Next<Value> {
        ValueObservationExpectations.Next(recorder: self, count: count)
    }
    
    public func prefix(_ maxLength: Int) -> ValueObservationExpectations.Prefix<Value> {
        ValueObservationExpectations.Prefix(recorder: self, maxLength: maxLength)
    }
}

// MARK: - ValueObservation + ValueObservationRecorder

extension ValueObservation {
    public func record(in reader: DatabaseReader) -> ValueObservationRecorder<Reducer.Value> {
        let recorder = ValueObservationRecorder<Reducer.Value>()
        let observer = start(
            in: reader,
            onError: recorder.onError,
            onChange: recorder.onChange)
        recorder.receive(observer)
        return recorder
    }
}

// MARK: - ValueObservationExpectation

public enum ValueRecordingError: Error {
    case notEnoughValues
    case notFailed
}

extension ValueRecordingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notEnoughValues:
            return "ValueRecordingError.notEnoughValues"
        case .notFailed:
            return "ValueRecordingError.notFailed"
        }
    }
}

public protocol _ValueObservationExpectationBase {
    func _setup(_ expectation: XCTestExpectation)
}

public protocol ValueObservationExpectation: _ValueObservationExpectationBase {
    associatedtype Output
    func get() throws -> Output
}

// MARK: - XCTestCase + ValueObservationExpectation

extension XCTestCase {
    public func wait<E: ValueObservationExpectation>(
        for valueObservationExpectation: E,
        timeout: TimeInterval,
        description: String = "")
        throws -> E.Output
    {
        let expectation = self.expectation(description: description)
        valueObservationExpectation._setup(expectation)
        wait(for: [expectation], timeout: timeout)
        return try valueObservationExpectation.get()
    }
    
    /// See testAssertValueObservationRecordingMatch()
    public func assertValueObservationRecordingMatch<Value>(
        recorded recordedValues: [Value],
        expected expectedValues: [Value],
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line)
        throws
        where Value: Equatable
    {
        try assertValueObservationRecordingMatch(
            recorded: recordedValues,
            expected: expectedValues,
            // Last value can't be missed, this is the most important of all!
            allowMissingLastValue: false,
            message(), file: file, line: line)
    }
    
    private func assertValueObservationRecordingMatch<R, E>(
        recorded recordedValues: R,
        expected expectedValues: E,
        allowMissingLastValue: Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: UInt = #line)
        throws
    where
        R: BidirectionalCollection,
        E: BidirectionalCollection,
        R.Element == E.Element,
        R.Element: Equatable
    {
        guard let value = expectedValues.last else {
            if !recordedValues.isEmpty {
                XCTFail("unexpected recorded prefix \(Array(recordedValues)) - \(message())", file: file, line: line)
            }
            return
        }
        
        let recordedSuffix = recordedValues.reversed().prefix(while: { $0 == value })
        let expectedSuffix = expectedValues.reversed().prefix(while: { $0 == value })
        if !allowMissingLastValue {
            // Both missing and duplicated values are allowed in the recorded values.
            // This is because of asynchronous DatabasePool observations.
            if recordedSuffix.isEmpty {
                XCTFail("missing expected value \(value) - \(message())", file: file, line: line)
            }
        }
        
        let remainingRecordedValues = recordedValues.prefix(recordedValues.count - recordedSuffix.count)
        let remainingExpectedValues = expectedValues.prefix(expectedValues.count - expectedSuffix.count)
        try assertValueObservationRecordingMatch(
            recorded: remainingRecordedValues,
            expected: remainingExpectedValues,
            // Other values can be missed
            allowMissingLastValue: true,
            message(), file: file, line: line)
    }
}

// MARK: - ValueObservationExpectations

public enum ValueObservationExpectations { }

extension ValueObservationExpectations {
    
    // MARK: Inverted
    
    public struct Inverted<Base: ValueObservationExpectation>: ValueObservationExpectation {
        let base: Base
        
        public func _setup(_ expectation: XCTestExpectation) {
            base._setup(expectation)
            expectation.isInverted.toggle()
        }
        
        public func get() throws -> Base.Output {
            try base.get()
        }
    }
    
    // MARK: NextOne
    
    public struct NextOne<Value>: ValueObservationExpectation {
        let recorder: ValueObservationRecorder<Value>
        
        public func _setup(_ expectation: XCTestExpectation) {
            recorder.fulfillOnValue(expectation, includingConsumed: false)
        }
        
        public func get() throws -> Value {
            try recorder.value { (_, error, remainingValues, consume) in
                if let next = remainingValues.first {
                    consume(1)
                    return next
                }
                if let error = error {
                    throw error
                } else {
                    throw ValueRecordingError.notEnoughValues
                }
            }
        }
        
        public var inverted: NextOneInverted<Value> {
            return NextOneInverted(recorder: recorder)
        }
    }
    
    // MARK: NextOneInverted
    
    public struct NextOneInverted<Value>: ValueObservationExpectation {
        let recorder: ValueObservationRecorder<Value>
        
        public func _setup(_ expectation: XCTestExpectation) {
            expectation.isInverted = true
            recorder.fulfillOnValue(expectation, includingConsumed: false)
        }
        
        public func get() throws {
            try recorder.value { (_, error, remainingValues, consume) in
                if remainingValues.isEmpty == false {
                    return
                }
                if let error = error {
                    throw error
                }
            }
        }
    }
    
    // MARK: Next
    
    public struct Next<Value>: ValueObservationExpectation {
        let recorder: ValueObservationRecorder<Value>
        let count: Int
        
        init(recorder: ValueObservationRecorder<Value>, count: Int) {
            precondition(count >= 0, "Invalid negative count")
            self.recorder = recorder
            self.count = count
        }
        
        public func _setup(_ expectation: XCTestExpectation) {
            if count == 0 {
                // Such an expectation is immediately fulfilled, by essence.
                expectation.expectedFulfillmentCount = 1
                expectation.fulfill()
            } else {
                expectation.expectedFulfillmentCount = count
                recorder.fulfillOnValue(expectation, includingConsumed: false)
            }
        }
        
        public func get() throws -> [Value] {
            try recorder.value { (_, error, remainingValues, consume) in
                if remainingValues.count >= count {
                    consume(count)
                    return Array(remainingValues.prefix(count))
                }
                if let error = error {
                    throw error
                } else {
                    throw ValueRecordingError.notEnoughValues
                }
            }
        }
    }
    
    // MARK: Prefix
    
    public struct Prefix<Value>: ValueObservationExpectation {
        let recorder: ValueObservationRecorder<Value>
        let maxLength: Int
        
        init(recorder: ValueObservationRecorder<Value>, maxLength: Int) {
            precondition(maxLength >= 0, "Invalid negative count")
            self.recorder = recorder
            self.maxLength = maxLength
        }
        
        public func _setup(_ expectation: XCTestExpectation) {
            if maxLength == 0 {
                // Such an expectation is immediately fulfilled, by essence.
                expectation.expectedFulfillmentCount = 1
                expectation.fulfill()
            } else {
                expectation.expectedFulfillmentCount = maxLength
                recorder.fulfillOnValue(expectation, includingConsumed: true)
            }
        }
        
        public func get() throws -> [Value] {
            try recorder.value { (values, error, remainingValues, consume) in
                if values.count >= maxLength {
                    let extraCount = max(maxLength + remainingValues.count - values.count, 0)
                    consume(extraCount)
                    return Array(values.prefix(maxLength))
                }
                if let error = error {
                    throw error
                }
                consume(remainingValues.count)
                return values
            }
        }
        
        public var inverted: Inverted<Self> {
            return Inverted(base: self)
        }
    }
    
    // MARK: Failure
    
    public struct Failure<Value>: ValueObservationExpectation {
        let recorder: ValueObservationRecorder<Value>
        
        public func _setup(_ expectation: XCTestExpectation) {
            recorder.fulfillOnError(expectation)
        }
        
        public func get() throws -> (values: [Value], error: Error) {
            try recorder.value { (values, error, remainingValues, consume) in
                if let error = error {
                    consume(remainingValues.count)
                    return (values: values, error: error)
                } else {
                    throw ValueRecordingError.notFailed
                }
            }
        }
    }
}

// MARK: - Convenience

extension XCTestExpectation {
    fileprivate func fulfill(count: Int) {
        for _ in 0..<count {
            fulfill()
        }
    }
}
