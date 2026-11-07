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

  @Test func asyncSpec() async throws {
    MainActor.preconditionIsolated()
    let log = SpecLog()

    try await withKnownIssue {
      try await spec("Async main actor") {
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
        && issue.comments.map(\.rawValue) == ["Async main actor, nested, throws"]
    }

    #expect(log.entries == [
      "beforeAll", "aroundEach start", "beforeEach", "example", "afterEach",
      "aroundEach end", "afterAll",
    ])
  }
}
