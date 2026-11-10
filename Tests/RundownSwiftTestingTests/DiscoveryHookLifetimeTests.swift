#if canImport(Darwin) && compiler(>=6.4)
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
      it("First") {
        await Task.yield()
        record("first")
      }
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
      let nestedTrace = ["nested beforeAll", "nested beforeEach", "first", "nested afterEach",
                         "nested beforeEach", "second", "nested afterEach", "nested afterAll"]
      let children = Array(repeating: nestedTrace, count: events.filter { $0 == "first" }.count)
        + Array(repeating: ["tail"], count: events.filter { $0 == "tail" }.count)
      let wrappedChildren = children.flatMap {
        ["root aroundEach enter", "root beforeEach"] + $0 + ["root afterEach", "root aroundEach exit"]
      }
      #expect(!children.isEmpty)
      #expect(events == ["root beforeAll"] + wrappedChildren + ["root afterAll"])
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

private struct ExpectDiscoveryHookIssue: SuiteTrait, TestScoping {
  let matches: @Sendable (Issue) -> Bool

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    try await withKnownIssue {
      try await function()
    } matching: { matches($0) }
  }
}

@Suite(ExpectDiscoveryHookIssue { issue in
  issue.error is DiscoverySetupFailure && issue.comments.contains("FailingSetup, before all: open")
})
struct DiscoveryHookFailureTests {
  @Spec
  struct FailingSetup {
    var spec: ExampleGroup<AsyncCall> { return interruptedSetup(cancel: false) }
  }
}

@Suite(ExpectDiscoveryHookIssue { issue in
  guard case .expectationFailed = issue.kind else { return false }
  return issue.comments.contains("Intentional discovery teardown failure")
})
@Spec
struct DiscoveryHookTeardownSpec {
  var spec: ExampleGroup<AsyncCall> {
    it("First") {}
    it("Second") {}
    afterAll("close") {
      #expect(Bool(false), "Intentional discovery teardown failure")
    }
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
