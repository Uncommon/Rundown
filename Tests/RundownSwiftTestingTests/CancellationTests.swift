import os
import RundownSwiftTesting
import Testing

struct CancellationTests: SwiftTestingSuite {
  @Test func cancellationInAConcurrentChildStopsTheRestOfTheSpec() async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try await spec {
      context("concurrent group", .concurrent) {
        it("cancels its task") {
          withUnsafeCurrentTask { $0?.cancel() }
          try Task.checkCancellation()
        }
        afterEach { events.withLock { $0.append("child afterEach") } }
        afterAll { events.withLock { $0.append("group afterAll") } }
      }
      it("never starts") { Issue.record("Started an example after cancellation") }
      afterAll { events.withLock { $0.append("root afterAll") } }
    }

    #expect(!Task.isCancelled)
    #expect(events.withLock { $0 } == ["child afterEach", "group afterAll", "root afterAll"])
  }

#if compiler(>=6.3)
  @Test func cancellationInBeforeAllRunsAfterAll() throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try spec {
      beforeAll { try Test.cancel("Cancel in beforeAll") }
      beforeAll { Issue.record("Started another setup hook after cancellation") }
      it("never starts") { Issue.record("Started an example after cancellation") }
      afterAll { events.withLock { $0.append("afterAll") } }
    }

    #expect(events.withLock { $0 } == ["afterAll"])
  }

  @Test func cancellationInBeforeEachUnwindsEnclosingGroups() throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try spec {
      aroundEach { run in
        defer { events.withLock { $0.append("outer aroundEach cleanup") } }
        try run()
      }
      context("nested group") {
        beforeEach { try Test.cancel("Cancel in beforeEach") }
        it("never starts") { Issue.record("Started an example after cancellation") }
        afterEach { events.withLock { $0.append("nested afterEach") } }
        afterAll { events.withLock { $0.append("nested afterAll") } }
      }
      it("never starts either") { Issue.record("Started a sibling after cancellation") }
      afterEach { events.withLock { $0.append("root afterEach") } }
      afterAll { events.withLock { $0.append("root afterAll") } }
    }

    #expect(events.withLock { $0 } == [
      "nested afterEach", "nested afterAll", "root afterEach",
      "outer aroundEach cleanup", "root afterAll",
    ])
  }

  @Test func cancellationInAnAsyncAroundEachStopsLaterExamples() async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try await spec {
      aroundEach { run in
        try await run()
        try Test.cancel("Cancel after the wrapped example")
      }
      it("runs") { events.withLock { $0.append("example") } }
      it("never starts") { Issue.record("Started a sibling after cancellation") }
      afterEach { events.withLock { $0.append("afterEach") } }
      afterAll { events.withLock { $0.append("afterAll") } }
    }

    #expect(events.withLock { $0 } == ["example", "afterEach", "afterAll"])
  }
#endif
}
