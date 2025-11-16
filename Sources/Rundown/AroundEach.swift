public struct AroundEach<Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    AroundEachPhase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let block: Call.WithinCallback
  
  func execute(around callback: @Sendable () throws -> Void) throws where Call == SyncCall {
    try block {
      try callback()
    }
  }
  
  func execute(around callback: @Sendable () async throws -> Void) async throws where Call == AsyncCall {
    try await block {
      try await callback()
    }
  }
}

/// For each example, the given executor will be called. That
/// executor will be given a callback that runs the example as well
/// as any `beforeEach`/`afterEach` elements.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
public func aroundEach(_ name: String = "",
                       _ traits: (any Trait)...,
                       executor: @escaping SyncCall.WithinCallback)
  -> AroundEach<SyncCall> {
  .init(name: name, traits: traits, block: executor)
}
/// For each example, the given executor will be called. That
/// executor will be given a callback that runs the example as well
/// as any `beforeEach`/`afterEach` elements.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
@_disfavoredOverload
public func aroundEach(_ name: String = "",
                       _ traits: (any Trait)...,
                       executor: @escaping AsyncCall.WithinCallback)
  -> AroundEach<AsyncCall> {
  .init(name: name, traits: traits, block: executor)
}
