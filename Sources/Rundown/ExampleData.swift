import Foundation
import OSLog
import XCTest

public protocol Element {
  var description: String { get }
  var traits: [any Trait] { get }
  
  func execute(in run: ExampleRun) throws
}

public protocol HookTime {}
public enum BeforeTime: HookTime {}
public enum ExampleTime: HookTime {}
public enum AfterTime: HookTime {}
public protocol HookScope {}
public enum AllScope: HookScope {}
public enum EachScope: HookScope {}

public struct Hook<Phase: HookPhase>: Element {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: () throws -> Void
  
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              execute: @escaping () throws -> Void) {
    self.init(name, traits, execute: execute)
  }
  
  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping () throws -> Void) {
    self.name = name
    self.traits = traits
    self.block = execute
  }

  public func execute(in run: ExampleRun) throws {
    try block()
  }
}

public typealias BeforeAll = Hook<BeforeAllPhase>
public typealias BeforeEach = Hook<BeforeEachPhase>
public typealias AfterEach = Hook<AfterEachPhase>
public typealias AfterAll = Hook<AfterAllPhase>

public protocol ExampleElement: Element {
  var isDeepFocused: Bool { get }
}


/// Example group that allows for callback-based setup and teardown, such as
/// `TaskLocal.withValue()`
public struct Within: ExampleElement {
  public typealias Executor = (() throws -> Void) throws -> Void
  
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
  
  public func execute(in run: ExampleRun) throws {
    try executor { try group.execute(in: run) }
  }
}


public struct It: ExampleElement {
  public let description: String
  public let traits: [any Trait]
  let block: () throws -> Void
  
  public init(_ description: String,
              _ traits: (any Trait)...,
              execute: @escaping () throws -> Void) {
    self.init(description, traits, execute: execute)
  }
  
  public init(_ description: String,
              _ traits: [any Trait],
              execute: @escaping () throws -> Void) {
    self.description = description
    self.traits = traits
    self.block = execute
  }
  
  public func execute(in run: ExampleRun) throws {
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

extension String
{
  // TODO: Consolidate this because it's also in the macro target
  /// Returns the string with the given prefix removed, or returns the string
  /// unchanged if the prefix does not match.
  func droppingPrefix(_ prefix: String) -> String
  {
    guard hasPrefix(prefix)
    else { return self }
    
    return String(self[prefix.endIndex...])
  }
}
