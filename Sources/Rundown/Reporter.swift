/// How a traversal of an `ExampleNode` tree talks to whatever is running it.
///
/// The traversal owns the control flow: what runs, in what order, and what a
/// failure or a skip does to the rest of the run (see "Error and skip rules"
/// in Documentation/Roadmap.md). A reporter supplies what depends on the host:
///
/// - a **scope** around each node, such as an `XCTContext` activity, which has
///   to wrap the node's execution because it takes a closure;
/// - **classification** of an error as a failure or a skip, since `XCTSkip` is
///   a framework type that the traversal doesn't know about;
/// - the **disposition** of an error: whether it is recorded where it
///   happened, such as as an `XCTIssue`, or propagated to the caller.
///
/// A reporter is `Sendable` because concurrent groups call it from several
/// tasks or threads. Its methods are not isolated. A reporter that needs the
/// main actor, such as one for XCTest, does that work inside them with
/// `MainActor.assumeIsolated`, which the sync traversal also relies on.
protocol Reporter: Sendable {
  /// Runs `body` as the scope of `node`. The traversal calls this around the
  /// root group, each nested group, each example and each hook except
  /// `aroundEach`. Everything the node does happens inside `body`, including
  /// the calls to `report` for errors that it threw, so that a reporter can
  /// attach an error to the node it came from.
  ///
  /// `body` doesn't throw: the traversal handles errors itself.
  func scope(for node: ExampleNode, _ body: () async -> Void) async

  /// The sync version, for the sync traversal
  func scope(for node: ExampleNode, _ body: () -> Void)

  /// Whether an error means that something failed, or that it doesn't apply.
  func classify(_ error: any Error) -> ErrorKind

  /// Called once for each error thrown by a node's own code, in the scope of
  /// that node, except for `aroundEach` hooks, which have no scope. The
  /// returned disposition says whether the traversal should rethrow the error
  /// once the run is over, or consider it dealt with.
  ///
  /// This is also where a reporter logs a skip. The disposition of a skip
  /// matters only where a skip counts as a failure.
  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> Disposition
}

enum ErrorKind: Hashable, Sendable {
  /// Something went wrong
  case failure
  /// Something doesn't apply. What follows depends on where it was thrown.
  case skip
}

enum Disposition: Hashable, Sendable {
  /// The reporter has recorded the error. The traversal carries on and doesn't
  /// rethrow it.
  case record
  /// The traversal keeps the first of these and rethrows it at the end of the
  /// group, after teardown.
  case propagate
}

/// What the plain runners do: no scopes, every error is a failure, and every
/// failure propagates.
struct PlainReporter: Reporter {
  func scope(for node: ExampleNode, _ body: () async -> Void) async {
    await body()
  }

  func scope(for node: ExampleNode, _ body: () -> Void) {
    body()
  }

  func classify(_ error: any Error) -> ErrorKind { .failure }

  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> Disposition {
    .propagate
  }
}
