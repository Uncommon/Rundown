import Rundown
import Testing

func withRundownAssertionPaths(_ body: @Sendable () async throws -> Void) async throws {
#if compiler(>=6.2)
  if let test = Test.current {
    try await IssueHandlingTrait.rundownPaths.provideScope(
      for: test, testCase: Test.Case.current, performing: body)
    return
  }
#endif
  try await body()
}

#if compiler(>=6.2)
public extension Testing.Trait where Self == IssueHandlingTrait {
  /// Adds the current Rundown path to failed `#expect` and `#require` assertions.
  ///
  /// Apply `@Suite(.rundownPaths)` once to a `SwiftTestingSuite` that uses
  /// synchronous `spec` calls. Async `spec` calls install the same handler
  /// automatically. Swift Testing's issue scoping API is async, so sync specs
  /// rely on the host to install the handler before they run.
  ///
  /// Available with Swift 6.2 and later.
  static var rundownPaths: Self {
    .compactMapIssues { issue in
      guard case .expectationFailed = issue.kind,
            let path = ExampleRunner.current?.description, !path.isEmpty else { return issue }

      let comment = "Rundown path: \(path)"
      // The suite and spec scopes may both see the same issue.
      guard !issue.comments.contains(where: { $0.rawValue == comment }) else { return issue }

      var issue = issue
      issue.comments.append(Comment(rawValue: comment))
      return issue
    }
  }
}
#endif
