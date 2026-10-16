import XCTest
@testable import Rundown

/// Characterization tests for the XCTest runner. They pin down the structure
/// of the `XCTContext` activities (names and nesting) and the order of hooks
/// around `aroundEach`, so that changes to how the runner is built can be
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
  /// except an `aroundEach` callback, which runs in the group's activity.
  func testActivityNameMatchesInnermostElement() throws {
    let log = Log()

    try spec("Activities") {
      beforeAll { log.record("beforeAll") }
      beforeEach { log.record("beforeEach") }
      it("first") { log.record("first") }
      context("nested") {
        it("second") { log.record("second") }
      }
      afterEach { log.record("afterEach") }
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
      beforeEach { log.record("beforeEach") }
      it("first") { log.record("first") }
      context("nested") {
        beforeAll { log.record("nested beforeAll") }
        it("second") { log.record("second") }
        afterAll { log.record("nested afterAll") }
      }
      afterEach { log.record("afterEach") }
      afterAll { log.record("afterAll") }
    }

    let beforeAll = "before all"
    let beforeEach = "before each"
    let afterEach = "after each"
    let afterAll = "after all"

    XCTAssertEqual(log.snapshots.map(\.path), [
      ["Root", beforeAll],
      // beforeEach hooks belong to the group that declares them, so they run
      // as children of the group's activity, before the element's own.
      ["Root", beforeEach],
      ["Root", "first"],
      ["Root", afterEach],
      ["Root", beforeEach],
      // The nested context is one element of Root, so Root's each-hooks run
      // once around it, not around the example inside it.
      ["Root", "nested", beforeAll],
      ["Root", "nested", "second"],
      ["Root", "nested", afterAll],
      ["Root", afterEach],
      ["Root", afterAll],
    ])
    XCTAssertEqual(log.labels, [
      "beforeAll", "beforeEach", "first", "afterEach",
      "beforeEach", "nested beforeAll", "second", "nested afterAll",
      "afterEach", "afterAll",
    ])
  }

  /// Each element gets an activity of its own, rather than sharing one.
  func testEachElementHasItsOwnActivity() throws {
    let log = Log()

    try spec("Distinct") {
      beforeEach { log.record("beforeEach") }
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

  /// Hook order with `aroundEach`, which wraps each element together with the
  /// group's `beforeEach` and `afterEach` hooks.
  func testAroundEachHookOrder() throws {
    let log = Log()

    try spec("Around") {
      beforeAll { log.record("beforeAll") }
      aroundEach("outer") { callback in
        log.record("outer in")
        try callback()
        log.record("outer out")
      }
      aroundEach("inner") { callback in
        log.record("inner in")
        try callback()
        log.record("inner out")
      }
      beforeEach { log.record("beforeEach") }
      it("first") { log.record("first") }
      context("nested") {
        it("second") { log.record("second") }
      }
      afterEach { log.record("afterEach") }
      afterAll { log.record("afterAll") }
    }

    XCTAssertEqual(log.labels, [
      "beforeAll",
      "outer in", "inner in", "beforeEach", "first", "afterEach", "inner out", "outer out",
      "outer in", "inner in", "beforeEach", "second", "afterEach", "inner out", "outer out",
      "afterAll",
    ])
  }

  /// The `aroundEach` hook is not an activity itself. Its callbacks run in the
  /// activity of the group that declares it, and what it wraps nests inside.
  func testAroundEachActivityContext() throws {
    let log = Log()

    try spec("Around") {
      aroundEach { callback in
        log.record("around in")
        try callback()
        log.record("around out")
      }
      beforeEach { log.record("beforeEach") }
      it("first") { log.record("first") }
    }

    XCTAssertEqual(log.snapshots, [
      Snapshot(label: "around in", activity: "Around", path: ["Around"]),
      Snapshot(label: "beforeEach", activity: "before each", path: ["Around", "before each"]),
      Snapshot(label: "first", activity: "first", path: ["Around", "first"]),
      Snapshot(label: "around out", activity: "Around", path: ["Around"]),
    ])
  }

  /// A nested context is one element, so `aroundEach` wraps it once and not
  /// each example inside it.
  func testAroundEachWrapsNestedContextOnce() throws {
    let log = Log()

    try spec("Around") {
      aroundEach { callback in
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
