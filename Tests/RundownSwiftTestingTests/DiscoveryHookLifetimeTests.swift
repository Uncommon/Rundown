#if os(macOS) && compiler(>=6.4)
import os
import RundownSwiftTesting
import Testing

@Spec
struct DiscoveryHookLifetimeSpec {
  @TaskLocal private static var insideEach = false
  private let trace = OSAllocatedUnfairLock(initialState: [String]())

  var spec: ExampleGroup<AsyncCall> {
    beforeAll { record("root beforeAll") }
    aroundEach { run in
      record("root aroundEach enter")
      defer { record("root aroundEach exit") }
      try await Self.$insideEach.withValue(true) { try await run() }
    }
    beforeEach { record("root beforeEach") }
    context("Nested") {
      beforeAll { record("nested beforeAll") }
      beforeEach { record("nested beforeEach") }
      it("First") { record("first") }
      it("Second") { record("second") }
      afterEach { record("nested afterEach") }
      afterAll { record("nested afterAll") }
    }
    it("Tail") { record("tail") }
    afterEach { record("root afterEach") }
    afterAll {
      record("root afterAll")
      let events = trace.withLock { $0 }
      print("discovery hook trace: \(events.joined(separator: " | "))")
      let nested = events.filter { $0.hasPrefix("nested ") || $0 == "first" || $0 == "second" }
      let nestedTrace = ["nested beforeAll", "nested beforeEach", "first", "nested afterEach",
                         "nested beforeEach", "second", "nested afterEach", "nested afterAll"]
      let nestedRuns = nested.count / nestedTrace.count
      #expect(nested == Array(repeating: nestedTrace, count: nestedRuns).flatMap { $0 })
      let caseCount = nestedRuns + events.filter { $0 == "tail" }.count
      #expect(caseCount > 0)
      #expect(events.first == "root beforeAll")
      #expect(events.last == "root afterAll")
      for event in ["root aroundEach enter", "root beforeEach", "root afterEach", "root aroundEach exit"] {
        #expect(events.filter { $0 == event }.count == caseCount)
      }
      #expect(events.filter { $0 == "root afterAll" }.count == 1)
    }
  }

  private func record(_ event: String) {
    trace.withLock { events in
      if event != "root beforeAll" {
        #expect(events.filter { $0 == "root beforeAll" }.count == 1)
      }
      if event.hasPrefix("nested ") || ["first", "second", "tail"].contains(event) {
        #expect(Self.insideEach)
      }
      events.append(event)
    }
  }
}

struct DiscoveryHookLifetimeTests: SwiftTestingSuite {
  @Test func hostHookTrace() async throws {
    try await spec("DiscoveryHookLifetimeSpec") { return DiscoveryHookLifetimeSpec().spec }
  }
}

private struct DiscoverySetupFailure: Error {}

@ExampleBuilder<AsyncCall>
private func interruptedSetup(cancel: Bool) -> ExampleGroup<AsyncCall> {
  beforeAll("open") {
    if cancel { try Test.cancel("Discovery fixture unavailable") }
    throw DiscoverySetupFailure()
  }
  beforeAll { Issue.record("Ran setup after interruption") }
  it("Unreachable") { Issue.record("Ran a case after interrupted setup") }
  afterAll {
    print("discovery interrupted setup teardown: cancelled=\(Task.isCancelled)")
    #expect(Task.isCancelled == cancel)
  }
}

private struct ExpectDiscoverySetupFailure: SuiteTrait, TestScoping {
  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    try await withKnownIssue {
      try await function()
    } matching: { issue in
      issue.error is DiscoverySetupFailure && issue.comments.contains("FailingSetup, before all: open")
    }
  }
}

@Suite(ExpectDiscoverySetupFailure())
struct DiscoveryHookFailureTests {
  @Spec
  struct FailingSetup {
    var spec: ExampleGroup<AsyncCall> { return interruptedSetup(cancel: false) }
  }
}

@Spec
struct DiscoveryHookCancellationSpec {
  var spec: ExampleGroup<AsyncCall> { return interruptedSetup(cancel: true) }
}

@Spec
struct DiscoveryHookEmptySpec {
  var spec: ExampleGroup<AsyncCall> {
    beforeAll { Issue.record("Ran setup for an empty spec") }
    xIt("Excluded") { Issue.record("Ran an excluded case") }
    afterAll { Issue.record("Ran teardown for an empty spec") }
  }
}
#endif
