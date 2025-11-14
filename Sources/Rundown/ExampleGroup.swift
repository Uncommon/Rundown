public struct ExampleGroup<Call: CallType>: TestExample {
  typealias BeforeAll = TestHook<BeforeAllPhase, Call>
  typealias BeforeEach = TestHook<BeforeEachPhase, Call>
  typealias AfterEach = TestHook<AfterEachPhase, Call>
  typealias AfterAll = TestHook<AfterAllPhase, Call>

  public let description: String
  public let traits: [any Trait]
  let beforeAll: [BeforeAll]
  let aroundEachHooks: [AroundEach<Call>]
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
    self.aroundEachHooks = builtGroup.aroundEachHooks
    self.beforeEach = builtGroup.beforeEach
    self.afterEach = builtGroup.afterEach
    self.afterAll = builtGroup.afterAll
    self.elements = builtGroup.elements
  }

  init(description: String,
       traits: [any Trait],
       beforeAll: [BeforeAll],
       aroundEach: [AroundEach<Call>],
       beforeEach: [BeforeEach],
       afterEach: [AfterEach],
       afterAll: [AfterAll],
       elements: [any TestExample]) {
    self.description = description
    self.traits = traits
    self.beforeAll = beforeAll
    self.aroundEachHooks = aroundEach
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
                     aroundEach: aroundEachHooks,
                     beforeEach: beforeEach,
                     afterEach: afterEach,
                     afterAll: afterAll,
                     elements: elements)
  }
}

extension ExampleGroup where Call == SyncCall {
  public func run() throws {
    try ExampleRunner.run(self)
  }

  public func execute(in runner: ExampleRunner) throws {
    try runner.run(self)
  }
}

extension ExampleGroup where Call == AsyncCall {
  public init(fromSync other: ExampleGroup<SyncCall>) {
    self.description = other.description
    self.traits = other.traits
    self.beforeAll = other.beforeAll.map { .init(fromSync: $0) }
    self.aroundEachHooks = [] // TODO
    self.beforeEach = other.beforeEach.map { .init(fromSync: $0) }
    self.afterEach = other.afterEach.map { .init(fromSync: $0) }
    self.afterAll = other.afterAll.map { .init(fromSync: $0) }
    self.elements = other.elements.map {
      switch $0 {
        case let syncIt as It<SyncCall>:
          It<AsyncCall>.init(fromSync: syncIt)
        case let syncGroup as ExampleGroup<SyncCall>:
          ExampleGroup<AsyncCall>.init(fromSync: syncGroup)
        default:
          preconditionFailure("unexpected element")
      }
    }
  }

  public func run() async throws {
    try await ExampleRunner.run(self)
  }

  public func execute(in runner: ExampleRunner) async throws {
    try await runner.run(self)
  }
}

public func describe(_ description: String,
                     _ traits: (any Trait)...,
                     @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits, builder: builder)
}

// Disfavored overload enables mixing sync and async elements in the same test
// without ambiguity.
@_disfavoredOverload
public func describe(_ description: String,
                     _ traits: (any Trait)...,
                     @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits, builder: builder)
}

public func context(_ description: String,
                    _ traits: (any Trait)...,
                    @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits, builder: builder)
}

@_disfavoredOverload
public func context(_ description: String,
                    _ traits: (any Trait)...,
                    @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits, builder: builder)
}
