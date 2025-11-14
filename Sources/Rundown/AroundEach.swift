public struct AroundEach<Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    AroundEachPhase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Call.WithinCallback
  
  // init(fromSync:)
  
  func execute(around example: some TestExample,
               in runner: ExampleRunner) throws
               where Call == SyncCall {
    try block {
      switch example {
        case let it as It<Call>:
          try it.execute(in: runner)
        case let group as ExampleGroup<Call>:
          try group.execute(in: runner)
        default:
          preconditionFailure("unexpected element type")
      }
    }
  }
  
  func execute(around example: some TestExample,
               in runner: ExampleRunner) async throws
               where Call == AsyncCall {
    try await block {
      switch example {
        case let it as It<Call>:
          try await it.execute(in: runner)
        case let group as ExampleGroup<Call>:
          try await group.execute(in: runner)
        default:
          preconditionFailure("unexpected element type")
      }
    }
  }
}

/// For each example, the given executor will be called. That
/// executor will be given a callback that runs the example as well
/// as any `beforeEach`/`afterEach` elements.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
public func aroundEach(_ name: String,
                       _ traits: (any Trait)...,
                       executor: @escaping SyncCall.WithinCallback)
  -> AroundEach<SyncCall> {
  .init(name: name, traits: traits, block: executor)
}
@_disfavoredOverload
public func aroundEach(_ name: String,
                       _ traits: (any Trait)...,
                       executor: @escaping AsyncCall.WithinCallback)
  -> AroundEach<AsyncCall> {
  .init(name: name, traits: traits, block: executor)
}
