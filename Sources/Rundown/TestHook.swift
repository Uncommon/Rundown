public struct TestHook<Phase: HookPhase, Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Call.Callback

  public func execute(in runner: ExampleRunner) throws
                      where Call == SyncCall {
    try block()
  }

  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncCall {
    try await block()
  }
}

extension TestHook where Call == SyncCall {
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              execute: @escaping Call.Callback) {
    self.init(name, traits, execute: execute)
  }

  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.block = execute
  }
}

extension TestHook where Call == AsyncCall {
  public init(_ name: String = "",
              _ traits: [any Trait],
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.block = execute
  }
  
  public init(fromSync other: TestHook<Phase, SyncCall>) {
    self.name = other.name
    self.traits = other.traits
    self.block = other.block
  }
}

public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<BeforeAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

@_disfavoredOverload
public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<BeforeAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<BeforeEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

@_disfavoredOverload
public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<BeforeEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping SyncCall.Callback) -> TestHook<AfterEachPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

@_disfavoredOverload
public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                       execute: @escaping AsyncCall.Callback) -> TestHook<AfterEachPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}

public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping SyncCall.Callback) -> TestHook<AfterAllPhase, SyncCall> {
  .init(name, traits, execute: execute)
}

@_disfavoredOverload
public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                      execute: @escaping AsyncCall.Callback) -> TestHook<AfterAllPhase, AsyncCall> {
  .init(name, traits, execute: execute)
}
