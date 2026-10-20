import XCTest
@testable import Rundown

/// A reporter that notes what the traversal does, and records errors instead
/// of propagating them, as the XCTest reporter will. `TestSkip` counts as a skip.
final class RecordingReporter: Reporter, @unchecked Sendable {
  struct TestSkip: Error {}

  private let lock = NSLock()
  private var _events: [String] = []
  private var stack: [String] = []
  let disposition: Disposition

  init(disposition: Disposition = .record) {
    self.disposition = disposition
  }

  var events: [String] { lock.withLock { _events } }

  private func enter(_ node: ExampleNode) {
    lock.withLock {
      stack.append(node.name)
      _events.append("enter " + stack.joined(separator: "/"))
    }
  }

  private func exit() {
    lock.withLock {
      _events.append("exit " + stack.joined(separator: "/"))
      stack.removeLast()
    }
  }

  func scope(for node: ExampleNode, _ body: () async -> Void) async {
    enter(node)
    await body()
    exit()
  }

  func scope(for node: ExampleNode, _ body: () -> Void) {
    enter(node)
    body()
    exit()
  }

  func classify(_ error: any Error) -> ErrorKind {
    error is TestSkip ? .skip : .failure
  }

  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> Disposition {
    lock.withLock {
      let path = (stack + (stack.last == node.name ? [] : [node.name])).joined(separator: "/")
      _events.append("\(kind) \(path)")
    }
    return disposition
  }
}

final class ReporterTests: XCTestCase {
  func run(_ group: ExampleGroup<SyncCall>,
           reporter: RecordingReporter = .init()) throws -> RecordingReporter {
    try group.node.run(with: reporter)
    return reporter
  }

  func testScopesWrapNodesAndHooksButNotAroundEach() throws {
    let reporter = try run(describe("Root") {
      beforeAll {}
      aroundEach("wrap") { callback in try callback() }
      beforeEach {}
      it("first") {}
      context("nested") {
        it("second") {}
      }
      afterEach {}
      afterAll {}
    })

    XCTAssertEqual(reporter.events, [
      "enter Root",
      "enter Root/before all", "exit Root/before all",
      "enter Root/before each", "exit Root/before each",
      "enter Root/first", "exit Root/first",
      "enter Root/after each", "exit Root/after each",
      "enter Root/before each", "exit Root/before each",
      "enter Root/nested",
      "enter Root/nested/second", "exit Root/nested/second",
      "exit Root/nested",
      "enter Root/after each", "exit Root/after each",
      "enter Root/after all", "exit Root/after all",
      "exit Root",
    ])
  }

  func testAsyncTraversalUsesTheAsyncScope() async throws {
    let reporter = RecordingReporter()
    try await (describe("Root") {
      it("first") { await Task.yield() }
    } as ExampleGroup<AsyncCall>).node.run(with: reporter)

    XCTAssertEqual(reporter.events, ["enter Root", "enter Root/first", "exit Root/first", "exit Root"])
  }

  func testRecordedFailuresDontStopTheRunOrThrow() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      beforeEach { log.note("beforeEach") }
      it("fails") { log.note("fails"); throw TestError(id: 1) }
      it("still runs") { log.note("still runs") }
      afterEach { log.note("afterEach") }
    })

    XCTAssertEqual(log.wrappedValue, ["beforeEach", "fails", "afterEach",
                                      "beforeEach", "still runs", "afterEach"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }

  func testFailingBeforeEachSkipsOnlyItsElement() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      beforeEach { log.note("beforeEach"); throw TestError(id: 1) }
      it("never") { log.note("never") }
      afterEach { log.note("afterEach") }
    })

    XCTAssertEqual(log.wrappedValue, ["beforeEach", "afterEach"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/before each"])
  }

  func testFailingBeforeAllSkipsElementsButNotAfterAll() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      beforeAll { log.note("beforeAll"); throw TestError(id: 1) }
      it("never") { log.note("never") }
      afterAll { log.note("afterAll") }
    })
    XCTAssertEqual(log.wrappedValue, ["beforeAll", "afterAll"])
  }

  func testPropagatedFailureIsRethrownAfterTeardown() throws {
    let log = Box([String]())
    XCTAssertThrowsError(
      try run(describe("Root") {
        it("fails") { throw TestError(id: 1) }
        it("also fails") { throw TestError(id: 2) }
        afterAll { log.note("afterAll") }
      }, reporter: .init(disposition: .propagate))
    ) { XCTAssertEqual($0 as? TestError, TestError(id: 1)) }
    XCTAssertEqual(log.wrappedValue, ["afterAll"])
  }

  // MARK: Skips

  func testSkipInBeforeAllAbandonsTheGroupIncludingAfterAll() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      beforeAll { throw RecordingReporter.TestSkip() }
      it("never") { log.note("never") }
      afterAll { log.note("afterAll") }
    })

    XCTAssertEqual(log.wrappedValue, [])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") }, ["skip Root/before all"])
  }

  func testSkipInBeforeEachSkipsTheElementWithoutAfterEach() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      beforeEach { log.note("beforeEach"); throw RecordingReporter.TestSkip() }
      it("never") { log.note("never") }
      it("also never") { log.note("also never") }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    })

    // Both elements are tried, neither runs, no afterEach, afterAll does
    XCTAssertEqual(log.wrappedValue, ["beforeEach", "beforeEach", "afterAll"])
  }

  func testSkipInExampleIsSwallowedAndAfterEachRuns() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      it("skips") { throw RecordingReporter.TestSkip() }
      it("next") { log.note("next") }
      afterEach { log.note("afterEach") }
    }, reporter: .init(disposition: .propagate))

    // Nothing was thrown, even though the disposition is .propagate
    XCTAssertEqual(log.wrappedValue, ["afterEach", "next", "afterEach"])
  }

  /// A skip ends only the hook that threw it. The XCTest runner used to let
  /// it escape and abort the run, which skipped the remaining elements and
  /// `afterAll` hooks.
  func testSkipInTeardownEndsOnlyThatHook() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      it("runs") { log.note("runs") }
      it("runs too") { log.note("runs too") }
      afterEach("skips") { throw RecordingReporter.TestSkip() }
      afterEach("next") { log.note("afterEach") }
      afterAll("skips") { throw RecordingReporter.TestSkip() }
      afterAll("next") { log.note("afterAll") }
    }, reporter: .init(disposition: .propagate))

    // Nothing was thrown, though the disposition is .propagate
    XCTAssertEqual(log.wrappedValue,
                   ["runs", "afterEach", "runs too", "afterEach", "afterAll"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") },
                   ["skip Root/after each: skips", "skip Root/after each: skips",
                    "skip Root/after all: skips"])
  }

  func testSkipInNestedTeardownDoesntReachTheParent() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      context("nested") {
        it("x") { log.note("x") }
        afterEach { throw RecordingReporter.TestSkip() }
      }
      it("y") { log.note("y") }
      afterAll { log.note("afterAll") }
    }, reporter: .init(disposition: .propagate))

    XCTAssertEqual(log.wrappedValue, ["x", "y", "afterAll"])
  }

  // MARK: aroundEach

  func testErrorFromAroundEachIsReportedAtTheHook() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      aroundEach("wrap") { _ in throw TestError(id: 1) }
      it("never") { log.note("never") }
    })

    XCTAssertEqual(log.wrappedValue, [])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/around each: wrap"])
  }

  func testSkipInAroundEachBeforeTheCallbackSkipsTheElement() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      aroundEach("skips") { _ in throw RecordingReporter.TestSkip() }
      beforeEach { log.note("beforeEach") }
      it("never") { log.note("never") }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    }, reporter: .init(disposition: .propagate))

    XCTAssertEqual(log.wrappedValue, ["afterAll"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") },
                   ["skip Root/around each: skips"])
  }

  func testSkipInAroundEachAfterTheCallbackIsSwallowed() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      aroundEach { callback in
        try callback()
        throw RecordingReporter.TestSkip()
      }
      it("first") { log.note("first") }
      it("second") { log.note("second") }
      afterEach { log.note("afterEach") }
    }, reporter: .init(disposition: .propagate))

    XCTAssertEqual(log.wrappedValue, ["first", "afterEach", "second", "afterEach"])
  }

  func testErrorInsideAroundEachIsReportedOnce() throws {
    let reporter = try run(describe("Root") {
      aroundEach { callback in try callback() }
      it("fails") { throw TestError(id: 1) }
    })

    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }

  func testPropagatedErrorInsideAroundEachIsNotReportedAgain() throws {
    let reporter = RecordingReporter(disposition: .propagate)
    XCTAssertThrowsError(try run(describe("Root") {
      aroundEach { callback in try callback() }
      it("fails") { throw TestError(id: 1) }
    }, reporter: reporter))

    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }
}
