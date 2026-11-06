@_exported import Rundown

/// Adds `spec` overloads that report thrown errors to the current Swift Testing test.
/// Synchronous specs run `.concurrent` groups serially to preserve the host test context.
public protocol SwiftTestingSuite {}

public extension SwiftTestingSuite {
  // Prefer the async overload in async contexts so the solver can type-check
  // a large spec body once.
  @_disfavoredOverload
  func spec(@ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>,
            function: String = #function) throws {
    try spec(specDescription(forFunction: function), builder: builder)
  }

  @_disfavoredOverload
  func spec(_ description: String,
            @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) throws {
    let group = describe(description, builder: builder)
    try group.node.run(with: SwiftTestingReporter(allowsConcurrency: false))
  }

  func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>,
            function: String = #function) async throws {
    try await spec(specDescription(forFunction: function), builder: builder)
  }

  func spec(_ description: String,
            @ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async throws {
    let group = describe(description, builder: builder)
    try await group.node.run(with: SwiftTestingReporter(allowsConcurrency: true))
  }
}
