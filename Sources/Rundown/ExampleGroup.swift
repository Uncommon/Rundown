public struct ExampleGroup<Call: CallType>: TestExample {
  typealias BeforeAll = TestHook<BeforeAllPhase, Call>
  typealias BeforeEach = TestHook<BeforeEachPhase, Call>
  typealias AfterEach = TestHook<AfterEachPhase, Call>
  typealias AfterAll = TestHook<AfterAllPhase, Call>

  public let description: String
  public let traits: [any Trait]
  let beforeAll: [BeforeAll]
  let beforeEach: [BeforeEach]
  let afterEach: [AfterEach]
  let afterAll: [AfterAll]
  let elements: [any TestExample]
  
  public var isDeepFocused: Bool {
    isFocused || elements.contains(where: \.isDeepFocused)
  }

  public init(_ description: String,
              _ traits: (any Trait)...,
              @ExampleBuilder<Call> builder: () -> ExampleGroup<Call>) {
    self.init(description, traits, builder: builder)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              @ExampleBuilder<Call> builder: () -> ExampleGroup<Call>)
  {
    let builtGroup = builder()
    
    self.description = description
    self.traits = traits
    self.beforeAll = builtGroup.beforeAll
    self.beforeEach = builtGroup.beforeEach
    self.afterEach = builtGroup.afterEach
    self.afterAll = builtGroup.afterAll
    self.elements = builtGroup.elements
  }

  init(description: String,
       traits: [any Trait],
       beforeAll: [BeforeAll],
       beforeEach: [BeforeEach],
       afterEach: [AfterEach],
       afterAll: [AfterAll],
       elements: [any TestExample]) {
    self.description = description
    self.traits = traits
    self.beforeAll = beforeAll
    self.beforeEach = beforeEach
    self.afterEach = afterEach
    self.afterAll = afterAll
    self.elements = elements
  }
  
  /// Returns the group with a different name
  public func named(_ name: String) -> Self {
    return Self.init(description: name,
                     traits: traits,
                     beforeAll: beforeAll,
                     beforeEach: beforeEach,
                     afterEach: afterEach,
                     afterAll: afterAll,
                     elements: elements)
  }
  
  public func run() throws {
    try ExampleRun.run(self)
  }

  public func run() async throws {
    try await ExampleRun.run(self)
  }

  public func execute(in run: ExampleRun) throws {
    try run.run(self)
  }

  public func execute(in run: ExampleRun) async throws {
    try await run.run(self)
  }
}

public typealias Describe = ExampleGroup
public typealias Context = ExampleGroup
