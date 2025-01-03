import Foundation
import OSLog
import XCTest

public protocol Element {
  var description: String { get }
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
  let block: () throws -> Void
  
  public init(_ name: String = "", execute: @escaping () throws -> Void) {
    self.name = name
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

public protocol ExampleElement: Element {}

public struct ExampleGroup: ExampleElement {
  public let description: String
  let beforeAll: [BeforeAll]
  let beforeEach: [BeforeEach]
  let afterEach: [AfterEach]
  let afterAll: [AfterAll]
  let elements: [any ExampleElement]

  public init(_ description: String, @ExampleBuilder builder: () -> ExampleGroup)
  {
    let builtGroup = builder()
    
    self.description = description
    self.beforeAll = builtGroup.beforeAll
    self.beforeEach = builtGroup.beforeEach
    self.afterEach = builtGroup.afterEach
    self.afterAll = builtGroup.afterAll
    self.elements = builtGroup.elements
  }

  internal init(_ description: String = "", elements: [any ExampleElement]) {
    self.description = description
    self.beforeAll = []
    self.beforeEach = []
    self.afterEach = []
    self.afterAll = []
    self.elements = elements
  }

  init(description: String,
       beforeAll: [BeforeAll],
       beforeEach: [BeforeEach],
       afterEach: [AfterEach],
       afterAll: [AfterAll],
       elements: [any ExampleElement]) {
    self.description = description
    self.beforeAll = beforeAll
    self.beforeEach = beforeEach
    self.afterEach = afterEach
    self.afterAll = afterAll
    self.elements = elements
  }
  
  /// Returns the group with a different name
  public func named(_ name: String) -> Self {
    return Self.init(description: name,
                     beforeAll: beforeAll,
                     beforeEach: beforeEach,
                     afterEach: afterEach,
                     afterAll: afterAll,
                     elements: elements)
  }
  
  public func run() throws {
    try ExampleRun.run(self)
  }
  
  public func execute(in run: ExampleRun) throws {
    try run.run(self)
  }
}

/// Example group that allows for callback-based setup and teardown, such as
/// `TaskLocal.withValue()`
public struct Within: ExampleElement {
  public typealias Executor = (() throws -> Void) throws -> Void
  
  let executor: Executor
  let group: ExampleGroup
  
  public var description: String { group.description }
  
  public init(_ description: String,
       executor: @escaping Executor,
       @ExampleBuilder example: () -> ExampleGroup) {
    self.executor = executor
    self.group = .init(description, builder: example)
  }
  
  public func execute(in run: ExampleRun) throws {
    try executor { try group.execute(in: run) }
  }
}



public typealias Describe = ExampleGroup
public typealias Context = ExampleGroup

public struct It: ExampleElement {
  public let description: String
  let block: () throws -> Void
  
  public init(_ description: String, execute: @escaping () throws -> Void) {
    self.description = description
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
