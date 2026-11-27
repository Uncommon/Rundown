import RundownSwiftTesting
import Testing

private final class Counter {
  var value = 0
}

@Suite(.rundownPaths)
struct CounterTests: SwiftTestingSuite {
  @Test func synchronousFixture() throws {
    let counter = Fixture { Counter() }
    try spec("Counter") {
      context("with a fresh fixture") {
        it("increments its value", using: counter) { counter in
          counter.value += 1
          #expect(counter.value == 1)
        }
        it("starts each example at zero", using: counter) { counter in
          #expect(counter.value == 0)
        }
      }
    }
  }

  @Test func asynchronousFixture() async throws {
    let counter = AsyncFixture {
      await Task.yield()
      return Counter()
    }
    try await spec("Async counter") {
      aroundEach { run in try await run() }
      it("increments after suspension", using: counter) { counter in
        await Task.yield()
        counter.value += 1
        #expect(counter.value == 1)
      }
    }
  }
}

@Suite(.rundownPaths)
struct MainActorCounterTests: MainActorSwiftTestingSuite {
  @Test func mainActorFixture() async throws {
    let counter = AsyncMainActorFixture { Counter() }
    try await spec("Main-actor counter") {
      it("increments on the main actor", using: counter) { counter in
        MainActor.assertIsolated()
        counter.value += 1
        #expect(counter.value == 1)
      }
    }
  }
}
