import XCTest
@testable import Rundown

/// A reporter that notes what the traversal does, and records errors instead
/// of propagating them, as the XCTest reporter will. `TestSkip` counts as a skip.
final class RecordingReporter: Reporter, @unchecked Sendable {
  struct TestSkip: Error {}

  private let lock = NSLock()
  private var _events: [String] = []
  private var stack: [String] = []
  let decision: ErrorHandlingDecision

  init(decision: ErrorHandlingDecision = .record) {
    self.decision = decision
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

  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> ErrorHandlingDecision {
    lock.withLock {
      let path = (stack + (stack.last == node.name ? [] : [node.name])).joined(separator: "/")
      _events.append("\(kind) \(path)")
    }
    return decision
  }
}

final class ReporterTests: XCTestCase {
  func testXCTestReporterDoesNotSuppressUnmarkedOrUnrelatedErrors() {
    let reporter = XCTestReporter(test: self)
    let errors: [any Error] = [
      TestError(id: 1),
      NSError(domain: XCTestErrorDomain, code: 105),
      NSError(domain: XCTestErrorDomain, code: 105,
              userInfo: ["XCTestErrorUserInfoKeyShouldIgnore": false]),
      NSError(domain: "OtherErrors", code: 105,
              userInfo: ["XCTestErrorUserInfoKeyShouldIgnore": true]),
    ]
    for error in errors {
      XCTAssertEqual(reporter.classify(error), .failure, "\(error)")
    }
    XCTAssertEqual(reporter.classify(XCTSkip("skip")), .skip)
  }

  func run(_ group: ExampleGroup<SyncCall>,
           reporter: RecordingReporter = .init()) throws -> RecordingReporter {
    try group.node.run(with: reporter)
    return reporter
  }

  func testScopesWrapNodesAndHooksButNotAroundEachPeer() throws {
    let reporter = try run(describe("Root") {
      beforeAll {}
      aroundEachPeer("wrap") { callback in try callback() }
      beforeEachPeer {}
      it("first") {}
      context("nested") {
        it("second") {}
      }
      afterEachPeer {}
      afterAll {}
    })

    XCTAssertEqual(reporter.events, [
      "enter Root",
      "enter Root/before all", "exit Root/before all",
      "enter Root/before each peer", "exit Root/before each peer",
      "enter Root/first", "exit Root/first",
      "enter Root/after each peer", "exit Root/after each peer",
      "enter Root/before each peer", "exit Root/before each peer",
      "enter Root/nested",
      "enter Root/nested/second", "exit Root/nested/second",
      "exit Root/nested",
      "enter Root/after each peer", "exit Root/after each peer",
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
      beforeEachPeer { log.note("beforeEachPeer") }
      it("fails") { log.note("fails"); throw TestError(id: 1) }
      it("still runs") { log.note("still runs") }
      afterEachPeer { log.note("afterEachPeer") }
    })

    XCTAssertEqual(log.wrappedValue, ["beforeEachPeer", "fails", "afterEachPeer",
                                      "beforeEachPeer", "still runs", "afterEachPeer"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }

  func testFailingBeforeEachPeerSkipsOnlyItsElement() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      beforeEachPeer { log.note("beforeEachPeer"); throw TestError(id: 1) }
      it("never") { log.note("never") }
      afterEachPeer { log.note("afterEachPeer") }
    })

    XCTAssertEqual(log.wrappedValue, ["beforeEachPeer", "afterEachPeer"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/before each peer"])
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
      }, reporter: .init(decision: .propagate))
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

  func testSkipInBeforeEachPeerSkipsTheElementWithoutAfterEachPeer() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      beforeEachPeer { log.note("beforeEachPeer"); throw RecordingReporter.TestSkip() }
      it("never") { log.note("never") }
      it("also never") { log.note("also never") }
      afterEachPeer { log.note("afterEachPeer") }
      afterAll { log.note("afterAll") }
    })

    // Both elements are tried, neither runs, no afterEachPeer, afterAll does
    XCTAssertEqual(log.wrappedValue, ["beforeEachPeer", "beforeEachPeer", "afterAll"])
  }

  func testSkipInExampleIsSwallowedAndAfterEachPeerRuns() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      it("skips") { throw RecordingReporter.TestSkip() }
      it("next") { log.note("next") }
      afterEachPeer { log.note("afterEachPeer") }
    }, reporter: .init(decision: .propagate))

    // Nothing was thrown, even though the decision is .propagate
    XCTAssertEqual(log.wrappedValue, ["afterEachPeer", "next", "afterEachPeer"])
  }

  /// A skip ends only the hook that threw it. The XCTest runner used to let
  /// it escape and abort the run, which skipped the remaining elements and
  /// `afterAll` hooks.
  func testSkipInTeardownEndsOnlyThatHook() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      it("runs") { log.note("runs") }
      it("runs too") { log.note("runs too") }
      afterEachPeer("skips") { throw RecordingReporter.TestSkip() }
      afterEachPeer("next") { log.note("afterEachPeer") }
      afterAll("skips") { throw RecordingReporter.TestSkip() }
      afterAll("next") { log.note("afterAll") }
    }, reporter: .init(decision: .propagate))

    // Nothing was thrown, though the decision is .propagate
    XCTAssertEqual(log.wrappedValue,
                   ["runs", "afterEachPeer", "runs too", "afterEachPeer", "afterAll"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") },
                   ["skip Root/after each peer: skips", "skip Root/after each peer: skips",
                    "skip Root/after all: skips"])
  }

  func testSkipInNestedTeardownDoesntReachTheParent() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      context("nested") {
        it("x") { log.note("x") }
        afterEachPeer { throw RecordingReporter.TestSkip() }
      }
      it("y") { log.note("y") }
      afterAll { log.note("afterAll") }
    }, reporter: .init(decision: .propagate))

    XCTAssertEqual(log.wrappedValue, ["x", "y", "afterAll"])
  }

  // MARK: aroundEachPeer

  func testErrorFromAroundEachPeerIsReportedAtTheHook() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      aroundEachPeer("wrap") { _ in throw TestError(id: 1) }
      it("never") { log.note("never") }
    })

    XCTAssertEqual(log.wrappedValue, [])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/around each peer: wrap"])
  }

  func testSkipInAroundEachPeerBeforeTheCallbackSkipsTheElement() throws {
    let log = Box([String]())
    let reporter = try run(describe("Root") {
      aroundEachPeer("skips") { _ in throw RecordingReporter.TestSkip() }
      beforeEachPeer { log.note("beforeEachPeer") }
      it("never") { log.note("never") }
      afterEachPeer { log.note("afterEachPeer") }
      afterAll { log.note("afterAll") }
    }, reporter: .init(decision: .propagate))

    XCTAssertEqual(log.wrappedValue, ["afterAll"])
    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("skip") },
                   ["skip Root/around each peer: skips"])
  }

  func testSkipInAroundEachPeerAfterTheCallbackIsSwallowed() throws {
    let log = Box([String]())
    _ = try run(describe("Root") {
      aroundEachPeer { callback in
        try callback()
        throw RecordingReporter.TestSkip()
      }
      it("first") { log.note("first") }
      it("second") { log.note("second") }
      afterEachPeer { log.note("afterEachPeer") }
    }, reporter: .init(decision: .propagate))

    XCTAssertEqual(log.wrappedValue, ["first", "afterEachPeer", "second", "afterEachPeer"])
  }

  func testErrorInsideAroundEachPeerIsReportedOnce() throws {
    let reporter = try run(describe("Root") {
      aroundEachPeer { callback in try callback() }
      it("fails") { throw TestError(id: 1) }
    })

    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }

  func testPropagatedErrorInsideAroundEachPeerIsNotReportedAgain() throws {
    let reporter = RecordingReporter(decision: .propagate)
    XCTAssertThrowsError(try run(describe("Root") {
      aroundEachPeer { callback in try callback() }
      it("fails") { throw TestError(id: 1) }
    }, reporter: reporter))

    XCTAssertEqual(reporter.events.filter { $0.hasPrefix("failure") },
                   ["failure Root/fails"])
  }
}
