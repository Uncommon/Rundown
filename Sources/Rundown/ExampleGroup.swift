import os
public struct ExampleGroup<Call: CallType>: TestExample {
  typealias BeforeAll = TestHook<BeforeAllPhase, Call>
  typealias BeforeEachPeer = TestHook<BeforeEachPeerPhase, Call>
  typealias AfterEachPeer = TestHook<AfterEachPeerPhase, Call>
  typealias AfterAll = TestHook<AfterAllPhase, Call>

  public let description: String
  public let traits: [any Trait]
  let beforeAllHooks: [BeforeAll]
  let aroundEachPeerHooks: [AroundEachPeer<Call>]
  let beforeEachPeerHooks: [BeforeEachPeer]
  let afterEachPeerHooks: [AfterEachPeer]
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
    self.aroundEachPeerHooks = builtGroup.aroundEachPeerHooks
    self.beforeEachPeerHooks = builtGroup.beforeEachPeerHooks
    self.afterEachPeerHooks = builtGroup.afterEachPeerHooks
    self.afterAllHooks = builtGroup.afterAllHooks
    self.elements = builtGroup.elements
  }

  init(description: String,
       traits: [any Trait],
       beforeAll: [BeforeAll],
       aroundEachPeer: [AroundEachPeer<Call>],
       beforeEachPeer: [BeforeEachPeer],
       afterEachPeer: [AfterEachPeer],
       afterAll: [AfterAll],
       elements: [any TestExample]) {
    self.description = description
    self.traits = traits
    self.beforeAllHooks = beforeAll
    self.aroundEachPeerHooks = aroundEachPeer
    self.beforeEachPeerHooks = beforeEachPeer
    self.afterEachPeerHooks = afterEachPeer
    self.afterAllHooks = afterAll
    self.elements = elements
  }
  
  /// Returns the group with a different name
  public func named(_ name: String) -> Self {
    return Self.init(description: name,
                     traits: traits,
                     beforeAll: beforeAllHooks,
                     aroundEachPeer: aroundEachPeerHooks,
                     beforeEachPeer: beforeEachPeerHooks,
                     afterEachPeer: afterEachPeerHooks,
                     afterAll: afterAllHooks,
                     elements: elements)
  }
  
  @DeAsyncRD
  public func run() async throws where Call == AsyncCall {
    try await ExampleRunner.run(self)
  }
  
  @DeAsyncRD @MainActor
  public func run() async throws where Call == AsyncMainCall {
    try await ExampleRunner.run(self)
  }
}

extension ExampleGroup where Call == AsyncCall {
  /// Converts a group that was built with sync elements into an async group.
  ///
  /// - Important: `aroundEachPeer` hooks are dropped, in the group and in any
  /// nested groups. A sync `aroundEachPeer` calls its callback synchronously, so it
  /// can't wrap the async callback of an async group. An error is logged when
  /// this happens, but the converted group still runs, just without those hooks.
  /// To run a sync group that has `aroundEachPeer` hooks, run it as a sync group.
  public init(fromSync other: ExampleGroup<SyncCall>) {
    self.description = other.description
    self.traits = other.traits
    self.beforeAllHooks = other.beforeAllHooks.map { .init(fromSync: $0) }
    if !other.aroundEachPeerHooks.isEmpty {
      Logger(subsystem: "Rundown", category: "ExampleGroup")
        .error("aroundEachPeer cannot be converted from sync to async")
    }
    self.aroundEachPeerHooks = []
    self.beforeEachPeerHooks = other.beforeEachPeerHooks.map { .init(fromSync: $0) }
    self.afterEachPeerHooks = other.afterEachPeerHooks.map { .init(fromSync: $0) }
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
