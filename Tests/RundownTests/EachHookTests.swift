import XCTest
@testable import Rundown

extension MultiRunTests {
  func testEachHooksFollowExamplesThroughMultipleLevels() async throws {
    try await useAllRunners { runner, type in
      let log = Box([String]())
      let group = describe("root") {
        beforeAll { log.note("root all>") }
        beforeEach { log.note("root before 1") }
        beforeEach { log.note("root before 2") }
        context("nested") {
          beforeAll { log.note("nested all>") }
          beforeEach { log.note("nested before") }
          it("runs inherited hooks around a nested example") { log.note("one") }
          context("deeper") {
            beforeAll { log.note("deeper all>") }
            it("inherits hooks through multiple nested groups") { log.note("two") }
            afterAll { log.note("<deeper all") }
          }
          afterEach { log.note("nested after") }
          afterAll { log.note("<nested all") }
        }
        it("runs only the hooks of its enclosing group") { log.note("sibling") }
        afterEach { log.note("root after 1") }
        afterEach { log.note("root after 2") }
        afterAll { log.note("<root all") }
      }
      try await runner(group)
      XCTAssertEqual(log.wrappedValue, [
        "root all>", "nested all>",
        "root before 1", "root before 2", "nested before", "one",
        "nested after", "root after 1", "root after 2",
        "deeper all>", "root before 1", "root before 2", "nested before", "two",
        "nested after", "root after 1", "root after 2", "<deeper all", "<nested all",
        "root before 1", "root before 2", "sibling", "root after 1", "root after 2", "<root all",
      ], type)
    }
  }

  func testEachWrappersNestInsidePeerLifecycles() throws {
    try useSyncRunners { runner, type in
      let log = Box([String]())
      let group = describe("root") {
        aroundEach { run in
          log.note("root each>")
          defer { log.note("<root each") }
          try run()
        }
        aroundEachPeer { run in
          log.note("peer>")
          defer { log.note("<peer") }
          try run()
        }
        beforeEach { log.note("root before") }
        beforeEachPeer { log.note("peer before") }
        context("nested") {
          beforeAll { log.note("nested all>") }
          aroundEach { run in
            log.note("nested each>")
            defer { log.note("<nested each") }
            try run()
          }
          beforeEachPeer { log.note("nested peer before") }
          beforeEach { log.note("nested before") }
          it("runs inside inherited wrappers and peer hooks") { log.note("one") }
          it("gets a separate inherited wrapper lifecycle") { log.note("two") }
          afterEachPeer { log.note("nested peer after") }
          afterEach { log.note("nested after") }
          afterAll { log.note("<nested all") }
        }
        afterEach { log.note("root after") }
        afterEachPeer { log.note("peer after") }
      }
      try runner(group)
      let first = ["nested peer before", "root each>", "nested each>",
                   "root before", "nested before", "one", "nested after", "root after",
                   "<nested each", "<root each", "nested peer after"]
      let second = first.map { $0 == "one" ? "two" : $0 }
      XCTAssertEqual(log.wrappedValue,
                     ["peer>", "peer before", "nested all>"] + first + second
                       + ["<nested all", "peer after", "<peer"], type)
    }
  }

  func testEachHooksRespectSelectionAndDoNotRunForEmptyGroups() async throws {
    try await useAllRunners { runner, type in
      let log = Box([String]())
      let group = describe("root") {
        beforeEach("excluded", .excluded) { XCTFail("Excluded hook") }
        beforeEach { log.note("before") }
        context("unfocused") { it("does not run when another group is focused") { XCTFail("Unfocused example") } }
        xContext("excluded", .focused) { it("does not run in an excluded group") { XCTFail("Excluded group") } }
        fContext("selected") {
          context("empty") { xIt("does not run when excluded") { XCTFail("Excluded example") } }
          it("runs inherited hooks for the selected example") { log.note("one") }
        }
        afterEach { log.note("after") }
        afterEach("excluded", .excluded) { XCTFail("Excluded cleanup") }
      }
      try await runner(group)
      XCTAssertEqual(log.wrappedValue, ["before", "one", "after"], type)
    }
  }
}

final class EachHookFailureTests: XCTestCase {
  func testFailingAncestorSetupStillRunsAllExampleCleanupAndLaterExamples() throws {
    let log = Box([String]())
    let group: ExampleGroup<SyncCall> = describe("root") {
      beforeEach { log.note("root before"); throw TestError(id: 1) }
      context("nested") {
        beforeAll { log.note("nested all>") }
        beforeEach { XCTFail("Setup after failure") }
        it("is skipped when inherited setup fails") { XCTFail("Example after failure") }
        it("is skipped when the next setup attempt fails") { XCTFail("Example after failure") }
        afterEach { log.note("nested after"); throw TestError(id: 2) }
        afterAll { log.note("<nested all") }
      }
      afterEach { log.note("root after") }
    }
    let reporter = RecordingReporter(decision: .propagate)
    XCTAssertThrowsError(try group.node.run(with: reporter)) {
      XCTAssertEqual($0 as? TestError, TestError(id: 1))
    }
    XCTAssertEqual(log.wrappedValue, ["nested all>", "root before", "nested after", "root after",
                                      "root before", "nested after", "root after", "<nested all"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") }, [
      "failure root/nested/before each", "failure root/nested/after each",
      "failure root/nested/before each", "failure root/nested/after each",
    ])
  }

  func testSkipInInheritedSetupRunsCleanupAndUnwindsWrappers() throws {
    let log = Box([String]())
    let group: ExampleGroup<SyncCall> = describe("root") {
      aroundEach { run in
        log.note("around>")
        defer { log.note("<around") }
        try run()
      }
      beforeEach { log.note("before"); throw RecordingReporter.TestSkip() }
      context("nested") {
        it("is skipped when inherited setup requests a skip") { XCTFail("Skipped") }
        it("gets its own setup attempt before being skipped") { XCTFail("Skipped") }
        afterEach { log.note("nested after") }
      }
      afterEach { log.note("root after") }
    }
    let reporter = RecordingReporter(decision: .propagate)
    try group.node.run(with: reporter)
    let one = ["around>", "before", "nested after", "root after", "<around"]
    XCTAssertEqual(log.wrappedValue, one + one)
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") }.count, 2)
  }

  func testAroundFailureIsReportedOnceAndDoesNotEnterExampleHooks() throws {
    let group: ExampleGroup<SyncCall> = describe("root") {
      aroundEach("outer") { run in try run() }
      aroundEach("fails") { _ in throw TestError(id: 1) }
      beforeEach { XCTFail("Wrapper did not enter") }
      context("nested") { it("does not start when an inherited wrapper fails") { XCTFail("Wrapper did not enter") } }
      afterEach { XCTFail("Wrapper did not enter") }
    }
    let reporter = RecordingReporter(decision: .propagate)
    XCTAssertThrowsError(try group.node.run(with: reporter))
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure root/nested/around each: fails"])
  }
}

extension ExecutionTests {
  func testAsyncMainActorEachHooksAreInherited() async throws {
    let log = Box([String]())
    try await spec("main actor") {
      aroundEach { run in
        MainActor.assertIsolated()
        try await Self.$taskLocal.withValue(true) { try await run() }
      }
      beforeEach { log.note("sync before") }
      beforeEach {
        await Task.yield()
        MainActor.assertIsolated()
        XCTAssertTrue(Self.taskLocal)
        log.note("async before")
      }
      context("nested") {
        beforeAll { XCTAssertFalse(Self.taskLocal) }
        it("runs inherited hooks on the main actor") { XCTAssertTrue(Self.taskLocal); log.note("one") }
        it("repeats the main actor hook lifecycle for each example") { XCTAssertTrue(Self.taskLocal); log.note("two") }
        afterAll { XCTAssertFalse(Self.taskLocal) }
      }
      afterEach {
        await Task.yield()
        MainActor.assertIsolated()
        XCTAssertTrue(Self.taskLocal)
        log.note("after")
      }
    }
    XCTAssertEqual(log.wrappedValue, ["sync before", "async before", "one", "after",
                                      "sync before", "async before", "two", "after"])
    XCTAssertFalse(Self.taskLocal)
  }
}
