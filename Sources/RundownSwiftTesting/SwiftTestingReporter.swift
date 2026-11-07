import os
import Rundown
import Testing

struct SwiftTestingReporter: Reporter {
  // Async task groups inherit Swift Testing's context. The sync traversal's
  // GCD workers do not, so sync callers pass false.
  let allowsConcurrency: Bool
  private let receivedCancellation = OSAllocatedUnfairLock(initialState: false)

  var shouldStop: Bool {
    Task.isCancelled || receivedCancellation.withLock { $0 }
  }

  func scope(for node: ExampleNode, _ body: () async -> Void) async {
    await body()
  }

  func scope(for node: ExampleNode, _ body: () -> Void) {
    body()
  }

  func classify(_ error: any Error) -> ErrorKind {
    if error is ExpectationFailedError {
      return .alreadyReported
    }
    if error is CancellationError, Task.isCancelled {
      return .skip
    }
    // Test.cancel throws a type that the toolchain's Testing module does not
    // expose. Match its qualified name to avoid catching unrelated errors.
    if String(reflecting: type(of: error)) == "Testing.SkipInfo" {
      return .skip
    }
    return .failure
  }

  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> ErrorHandlingDecision {
    if kind == .skip {
      // A child can observe cancellation before the rest of the run does.
      receivedCancellation.withLock { $0 = true }
    }
    guard kind == .failure else { return .record }

    var path = ExampleRunner.current?.path ?? []
    // An aroundEach hook wraps its child outside its own node scope.
    if path.isEmpty || node.isAroundEachHook {
      path.append(node.description)
    }
    Issue.record(error, Comment(rawValue: path.joined(separator: ", ")))
    return .record
  }
}
