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
        aroundEach { run in
          log.append("aroundEach start")
          try run()
          log.append("aroundEach end")
        }
        beforeEach { log.append("beforeEach") }
        context("nested") {
          it("throws") {
            log.append("example")
            throw MainActorSpecFailure()
          }
        }
        afterEach { log.append("afterEach") }
        afterAll { log.append("afterAll") }
      }
    } matching: { issue in
      issue.error is MainActorSpecFailure
        && issue.comments.map(\.rawValue) == ["SyncSpec, nested, throws"]
    }

    #expect(log.entries == [
      "beforeAll", "aroundEach start", "beforeEach", "example", "afterEach",
      "aroundEach end", "afterAll",
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
        aroundEach { run in
          log.append("aroundEach start")
          try await run()
          log.append("aroundEach end")
        }
        beforeEach { log.append("beforeEach") }
        context("nested") {
          it("throws") {
            await Task.yield()
            log.append("example")
            throw MainActorSpecFailure()
          }
        }
        afterEach { log.append("afterEach") }
        afterAll { log.append("afterAll") }
      }
    } matching: { issue in
      issue.error is MainActorSpecFailure
        && issue.comments.map(\.rawValue) == ["AsyncSpec, nested, throws"]
    }

    #expect(log.entries == [
      "beforeAll", "aroundEach start", "beforeEach", "example", "afterEach",
      "aroundEach end", "afterAll",
    ])
  }

  @Test func namedSyncSpecSerializesMainActorConcurrentGroups() throws {
    let host = try #require(Test.current?.id)
    let log = SpecLog()

    try spec("Main actor fixtures") {
      let _ = MainActor.preconditionIsolated()
      context("serial workers", .concurrent) {
        beforeEach { log.append("setup") }
        for index in 0..<3 {
          it("worker \(index)") {
            #expect(Test.current?.id == host)
            #expect(ExampleRunner.current?.path == ["Main actor fixtures", "serial workers", "worker \(index)"])
            log.append("worker \(index)")
          }
        }
        afterEach { log.append("teardown") }
      }
    }

    #expect(log.entries == ["setup", "worker 0", "teardown", "setup", "worker 1", "teardown",
                            "setup", "worker 2", "teardown"])
  }

  @Test func namedAsyncSpecRejectsMainActorConcurrentGroupsBeforeTheirHooks() async throws {
    let log = SpecLog()

    do {
      try await spec("Main actor fixtures") {
        beforeEach { log.append("root setup") }
        context("invalid workers", .concurrent) {
          beforeAll { Issue.record("Set up an invalid concurrent group") }
          it("never starts") {
            await Task.yield()
            Issue.record("Ran an example in an invalid concurrent group")
          }
          afterAll { Issue.record("Tore down an invalid concurrent group") }
        }
        it("valid sibling") { log.append("sibling") }
        afterEach { log.append("root element teardown") }
        afterAll { log.append("root teardown") }
      }
      Issue.record("Expected ConcurrentDisallowedError from the spec")
    } catch is ConcurrentDisallowedError {
      #expect(log.entries == ["root setup", "root element teardown", "root setup", "sibling",
                              "root element teardown", "root teardown"])
    }
  }
}
