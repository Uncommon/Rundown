import os
import RundownSwiftTesting
import Testing

struct DiscoveryComparisonFixture: Sendable {
  struct ExampleFailure: Error {}

  private let log = OSAllocatedUnfairLock(initialState: [String]())

  var trace: [String] { log.withLock { $0 } }

  @ExampleBuilder<AsyncCall>
  func build() -> ExampleGroup<AsyncCall> {
    beforeAll { record("root beforeAll") }
    aroundEach { run in
      record("root aroundEach enter")
      defer { record("root aroundEach exit") }
      try await run()
    }
    beforeEach { record("root beforeEach") }
    generatedGroup(values: [1, 2])
    it("Independent example") { record("independent example") }
    afterEach { record("root afterEach") }
    afterAll { record("root afterAll") }
  }

  private func generatedGroup(values: [Int]) -> ExampleGroup<AsyncCall> {
    context("Generated group") {
      beforeAll { record("group beforeAll") }
      beforeEach { record("group beforeEach") }
      for value in values {
        if value.isMultiple(of: 2) {
          it("Repeated discovery label") {
            await Task.yield()
            record("async example \(value)")
            #expect(Bool(false), "Discovery fixture expectation")
          }
        } else {
          let example: It<SyncCall> = it("Repeated discovery label") {
            record("sync example \(value)")
          }
          example
        }
      }
      it("Required assertion") {
        record("required assertion")
        try #require(Bool(false), "Discovery fixture requirement")
      }
      it("Thrown error") {
        record("thrown error")
        throw ExampleFailure()
      }
      afterEach { record("group afterEach") }
      afterAll { record("group afterAll") }
    }
  }

  private func record(_ event: String) {
    log.withLock { $0.append(event) }
  }
}

struct DiscoveryComparisonTests: SwiftTestingSuite {
  @Test func hostAdapterBaseline() async throws {
    let fixture = DiscoveryComparisonFixture()
    let issues = OSAllocatedUnfairLock(initialState: 0)

    try await withKnownIssue {
      try await spec("Discovery comparison", builder: fixture.build)
    } matching: { issue in
      let matches = issue.error is DiscoveryComparisonFixture.ExampleFailure
        || issue.comments.contains { comment in
          comment.rawValue == "Discovery fixture expectation"
            || comment.rawValue == "Discovery fixture requirement"
        }
      if matches { issues.withLock { $0 += 1 } }
      return matches
    }

    #expect(issues.withLock { $0 } == 3)
    #expect(fixture.trace == [
      "root beforeAll",
      "root aroundEach enter", "root beforeEach", "group beforeAll",
      "group beforeEach", "sync example 1", "group afterEach",
      "group beforeEach", "async example 2", "group afterEach",
      "group beforeEach", "required assertion", "group afterEach",
      "group beforeEach", "thrown error", "group afterEach",
      "group afterAll", "root afterEach", "root aroundEach exit",
      "root aroundEach enter", "root beforeEach", "independent example",
      "root afterEach", "root aroundEach exit", "root afterAll",
    ])
  }
}

@MainActor
final class MainActorDiscoveryComparisonFixture: MainActorSuite {
  private(set) var trace: [String] = []

  @ExampleBuilder<AsyncMainCall>
  func build() -> ExampleGroup<AsyncMainCall> {
    let _ = MainActor.preconditionIsolated()
    beforeAll { self.record("root beforeAll") }
    context("Isolated group") {
      beforeEach { self.record("group beforeEach") }
      it("Suspending main-actor example") {
        await Task.yield()
        self.record("main-actor example")
      }
      afterEach { self.record("group afterEach") }
    }
    afterAll { self.record("root afterAll") }
  }

  private func record(_ event: String) {
    MainActor.preconditionIsolated()
    trace.append(event)
  }
}

struct MainActorDiscoveryComparisonTests: MainActorSwiftTestingSuite {
  @Test func mainActorBaseline() async throws {
    let fixture = MainActorDiscoveryComparisonFixture()

    try await spec("Main-actor discovery comparison", builder: fixture.build)

    #expect(fixture.trace == [
      "root beforeAll", "group beforeEach", "main-actor example",
      "group afterEach", "root afterAll",
    ])
  }
}
