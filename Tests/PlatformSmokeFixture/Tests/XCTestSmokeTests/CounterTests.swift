import Rundown
import XCTest

@MainActor
private final class Counter {
  var value = 0
}

final class CounterTests: Rundown.TestCase {
  @MainActor
  func testSynchronousFixture() throws {
    let counter = MainActorFixture { Counter() }
    try spec("Counter") {
      context("with a fresh fixture") {
        aroundEach { run in try run() }
        it("increments its value", using: counter) { counter in
          counter.value += 1
          XCTAssertEqual(counter.value, 1)
        }
        it("starts each example at zero", using: counter) { counter in
          XCTAssertEqual(counter.value, 0)
        }
      }
    }
  }

  @MainActor
  func testAsynchronousFixture() async throws {
    let counter = AsyncMainActorFixture {
      await Task.yield()
      return Counter()
    }
    try await spec("Async counter") {
      it("increments after suspension", using: counter) { counter in
        await Task.yield()
        counter.value += 1
        XCTAssertEqual(counter.value, 1)
      }
    }
  }
}
