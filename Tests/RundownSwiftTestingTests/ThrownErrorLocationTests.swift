import os
import RundownSwiftTesting
import Testing

private struct LocatedFailure: Error {
  let line: Int
}

private enum ThrownIssueProbe {
  @TaskLocal static var issues: OSAllocatedUnfairLock<[Issue]>?

  static let capture = IssueHandlingTrait.compactMapIssues { issue in
    guard let issues, issue.error is LocatedFailure
    else { return issue }
    issues.withLock { $0.append(issue) }
    return nil
  }

  static func check(_ issues: OSAllocatedUnfairLock<[Issue]>, paths: [String]) {
    let recorded = issues.withLock { $0 }
    #expect(recorded.map { $0.comments.map(\.rawValue) } == paths.map { [$0] })
    for issue in recorded {
      #expect(issue.sourceLocation?.fileID == #fileID)
#if compiler(>=6.3)
      #expect(issue.sourceLocation?.filePath == #filePath)
#endif
      #expect(issue.sourceLocation?.line == (issue.error as? LocatedFailure)?.line)
      #expect((issue.sourceLocation?.column ?? 0) > 0)
    }
  }
}

// Reusable result-builder groups keep their own declarations even when named,
// nested in another spec, or explicitly converted to async.
@ExampleBuilder<SyncCall>
private func sharedFailures() -> ExampleGroup<SyncCall> {
  context("setup") {
    let line = #line + 1
    beforeAll { throw LocatedFailure(line: line) }
    it("skipped") { Issue.record("Ran after shared setup failed") }
  }
  let line = #line + 1
  it("example") { throw LocatedFailure(line: line) }
}

struct ThrownErrorLocationTests: SwiftTestingSuite {
  @Test(ThrownIssueProbe.capture)
  func syncHooksAndExamplesUseTheirDeclarations() throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())

    try ThrownIssueProbe.$issues.withValue(issues) {
      try spec("Sync") {
        context("setup") {
          let line = #line + 1
          beforeAll("open") { throw LocatedFailure(line: line) }
          beforeAll { Issue.record("Ran remaining setup") }
          it("skipped") { Issue.record("Ran after failed setup") }
          let cleanupLine = #line + 1
          afterAll("close") { throw LocatedFailure(line: cleanupLine) }
          afterAll { trace.withLock { $0.append("cleanup") } }
        }
        context("each") {
          let line = #line + 1
          beforeEach { throw LocatedFailure(line: line) }
          it("skipped") { Issue.record("Ran after failed beforeEach") }
          let cleanupLine = #line + 1
          afterEach { throw LocatedFailure(line: cleanupLine) }
        }
        context("peer") {
          let line = #line + 1
          beforeEachPeer { throw LocatedFailure(line: line) }
          it("skipped") { Issue.record("Ran after failed beforeEachPeer") }
          let cleanupLine = #line + 1
          afterEachPeer { throw LocatedFailure(line: cleanupLine) }
        }
        context("wrapper") {
          let line = #line + 1
          aroundEach("named") { _ in throw LocatedFailure(line: line) }
          it("skipped") { Issue.record("Ran after failed aroundEach") }
        }
        context("peer wrapper") {
          let line = #line + 1
          aroundEachPeer { _ in throw LocatedFailure(line: line) }
          it("skipped") { Issue.record("Ran after failed aroundEachPeer") }
        }
        let line = #line + 1
        it("throws", []) { throw LocatedFailure(line: line) }
        sharedFailures().named("helper")
        it("continues") { trace.withLock { $0.append("sibling") } }
      }
    }

    ThrownIssueProbe.check(issues, paths: [
      "Sync, setup, before all: open", "Sync, setup, after all: close",
      "Sync, each, before each", "Sync, each, after each",
      "Sync, peer, before each peer", "Sync, peer, after each peer",
      "Sync, wrapper, around each: named", "Sync, peer wrapper, around each peer",
      "Sync, throws", "Sync, helper, setup, before all", "Sync, helper, example",
    ])
    #expect(trace.withLock { $0 } == ["cleanup", "sibling"])
  }

  @Test(ThrownIssueProbe.capture)
  func asyncHooksExamplesAndConvertedHelpersKeepLocations() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())

    try await ThrownIssueProbe.$issues.withValue(issues) {
      try await spec("Async") {
        context("setup") {
          let line = #line + 1
          beforeAll {
            await Task.yield()
            throw LocatedFailure(line: line)
          }
          it("skipped") { Issue.record("Ran after failed async setup") }
          afterAll { trace.withLock { $0.append("cleanup") } }
        }
        context("workers", .concurrent) {
          let line = #line + 1
          aroundEach { run in
            try await run()
            throw LocatedFailure(line: line)
          }
          let exampleLine = #line + 1
          it("throws") {
            await Task.yield()
            throw LocatedFailure(line: exampleLine)
          }
        }
        ExampleGroup<AsyncCall>(fromSync: sharedFailures()).named("helper")
        it("continues") { trace.withLock { $0.append("sibling") } }
      }
    }

    ThrownIssueProbe.check(issues, paths: [
      "Async, setup, before all", "Async, workers, throws", "Async, workers, around each",
      "Async, helper, setup, before all", "Async, helper, example",
    ])
    #expect(trace.withLock { $0 } == ["cleanup", "sibling"])
  }

  @Test(ThrownIssueProbe.capture)
  func fixtureErrorsUseTheExampleDeclaration() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    try await ThrownIssueProbe.$issues.withValue(issues) {
      try await spec("Fixtures") {
        let setupLine = #line + 1
        it("setup", using: AsyncFixture<Int>({ throw LocatedFailure(line: setupLine) })) { _ in
          Issue.record("Ran with a failed fixture")
        }
        let bodyLine = #line + 1
        it("body", [], using: Fixture({ 1 })) { _ in
          throw LocatedFailure(line: bodyLine)
        }
        let cleanupLine = #line + 1
        it("cleanup", using: Fixture({ 1 }, cleanup: { _ in throw LocatedFailure(line: cleanupLine) })) { _ in }
      }
    }
    ThrownIssueProbe.check(issues, paths: [
      "Fixtures, setup, fixture setup", "Fixtures, body", "Fixtures, cleanup, fixture cleanup",
    ])
  }
}

struct MainActorThrownErrorLocationTests: MainActorSwiftTestingSuite {
  @ExampleBuilder<SyncMainCall>
  private func sharedSetup() -> ExampleGroup<SyncMainCall> {
    let line = #line + 1
    beforeAll { throw LocatedFailure(line: line) }
    it("skipped") { Issue.record("Ran after failed shared main-actor setup") }
  }

  @Test(ThrownIssueProbe.capture)
  func syncMainActorFailuresUseDeclarations() throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    try ThrownIssueProbe.$issues.withValue(issues) {
      try spec("Main sync") {
        sharedSetup().named("helper")
        context("wrapper") {
          let line = #line + 1
          aroundEachPeer("named") { _ in throw LocatedFailure(line: line) }
          it("skipped") { Issue.record("Ran after failed wrapper") }
        }
        context("example") {
          let line = #line + 1
          it("throws") { throw LocatedFailure(line: line) }
        }
      }
    }
    ThrownIssueProbe.check(issues, paths: [
      "Main sync, helper, before all", "Main sync, wrapper, around each peer: named",
      "Main sync, example, throws",
    ])
  }

  @Test(ThrownIssueProbe.capture)
  func asyncMainActorSetupSkipsItsGroupAndContinues() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())
    try await ThrownIssueProbe.$issues.withValue(issues) {
      try await spec("Remote list publisher refreshes") {
        context("when references change") {
          let line = #line + 1
          beforeAll {
            MainActor.assertIsolated()
            await Task.yield()
            throw LocatedFailure(line: line)
          }
          it("publishes the refreshed hierarchy") { Issue.record("This example should have been skipped") }
          afterAll { trace.withLock { $0.append("cleanup") } }
        }
        // A sync reusable group also runs inside an async-main spec.
        sharedSetup().named("helper")
        context("independent") {
          let line = #line + 1
          aroundEach { run in
            try await run()
            throw LocatedFailure(line: line)
          }
          let exampleLine = #line + 1
          it("throws") {
            MainActor.assertIsolated()
            await Task.yield()
            throw LocatedFailure(line: exampleLine)
          }
        }
        it("continues") { trace.withLock { $0.append("sibling") } }
      }
    }
    ThrownIssueProbe.check(issues, paths: [
      "Remote list publisher refreshes, when references change, before all",
      "Remote list publisher refreshes, helper, before all",
      "Remote list publisher refreshes, independent, throws",
      "Remote list publisher refreshes, independent, around each",
    ])
    #expect(trace.withLock { $0 } == ["cleanup", "sibling"])
  }
}
