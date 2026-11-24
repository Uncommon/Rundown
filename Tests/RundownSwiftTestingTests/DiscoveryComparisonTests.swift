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
    aroundEachPeer { run in
      record("root aroundEachPeer enter")
      defer { record("root aroundEachPeer exit") }
      try await run()
    }
    beforeEachPeer { record("root beforeEachPeer") }
    generatedGroup(values: [1, 2])
    it("Independent example") { record("independent example") }
    afterEachPeer { record("root afterEachPeer") }
    afterAll { record("root afterAll") }
  }

  private func generatedGroup(values: [Int]) -> ExampleGroup<AsyncCall> {
    context("Generated group") {
      beforeAll { record("group beforeAll") }
      beforeEachPeer { record("group beforeEachPeer") }
      for value in values {
        if value.isMultiple(of: 2) {
          it("Repeated discovery label") {
            await Task.yield()
            record("async example \(value)")
            #expect(Bool(false), "Discovery fixture expectation")
          }
        }
        else {
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
      afterEachPeer { record("group afterEachPeer") }
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
      "root aroundEachPeer enter", "root beforeEachPeer", "group beforeAll",
      "group beforeEachPeer", "sync example 1", "group afterEachPeer",
      "group beforeEachPeer", "async example 2", "group afterEachPeer",
      "group beforeEachPeer", "required assertion", "group afterEachPeer",
      "group beforeEachPeer", "thrown error", "group afterEachPeer",
      "group afterAll", "root afterEachPeer", "root aroundEachPeer exit",
      "root aroundEachPeer enter", "root beforeEachPeer", "independent example",
      "root afterEachPeer", "root aroundEachPeer exit", "root afterAll",
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
      beforeEachPeer { self.record("group beforeEachPeer") }
      it("Suspending main-actor example") {
        await Task.yield()
        self.record("main-actor example")
      }
      afterEachPeer { self.record("group afterEachPeer") }
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
      "root beforeAll", "group beforeEachPeer", "main-actor example",
      "group afterEachPeer", "root afterAll",
    ])
  }
}
