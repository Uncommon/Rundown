@_exported import Rundown

/// Conform your Swift Testing suite to use `spec` inside a `@Test`.
/// Rundown records thrown errors with the full example or hook path.
///
/// ### Paths on assertion failures
///
/// With Swift 6.2 or later, `try await spec { ... }` automatically adds a
/// `Rundown path` comment to failed `#expect` and `#require` assertions.
/// The issue keeps its original source location and comments.
///
/// For synchronous `try spec { ... }`, put `@Suite(.rundownPaths)` on the
/// enclosing type once. Swift Testing's issue-scoping API is async, so the
/// annotation lets Swift Testing install the handler before the sync test runs.
///
/// ```swift
/// import RundownSwiftTesting
/// import Testing
///
/// @Suite(.rundownPaths)
/// struct CartTests: SwiftTestingSuite {
///   @Test func totalsItems() throws {
///     try spec("Cart") {
///       it("adds the prices") {
///         let total = [19, 23].reduce(0, +)
///         #expect(total == 42)
///       }
///     }
///   }
/// }
/// ```
///
/// In a mixed suite, the annotation covers sync tests and async failures still
/// receive a single path comment. On Swift 6.0 and 6.1, native assertions use
/// Swift Testing's standard output and thrown errors still include Rundown paths.
///
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
    let node = describe(description, builder: builder).node
    try await withRundownAssertionPaths {
      try await node.run(with: SwiftTestingReporter(allowsConcurrency: true))
    }
  }
}
