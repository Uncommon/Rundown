import Foundation
import OSLog
import XCTest

public protocol CallType: Sendable {
  associatedtype Callback: Sendable
  associatedtype WithinCallback: Sendable
}

public enum SyncCall: CallType {
  public typealias Callback = @Sendable () throws -> Void
  public typealias WithinCallback = @Sendable (Callback) throws -> Void
}
public enum AsyncCall: CallType {
  public typealias Callback = @Sendable () async throws -> Void
  public typealias WithinCallback = @Sendable (Callback) async throws -> Void
}

/// An async test element was found while running a non-async test
public struct UnexpectedAsyncError: Error {}

public protocol TestElement: Sendable {
  var description: String { get }
  var traits: [any Trait] { get }
}

public struct TestHook<Phase: HookPhase, Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Call.Callback

  public func execute(in runner: ExampleRunner) throws
                      where Call == SyncCall {
    try block()
  }

  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncCall {
    try await block()
  }
}

extension TestHook where Call == SyncCall {
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              execute: @escaping Call.Callback) {
    self.init(name, traits, execute: execute)
  }

  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.block = execute
  }
}

extension TestHook where Call == AsyncCall {
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.block = execute
  }
  
  public init(fromSync other: TestHook<Phase, SyncCall>) {
    self.name = other.name
    self.traits = other.traits
    self.block = other.block
  }
}

public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<BeforeAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<BeforeAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<BeforeEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<BeforeEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping SyncCall.Callback) -> TestHook<AfterEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping AsyncCall.Callback) -> TestHook<AfterEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<AfterAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<AfterAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public protocol TestExample: TestElement {
  var isDeepFocused: Bool { get }
}


public struct It<Call: CallType>: TestExample {
  public let description: String
  public let traits: [any Trait]
  let block: Call.Callback

  // These pairs of functions are identical except for the
  // "where Call ==" clause. They must be duplicated because there is
  // no way to express that Call.Callback is always a function type
  // and therefore can be @escaping.
  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping Call.Callback)
              where Call == SyncCall {
    self.init(description, traits, execute: execute)
  }
  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping Call.Callback)
              where Call == AsyncCall {
    self.init(description, traits, execute: execute)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping Call.Callback)
              where Call == SyncCall {
    self.description = description
    self.traits = traits
    self.block = execute
  }
  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping Call.Callback)
              where Call == AsyncCall {
    self.description = description
    self.traits = traits
    self.block = execute
  }

  /// "Casts" a sync instance to an async one
  public init(fromSync other: It<SyncCall>)
              where Call == AsyncCall {
    self.description = other.description
    self.traits = other.traits
    self.block = { try other.block() }
  }

  public func execute(in runner: ExampleRunner) throws
                      where Call == SyncCall {
    try block()
  }
  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncCall {
    try await block()
  }
}

// These two could almost be a single generic function, except again
// the compiler doesn't know that CallType.Callback is a function.
public func it(_ description: String,
               _ traits: (any Trait)...,
               execute: @escaping SyncCall.Callback) -> It<SyncCall> {
  .init(description, traits, execute: execute)
}

public func it(_ description: String,
               _ traits: (any Trait)...,
               execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits, execute: execute)
}

public func spec(@ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>,
                 function: String = #function) throws {
  let description = dropTestPrefix(function)
  try describe(description, builder: builder).run()
}

public func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>,
                 function: String = #function) async throws {
  let description = dropTestPrefix(function)
  try await describe(description, builder: builder).run()
}

private func dropTestPrefix(_ string: String) -> String {
  .init(string.prefix { $0.isIdentifier })
    .droppingPrefix("test")
}

public func spec(_ description: String,
                 @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) throws {
  try describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async throws {
  try await describe(description, builder: builder).run()
}
