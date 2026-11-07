#if compiler(>=6.2)
import os
import RundownSwiftTesting
import Testing

private enum AssertionProbe {
  @TaskLocal static var issues: OSAllocatedUnfairLock<[Issue]>?

  // Observe the final comments after Rundown's handler and suppress only
  // deliberate failures, so unexpected issues still fail the test.
  static let capture = IssueHandlingTrait.compactMapIssues { issue in
    guard let issues, case .expectationFailed = issue.kind,
          issue.comments.contains(where: { $0.rawValue.hasPrefix("probe ") }) else { return issue }
    issues.withLock { $0.append(issue) }
    return nil
  }
}

struct AsyncAssertionPathTests: SwiftTestingSuite {
  @Test(AssertionProbe.capture)
  func asyncSpecAddsPathsToNativeAssertions() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())

    try await AssertionProbe.$issues.withValue(issues) {
      try await spec("Checkout") {
        context("signed in", .concurrent) {
          it("checks the total") {
            await Task.yield()
            #expect(Bool(false), "probe expect")
          }
          it("requires a receipt") {
            try #require(Bool(false), "probe require")
          }
        }
      }
      #expect(Bool(false), "probe outside")
    }

    let recorded = issues.withLock { $0 }
    #expect(recorded.count == 3)
    #expect(recorded.allSatisfy { $0.sourceLocation?.fileID == #fileID })
    let comments = recorded.map { $0.comments.map(\.rawValue) }
    #expect(comments.contains(["probe expect", "Rundown path: Checkout, signed in, checks the total"]))
    #expect(comments.contains(["probe require", "Rundown path: Checkout, signed in, requires a receipt"]))
    #expect(comments.contains(["probe outside"]))
  }

  @Test(AssertionProbe.capture)
  func failedRequirementsInHooksRecordOnceAndRunTeardown() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())
    let assertionLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)

    try await AssertionProbe.$issues.withValue(issues) {
      try await spec("Requirements") {
        context("nested") {
          aroundEach { run in
            defer { trace.withLock { $0.append("wrapper exit") } }
            try await run()
          }
          beforeEach("fixture") {
            await Task.yield()
            try #require(Bool(false), "probe setup", sourceLocation: assertionLocation)
          }
          it("never starts") { Issue.record("Ran an example after a failed setup requirement") }
          afterEach("release") { try #require(Bool(false), "probe teardown") }
          afterEach { trace.withLock { $0.append("remaining afterEach") } }
          afterAll { trace.withLock { $0.append("nested afterAll") } }
        }
        it("runs after the nested group") { trace.withLock { $0.append("sibling") } }
      }
    }

    let recorded = issues.withLock { $0 }
    #expect(recorded.map { $0.comments.map(\.rawValue) } == [
      ["probe setup", "Rundown path: Requirements, nested, before each: fixture"],
      ["probe teardown", "Rundown path: Requirements, nested, after each: release"],
    ])
    #expect(recorded.first?.sourceLocation == assertionLocation)
    #expect(trace.withLock { $0 } == ["remaining afterEach", "wrapper exit", "nested afterAll", "sibling"])
  }
}

@Suite(AssertionProbe.capture, .rundownPaths)
struct SuiteAssertionPathTests: SwiftTestingSuite {
  @Test func syncSpecUsesSuiteTrait() throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())

    try AssertionProbe.$issues.withValue(issues) {
      try spec("Sync spec") {
        it("fails") { #expect(Bool(false), "probe sync") }
      }
      #expect(Bool(false), "probe outside")
    }

    let comments = issues.withLock { $0.map { $0.comments.map(\.rawValue) } }
    #expect(comments == [["probe sync", "Rundown path: Sync spec, fails"], ["probe outside"]])
  }

  @Test func suiteTraitAndAsyncSpecAddOnePath() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())

    try await AssertionProbe.$issues.withValue(issues) {
      try await spec("Async spec") {
        it("fails") {
          await Task.yield()
          #expect(Bool(false), "probe async")
        }
      }
    }

    let comments = issues.withLock { $0.map { $0.comments.map(\.rawValue) } }
    #expect(comments == [["probe async", "Rundown path: Async spec, fails"]])
  }
}
#endif
