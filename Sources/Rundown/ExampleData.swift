import Foundation
import OSLog
import XCTest

public protocol Element {
  var description: String { get }
  func execute() throws
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
  
  public init(_ name: String = "", execute: @escaping () -> Void) {
    self.name = name
    self.block = execute
  }
  
  public func execute() throws {
    try block()
  }
}

public typealias BeforeAll = Hook<BeforeAllPhase>
public typealias BeforeEach = Hook<BeforeEachPhase>
public typealias AfterEach = Hook<AfterEachPhase>
public typealias AfterAll = Hook<AfterAllPhase>

public protocol ExampleElement: Element {
  func execute(in run: ExampleRun) throws
}

extension ExampleElement {
  public func execute() throws {
    try ExampleRun.run(self)
  }
}

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
  
  public func named(_ name: String) -> Self {
    return Self.init(description: name,
                     beforeAll: beforeAll,
                     beforeEach: beforeEach,
                     afterEach: afterEach,
                     afterAll: afterAll,
                     elements: elements)
  }

  func execute(_ wrapper: (any Element) throws -> Void) throws {
    for hook in beforeAll {
      try wrapper(hook)
    }
    for element in elements {
      for hook in beforeEach {
        try wrapper(hook)
      }
      try wrapper(element)
      for hook in afterEach {
        try wrapper(hook)
      }
    }
    for hook in afterAll {
      try wrapper(hook)
    }
  }

  public func execute(in run: ExampleRun) throws {
    try execute {
      element in
      try run.with(self) {
        if let example = element as? ExampleElement {
          try example.execute(in: run)
        }
        else {
          try element.execute()
        }
      }
    }
  }
  
  public func run() throws {
    try ExampleRun.run(self)
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
  
  public init(_ description: String, execute: @escaping () -> Void) {
    self.description = description
    self.block = execute
  }
  
  public func execute(in run: ExampleRun) throws {
    try run.with(self) {
      try block()
    }
  }
}

