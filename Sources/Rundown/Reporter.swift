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
/// - a **decision** about whether to record the error where it happened,
///   for example as an `XCTIssue`, or propagate it to the caller.
///
/// A reporter is `Sendable` because concurrent groups call it from several
/// tasks or threads. Its methods are not isolated. A reporter that needs the
/// main actor, such as one for XCTest, does that work inside them with
/// `MainActor.assumeIsolated`, which the sync traversal also relies on.
package protocol Reporter: Sendable {
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

  /// Whether an error is a new failure, an already reported failure, or a skip.
  func classify(_ error: any Error) -> ErrorKind

  /// Called for a new failure or skip thrown by a node's own code, in the
  /// scope of that node, except for `aroundEach` hooks, which have no scope.
  /// The returned decision says whether the traversal should rethrow the
  /// error once the run is over, or consider it dealt with.
  ///
  /// This is also where a reporter logs a skip. The traversal ignores the
  /// returned decision for skips.
  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> ErrorHandlingDecision

  /// Whether groups with the `.concurrent` trait run their children at once.
  /// If not, the trait is ignored and they run one after another. The XCTest
  /// reporter says no, because `XCTContext` only works on the main thread.
  var allowsConcurrency: Bool { get }

  /// Whether to stop starting setup hooks and examples and unwind the run.
  /// A reporter can set this when it receives a skip that cancels the run.
  /// The traversal still calls teardown for groups and elements it entered.
  var shouldStop: Bool { get }
}

extension Reporter {
  package var allowsConcurrency: Bool { true }
  package var shouldStop: Bool { false }
}

package enum ErrorKind: Hashable, Sendable {
  /// Something went wrong
  case failure
  /// Something went wrong and the host has already recorded the issue.
  case alreadyReported
  /// Something doesn't apply. What follows depends on where it was thrown.
  case skip
}

/// The reporter's decision to treat a thrown failure as handled or let the
/// traversal rethrow it after teardown. The traversal ignores this value for skips.
package enum ErrorHandlingDecision: Hashable, Sendable {
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

  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> ErrorHandlingDecision {
    .propagate
  }
}
