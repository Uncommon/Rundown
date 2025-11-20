public struct ExampleGroup<Call: CallType>: TestExample {
  typealias BeforeAll = TestHook<BeforeAllPhase, Call>
  typealias BeforeEach = TestHook<BeforeEachPhase, Call>
  typealias AfterEach = TestHook<AfterEachPhase, Call>
  typealias AfterAll = TestHook<AfterAllPhase, Call>

  public let description: String
  public let traits: [any Trait]
  let beforeAllHooks: [BeforeAll]
  let aroundEachHooks: [AroundEach<Call>]
  let beforeEachHooks: [BeforeEach]
  let afterEachHooks: [AfterEach]
  let afterAllHooks: [AfterAll]
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
    self.beforeAllHooks = builtGroup.beforeAllHooks
    self.aroundEachHooks = builtGroup.aroundEachHooks
    self.beforeEachHooks = builtGroup.beforeEachHooks
    self.afterEachHooks = builtGroup.afterEachHooks
    self.afterAllHooks = builtGroup.afterAllHooks
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
    self.beforeAllHooks = beforeAll
    self.aroundEachHooks = aroundEach
    self.beforeEachHooks = beforeEach
    self.afterEachHooks = afterEach
    self.afterAllHooks = afterAll
    self.elements = elements
  }
  
  /// Returns the group with a different name
  public func named(_ name: String) -> Self {
    return Self.init(description: name,
                     traits: traits,
                     beforeAll: beforeAllHooks,
                     aroundEach: aroundEachHooks,
                     beforeEach: beforeEachHooks,
                     afterEach: afterEachHooks,
                     afterAll: afterAllHooks,
                     elements: elements)
  }
  
  @DeAsyncRD
  public func run() async throws where Call == AsyncCall {
    try await ExampleRunner.run(self)
  }

  @DeAsyncRD
  public func execute(in runner: ExampleRunner) async throws where Call == AsyncCall {
    try await runner.run(self)
  }
}

extension ExampleGroup where Call == AsyncCall {
  public init(fromSync other: ExampleGroup<SyncCall>) {
    self.description = other.description
    self.traits = other.traits
    self.beforeAllHooks = other.beforeAllHooks.map { .init(fromSync: $0) }
    self.aroundEachHooks = [] // TODO
    self.beforeEachHooks = other.beforeEachHooks.map { .init(fromSync: $0) }
    self.afterEachHooks = other.afterEachHooks.map { .init(fromSync: $0) }
    self.afterAllHooks = other.afterAllHooks.map { .init(fromSync: $0) }
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
}

// Disfavored overload enables mixing sync and async elements in the same test
// without ambiguity.
@DeAsyncRD
@_disfavoredOverload
public func describe(_ description: String,
                     _ traits: (any Trait)...,
                     @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits, builder: builder)
}

@DeAsyncRD
@_disfavoredOverload
public func context(_ description: String,
                    _ traits: (any Trait)...,
                    @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits, builder: builder)
}
