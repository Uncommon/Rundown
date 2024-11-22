import Foundation
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
  public let description: String
  let block: () throws -> Void
  
  public init(_ description: String = "", execute: @escaping () -> Void) {
    self.description = description
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
  func execute(in test: TestCase) throws
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

  public func execute() throws {
    try execute { try $0.execute() }
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

  @MainActor
  public func executeMain() throws {
    try execute {
      element in
      try XCTContext.runActivity(named: element.description) { _ in
        try element.execute()
      }
    }
  }

  public func execute(in test: TestCase) throws {
    try execute {
      element in
      try test.withElement(self) {
        if let example = element as? ExampleElement {
          try example.execute(in: test)
        }
        else {
          try element.execute()
        }
      }
    }
  }
}

/// This subclass of `XCTestCase` is necessary in order to track the hierarchy
/// of test elements and construct the full description when recording an issue.
open class TestCase: XCTestCase {
  var elementStack: [any Element] = []

  func withElement(_ element: some Element, block: () throws -> Void) rethrows {
    elementStack.append(element)
    try block()
    _ = elementStack.popLast()
  }

  /// Adds the full test element description to the issue before recording
  public override func record(_ issue: XCTIssue) {
    let description = elementStack.map { $0.description }.joined(separator: ", ")

    let newIssue = XCTIssue(
      type: issue.type,
      compactDescription: "\(description) \(issue.compactDescription)",
      detailedDescription: issue.description,
      sourceCodeContext: issue.sourceCodeContext,
      associatedError: issue.associatedError,
      attachments: issue.attachments)

    super.record(newIssue)
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
  
  public func execute() throws {
    try block()
  }

  public func execute(in test: TestCase) throws {
    try test.withElement(self) {
      try block()
    }
  }
}

