import Foundation

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
  
  init(_ description: String = "", execute: @escaping () -> Void) {
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

  public func execute() throws {
    // TODO: XCTContext.runActivity() and Swift Testing equivalent (if any)
    // TODO: Logging so Xcode recognizes test steps
    try beforeAll.forEach { try $0.execute() }
    for element in elements {
      try beforeEach.execute()
      try element.execute()
      try afterEach.execute()
    }
    try afterAll.execute()
  }
}

extension Array where Self.Element: Scaff.Element {
  func execute() throws {
    try forEach { try $0.execute() }
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
}

