import os
import XCTest
@testable import Rundown

// Intentionally not Sendable: constructed values stay local to an execution.
private final class FixtureValue {
  var uses = 0
}

final class FixtureTests: XCTestCase {
  func testFreshValuesAcrossNestingAndRepeatedRuns() throws {
    let log = Box([String]())
    let fixture = Fixture {
      log.note("make")
      return FixtureValue()
    } cleanup: { value in
      XCTAssertEqual(value.uses, 1)
      log.note("cleanup")
    }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      beforeEachPeer { log.note("beforeEachPeer") }
      it("uses a fresh fixture", using: fixture) { value in
        XCTAssertEqual(value.uses, 0)
        value.uses += 1
        log.note("first")
      }
      context("nested") {
        for index in 0..<2 {
          it("uses a fresh fixture in nested example \(index)", using: fixture) { value in
            XCTAssertEqual(value.uses, 0)
            value.uses += 1
            log.note("inner \(index)")
          }
        }
      }
      afterEachPeer { log.note("afterEachPeer") }
    }
    XCTAssertEqual(log.wrappedValue, [], "Building the tree must not construct a fixture")
    try group.run()
    try group.run()
    let oneRun = ["beforeEachPeer", "make", "first", "cleanup", "afterEachPeer",
                  "beforeEachPeer", "make", "inner 0", "cleanup", "make", "inner 1", "cleanup", "afterEachPeer"]
    XCTAssertEqual(log.wrappedValue, oneRun + oneRun)
  }

  func testSelectionAndFailedEnclosingSetupDoNotConstructFixtures() throws {
    let count = Box(0)
    let fixture = Fixture { count.bump(); return 42 }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      it("does not run when unfocused", using: fixture) { _ in XCTFail("Unselected") }
      xIt("does not run when excluded", .focused, using: fixture) { _ in XCTFail("Excluded") }
      fIt("runs when focused", using: fixture) { XCTAssertEqual($0, 42) }
      context("blocked", .focused) {
        beforeEachPeer { throw TestError(id: 1) }
        it("does not start after enclosing setup fails", using: fixture) { _ in XCTFail("Blocked") }
      }
    }
    try group.node.run(with: RecordingReporter())
    XCTAssertEqual(count.wrappedValue, 1)
  }

  func testFactoryFailureSkipsBodyAndFixtureCleanupButRunsHooksAndSiblings() throws {
    let log = Box([String]())
    let fixture = Fixture<Int> { throw TestError(id: 1) } cleanup: { _ in
      XCTFail("No value was constructed")
    }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      aroundEachPeer { run in
        log.note("around start")
        try run()
        log.note("around end")
      }
      beforeEachPeer { log.note("beforeEachPeer") }
      it("reports a setup failure", using: fixture) { _ in XCTFail("Setup failed") }
      it("runs the next example") { log.note("sibling") }
      afterEachPeer { log.note("afterEachPeer") }
    }
    let reporter = RecordingReporter()
    try group.node.run(with: reporter)
    XCTAssertEqual(log.wrappedValue, ["around start", "beforeEachPeer", "afterEachPeer", "around end",
                                      "around start", "beforeEachPeer", "sibling", "afterEachPeer", "around end"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/reports a setup failure/fixture setup"])
  }

  func testBodyAndCleanupErrorsAreReportedSeparatelyAndFirstErrorPropagates() throws {
    let fixture = Fixture { 42 } cleanup: { _ in throw TestError(id: 2) }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      it("reports example and cleanup failures", using: fixture) { _ in throw TestError(id: 1) }
    }
    let reporter = RecordingReporter(decision: .propagate)
    XCTAssertThrowsError(try group.node.run(with: reporter)) { error in
      XCTAssertEqual(error as? TestError, TestError(id: 1))
    }
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/reports example and cleanup failures",
                    "failure Root/reports example and cleanup failures/fixture cleanup"])
  }

  func testCleanupFailureAfterSuccessPropagatesOriginalError() throws {
    let fixture = Fixture { 42 } cleanup: { _ in throw TestError(id: 2) }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      it("reports a cleanup failure", using: fixture) { XCTAssertEqual($0, 42) }
    }
    XCTAssertThrowsError(try group.run()) { error in
      XCTAssertEqual(error as? TestError, TestError(id: 2))
    }
  }

  func testSkipsInEveryPhaseRetainClassificationAndUnwind() throws {
    for phase in ["setup", "body", "cleanup"] {
      let log = Box([String]())
      let fixture = Fixture {
        log.note("setup")
        if phase == "setup" { throw RecordingReporter.TestSkip() }
        return 42
      } cleanup: { _ in
        log.note("cleanup")
        if phase == "cleanup" { throw RecordingReporter.TestSkip() }
      }
      let group: ExampleGroup<SyncCall> = describe("Root") {
        it("unwinds after a skip", using: fixture) { _ in
          log.note("body")
          if phase == "body" { throw RecordingReporter.TestSkip() }
        }
        it("runs the next example") { log.note("next") }
        afterEachPeer { log.note("afterEachPeer") }
      }
      let reporter = RecordingReporter(decision: .propagate)
      try group.node.run(with: reporter)
      let expected = (phase == "setup" ? ["setup"] : ["setup", "body", "cleanup"])
        + ["afterEachPeer", "next", "afterEachPeer"]
      XCTAssertEqual(log.wrappedValue, expected, phase)
      XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") }.count, 1, phase)
      XCTAssertFalse(reporter.events.contains { $0.hasPrefix("failure") }, phase)
    }
  }

  func testCleanupFailureIsNotHiddenByBodySkip() throws {
    let fixture = Fixture { 42 } cleanup: { _ in throw TestError(id: 2) }
    let group: ExampleGroup<SyncCall> = describe("Root") {
      it("reports a cleanup failure after a skip", using: fixture) { _ in throw RecordingReporter.TestSkip() }
    }
    XCTAssertThrowsError(try group.node.run(with: RecordingReporter(decision: .propagate))) { error in
      XCTAssertEqual(error as? TestError, TestError(id: 2))
    }
  }

  func testSyncFixturesSurviveConversionToAnAsyncGroup() async throws {
    let log = Box([String]())
    let fixture = Fixture { FixtureValue() } cleanup: { value in
      XCTAssertEqual(value.uses, 1)
      log.note("cleanup")
    }
    let sync: ExampleGroup<SyncCall> = describe("Root") {
      it("uses the constructed value", using: fixture) { $0.uses += 1 }
    }
    try await ExampleGroup<AsyncCall>(fromSync: sync).run()
    XCTAssertEqual(log.wrappedValue, ["cleanup"])
  }

  func testConcurrentAsyncFixturesKeepValuesAndPathsLocal() async throws {
    let paths = OSAllocatedUnfairLock(initialState: [String]())
    let fixture = AsyncFixture {
      await Task.yield()
      paths.withLock { $0.append(ExampleRunner.current!.description) }
      return FixtureValue()
    } cleanup: { value in
      await Task.yield()
      XCTAssertEqual(value.uses, 1)
      paths.withLock { $0.append(ExampleRunner.current!.description) }
    }
    let group: ExampleGroup<AsyncCall> = describe("Root", .concurrent) {
      for index in 0..<12 {
        it("uses a separate fixture for worker \(index)", using: fixture) { value in
          XCTAssertEqual(value.uses, 0)
          value.uses += 1
          await Task.yield()
          XCTAssertEqual(value.uses, 1)
          XCTAssertEqual(ExampleRunner.current?.description, "Root, uses a separate fixture for worker \(index)")
        }
      }
    }
    try await group.run()
    let expected = (0..<12).flatMap {
      ["Root, uses a separate fixture for worker \($0), fixture setup",
       "Root, uses a separate fixture for worker \($0), fixture cleanup"]
    }
    XCTAssertEqual(paths.withLock { $0.sorted() }, expected.sorted())
    XCTAssertNil(ExampleRunner.current)
  }

  func testAsyncSetupAndCleanupFailures() async throws {
    let log = Box([String]())
    let failingSetup = AsyncFixture<Int> {
      await Task.yield()
      throw TestError(id: 1)
    } cleanup: { _ in XCTFail("No constructed value") }
    let failingCleanup = AsyncFixture { 42 } cleanup: { _ in
      await Task.yield()
      log.note("cleanup")
      throw TestError(id: 3)
    }
    let group: ExampleGroup<AsyncCall> = describe("Root") {
      it("reports an asynchronous setup failure", using: failingSetup) { _ in XCTFail("Setup failed") }
      it("reports asynchronous example and cleanup failures", using: failingCleanup) { _ in
        await Task.yield()
        throw TestError(id: 2)
      }
      afterAll { log.note("afterAll") }
    }
    let reporter = RecordingReporter()
    try await group.node.run(with: reporter)
    XCTAssertEqual(log.wrappedValue, ["cleanup", "afterAll"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") }, [
      "failure Root/reports an asynchronous setup failure/fixture setup",
      "failure Root/reports asynchronous example and cleanup failures",
      "failure Root/reports asynchronous example and cleanup failures/fixture cleanup",
    ])
  }
}
