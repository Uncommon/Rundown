/// Example group that allows for callback-based setup and teardown, such as
/// `TaskLocal.withValue()`
public struct Within<Call: CallType>: TestExample {
  public let traits: [any Trait]
  let executor: Call.WithinCallback
  let group: ExampleGroup<Call>
  
  public var description: String { group.description }
  
  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: @escaping Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
              where Call == SyncCall {
    self.init(description, traits, executor: executor, example: example)
  }
  public init(_ description: String,
              _ traits: (any Trait)...,
              executor: @escaping Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
              where Call == AsyncCall {
    self.init(description, traits, executor: executor, example: example)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              executor: @escaping Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
              where Call == SyncCall {
    self.traits = traits
    self.executor = executor
    self.group = .init(description, builder: example)
  }
  public init(_ description: String,
              _ traits: [any Trait],
              executor: @escaping Call.WithinCallback,
              @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
              where Call == AsyncCall {
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

extension Within {
  /// Convenience initializer for using a task local value.
  public init<Value>(_ description: String,
                     _ traits: (any Trait)...,
                     local: TaskLocal<Value>,
                     _ value: Value,
                     @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
                     where Value: Sendable, Call == SyncCall {
    self.traits = traits
    self.executor = { callback in
      try local.withValue(value) {
        try callback()
      }
    }
    self.group = .init(description, builder: example)
  }
  /// Convenience initializer for using a task local value.
  public init<Value>(_ description: String,
                     _ traits: (any Trait)...,
                     local: TaskLocal<Value>,
                     _ value: Value,
                     @ExampleBuilder<Call> example: () -> ExampleGroup<Call>)
                     where Value: Sendable, Call == AsyncCall {
    self.traits = traits
    self.executor = { callback in
      try await local.withValue(value) {
        try await callback()
      }
    }
    self.group = .init(description, builder: example)
  }
}
