import RundownSwiftTesting
import Testing

@MainActor
private final class SpecLog {
  private(set) var entries: [String] = []

  func append(_ entry: String) {
    MainActor.preconditionIsolated()
    entries.append(entry)
  }
}

private struct MainActorSpecFailure: Error {}

struct MainActorSpecTests: MainActorSwiftTestingSuite {
  @Test func testSyncSpec() throws {
    MainActor.preconditionIsolated()
    let log = SpecLog()

    try withKnownIssue {
      try spec {
        beforeAll { log.append("beforeAll") }
        aroundEachPeer { run in
          log.append("aroundEachPeer start")
          try run()
          log.append("aroundEachPeer end")
        }
        beforeEachPeer { log.append("beforeEachPeer") }
        context("nested") {
          it("throws") {
            log.append("example")
            throw MainActorSpecFailure()
          }
        }
        afterEachPeer { log.append("afterEachPeer") }
        afterAll { log.append("afterAll") }
      }
    } matching: { issue in
      issue.error is MainActorSpecFailure
        && issue.comments.map(\.rawValue) == ["SyncSpec, nested, throws"]
    }

    #expect(log.entries == [
      "beforeAll", "aroundEachPeer start", "beforeEachPeer", "example", "afterEachPeer",
      "aroundEachPeer end", "afterAll",
    ])
  }

  @Test func testAsyncSpec() async throws {
    MainActor.preconditionIsolated()
    let log = SpecLog()

    try await withKnownIssue {
      try await spec {
        let _ = MainActor.preconditionIsolated()
        beforeAll {
          await Task.yield()
          log.append("beforeAll")
        }
        aroundEachPeer { run in
          log.append("aroundEachPeer start")
          try await run()
          log.append("aroundEachPeer end")
        }
        beforeEachPeer { log.append("beforeEachPeer") }
        context("nested") {
          it("throws") {
            await Task.yield()
            log.append("example")
            throw MainActorSpecFailure()
          }
        }
        afterEachPeer { log.append("afterEachPeer") }
        afterAll { log.append("afterAll") }
      }
    } matching: { issue in
      issue.error is MainActorSpecFailure
        && issue.comments.map(\.rawValue) == ["AsyncSpec, nested, throws"]
    }

    #expect(log.entries == [
      "beforeAll", "aroundEachPeer start", "beforeEachPeer", "example", "afterEachPeer",
      "aroundEachPeer end", "afterAll",
    ])
  }

  @Test func namedSyncSpecSerializesMainActorConcurrentGroups() throws {
    let host = try #require(Test.current?.id)
    let log = SpecLog()

    try spec("Main actor fixtures") {
      let _ = MainActor.preconditionIsolated()
      context("serial workers", .concurrent) {
        beforeEachPeer { log.append("setup") }
        for index in 0..<3 {
          it("worker \(index)") {
            #expect(Test.current?.id == host)
            #expect(ExampleRunner.current?.path == ["Main actor fixtures", "serial workers", "worker \(index)"])
            log.append("worker \(index)")
          }
        }
        afterEachPeer { log.append("teardown") }
      }
    }

    #expect(log.entries == ["setup", "worker 0", "teardown", "setup", "worker 1", "teardown",
                            "setup", "worker 2", "teardown"])
  }

  @Test func namedAsyncSpecRejectsMainActorConcurrentGroupsBeforeTheirHooks() async throws {
    let log = SpecLog()

    do {
      try await spec("Main actor fixtures") {
        beforeEachPeer { log.append("root setup") }
        context("invalid workers", .concurrent) {
          beforeAll { Issue.record("Set up an invalid concurrent group") }
          it("never starts") {
            await Task.yield()
            Issue.record("Ran an example in an invalid concurrent group")
          }
          afterAll { Issue.record("Tore down an invalid concurrent group") }
        }
        it("valid sibling") { log.append("sibling") }
        afterEachPeer { log.append("root element teardown") }
        afterAll { log.append("root teardown") }
      }
      Issue.record("Expected ConcurrentDisallowedError from the spec")
    } catch is ConcurrentDisallowedError {
      #expect(log.entries == ["root setup", "root element teardown", "root setup", "sibling",
                              "root element teardown", "root teardown"])
    }
  }
}
