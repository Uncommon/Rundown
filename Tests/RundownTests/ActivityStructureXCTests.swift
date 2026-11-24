import XCTest
@testable import Rundown

/// Characterization tests for the XCTest runner. They pin down the structure
/// of the `XCTContext` activities (names and nesting) and the order of hooks
/// around `aroundEachPeer`, so that changes to how the runner is built can be
/// shown not to alter its behavior.
///
/// XCTest has no public way to observe activities from outside, so each step
/// records the activity that is current when it runs, along with the runner's
/// path. The path is the stack of nested activities: every element's activity
/// is opened by `withElementActivity`, which also pushes the element on the
/// path.
@MainActor
final class ActivityStructureXCTests: Rundown.TestCase {

  /// What a step saw when it ran
  struct Snapshot: Equatable {
    var label: String
    /// Name of `ExampleRunner.activity`
    var activity: String?
    var path: [String]
  }

  final class Log {
    var snapshots: [Snapshot] = []
    var activities: [(label: String, activity: any XCTActivity)] = []

    @MainActor
    func record(_ label: String) {
      snapshots.append(Snapshot(label: label,
                                activity: ExampleRunner.activity?.name,
                                path: ExampleRunner.current?.path ?? []))
      if let activity = ExampleRunner.activity {
        activities.append((label, activity))
      }
    }

    var labels: [String] { snapshots.map(\.label) }
  }

  /// Every step runs in an activity named for the last element of its path,
  /// except an `aroundEachPeer` callback, which runs in the group's activity.
  func testActivityNameMatchesInnermostElement() throws {
    let log = Log()

    try spec("Activities") {
      beforeAll { log.record("beforeAll") }
      beforeEachPeer { log.record("beforeEachPeer") }
      it("first") { log.record("first") }
      context("nested") {
        it("second") { log.record("second") }
      }
      afterEachPeer { log.record("afterEachPeer") }
      afterAll { log.record("afterAll") }
    }

    for snapshot in log.snapshots {
      XCTAssertEqual(snapshot.activity, snapshot.path.last,
                     "activity for \(snapshot.label)")
    }
  }

  /// Names and nesting: the spec is the root, hooks and examples are its
  /// children, and a nested context holds its own elements.
  func testActivityNamesAndNesting() throws {
    let log = Log()

    try spec("Root") {
      beforeAll { log.record("beforeAll") }
      beforeEachPeer { log.record("beforeEachPeer") }
      it("first") { log.record("first") }
      context("nested") {
        beforeAll { log.record("nested beforeAll") }
        it("second") { log.record("second") }
        afterAll { log.record("nested afterAll") }
      }
      afterEachPeer { log.record("afterEachPeer") }
      afterAll { log.record("afterAll") }
    }

    let beforeAll = "before all"
    let beforeEachPeer = "before each peer"
    let afterEachPeer = "after each peer"
    let afterAll = "after all"

    XCTAssertEqual(log.snapshots.map(\.path), [
      ["Root", beforeAll],
      // beforeEachPeer hooks belong to the group that declares them, so they run
      // as children of the group's activity, before the element's own.
      ["Root", beforeEachPeer],
      ["Root", "first"],
      ["Root", afterEachPeer],
      ["Root", beforeEachPeer],
      // The nested context is one element of Root, so Root's peer hooks run
      // once around it, not around the example inside it.
      ["Root", "nested", beforeAll],
      ["Root", "nested", "second"],
      ["Root", "nested", afterAll],
      ["Root", afterEachPeer],
      ["Root", afterAll],
    ])
    XCTAssertEqual(log.labels, [
      "beforeAll", "beforeEachPeer", "first", "afterEachPeer",
      "beforeEachPeer", "nested beforeAll", "second", "nested afterAll",
      "afterEachPeer", "afterAll",
    ])
  }

  /// Each element gets an activity of its own, rather than sharing one.
  func testEachElementHasItsOwnActivity() throws {
    let log = Log()

    try spec("Distinct") {
      beforeEachPeer { log.record("beforeEachPeer") }
      it("first") { log.record("first") }
      it("second") { log.record("second") }
    }

    XCTAssertEqual(log.activities.count, 4)
    for (i, a) in log.activities.enumerated() {
      for b in log.activities[(i + 1)...] {
        XCTAssertFalse(a.activity as AnyObject === b.activity as AnyObject,
                       "\(a.label) and \(b.label) share an activity")
      }
    }
  }

  /// `spec(_:)` uses its description for the root activity, and `spec()` uses
  /// the name of the test function without its "test" prefix.
  func testRootActivityNames() throws {
    let log = Log()

    try spec { it("runs") { log.record("it") } }
    try spec("Explicit name") { it("runs") { log.record("it") } }

    XCTAssertEqual(log.snapshots.map(\.path), [
      ["RootActivityNames", "runs"],
      ["Explicit name", "runs"],
    ])
  }

  /// Hook order with `aroundEachPeer`, which wraps each element together with the
  /// group's `beforeEachPeer` and `afterEachPeer` hooks.
  func testAroundEachPeerHookOrder() throws {
    let log = Log()

    try spec("Around") {
      beforeAll { log.record("beforeAll") }
      aroundEachPeer("outer") { callback in
        log.record("outer in")
        try callback()
        log.record("outer out")
      }
      aroundEachPeer("inner") { callback in
        log.record("inner in")
        try callback()
        log.record("inner out")
      }
      beforeEachPeer { log.record("beforeEachPeer") }
      it("first") { log.record("first") }
      context("nested") {
        it("second") { log.record("second") }
      }
      afterEachPeer { log.record("afterEachPeer") }
      afterAll { log.record("afterAll") }
    }

    XCTAssertEqual(log.labels, [
      "beforeAll",
      "outer in", "inner in", "beforeEachPeer", "first", "afterEachPeer", "inner out", "outer out",
      "outer in", "inner in", "beforeEachPeer", "second", "afterEachPeer", "inner out", "outer out",
      "afterAll",
    ])
  }

  /// The `aroundEachPeer` hook is not an activity itself. Its callbacks run in the
  /// activity of the group that declares it, and what it wraps nests inside.
  func testAroundEachPeerActivityContext() throws {
    let log = Log()

    try spec("Around") {
      aroundEachPeer { callback in
        log.record("around in")
        try callback()
        log.record("around out")
      }
      beforeEachPeer { log.record("beforeEachPeer") }
      it("first") { log.record("first") }
    }

    XCTAssertEqual(log.snapshots, [
      Snapshot(label: "around in", activity: "Around", path: ["Around"]),
      Snapshot(label: "beforeEachPeer", activity: "before each peer", path: ["Around", "before each peer"]),
      Snapshot(label: "first", activity: "first", path: ["Around", "first"]),
      Snapshot(label: "around out", activity: "Around", path: ["Around"]),
    ])
  }

  /// A nested context is one element, so `aroundEachPeer` wraps it once and not
  /// each example inside it.
  func testAroundEachPeerWrapsNestedContextOnce() throws {
    let log = Log()

    try spec("Around") {
      aroundEachPeer { callback in
        log.record("around in")
        try callback()
        log.record("around out")
      }
      context("nested") {
        it("first") { log.record("first") }
        it("second") { log.record("second") }
      }
    }

    XCTAssertEqual(log.labels, ["around in", "first", "second", "around out"])
  }
}
