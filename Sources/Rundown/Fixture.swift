/// Defines setup and optional cleanup for one example execution.
///
/// The descriptor stores closures, never a constructed value. Every execution
/// of an example using it invokes the factory again. The factory is responsible
/// for returning a fresh value and undoing partial setup if it throws.
/// The value need not conform to `Sendable`.
public struct Fixture<Value>: Sendable {
  let make: @Sendable () throws -> Value
  let cleanup: @Sendable (Value) throws -> Void

  /// Stores the callbacks without constructing a value. Cleanup is attempted
  /// after the example returns or throws, only if the factory returned a value.
  public init(_ make: @escaping @Sendable () throws -> Value,
              cleanup: @escaping @Sendable (Value) throws -> Void = { _ in }) {
    self.make = make
    self.cleanup = cleanup
  }
}

/// An asynchronous fixture factory and optional cleanup.
public struct AsyncFixture<Value>: Sendable {
  let make: @Sendable () async throws -> Value
  let cleanup: @Sendable (Value) async throws -> Void

  /// Stores the callbacks without constructing a value. Cleanup is attempted
  /// after the example returns or throws, only if the factory returned a value.
  public init(_ make: @escaping @Sendable () async throws -> Value,
              cleanup: @escaping @Sendable (Value) async throws -> Void = { _ in }) {
    self.make = make
    self.cleanup = cleanup
  }
}

/// A main-actor synchronous fixture factory and optional cleanup.
public struct MainActorFixture<Value>: Sendable {
  let make: @Sendable @MainActor () throws -> Value
  let cleanup: @Sendable @MainActor (Value) throws -> Void

  /// Stores the callbacks without constructing a value. Cleanup is attempted
  /// after the example returns or throws, only if the factory returned a value.
  public init(_ make: @escaping @Sendable @MainActor () throws -> Value,
              cleanup: @escaping @Sendable @MainActor (Value) throws -> Void = { _ in }) {
    self.make = make
    self.cleanup = cleanup
  }
}

/// A main-actor asynchronous fixture factory and optional cleanup.
public struct AsyncMainActorFixture<Value>: Sendable {
  let make: @Sendable @MainActor () async throws -> Value
  let cleanup: @Sendable @MainActor (Value) async throws -> Void

  /// Stores the callbacks without constructing a value. Cleanup is attempted
  /// after the example returns or throws, only if the factory returned a value.
  public init(_ make: @escaping @Sendable @MainActor () async throws -> Value,
              cleanup: @escaping @Sendable @MainActor (Value) async throws -> Void = { _ in }) {
    self.make = make
    self.cleanup = cleanup
  }
}

// MARK: - Nonisolated examples

@DeAsyncRD
@_disfavoredOverload
public func it<Value>(_ description: String,
                      _ traits: [any Trait],
                      using fixture: Fixture<Value>,
                      execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  .init(description, traits, execute: {
    try await runFixture(make: fixture.make, cleanup: fixture.cleanup, execute: execute)
  })
}

/// Passes a newly constructed fixture value directly to the example.
@DeAsyncRD
@_disfavoredOverload
public func it<Value>(_ description: String,
                      _ traits: (any Trait)...,
                      using fixture: Fixture<Value>,
                      execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits, using: fixture, execute: execute)
}

@DeAsyncRD
@_disfavoredOverload
public func fIt<Value>(_ description: String,
                       _ traits: (any Trait)...,
                       using fixture: Fixture<Value>,
                       execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits + [.focused], using: fixture, execute: execute)
}

@DeAsyncRD
@_disfavoredOverload
public func xIt<Value>(_ description: String,
                       _ traits: (any Trait)...,
                       using fixture: Fixture<Value>,
                       execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits + [.excluded], using: fixture, execute: execute)
}

public func it<Value>(_ description: String,
                      _ traits: [any Trait],
                      using fixture: AsyncFixture<Value>,
                      execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  .init(description, traits, execute: {
    try await runFixture(make: fixture.make, cleanup: fixture.cleanup, execute: execute)
  })
}

/// Passes a newly constructed fixture value directly to the example.
public func it<Value>(_ description: String,
                      _ traits: (any Trait)...,
                      using fixture: AsyncFixture<Value>,
                      execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits, using: fixture, execute: execute)
}

public func fIt<Value>(_ description: String,
                       _ traits: (any Trait)...,
                       using fixture: AsyncFixture<Value>,
                       execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits + [.focused], using: fixture, execute: execute)
}

public func xIt<Value>(_ description: String,
                       _ traits: (any Trait)...,
                       using fixture: AsyncFixture<Value>,
                       execute: @escaping @Sendable (Value) async throws -> Void) -> It<AsyncCall> {
  it(description, traits + [.excluded], using: fixture, execute: execute)
}

// MARK: - Main-actor examples

public extension MainActorSuite {
  @DeAsyncRD
  @_disfavoredOverload
  func it<Value>(_ description: String,
                 _ traits: [any Trait],
                 using fixture: Fixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    .init(description, traits, execute: {
      try await runMainActorFixture(make: fixture.make, cleanup: fixture.cleanup, execute: execute)
    })
  }

  /// Passes a newly constructed fixture value directly to the example.
  @DeAsyncRD
  @_disfavoredOverload
  func it<Value>(_ description: String,
                 _ traits: (any Trait)...,
                 using fixture: Fixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits, using: fixture, execute: execute)
  }

  @DeAsyncRD
  @_disfavoredOverload
  func fIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: Fixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.focused], using: fixture, execute: execute)
  }

  @DeAsyncRD
  @_disfavoredOverload
  func xIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: Fixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.excluded], using: fixture, execute: execute)
  }

  @DeAsyncRD
  @_disfavoredOverload
  func it<Value>(_ description: String,
                 _ traits: [any Trait],
                 using fixture: MainActorFixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    .init(description, traits, execute: {
      try await runMainActorFixture(make: fixture.make, cleanup: fixture.cleanup, execute: execute)
    })
  }

  /// Passes a newly constructed fixture value directly to the example.
  @DeAsyncRD
  @_disfavoredOverload
  func it<Value>(_ description: String,
                 _ traits: (any Trait)...,
                 using fixture: MainActorFixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits, using: fixture, execute: execute)
  }

  @DeAsyncRD
  @_disfavoredOverload
  func fIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: MainActorFixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.focused], using: fixture, execute: execute)
  }

  @DeAsyncRD
  @_disfavoredOverload
  func xIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: MainActorFixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.excluded], using: fixture, execute: execute)
  }

  func it<Value>(_ description: String,
                 _ traits: [any Trait],
                 using fixture: AsyncMainActorFixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    .init(description, traits, execute: {
      try await runMainActorFixture(make: fixture.make, cleanup: fixture.cleanup, execute: execute)
    })
  }

  /// Passes a newly constructed fixture value directly to the example.
  func it<Value>(_ description: String,
                 _ traits: (any Trait)...,
                 using fixture: AsyncMainActorFixture<Value>,
                 execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits, using: fixture, execute: execute)
  }

  func fIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: AsyncMainActorFixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.focused], using: fixture, execute: execute)
  }

  func xIt<Value>(_ description: String,
                  _ traits: (any Trait)...,
                  using fixture: AsyncMainActorFixture<Value>,
                  execute: @escaping @Sendable @MainActor (Value) async throws -> Void) -> It<AsyncMainCall> {
    it(description, traits + [.excluded], using: fixture, execute: execute)
  }

}
