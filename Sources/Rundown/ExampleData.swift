import Foundation
import OSLog
import XCTest

public typealias TestCallback = @Sendable () throws -> Void

public protocol TestElement: Sendable {
  var description: String { get }
  var traits: [any Trait] { get }
  
  func execute(in run: ExampleRunner) throws
}

public struct TestHook<Phase: HookPhase>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: TestCallback

  public init(_ name: String = "",
              _ traits: (any Trait)...,
              execute: @escaping TestCallback) {
    self.init(name, traits, execute: execute)
  }
  
  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping TestCallback) {
    self.name = name
    self.traits = traits
    self.block = execute
  }

  public func execute(in run: ExampleRunner) throws {
    try block()
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
  public typealias Executor = @Sendable (() throws -> Void) throws -> Void

  public let traits: [any Trait]
  let executor: Executor
  let group: ExampleGroup
  
  public var description: String { group.description }
  
  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: @escaping Executor,
              @ExampleBuilder example: () -> ExampleGroup) {
    self.init(description, traits, executor: executor, example: example)
  }
  
  public init(_ description: String,
            _ traits: [any Trait],
            executor: @escaping Executor,
            @ExampleBuilder example: () -> ExampleGroup) {
    self.traits = traits
    self.executor = executor
    self.group = .init(description, builder: example)
  }
  
  public func execute(in run: ExampleRunner) throws {
    try executor { try group.execute(in: run) }
  }
}

extension Within {
  /// Convenience initializer for using a task local value.
  public init<Value>(_ description: String,
                     _ traits: (any Trait)...,
                     local: TaskLocal<Value>,
                     _ value: Value,
                     @ExampleBuilder example: () -> ExampleGroup)where Value: Sendable {
    self.traits = traits
    self.executor = { callback in
      try local.withValue(value) {
        try callback()
      }
    }
    self.group = .init(description, builder: example)
  }
}


public struct It: TestExample {
  public let description: String
  public let traits: [any Trait]
  let block: TestCallback

  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping TestCallback) {
    self.init(description, traits, execute: execute)
  }
  
  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping TestCallback) {
    self.description = description
    self.traits = traits
    self.block = execute
  }
  
  public func execute(in run: ExampleRunner) throws {
    try block()
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
