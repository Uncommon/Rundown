import Foundation

public protocol Element {
  var description: String { get }
  func execute() throws
}

public protocol HookTime {}
public enum BeforeTime: HookTime {}
public enum AfterTime: HookTime {}
public protocol HookScope {}
public enum AllScope: HookScope {}
public enum EachScope: HookScope {}

public struct Hook<Time: HookTime, Scope: HookScope>: Element {
  let description: String
  let execute: () throws -> Void
  
  init(_ description: String = "", execute: @escaping () -> Void) {
    self.description = description
    self.execute = execute
  }
}

public typealias BeforeAll = Hook<BeforeTime, AllScope>
public typealias BeforeEach = Hook<BeforeTime, EachScope>
public typealias AfterEach = Hook<AfterTime, EachScope>
public typealias AfterAll = Hook<AfterTime, AllScope>

public protocol ExampleElement: Element {}

public struct ExampleGroup: ExampleElement {
  let description: String
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

  func execute() throws {
    // TODO: XCTContext.runActivity() and Swift Testing equivalent (if any)
    // TODO: Logging so Xcode recognizes test steps
    try beforeAll.map { try $0.execute() }
    for element in elements {
      try beforeEach.map { try $0.execute() }
      try element.execute()
      try afterEach.map { try $0.execute() }
    }
    try afterAll.map { try $0.execute() }
  }
}

public typealias Describe = ExampleGroup
public typealias Context = ExampleGroup

public struct It: ExampleElement {
  let description: String
  let execute: () throws -> Void
  
  init(_ description: String, execute: @escaping () -> Void) {
    self.description = description
    self.execute = execute
  }
}

