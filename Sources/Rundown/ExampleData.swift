import Foundation
import OSLog
import XCTest

/// Contains either a sync or async callback with no parameters.
public enum Callback: Sendable {
  public typealias Sync = @Sendable () throws -> Void
  public typealias Async = @Sendable () async throws -> Void

  case sync(Sync)
  case async(Async)

  func call() throws {
    guard case .sync(let block) = self else {
      preconditionFailure("calling async callback as sync")
    }
    try block()
  }

  func call() async throws {
    switch self {
      case .async(let block):
        try await block()
      case .sync(let block):
        try block()
    }
  }
}

// The initial thought was to use a parameter pack and have a single enum
// for all parameter counts, but parameter packs are currently only available
// for functions.
/// One-parameter variation of `Callback`.
public enum Callback1<T>: Sendable {
  public typealias Sync = @Sendable (T) throws -> Void
  public typealias Async = @Sendable (T) async throws -> Void

  case sync(Sync)
  case async(Async)

  func call(_ param: T) throws {
    guard case .sync(let block) = self else {
      preconditionFailure("calling async callback as sync")
    }
    try block(param)
  }

  func call(_ param: T) async throws {
    switch self {
      case .async(let block):
        try await block(param)
      case .sync(let block):
        try block(param)
    }
  }
}

public protocol CallType: Sendable {}

public enum SyncCall: CallType {}
public enum AsyncCall: CallType {}

public protocol TestElement: Sendable {
  var description: String { get }
  var traits: [any Trait] { get }
  
  func execute(in runner: ExampleRunner) throws
  func execute(in runner: ExampleRunner) async throws
}

public struct TestHook<Phase: HookPhase, Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Callback

  public func execute(in runner: ExampleRunner) throws {
    try block.call()
  }

  public func execute(in runner: ExampleRunner) async throws {
    try await block.call()
  }
}

extension TestHook where Call == SyncCall {
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              execute: @escaping Callback.Sync) {
    self.init(name, traits, execute: execute)
  }

  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Callback.Sync) {
    self.name = name
    self.traits = traits
    self.block = .sync(execute)
  }
}

extension TestHook where Call == AsyncCall {
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Callback.Async) {
    self.name = name
    self.traits = traits
    self.block = .async(execute)
  }
}

public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Sync) -> TestHook<BeforeAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Async) -> TestHook<BeforeAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Sync) -> TestHook<BeforeEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Async) -> TestHook<BeforeEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping Callback.Sync) -> TestHook<AfterEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping Callback.Async) -> TestHook<AfterEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Sync) -> TestHook<AfterAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping Callback.Async) -> TestHook<AfterAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public protocol TestExample: TestElement {
  var isDeepFocused: Bool { get }
}


#if false // TODO: figure out async Within
/// Example group that allows for callback-based setup and teardown, such as
/// `TaskLocal.withValue()`
public struct Within: TestExample {
  public typealias Executor = Callback1<Callback>

  public let traits: [any Trait]
  let executor: Executor
  let group: ExampleGroup
  
  public var description: String { group.description }
  
  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: @escaping @Sendable (Callback) throws -> Void,
              @ExampleBuilder example: () -> ExampleGroup) {
    self.init(description, traits, executor: .sync(executor), example: example)
  }

  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: @escaping @Sendable (Callback) async throws -> Void,
              @ExampleBuilder example: () -> ExampleGroup) {
    self.init(description, traits, executor: .async(executor), example: example)
  }

  public init(_ description: String,
            _ traits: [any Trait],
            executor: Executor,
            @ExampleBuilder example: () -> ExampleGroup) {
    self.traits = traits
    self.executor = executor
    self.group = .init(description, builder: example)
  }
  
  public func execute(in runner: ExampleRunner) throws {
    try executor.call(.sync { try group.execute(in: runner) })
  }

  public func execute(in runner: ExampleRunner) async throws {
    try await executor.call(.async { try await group.execute(in: runner) })
  }
}

extension Within {
  /// Convenience initializer for using a task local value.
  public init<Value>(_ description: String,
                     _ traits: (any Trait)...,
                     local: TaskLocal<Value>,
                     _ value: Value,
                     @ExampleBuilder example: () -> ExampleGroup) where Value: Sendable {
    self.traits = traits
    self.executor = .sync { callback in
      try local.withValue(value) {
        try callback.call()
      }
    }
    self.group = .init(description, builder: example)
  }
}
#endif


public struct It: TestExample {
  public let description: String
  public let traits: [any Trait]
  let block: Callback

  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping Callback.Sync) {
    self.init(description, traits, execute: execute)
  }
  
  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping Callback.Sync) {
    self.description = description
    self.traits = traits
    self.block = .sync(execute)
  }

  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping Callback.Async) {
    self.init(description, traits, execute: execute)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping Callback.Async) {
    self.description = description
    self.traits = traits
    self.block = .async(execute)
  }

  public func execute(in runner: ExampleRunner) throws {
    try block.call()
  }

  public func execute(in runner: ExampleRunner) async throws {
    try await block.call()
  }
}

public func spec(@ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>,
                 function: String = #function) throws {
  let description = String(function.prefix { $0.isIdentifier })
    .droppingPrefix("test")
  try Describe(description, builder: builder).run()
}

public func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>,
                 function: String = #function) async throws {
  let description = String(function.prefix { $0.isIdentifier })
    .droppingPrefix("test")
  try await Describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) throws {
  try Describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async throws {
  try await Describe(description, builder: builder).run()
}
