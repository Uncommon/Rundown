import XCTest
@testable import Rundown

// In an async test, `run(with:)` would pick the async version, so the sync one
// is called through these non-async functions.
private func runSync<Call: NodeCallType>(_ group: ExampleGroup<Call>) throws {
  try group.node.run(with: PlainReporter())
}

@MainActor
private func runSyncOnMainActor(_ group: ExampleGroup<SyncMainCall>) throws {
  try group.node.run(with: PlainReporter())
}

/// Checks `.concurrent` and the element path in the node traversal, using the
/// same scenarios as `MultiRunTests` and `MainActorErrorTests` do for the
/// existing runners. The sync version of the traversal runs children on GCD
/// threads and the async version in a task group.
final class NodeTraversalConcurrencyTests: XCTestCase {
  /// Runs the same description as a sync group and as an async group, through
  /// the matching version of the traversal.
  func bothFlavors(
    sync: () -> ExampleGroup<SyncCall>,
    async: () -> ExampleGroup<AsyncCall>,
    check: (String) -> Void
  ) async throws {
    check("sync")
    do { try runSync(sync()) } catch { XCTFail("sync: \(error)") }
    check("async")
    do { try await async().node.run(with: PlainReporter()) } catch { XCTFail("async: \(error)") }
  }

  func testPathOfNonConcurrentNodes() throws {
    let paths = Box([String]())

    try describe("Root") {
      beforeEach { paths.note(ExampleRunner.current?.description ?? "none") }
      it("first") { paths.note(ExampleRunner.current?.description ?? "none") }
      context("nested") {
        it("inner") { paths.note(ExampleRunner.current?.description ?? "none") }
      }
      afterAll { paths.note(ExampleRunner.current?.description ?? "none") }
    }.node.run(with: PlainReporter())

    XCTAssertEqual(paths.wrappedValue, [
      "Root, before each", "Root, first",
      "Root, before each", "Root, nested, inner",
      "Root, after all",
    ])
    XCTAssertNil(ExampleRunner.current, "the runner should not outlive the run")
  }

  func testAroundEachSeesTheGroupsPath() throws {
    let path = Box("")

    try describe("Root") {
      aroundEach { callback in
        path.wrappedValue = ExampleRunner.current?.description ?? "none"
        try callback()
      }
      it("first") {}
    }.node.run(with: PlainReporter())

    XCTAssertEqual(path.wrappedValue, "Root")
  }

  func testConcurrentChildrenOverlap() async throws {
    // Each example waits until the other has started, which only happens if
    // they really are running at once.
    let started = Box(0)
    let lock = NSLock()
    let timedOut = Box([String]())

    @Sendable func rendezvous(_ label: String) {
      lock.withLock { started.wrappedValue += 1 }
      let deadline = Date().addingTimeInterval(5)
      while lock.withLock({ started.wrappedValue }) < 2 {
        if Date() > deadline {
          lock.withLock { timedOut.note(label) }
          return
        }
        Thread.sleep(forTimeInterval: 0.001)
      }
    }

    try await bothFlavors(
      sync: {
        describe("overlap", .concurrent) {
          it("one") { rendezvous("sync one") }
          it("two") { rendezvous("sync two") }
        }
      },
      async: {
        describe("overlap", .concurrent) {
          it("one") { rendezvous("async one") }
          it("two") { rendezvous("async two") }
        }
      },
      check: { _ in started.wrappedValue = 0 })

    XCTAssertEqual(timedOut.wrappedValue, [])
  }

  func testConcurrentExamplesHaveTheirOwnPaths() async throws {
    let count = 16
    let wrong = Box([String]())
    let lock = NSLock()

    @Sendable func check(_ expected: String) {
      Thread.sleep(forTimeInterval: Double.random(in: 0...0.01))
      let actual = ExampleRunner.current?.description ?? "no runner"

      if actual != expected {
        lock.withLock { wrong.note("expected \"\(expected)\" but got \"\(actual)\"") }
      }
    }

    @Sendable func spec() -> ExampleGroup<SyncCall> {
      describe("paths") {
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
    }

    try runSync(spec())
    XCTAssertEqual(wrong.wrappedValue, [], "sync")
    try await ExampleGroup<AsyncCall>(fromSync: spec()).node.run(with: PlainReporter())
    XCTAssertEqual(wrong.wrappedValue, [], "async")
  }

  func testConcurrentFailureRunsEverythingAndThrowsTheFirstError() async throws {
    let stepCount = 8

    @Sendable func spec(_ count: Box<Int>, _ ranAfterAll: Box<Bool>) -> ExampleGroup<SyncCall> {
      let lock = NSLock()
      return describe("concurrent failure", .concurrent) {
        for step in 1...stepCount {
          it("runs step \(step)") {
            lock.withLock { count.bump() }
            if step == 3 { throw TestError(id: 1) }
          }
        }
        afterAll { ranAfterAll.set() }
      }
    }

    for flavor in ["sync", "async"] {
      let count = Box(0)
      let ranAfterAll = Box(false)
      let group = spec(count, ranAfterAll)

      do {
        if flavor == "sync" {
          try runSync(group)
        }
        else {
          try await ExampleGroup<AsyncCall>(fromSync: group).node.run(with: PlainReporter())
        }
        XCTFail("\(flavor): no error thrown")
      }
      catch let error as TestError {
        XCTAssertEqual(error, TestError(id: 1), flavor)
      }
      XCTAssertEqual(count.wrappedValue, stepCount, flavor)
      XCTAssert(ranAfterAll.wrappedValue, "\(flavor): afterAll did not run")
    }
  }
}

final class NodeTraversalMainActorConcurrencyTests: XCTestCase, MainActorSuite {
  /// Main actor groups can't be concurrent, which has to be reported before
  /// anything runs.
  @MainActor
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

    XCTAssertThrowsError(try runSyncOnMainActor(syncGroup)) {
      XCTAssert($0 is ConcurrentDisallowedError, "sync: \($0)")
    }
    do {
      try await asyncGroup.node.run(with: PlainReporter())
      XCTFail("async: no error thrown")
    }
    catch {
      XCTAssert(error is ConcurrentDisallowedError, "async: \(error)")
    }
    XCTAssertEqual(log.wrappedValue, [])
  }
}
