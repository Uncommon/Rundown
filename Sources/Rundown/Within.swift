/// Example group that allows for callback-based setup and teardown, such as
/// `TaskLocal.withValue()`.
///
/// Be sure to call the given callback in your `executor` callback,
/// or else the enclosed test will not run.
public struct Within<Call: CallType>: TestExample {
  public let traits: [any Trait]
  let executor: Call.WithinCallback
  let group: ExampleGroup<Call>
  
  public var description: String { group.description }
  
  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>) {
    self.init(description, traits, executor: executor, example: example)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              executor: Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>) {
    self.traits = traits
    self.executor = executor
    self.group = .init(description, builder: example)
  }

  public func execute(in runner: ExampleRunner) throws
                      where Call == SyncCall {
    try executor { try group.execute(in: runner) }
  }

  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncCall {
    try await executor { try await group.execute(in: runner) }
  }
}

// As with it(), we need two versions rather than one generic version
// so the call site in unambiguous.
public func within(_ description: String,
                   _ traits: (any Trait)...,
                   executor: @escaping SyncCall.WithinCallback,
                   @ExampleBuilder<SyncCall> example: () -> ExampleGroup<SyncCall>) -> Within<SyncCall> {
  .init(description, traits, executor: executor, example: example)
}
@_disfavoredOverload
public func within(_ description: String,
                   _ traits: (any Trait)...,
                   executor: @escaping AsyncCall.WithinCallback,
                   @ExampleBuilder<AsyncCall> example: () -> ExampleGroup<AsyncCall>) -> Within<AsyncCall> {
  .init(description, traits, executor: executor, example: example)
}

/// Convenience initializer for using a task local value (non-async).
public func within<Value: Sendable>(
    _ description: String,
    _ traits: (any Trait)...,
    local: TaskLocal<Value>,
    _ value: Value,
    @ExampleBuilder<SyncCall> example: () -> ExampleGroup<SyncCall>) -> Within<SyncCall> {
  .init(description, traits,
        executor: { callback in
          try local.withValue(value) {
            try callback()
          }
        },
        example: example)
}
/// Convenience initializer for using a task local value (async).
@_disfavoredOverload
public func within<Value: Sendable>(
    _ description: String,
    _ traits: (any Trait)...,
    local: TaskLocal<Value>,
    _ value: Value,
    @ExampleBuilder<AsyncCall> example: () -> ExampleGroup<AsyncCall>) -> Within<AsyncCall> {
  .init(description, traits,
        executor: { callback in
          try await local.withValue(value) {
            try await callback()
          }
        },
        example: example)
}
