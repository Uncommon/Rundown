import Rundown

/// A Swift Testing suite whose `spec` builders, hooks, and examples run on the main actor.
///
/// Swift infers `@MainActor` for the suite when you declare this conformance
/// in the same file as the suite type.
///
/// Use `try spec { ... }` in synchronous tests and `try await spec { ... }` in
/// asynchronous tests. Async specs add assertion paths automatically on Swift
/// 6.2 and later. Apply `@Suite(.rundownPaths)` to add them to sync specs.
///
/// Sync specs run `.concurrent` groups serially. Async specs reject
/// `.concurrent` on main-actor groups before running their hooks.
@MainActor
public protocol MainActorSwiftTestingSuite: MainActorSuite {}

public extension MainActorSwiftTestingSuite {
  // Keep the sync overloads favored equally with MainActorSuite's so that
  // sync tests select the Swift Testing reporter.
  func spec(@ExampleBuilder<SyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<SyncMainCall>,
            function: String = #function) throws {
    try spec(specDescription(forFunction: function), builder: builder)
  }

  func spec(_ description: String,
            @ExampleBuilder<SyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<SyncMainCall>) throws {
    let group = describe(description, builder: builder)
    try group.node.run(with: SwiftTestingReporter(allowsConcurrency: false))
  }

  func spec(@ExampleBuilder<AsyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<AsyncMainCall>,
            function: String = #function) async throws {
    try await spec(specDescription(forFunction: function), builder: builder)
  }

  func spec(_ description: String,
            @ExampleBuilder<AsyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<AsyncMainCall>) async throws {
    let node = describe(description, builder: builder).node
    try await withRundownAssertionPaths {
      try await node.run(with: SwiftTestingReporter(allowsConcurrency: true))
    }
  }
}
