import XCTest
@testable import Rundown

/// Error handling in the main actor versions of the plain and async runners,
/// which the runner matrix in `MultiRunTests` doesn't reach.
@MainActor
final class MainActorErrorTests: Rundown.TestCase {
  func testSyncRunnerRunsTeardownAndContinues() throws {
    for scenario in MultiRunTests.errorScenarios() {
      let group = ExampleGroup<SyncMainCall>(fromSync: scenario.group)

      XCTAssertThrowsError(try group.run(), scenario.name) { error in
        XCTAssertEqual(error as? TestError, TestError(id: 1), scenario.name)
      }
      XCTAssertEqual(scenario.log.wrappedValue, scenario.expectedLog, scenario.name)
    }
  }

  func testAsyncRunnerRunsTeardownAndContinues() async throws {
    let log = Box([String]())
    let group: ExampleGroup<AsyncMainCall> = describe("async main") {
      beforeAll { log.note("beforeAll") }
      beforeEach { log.note("beforeEach") }
      it("fails") {
        await Task.yield()
        log.note("fails")
        throw TestError(id: 1)
      }
      it("passes") { log.note("passes") }
      afterEach { log.note("afterEach") }
      // Async on purpose: a sync afterAll can't follow a sync afterEach in an
      // async group, because the builder doesn't promote it.
      afterAll {
        await Task.yield()
        log.note("afterAll")
      }
    }

    do {
      try await group.run()
      XCTFail("no error thrown")
    }
    catch let error as TestError {
      XCTAssertEqual(error, TestError(id: 1))
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeAll", "beforeEach", "fails", "afterEach",
                    "beforeEach", "passes", "afterEach", "afterAll"])
  }

  func testAsyncRunnerRunsAfterAllWhenBeforeAllThrows() async throws {
    let log = Box([String]())
    let group: ExampleGroup<AsyncMainCall> = describe("async main") {
      beforeAll {
        await Task.yield()
        log.note("beforeAll")
        throw TestError(id: 1)
      }
      beforeEach { log.note("beforeEach") }
      it("never runs") { log.note("never runs") }
      afterAll { log.note("afterAll") }
    }

    do {
      try await group.run()
      XCTFail("no error thrown")
    }
    catch let error as TestError {
      XCTAssertEqual(error, TestError(id: 1))
    }
    XCTAssertEqual(log.wrappedValue, ["beforeAll", "afterAll"])
  }

  /// Main actor groups can't be concurrent. That has to be reported before
  /// anything runs, since a hook that has already run would never get its
  /// matching teardown.
  func testConcurrentIsRejectedBeforeAnyHookRuns() async throws {
    let log = Box([String]())
    let syncGroup: ExampleGroup<SyncMainCall> = describe("sync", .concurrent) {
      beforeAll { log.note("beforeAll") }
      it("never runs") { log.note("it") }
      afterAll { log.note("afterAll") }
    }
    let asyncGroup: ExampleGroup<AsyncMainCall> = describe("async", .concurrent) {
      beforeAll { log.note("beforeAll") }
      it("never runs") { await Task.yield(); log.note("it") }
      afterAll { log.note("afterAll") }
    }

    XCTAssertThrowsError(try syncGroup.run()) {
      XCTAssert($0 is ConcurrentDisallowedError, "sync: \($0)")
    }
    do {
      try await asyncGroup.run()
      XCTFail("async: no error thrown")
    }
    catch {
      XCTAssert(error is ConcurrentDisallowedError, "async: \(error)")
    }
    XCTAssertEqual(log.wrappedValue, [])
  }
}
