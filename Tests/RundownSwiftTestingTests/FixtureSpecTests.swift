import os
import RundownSwiftTesting
import Testing

private enum FixtureSpecFailure: Error { case setup, body, cleanup }

private enum FixtureAssertionProbe {
  @TaskLocal static var issues: OSAllocatedUnfairLock<[Issue]>?

  static let capture = IssueHandlingTrait.compactMapIssues { issue in
    guard let issues, case .expectationFailed = issue.kind,
          issue.comments.contains(where: { $0.rawValue == "fixture probe" })
    else { return issue }
    issues.withLock { $0.append(issue) }
    return nil
  }
}

@Suite(FixtureAssertionProbe.capture, .rundownPaths)
struct FixtureSpecTests: SwiftTestingSuite {
  @Test func recordsOriginalErrorsWithPhasePaths() throws {
    let paths = OSAllocatedUnfairLock(initialState: [String]())
    let events = OSAllocatedUnfairLock(initialState: [String]())
    let failedSetup = Fixture<Int> { throw FixtureSpecFailure.setup } cleanup: { _ in
      Issue.record("Cleaned up an unconstructed value")
    }
    let failedCleanup = Fixture { 42 } cleanup: { _ in throw FixtureSpecFailure.cleanup }

    try withKnownIssue {
      try spec("Fixtures") {
        it("reports a setup failure", using: failedSetup) { _ in Issue.record("Ran after failed setup") }
        it("reports example and cleanup failures", using: failedCleanup) { _ in throw FixtureSpecFailure.body }
        it("continues after failed examples") { events.withLock { $0.append("sibling") } }
        afterEachPeer { events.withLock { $0.append("afterEachPeer") } }
      }
    } matching: { issue in
      guard issue.error is FixtureSpecFailure, issue.comments.count == 1,
            let path = issue.comments.first?.rawValue
      else { return false }
      paths.withLock { $0.append(path) }
      return true
    }
    #expect(paths.withLock { $0 } == ["Fixtures, reports a setup failure, fixture setup",
                                     "Fixtures, reports example and cleanup failures",
                                     "Fixtures, reports example and cleanup failures, fixture cleanup"])
    #expect(events.withLock { $0 } == ["afterEachPeer", "afterEachPeer", "sibling", "afterEachPeer"])
  }

  @Test func requireFailuresAreNotDuplicatedAndCleanupStillRuns() async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    let events = OSAllocatedUnfairLock(initialState: [String]())
    let failedSetup = AsyncFixture {
      await Task.yield()
      return try #require(nil as Int?, "fixture probe")
    } cleanup: { _ in Issue.record("Cleaned up an unconstructed value") }
    let failedCleanup = Fixture { 42 } cleanup: { _ in _ = try #require(nil as Int?, "fixture probe") }

    try await FixtureAssertionProbe.$issues.withValue(issues) {
      try await spec("Assertions") {
        it("reports a failed setup requirement", using: failedSetup) { _ in Issue.record("Ran after failed requirement") }
        it("reports failed example and cleanup requirements", using: failedCleanup) { _ in
          await Task.yield()
          _ = try #require(nil as Int?, "fixture probe")
        }
        it("continues after failed examples") { events.withLock { $0.append("sibling") } }
        afterEachPeer { events.withLock { $0.append("afterEachPeer") } }
      }
    }
    let recorded = issues.withLock { $0 }
    #expect(recorded.count == 3)
    #expect(recorded.allSatisfy { $0.sourceLocation?.fileID == #fileID })
    #expect(recorded.map { $0.comments.map(\.rawValue) } == [
      ["fixture probe", "Rundown path: Assertions, reports a failed setup requirement, fixture setup"],
      ["fixture probe", "Rundown path: Assertions, reports failed example and cleanup requirements"],
      ["fixture probe", "Rundown path: Assertions, reports failed example and cleanup requirements, fixture cleanup"],
    ])
    #expect(events.withLock { $0 } == ["afterEachPeer", "afterEachPeer", "sibling", "afterEachPeer"])
  }

#if compiler(>=6.3)
  @Test func cancellationDuringSuccessfulSetupCleansUpWithoutStartingBody() async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())
    let fixture = AsyncFixture {
      await Task.yield()
      withUnsafeCurrentTask { $0?.cancel() }
      return 42
    } cleanup: { _ in events.withLock { $0.append("cleanup") } }
    try await Task {
      try await spec("Cancellation") {
        it("does not start after cancellation", using: fixture) { _ in Issue.record("Started body after cancellation") }
        it("does not start a sibling after cancellation") { Issue.record("Started sibling after cancellation") }
        afterEachPeer { events.withLock { $0.append("afterEachPeer") } }
      }
    }.value
    #expect(!Task.isCancelled)
    #expect(events.withLock { $0 } == ["cleanup", "afterEachPeer"])
  }

  @Test(arguments: [false, true])
  func cancellationUnwindsFixturesAndStopsLaterExamples(inSetup: Bool) async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())
    let fixture = AsyncFixture {
      await Task.yield()
      events.withLock { $0.append("setup") }
      if inSetup { try Test.cancel("No fixture available") }
      return 42
    } cleanup: { _ in
      await Task.yield()
      events.withLock { $0.append("cleanup") }
    }
    try await spec("Cancellation") {
      it("cancels the current example", using: fixture) { _ in
        events.withLock { $0.append("body") }
        try Test.cancel("Done with this case")
      }
      it("does not start after cancellation") { Issue.record("Started an example after cancellation") }
      afterEachPeer { events.withLock { $0.append("afterEachPeer") } }
      afterAll { events.withLock { $0.append("afterAll") } }
    }
    #expect(Task.isCancelled)
    let expected = (inSetup ? ["setup"] : ["setup", "body", "cleanup"]) + ["afterEachPeer", "afterAll"]
    #expect(events.withLock { $0 } == expected)
  }
#endif
}

@MainActor
private final class UIFixtureValue {
  var count = 0
}

struct MainActorFixtureSpecTests: MainActorSwiftTestingSuite {
  @Test func syncAndAsyncMainActorFixtures() async throws {
    var cleanups = 0
    let sync = MainActorFixture { UIFixtureValue() } cleanup: { value in
      MainActor.preconditionIsolated()
      #expect(value.count == 1)
      cleanups += 1
    }
    let async = AsyncMainActorFixture {
      await Task.yield()
      MainActor.preconditionIsolated()
      return UIFixtureValue()
    } cleanup: { value in
      await Task.yield()
      MainActor.preconditionIsolated()
      #expect(value.count == 1)
      cleanups += 1
    }
    try await spec("UI") {
      it("uses a synchronous main-actor fixture", using: sync) { value in value.count += 1 }
      it("uses an asynchronous main-actor fixture", using: async) { value in
        await Task.yield()
        MainActor.preconditionIsolated()
        value.count += 1
      }
    }
    #expect(cleanups == 2)
  }
}
