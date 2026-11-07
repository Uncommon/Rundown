import os
import RundownSwiftTesting
import Testing

struct CancellationTests: SwiftTestingSuite {
  @Test func cancellationInAConcurrentChildStopsTheRestOfTheSpec() async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    @Sendable func waitFor(_ event: String) async throws {
      let clock = ContinuousClock()
      let deadline = clock.now + .seconds(5)
      while !events.withLock({ $0.contains(event) }) && clock.now < deadline {
        try await clock.sleep(for: .milliseconds(1))
      }
      try #require(events.withLock { $0.contains(event) })
    }

    try await spec {
      context("concurrent group", .concurrent) {
        context("cancelling child") {
          it("cancels its task") {
            try await waitFor("sibling in flight")
            withUnsafeCurrentTask { $0?.cancel() }
            try Task.checkCancellation()
          }
          afterEach { events.withLock { $0.append("child afterEach") } }
          afterAll { events.withLock { $0.append("child afterAll") } }
        }
        it("finishes once already running") {
          events.withLock { $0.append("sibling in flight") }
          try await waitFor("child afterAll")
          #expect(!Task.isCancelled)
          events.withLock { $0.append("sibling finished") }
        }
        afterAll { events.withLock { $0.append("group afterAll") } }
      }
      it("never starts") { Issue.record("Started an example after cancellation") }
      afterAll { events.withLock { $0.append("root afterAll") } }
    }

    #expect(!Task.isCancelled)
    #expect(events.withLock { $0 } == [
      "sibling in flight", "child afterEach", "child afterAll", "sibling finished", "group afterAll", "root afterAll",
    ])
  }

#if compiler(>=6.3)
  @Test func cancellationInBeforeAllRunsAfterAll() throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try spec("Fixture setup") {
      beforeAll("open fixture") {
        let path = try #require(ExampleRunner.current?.description)
        events.withLock { $0.append(path) }
        try Test.cancel("Fixture unavailable at \(path)")
      }
      beforeAll { Issue.record("Started another setup hook after cancellation") }
      it("never starts") { Issue.record("Started an example after cancellation") }
      afterAll { events.withLock { $0.append("afterAll") } }
    }

    #expect(Task.isCancelled)
    #expect(events.withLock { $0 } == ["Fixture setup, before all: open fixture", "afterAll"])
  }

  @Test func cancellationInBeforeEachUnwindsEnclosingGroups() throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try spec("Example setup") {
      aroundEach { run in
        defer { events.withLock { $0.append("outer aroundEach cleanup") } }
        try run()
      }
      context("nested group") {
        beforeEach("open fixture") {
          let path = try #require(ExampleRunner.current?.description)
          events.withLock { $0.append(path) }
          try Test.cancel("Fixture unavailable at \(path)")
        }
        it("never starts") { Issue.record("Started an example after cancellation") }
        afterEach { events.withLock { $0.append("nested afterEach") } }
        afterAll { events.withLock { $0.append("nested afterAll") } }
      }
      it("never starts either") { Issue.record("Started a sibling after cancellation") }
      afterEach { events.withLock { $0.append("root afterEach") } }
      afterAll { events.withLock { $0.append("root afterAll") } }
    }

    #expect(Task.isCancelled)
    #expect(events.withLock { $0 } == [
      "Example setup, nested group, before each: open fixture",
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

  @Test(arguments: [false, true])
  func cancellationInTeardownOnlyStopsTheCurrentCase(cancel: Bool) async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())

    try await spec("Parameterized cleanup") {
      context("fixture") {
        it("runs") {
          await Task.yield()
          #expect(Test.Case.current?.isParameterized == true)
          events.withLock { $0.append("example") }
        }
        afterEach("cancel if needed") {
          if cancel {
            let path = try #require(ExampleRunner.current?.description)
            try Test.cancel("Cancel only this case at \(path)")
          }
        }
        afterEach { events.withLock { $0.append("remaining afterEach") } }
        afterAll { events.withLock { $0.append("group afterAll") } }
      }
      it("runs only in the active case") { events.withLock { $0.append("sibling") } }
      afterAll { events.withLock { $0.append("root afterAll") } }
    }

    #expect(Task.isCancelled == cancel)
    let expected = ["example", "remaining afterEach", "group afterAll"]
      + (cancel ? [] : ["sibling"]) + ["root afterAll"]
    #expect(events.withLock { $0 } == expected)
  }
#endif
}
