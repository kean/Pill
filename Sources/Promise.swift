// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A promise represents a value which may be available now, or in the future,
/// or never. Use `then()` to get the result of the promise. Use `catch()`
/// to catch errors.
///
/// Promises start in a *pending* state and either get *fulfilled* with a
/// value or get *rejected* with an error.
public final class Promise<T> {
    private var state: State<T> = .pending(Handlers<T>())
    private let lock = NSLock()

    // MARK: Creation

    /// Creates a new, pending promise.
    ///
    /// - parameter closure: The closure is called immediately on the current
    /// thread. You should start an asynchronous task and call either `fulfill`
    /// or `reject` when it completes.
    public init(_ closure: (_ fulfill: @escaping (T) -> Void, _ reject: @escaping (Error) -> Void) -> Void) {
        closure({ self._fulfill($0) }, { self._reject($0) })
    }
    
    private func _fulfill(_ value: T) {
        _resolve { handlers in
            state = .fulfilled(value)
            // Handlers only contain `queue.async` calls which are fast
            // enough for a critical section (no real need to optimize this).
            handlers.fulfill.forEach { $0(value) }
        }
    }
    
    private func _reject(_ error: Error) {
        _resolve { handlers in
            state = .rejected(error)
            handlers.reject.forEach { $0(error) }
        }
    }
    
    private func _resolve(_ closure: (Handlers<T>) -> Void) {
        lock.lock(); defer { lock.unlock() }
        if case let .pending(handlers) = state { closure(handlers) }
    }
    
    /// Creates a promise fulfilled with a given value.
    public init(value: T) { state = .fulfilled(value) }

    /// Creates a promise rejected with a given error.
    public init(error: Error) { state = .rejected(error) }
    
    // MARK: Synchronous Inspection

    public var value: T? {
        lock.lock(); defer { lock.unlock() } // a bit of ninja coding
        if case let .fulfilled(val) = state { return val } else { return nil }
    }
    
    public var error: Error? {
        lock.lock(); defer { lock.unlock() }
        if case let .rejected(err) = state { return err } else { return nil }
    }

    // MARK: Callbacks
    
    private func _observe(on queue: DispatchQueue, fulfill: @escaping (T) -> Void, reject: @escaping (Error) -> Void) {
        // `fulfill` and `reject` are called asynchronously on the `queue`
        let _fulfill: (T) -> Void = { value in queue.async { fulfill(value) } }
        let _reject: (Error) -> Void = { error in queue.async { reject(error) } }
        
        lock.lock(); defer { lock.unlock() }
        switch state {
        case let .pending(handlers):
            handlers.fulfill.append(_fulfill)
            handlers.reject.append(_reject)
        case let .fulfilled(value): _fulfill(value)
        case let .rejected(error): _reject(error)
        }
    }
    
    // MARK: Then
    
    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise fulfilled with a value returned by the closure.
    @discardableResult public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) throws -> U) -> Promise<U> {
        return _then(on: queue) { value, fulfill, _ in
            fulfill(try closure(value))
        }
    }

    /// The provided closure executes asynchronously when the promise fulfills
    /// with a value.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise that resolves by the promise returned by the closure.
    @discardableResult public func then<U>(on queue: DispatchQueue = .main, _ closure: @escaping (T) throws -> Promise<U>) -> Promise<U> {
        return _then(on: queue) { value, fulfill, reject in
            try closure(value)._observe(on: queue, fulfill: fulfill, reject: reject)
        }
    }
    
    /// Returns a new promise.
    /// - when `self` is fufilled the closure is called (you control it)
    /// - when `self` is rejected the promise is rejected
    private func _then<U>(on queue: DispatchQueue, _ closure: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void) throws -> Void) -> Promise<U> {
        return Promise<U>() { fulfill, reject in
            _observe(on: queue, fulfill: {
                do { try closure($0, fulfill, reject) } catch { reject(error) }
            }, reject: reject)
        }
    }

    // MARK: Catch

    /// The provided closure executes asynchronously when the promise is
    /// rejected with an error.
    ///
    /// A promise bubbles up errors. It allows you to catch all errors returned
    /// by a chain of promises with a single `catch()`.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    @discardableResult public func `catch`(on queue: DispatchQueue = .main, _ closure: @escaping (Error) throws -> Void) -> Promise<T> {
        return _catch(on: queue) { error, _, reject in
            try closure(error)
            reject(error) // If closure doesn't throw, bubble previous error up
        }
    }

    /// Unlike `catch` `recover` allows you to continue the chain of promises
    /// by recovering from the error by returning a new value.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise fulfilled with a value returned by the closure.
    @discardableResult public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) throws -> T) -> Promise<T> {
        return _catch(on: queue) { error, fulfill, _ in
            fulfill(try closure(error))
        }
    }
    
    /// Unlike `catch` `recover` allows you to continue the chain of promises
    /// by recovering from the error by creating a new promise.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    /// - returns: A promise that resolves by the promise returned by the closure.
    @discardableResult public func recover(on queue: DispatchQueue = .main, _ closure: @escaping (Error) throws -> Promise<T>) -> Promise<T> {
        return _catch(on: queue) { error, fulfill, reject in
            try closure(error)._observe(on: queue, fulfill: fulfill, reject: reject)
        }
    }
    
    /// Returns a new promise.
    /// - when `self` is fufilled the promise is fulfilled
    /// - when `self` is rejected the closure is called (you control it)
    private func _catch(on queue: DispatchQueue, _ closure: @escaping (Error, @escaping (T) -> Void, @escaping (Error) -> Void) throws -> Void) -> Promise<T> {
        return Promise<T>() { fulfill, reject in
            _observe(on: queue, fulfill: fulfill, reject: {
                do { try closure($0, fulfill, reject) } catch { reject(error) }
            })
        }
    }
    
    // MARK: Finally
    
    /// The provided closure executes asynchronously when the promise is
    /// either fulfilled or rejected. Returns `self`.
    ///
    /// - parameter on: A queue on which the closure is run. `.main` by default.
    @discardableResult public func finally(on queue: DispatchQueue = .main, _ closure: @escaping (Void) -> Void) -> Promise<T> {
        _observe(on: queue, fulfill: { _ in closure() }, reject: { _ in closure() })
        return self
    }
}

private final class Handlers<T> { // boxed handlers
    var fulfill = [(T) -> Void]()
    var reject = [(Error) -> Void]()
}

private enum State<T> {
    case pending(Handlers<T>), fulfilled(T), rejected(Error)
}
