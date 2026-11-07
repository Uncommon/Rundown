import os
import RundownSwiftTesting
import Testing

struct SwiftTestingSuiteTests: SwiftTestingSuite {
  @Test func testSyncSpecPreservesHostContext() throws {
    let host = try #require(Test.current?.id)
    let order = OSAllocatedUnfairLock(initialState: [Int]())

    try spec {
      context("concurrent group", .concurrent) {
        for index in 0..<8 {
          it("example \(index)") {
            #expect(Test.current?.id == host)
            #expect(ExampleRunner.current?.path == [
              "SyncSpecPreservesHostContext", "concurrent group", "example \(index)",
            ])
            order.withLock { $0.append(index) }
          }
        }
      }
    }

    #expect(order.withLock { $0 } == Array(0..<8))
  }

  @Test func testAsyncSpecPreservesConcurrentHostContext() async throws {
    let host = try #require(Test.current?.id)
    let started = OSAllocatedUnfairLock(initialState: 0)
    let clock = ContinuousClock()

    try await spec {
      context("concurrent group", .concurrent) {
        for index in 0..<2 {
          it("example \(index)") {
            #expect(Test.current?.id == host)
            #expect(ExampleRunner.current?.path == [
              "AsyncSpecPreservesConcurrentHostContext", "concurrent group", "example \(index)",
            ])

            // Both examples must start before either returns.
            started.withLock { $0 += 1 }
            let deadline = clock.now + .seconds(5)
            while started.withLock({ $0 }) < 2 && clock.now < deadline {
              try await clock.sleep(for: .milliseconds(1))
            }
            #expect(started.withLock { $0 } == 2)
          }
        }
      }
    }

    #expect(started.withLock { $0 } == 2)
  }

  @Test func asyncSpecRunsInATaskWithoutHostContext() async throws {
    let path = OSAllocatedUnfairLock(initialState: [String]())

    try await Task.detached {
      try await spec("Detached spec") {
        it("runs") {
          await Task.yield()
          path.withLock { $0 = ExampleRunner.current?.path ?? [] }
        }
      }
    }.value

    #expect(path.withLock { $0 } == ["Detached spec", "runs"])
  }
}
