import Foundation
import OSLog
import XCTest

public typealias TestCallback = @Sendable () throws -> Void

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
  
  func execute(in run: ExampleRun) throws
  func execute(in run: ExampleRun) async throws
}

public struct TestHook<Phase: HookPhase>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Callback

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

  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Callback.Async) {
    self.name = name
    self.traits = traits
    self.block = .async(execute)
  }

  public func execute(in run: ExampleRun) throws {
    try block.call()
  }

  public func execute(in run: ExampleRun) async throws {
    try await block.call()
  }
}

public typealias BeforeAll = TestHook<BeforeAllPhase>
public typealias BeforeEach = TestHook<BeforeEachPhase>
public typealias AfterEach = TestHook<AfterEachPhase>
public typealias AfterAll = TestHook<AfterAllPhase>

public protocol TestExample: TestElement {
  var isDeepFocused: Bool { get }
}


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
  
  public func execute(in run: ExampleRun) throws {
    try executor.call(.sync { try group.execute(in: run) })
  }

  public func execute(in run: ExampleRun) async throws {
    try await executor.call(.async { try await group.execute(in: run) })
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
  
  public func execute(in run: ExampleRun) throws {
    try block.call()
  }

  public func execute(in run: ExampleRun) async throws {
    try await block.call()
  }
}

public func spec(@ExampleBuilder builder: () -> ExampleGroup,
                 function: String = #function) throws {
  let description = String(function.prefix { $0.isIdentifier })
    .droppingPrefix("test")
  try Describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder builder: () -> ExampleGroup) throws {
  try Describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder builder: () -> ExampleGroup) async throws {
  try await Describe(description, builder: builder).run()
}
