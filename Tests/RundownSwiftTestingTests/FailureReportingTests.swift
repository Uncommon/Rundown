import os
import RundownSwiftTesting
import Testing

struct FailureReportingTests: SwiftTestingSuite {
  private struct HookFailure: Error {}

  @Test func syncSpecRecordsHookFailuresAndContinuesTeardown() throws {
    let paths = OSAllocatedUnfairLock(initialState: [String]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())

    try withKnownIssue {
      try spec("Fixtures") {
        context("failed group setup") {
          beforeAll("open") { throw HookFailure() }
          beforeAll { Issue.record("Ran setup after a failing beforeAll") }
          it("never starts") { Issue.record("Ran an example after a failing beforeAll") }
          afterAll("close") { throw HookFailure() }
          afterAll { trace.withLock { $0.append("group teardown") } }
        }
        context("failed example setup") {
          aroundEach { run in
            defer { trace.withLock { $0.append("wrapper exit") } }
            try run()
          }
          beforeEach("open") { throw HookFailure() }
          beforeEach { Issue.record("Ran setup after a failing beforeEach") }
          it("never starts") { Issue.record("Ran an example after a failing beforeEach") }
          afterEach("close") { throw HookFailure() }
          afterEach { trace.withLock { $0.append("example teardown") } }
        }
        context("failed wrapper") {
          aroundEach("allocate") { _ in throw HookFailure() }
          beforeEach { Issue.record("Ran setup after a wrapper failed before its callback") }
          it("never starts") { Issue.record("Ran an example whose wrapper never called it") }
          afterEach { Issue.record("Tore down an element that was never entered") }
          afterAll { trace.withLock { $0.append("wrapper group teardown") } }
        }
        it("runs later") { trace.withLock { $0.append("sibling") } }
      }
    } matching: { issue in
      guard issue.error is HookFailure, let path = issue.comments.first?.rawValue,
            issue.comments.count == 1 else { return false }
      paths.withLock { $0.append(path) }
      return true
    }

    #expect(paths.withLock { $0 } == [
      "Fixtures, failed group setup, before all: open",
      "Fixtures, failed group setup, after all: close",
      "Fixtures, failed example setup, before each: open",
      "Fixtures, failed example setup, after each: close",
      "Fixtures, failed wrapper, around each: allocate",
    ])
    #expect(trace.withLock { $0 } == [
      "group teardown", "example teardown", "wrapper exit", "wrapper group teardown", "sibling",
    ])
  }

  @Test func asyncSpecRecordsChildAndWrapperFailuresSeparately() async throws {
    let paths = OSAllocatedUnfairLock(initialState: [String]())
    let trace = OSAllocatedUnfairLock(initialState: [String]())

    try await withKnownIssue {
      try await spec("Concurrent failures") {
        context("workers", .concurrent) {
          aroundEach("close") { run in
            try await run()
            throw HookFailure()
          }
          it("throws cancellation in an active task") {
            #expect(!Task.isCancelled)
            throw CancellationError()
          }
          it("throws after suspension") {
            await Task.yield()
            throw HookFailure()
          }
          afterEach { trace.withLock { $0.append("worker teardown") } }
          afterAll { trace.withLock { $0.append("group teardown") } }
        }
        it("runs after workers finish") { trace.withLock { $0.append("sibling") } }
      }
    } matching: { issue in
      guard let path = issue.comments.first?.rawValue, issue.comments.count == 1 else { return false }
      if path == "Concurrent failures, workers, throws cancellation in an active task" {
        guard issue.error is CancellationError else { return false }
      } else {
        guard issue.error is HookFailure else { return false }
      }
      paths.withLock { $0.append(path) }
      return true
    }

    #expect(paths.withLock { $0.sorted() } == [
      "Concurrent failures, workers, around each: close",
      "Concurrent failures, workers, around each: close",
      "Concurrent failures, workers, throws after suspension",
      "Concurrent failures, workers, throws cancellation in an active task",
    ])
    #expect(trace.withLock { $0 } == ["worker teardown", "worker teardown", "group teardown", "sibling"])
  }
}
