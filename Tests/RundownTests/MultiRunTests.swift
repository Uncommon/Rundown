import XCTest
import Synchronization
@testable import Rundown

/// An error with an identity, for checking which error a run reports.
struct TestError: Error, Equatable {
  var id: Int
}

extension Box where T == [String] {
  /// Appends an entry to the log
  func note(_ entry: String) { wrappedValue.append(entry) }
}

/// Tests that verify execution on the regular, XCTest, and async versions
/// of the run method.
@MainActor
class MultiRunTests: XCTestCase {
  func plainRunner(group: ExampleGroup<SyncCall>) throws {
    try group.run()
  }

  func asyncRunner(group: ExampleGroup<AsyncCall>) async throws {
    // Errors have to propagate: a failure here must fail the test, not leave
    // it waiting for an expectation that is never fulfilled.
    try await Task { try await group.run() }.value
  }

  func asyncRunner(group: ExampleGroup<SyncCall>) async throws {
    try await asyncRunner(group: .init(fromSync: group))
  }

  func xcTestRunner(group: ExampleGroup<SyncMainCall>) throws {
    try group.runActivity(under: self)
  }

  /// The tests build `SyncCall` groups, so adapt them for the XCTest runner.
  /// Note that `runActivity()` does not implement `.concurrent`; those
  /// groups simply run serially.
  func xcTestRunner(group: ExampleGroup<SyncCall>) throws {
    try xcTestRunner(group: .init(fromSync: group))
  }

  func useAllRunners(test: @MainActor ((ExampleGroup<SyncCall>) async throws -> Void, String) async throws -> Void) async throws {
    try await test(plainRunner, "plain")
    try await test(xcTestRunner, "XCTest")
    try await test(asyncRunner, "async")
  }

  func useSyncRunners(test: @MainActor ((ExampleGroup<SyncCall>) throws -> Void, String) throws -> Void) throws {
    try test(plainRunner, "plain")
    try test(xcTestRunner, "XCTest")
  }

  func testExcludeOneOfTwo() async throws {
    try await useAllRunners { (runner, type) in
      let ranBeforeAll = Box(false)
      let ranBeforeEachPeer = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEachPeer = Box(false)
      let ranAfterAll = Box(false)

      let describe = describe("Exclude one of two") {
        beforeAll {
          ranBeforeAll.set()
        }
        beforeEachPeer {
          ranBeforeEachPeer.set()
        }
        it("one", .excluded) {
          ran1.set()
        }
        it("two") {
          ran2.set()
        }
        afterEachPeer {
          ranAfterEachPeer.set()
        }
        afterAll {
          ranAfterAll.set()
        }
      }
      
      try await runner(describe)

      XCTAssertTrue(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranBeforeEachPeer.wrappedValue, "\(type) failure")
      XCTAssertFalse(ran1.wrappedValue, "\(type) failure")
      XCTAssertTrue(ran2.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterEachPeer.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }
  
  // No hooks should run if all elements are excluded
  func testExcludeHooks() async throws {
    try await useAllRunners { (runner, type) in
      let ranBeforeAll = Box(false)
      let ranBeforeEachPeer = Box(false)
      let ranIt = Box(false)
      let ranAfterEachPeer = Box(false)
      let ranAfterAll = Box(false)

      let group = describe("Skip hooks") {
        beforeAll { ranBeforeAll.set() }
        beforeEachPeer { ranBeforeEachPeer.set() }
        it("excludes", .excluded) { ranIt.set() }
        afterEachPeer { ranAfterEachPeer.set() }
        afterAll { ranAfterAll.set() }
      }

      try await runner(group)
      XCTAssertFalse(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranBeforeEachPeer.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranIt.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranAfterEachPeer.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }

  func testFocusOneOfTwo() async throws {
    try await useAllRunners { (runner, type) in
      let ranBeforeAll = Box(false)
      let ranBeforeEachPeer = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEachPeer = Box(false)
      let ranAfterAll = Box(false)

      let group = describe("Skip one of two") {
        beforeAll { ranBeforeAll.set() }
        beforeEachPeer { ranBeforeEachPeer.set() }
        it("one", .focused) { ran1.set() }
        it("two") { ran2.set() }
        afterEachPeer { ranAfterEachPeer.set() }
        afterAll { ranAfterAll.set() }
      }

      try await runner(group)

      XCTAssertTrue(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranBeforeEachPeer.wrappedValue, "\(type) failure")
      XCTAssertTrue(ran1.wrappedValue, "\(type) failure")
      XCTAssertFalse(ran2.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterEachPeer.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }
  
  func testDeepFocus() async throws {
    try await useAllRunners { (runner, type) in
      let ranBeforeAll1 = Box(false)
      let ranAfterAll1 = Box(false)
      let ranBeforeAll2 = Box(false)
      let ranAfterAll2 = Box(false)
      let beforeEachPeerCount1 = Box(0)
      let afterEachPeerCount1 = Box(0)
      let beforeEachPeerCount2 = Box(0)
      let afterEachPeerCount2 = Box(0)
      let ran2 = Box(false)

      let group = describe("Deep focus") {
        beforeAll { ranBeforeAll1.set() }
        beforeEachPeer { beforeEachPeerCount1.bump() }
        it("skips") { XCTFail("ran outer unfocused test") }
        describe("subgroup") {
          beforeAll { ranBeforeAll2.set() }
          beforeEachPeer { beforeEachPeerCount2.bump() }
          it("runs focused", .focused) { ran2.set() }
          it("skips") { XCTFail("ran inner unfocused test") }
          afterEachPeer { afterEachPeerCount2.bump() }
          afterAll { ranAfterAll2.set() }
        }
        afterEachPeer { afterEachPeerCount1.bump() }
        afterAll { ranAfterAll1.set() }
      }

      try await runner(group)

      XCTAssert(ranBeforeAll1.wrappedValue, "\(type) failure")
      XCTAssertEqual(beforeEachPeerCount1.wrappedValue, 1, "\(type) failure")
      XCTAssert(ranBeforeAll2.wrappedValue, "\(type) failure")
      XCTAssertEqual(beforeEachPeerCount2.wrappedValue, 1, "\(type) failure")
      XCTAssert(ran2.wrappedValue, "\(type) failure")
      XCTAssertEqual(afterEachPeerCount2.wrappedValue, 1, "\(type) failure")
      XCTAssert(ranAfterAll2.wrappedValue, "\(type) failure")
      XCTAssertEqual(afterEachPeerCount1.wrappedValue, 1, "\(type) failure")
      XCTAssert(ranAfterAll1.wrappedValue, "\(type) failure")
    }
  }
  
  func testConcurrent() async throws {
    try await useAllRunners { (runner, type) in
      let stepCount = 10
      let runCount = Atomic<Int>(0)
      
      let group = describe("concurrent", .concurrent) {
        for step in 1...stepCount {
          it("runs step \(step)") {
            runCount.add(1, ordering: .relaxed)
          }
        }
      }
      
      try await runner(group)
      
      XCTAssertEqual(runCount.load(ordering: .relaxed), stepCount, "\(type) failure")
    }
  }
  
  func testAroundEachPeer() async throws {
    // aroundEachPeer can't be converted from sync to async, so the async runner
    // doesn't work
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      
      let group = describe("around each peer") {
        aroundEachPeer { (callback) in
          result.wrappedValue.append("outer before")
          try "".withCString { _ in
            result.wrappedValue.append("inner before")
            try callback()
            result.wrappedValue.append("inner after")
          }
          result.wrappedValue.append("outer after")
        }
        it("works") {
          result.wrappedValue.append("it")
        }
      }
      
      try runner(group)
      
      XCTAssertEqual(result.wrappedValue,
                     ["outer before", "inner before", "it", "inner after", "outer after"],
                     "\(type) failure")
    }
  }

  func testExcludedAroundEachPeer() async throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      
      let group = describe("around each peer") {
        aroundEachPeer(.excluded) { (callback) in
          result.wrappedValue.append("around")
          try callback()
        }
        it("works") {
          result.wrappedValue.append("it")
        }
      }
      
      try runner(group)
      
      XCTAssertEqual(result.wrappedValue,
                     ["it"],
                     "\(type) failure")
    }
  }

  /// A second aroundEachPeer should be executed inside the callback of the first
  func testDoubleAroundEachPeer() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        aroundEachPeer { (callback) in
          result.wrappedValue.append("around 1 start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around 1 end")
        }

        aroundEachPeer { (callback) in
          result.wrappedValue.append("around 2 start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around 2 end")
        }

        it("works") {
          result.wrappedValue.append("it")
        }
      }
      
      try runner(group)

      XCTAssertEqual(result.wrappedValue,
                     ["around 1 start", "around 2 start",
                      "it",
                      "around 2 end", "around 1 end"],
                     "\(type) failure")
    }
  }
  
  func testAroundEachPeerWithHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        beforeAll {
          result.wrappedValue.append("beforeAll")
        }
        aroundEachPeer { (callback) in
          result.wrappedValue.append("around start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around end")
        }
        beforeEachPeer {
          result.wrappedValue.append("beforeEachPeer")
        }
        
        it("works") {
          result.wrappedValue.append("it")
        }
        
        afterEachPeer {
          result.wrappedValue.append("afterEachPeer")
        }
        afterAll {
          result.wrappedValue.append("afterAll")
        }
      }
      
      try runner(group)
      
      XCTAssertEqual(result.wrappedValue,
                     ["beforeAll",
                      "around start",
                      "beforeEachPeer", "it", "afterEachPeer",
                      "around end",
                      "afterAll",
                     ],
                     "\(type) failure")
    }
  }

  func testAroundEachPeerOnlyAllHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        beforeAll {
          result.wrappedValue.append("beforeAll")
        }
        aroundEachPeer { (callback) in
          result.wrappedValue.append("around start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around end")
        }

        it("works") {
          result.wrappedValue.append("it")
        }

        afterAll {
          result.wrappedValue.append("afterAll")
        }
      }
      
      try runner(group)

      XCTAssertEqual(result.wrappedValue,
                     ["beforeAll",
                      "around start",
                      "it",
                      "around end",
                      "afterAll",
                     ],
                     "\(type) failure")
    }
  }

  func testAroundEachPeerOnlyPeerHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        aroundEachPeer { (callback) in
          result.wrappedValue.append("around start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around end")
        }
        beforeEachPeer {
          result.wrappedValue.append("beforeEachPeer")
        }

        it("works") {
          result.wrappedValue.append("it")
        }

        afterEachPeer {
          result.wrappedValue.append("afterEachPeer")
        }
      }
      
      try runner(group)

      XCTAssertEqual(result.wrappedValue,
                     ["around start",
                      "beforeEachPeer", "it", "afterEachPeer",
                      "around end",
                     ],
                     "\(type) failure")
    }
  }

  // MARK: Peer hooks and contexts

  // beforeEachPeer, afterEachPeer and aroundEachPeer apply to the elements of the group
  // they are declared in, and a nested context is one such element. They run
  // once around the whole context, not around each example inside it. To run
  // something for every example in a context, declare it inside that context.

  func testPeerHooksApplyToElementsOfTheirGroup() async throws {
    try await useAllRunners { (runner, type) in
      let log = Box([String]())
      let group = describe("peer hooks") {
        beforeEachPeer { log.note("outer before") }
        context("nested") {
          beforeEachPeer { log.note("inner before") }
          it("one") { log.note("one") }
          it("two") { log.note("two") }
          afterEachPeer { log.note("inner after") }
        }
        it("sibling") { log.note("sibling") }
        afterEachPeer { log.note("outer after") }
      }

      try await runner(group)

      XCTAssertEqual(log.wrappedValue,
                     // The outer hooks wrap the context once, and the sibling once
                     ["outer before",
                        "inner before", "one", "inner after",
                        "inner before", "two", "inner after",
                      "outer after",
                      "outer before", "sibling", "outer after"],
                     "\(type) failure")
    }
  }

  func testAroundEachPeerWrapsNestedGroupOnce() throws {
    try useSyncRunners { (runner, type) in
      let log = Box([String]())
      let group = describe("around each peer") {
        aroundEachPeer { (callback) in
          log.note("outer around>")
          try callback()
          log.note("<outer around")
        }
        context("nested") {
          aroundEachPeer { (callback) in
            log.note("inner around>")
            try callback()
            log.note("<inner around")
          }
          it("one") { log.note("one") }
          it("two") { log.note("two") }
        }
      }

      try runner(group)

      XCTAssertEqual(log.wrappedValue,
                     ["outer around>",
                        "inner around>", "one", "<inner around",
                        "inner around>", "two", "<inner around",
                      "<outer around"],
                     "\(type) failure")
    }
  }

  /// Hooks don't cascade into contexts, so setup that several contexts need
  /// comes from a function that returns the hook.
  func testSharedHookFunction() async throws {
    func sharedSetup(_ log: Box<[String]>) -> TestHook<BeforeEachPeerPhase, SyncCall> {
      beforeEachPeer("shared") { log.note("shared setup") }
    }

    try await useAllRunners { (runner, type) in
      let log = Box([String]())
      let group = describe("shared") {
        context("first") {
          sharedSetup(log)
          it("one") { log.note("one") }
          it("two") { log.note("two") }
        }
        context("second") {
          sharedSetup(log)
          it("three") { log.note("three") }
        }
      }

      try await runner(group)

      XCTAssertEqual(log.wrappedValue,
                     ["shared setup", "one", "shared setup", "two", "shared setup", "three"],
                     "\(type) failure")
    }
  }

  // MARK: Errors

  /// Runners that report an error from an example by throwing it from the run.
  /// The XCTest runner records an issue instead, so it has its own test.
  func useThrowingRunners(test: @MainActor ((ExampleGroup<SyncCall>) async throws -> Void, String) async throws -> Void) async throws {
    try await test(plainRunner, "plain")
    try await test(asyncRunner, "async")
  }

  /// A group that fails in some way, and the log that every runner should
  /// produce for it: a failure never skips teardown or the remaining elements.
  struct ErrorScenario {
    let name: String
    let group: ExampleGroup<SyncCall>
    let log: Box<[String]>
    let expectedLog: [String]
    /// How many issues the XCTest runner should record, which is one per
    /// failing step. The other runners throw only the first error, which is
    /// always `TestError(id: 1)`.
    let issueCount: Int
  }

  static func errorScenarios() -> [ErrorScenario] {
    var scenarios: [ErrorScenario] = []
    func add(_ name: String,
             expecting expectedLog: [String],
             issues: Int,
             group: (Box<[String]>) -> ExampleGroup<SyncCall>) {
      let log = Box([String]())
      scenarios.append(.init(name: name, group: group(log), log: log,
                             expectedLog: expectedLog, issueCount: issues))
    }

    add("it throws",
        expecting: ["beforeAll", "beforeEachPeer", "fails", "afterEachPeer",
                    "beforeEachPeer", "passes", "afterEachPeer", "afterAll"],
        issues: 1) { log in
      describe("it throws") {
        beforeAll { log.note("beforeAll") }
        beforeEachPeer { log.note("beforeEachPeer") }
        it("fails") { log.note("fails"); throw TestError(id: 1) }
        it("passes") { log.note("passes") }
        afterEachPeer { log.note("afterEachPeer") }
        afterAll { log.note("afterAll") }
      }
    }

    add("first error wins",
        expecting: ["fails 1", "fails 2", "afterAll"],
        issues: 2) { log in
      describe("two failures") {
        it("fails 1") { log.note("fails 1"); throw TestError(id: 1) }
        it("fails 2") { log.note("fails 2"); throw TestError(id: 2) }
        afterAll { log.note("afterAll") }
      }
    }

    add("beforeEachPeer throws",
        expecting: ["beforeAll", "beforeEachPeer", "afterEachPeer",
                    "beforeEachPeer", "afterEachPeer", "afterAll"],
        issues: 2) { log in
      describe("beforeEachPeer throws") {
        beforeAll { log.note("beforeAll") }
        beforeEachPeer { log.note("beforeEachPeer"); throw TestError(id: 1) }
        it("first") { log.note("first") }
        it("second") { log.note("second") }
        afterEachPeer { log.note("afterEachPeer") }
        afterAll { log.note("afterAll") }
      }
    }

    add("beforeAll throws",
        expecting: ["beforeAll 1", "beforeAll 2", "afterAll"],
        issues: 1) { log in
      describe("beforeAll throws") {
        beforeAll("one") { log.note("beforeAll 1") }
        beforeAll("two") { log.note("beforeAll 2"); throw TestError(id: 1) }
        beforeAll("three") { log.note("beforeAll 3") }
        beforeEachPeer { log.note("beforeEachPeer") }
        it("never runs") { log.note("never runs") }
        afterEachPeer { log.note("afterEachPeer") }
        afterAll { log.note("afterAll") }
      }
    }

    add("afterEachPeer throws",
        expecting: ["first", "afterEachPeer 1", "afterEachPeer 2",
                    "second", "afterEachPeer 1", "afterEachPeer 2", "afterAll"],
        issues: 2) { log in
      describe("afterEachPeer throws") {
        it("first") { log.note("first") }
        it("second") { log.note("second") }
        afterEachPeer("one") { log.note("afterEachPeer 1"); throw TestError(id: 1) }
        afterEachPeer("two") { log.note("afterEachPeer 2") }
        afterAll { log.note("afterAll") }
      }
    }

    add("afterAll throws",
        expecting: ["passes", "afterAll 1", "afterAll 2"],
        issues: 1) { log in
      describe("afterAll throws") {
        it("passes") { log.note("passes") }
        afterAll("one") { log.note("afterAll 1"); throw TestError(id: 1) }
        afterAll("two") { log.note("afterAll 2") }
      }
    }

    add("nested group fails",
        expecting: ["outer beforeAll", "outer beforeEachPeer",
                    "inner beforeAll", "fails", "inner afterAll",
                    "outer afterEachPeer", "outer beforeEachPeer", "outer it",
                    "outer afterEachPeer", "outer afterAll"],
        issues: 1) { log in
      describe("outer") {
        beforeAll { log.note("outer beforeAll") }
        beforeEachPeer { log.note("outer beforeEachPeer") }
        context("inner") {
          beforeAll { log.note("inner beforeAll") }
          it("fails") { log.note("fails"); throw TestError(id: 1) }
          afterAll { log.note("inner afterAll") }
        }
        it("outer it") { log.note("outer it") }
        afterEachPeer { log.note("outer afterEachPeer") }
        afterAll { log.note("outer afterAll") }
      }
    }

    return scenarios
  }

  func testErrorsRunTeardownAndContinue() async throws {
    try await useThrowingRunners { (runner, type) in
      for scenario in MultiRunTests.errorScenarios() {
        let label = "\(type) runner, \(scenario.name)"

        do {
          try await runner(scenario.group)
          XCTFail("\(label): no error thrown")
        }
        catch let error as TestError {
          XCTAssertEqual(error, TestError(id: 1), "\(label): wrong error")
        }
        XCTAssertEqual(scenario.log.wrappedValue, scenario.expectedLog, label)
      }
    }
  }

  /// Runs a group with the XCTest runner, which records errors as issues
  /// instead of throwing them, and checks that it recorded `issueCount`.
  func xcTestRunnerRecordingErrors(_ group: ExampleGroup<SyncCall>,
                                   issueCount: Int,
                                   _ label: String) {
    let recorded = Box(0)
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      // Only issues the runner records. An error that escapes the run would
      // arrive as .thrownError, and must not be mistaken for one of these.
      guard issue.type == .uncaughtException,
            issue.associatedError is TestError
      else { return false }
      recorded.bump()
      return true
    }

    XCTExpectFailure("errors are recorded as issues", options: options) {
      do {
        try xcTestRunner(group: group)
      }
      catch {
        XCTFail("\(label): error escaped the runner: \(error)")
      }
    }
    XCTAssertEqual(recorded.wrappedValue, issueCount, label)
  }

  /// The XCTest runner records errors as issues instead of throwing them, so
  /// that each shows up with the path of the element that failed.
  func testXCTestRunnerRecordsErrorsAndContinues() throws {
    for scenario in MultiRunTests.errorScenarios() {
      xcTestRunnerRecordingErrors(scenario.group,
                                  issueCount: scenario.issueCount,
                                  scenario.name)
      XCTAssertEqual(scenario.log.wrappedValue, scenario.expectedLog, scenario.name)
    }
  }

  // aroundEachPeer can't be converted from sync to async, so these aren't part of
  // the shared scenarios.

  func testAroundEachPeerErrorRunsAfterAll() throws {
    let log = Box([String]())
    let group = describe("aroundEachPeer throws") {
      beforeAll { log.note("beforeAll") }
      aroundEachPeer { _ in
        log.note("around")
        throw TestError(id: 1)
      }
      it("never runs") { log.note("never runs") }
      afterAll { log.note("afterAll") }
    }

    XCTAssertThrowsError(try plainRunner(group: group)) {
      XCTAssertEqual($0 as? TestError, TestError(id: 1))
    }
    XCTAssertEqual(log.wrappedValue, ["beforeAll", "around", "afterAll"])
  }

  func testXCTestRunnerRecordsAroundEachPeerError() throws {
    let log = Box([String]())
    let group = describe("aroundEachPeer throws") {
      beforeAll { log.note("beforeAll") }
      aroundEachPeer { _ in
        log.note("around")
        throw TestError(id: 1)
      }
      it("never runs") { log.note("never runs") }
      afterAll { log.note("afterAll") }
    }

    xcTestRunnerRecordingErrors(group, issueCount: 1, "aroundEachPeer throws")
    XCTAssertEqual(log.wrappedValue, ["beforeAll", "around", "afterAll"])
  }

  /// Each concurrent example has its own path, with nothing from the examples
  /// running alongside it, and it can find its runner. (The sync version runs
  /// on GCD threads, which don't inherit the runner or the path.)
  func testConcurrentExamplesHaveTheirOwnPaths() async throws {
    try await useAllRunners { (runner, type) in
      let count = 16
      let wrong = Box([String]())
      let lock = NSLock()

      @Sendable func check(_ expected: String) {
        Thread.sleep(forTimeInterval: Double.random(in: 0...0.01))
        let actual = ExampleRunner.current?.description ?? "no runner"

        if actual != expected {
          lock.lock()
          wrong.note("expected \"\(expected)\" but got \"\(actual)\"")
          lock.unlock()
        }
      }

      let group = describe("paths") {
        context("examples", .concurrent) {
          for index in 0..<count {
            it("ex \(index)") { check("paths, examples, ex \(index)") }
          }
        }
        context("contexts", .concurrent) {
          for index in 0..<count {
            context("ctx \(index)") {
              it("inner") { check("paths, contexts, ctx \(index), inner") }
            }
          }
        }
      }

      try await runner(group)

      XCTAssertEqual(wrong.wrappedValue, [], "\(type) failure")
    }
  }

  func testConcurrentFailureRunsEverything() async throws {
    try await useThrowingRunners { (runner, type) in
      let stepCount = 8
      let runCount = Atomic<Int>(0)
      let ranAfterAll = Box(false)

      let group = describe("concurrent failure", .concurrent) {
        for step in 1...stepCount {
          it("runs step \(step)") {
            runCount.add(1, ordering: .relaxed)
            if step == 3 {
              throw TestError(id: 1)
            }
          }
        }
        afterAll { ranAfterAll.set() }
      }

      do {
        try await runner(group)
        XCTFail("\(type): no error thrown")
      }
      catch let error as TestError {
        XCTAssertEqual(error, TestError(id: 1), "\(type): wrong error")
      }
      XCTAssertEqual(runCount.load(ordering: .relaxed), stepCount, "\(type) failure")
      XCTAssert(ranAfterAll.wrappedValue, "\(type): afterAll did not run")
    }
  }
}

// MARK: - SyncCall -> SyncMainCall

// Test-only conversion so the same groups can be run by the XCTest runner,
// which requires main actor call types. Everything runs on the main thread in
// these tests, so assumeIsolated() is safe where a callback crosses back.

private extension TestHook where Call == SyncMainCall {
  init(fromSyncCall other: TestHook<Phase, SyncCall>) {
    let block = other.block
    self.init(other.name, other.traits, execute: { try block() })
  }
}

private extension AroundEachPeer where Call == SyncMainCall {
  init(fromSyncCall other: AroundEachPeer<SyncCall>) {
    let block = other.block
    self.init(name: other.name, traits: other.traits) { inner in
      try block {
        try MainActor.assumeIsolated { try inner() }
      }
    }
  }
}

extension ExampleGroup where Call == SyncMainCall {
  init(fromSync other: ExampleGroup<SyncCall>) {
    self.init(description: other.description,
              traits: other.traits,
              beforeAll: other.beforeAllHooks.map { .init(fromSyncCall: $0) },
              aroundEachPeer: other.aroundEachPeerHooks.map { .init(fromSyncCall: $0) },
              beforeEachPeer: other.beforeEachPeerHooks.map { .init(fromSyncCall: $0) },
              afterEachPeer: other.afterEachPeerHooks.map { .init(fromSyncCall: $0) },
              afterAll: other.afterAllHooks.map { .init(fromSyncCall: $0) },
              elements: other.elements.map {
                switch $0 {
                  case let it as It<SyncCall>:
                    let block = it.block
                    return It<SyncMainCall>(it.description, it.traits,
                                            execute: { try block() })
                  case let group as ExampleGroup<SyncCall>:
                    return ExampleGroup<SyncMainCall>(fromSync: group)
                  default:
                    preconditionFailure("unexpected element")
                }
              })
  }
}
