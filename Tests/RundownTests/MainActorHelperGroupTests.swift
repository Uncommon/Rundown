import XCTest
import Rundown  // Not @testable, so this only sees the public API

// Shared groups for main actor specs. The DSL functions for the main actor are
// members of `MainActorSuite`, so helpers that build groups need to be members
// of a type that conforms to it, rather than free functions: a protocol that
// extends `MainActorSuite` for helpers shared between test classes, or a small
// type of their own for a namespace. Inside them no closure needs marking
// with `@MainActor`.

@MainActor
private func isolatedRecord(_ log: Box<[String]>, _ entry: String) {
  MainActor.assertIsolated()
  log.note(entry)
}

/// Helpers that any test class can adopt
protocol SharedSearchGroups: MainActorSuite {}

extension SharedSearchGroups {
  @ExampleBuilder<SyncMainCall>
  func searchGroup(_ log: Box<[String]>) -> ExampleGroup<SyncMainCall> {
    beforeAll { isolatedRecord(log, "beforeAll") }
    aroundEach { callback in
      isolatedRecord(log, "around>")
      try callback()
      isolatedRecord(log, "<around")
    }
    beforeEach { isolatedRecord(log, "beforeEach") }
    it("first") { isolatedRecord(log, "first") }
    context("nested") {
      it("second") { isolatedRecord(log, "second") }
    }
    for index in 1...2 {
      it("loop \(index)") { isolatedRecord(log, "loop \(index)") }
    }
    if Bool.random() || true {
      it("conditional") { isolatedRecord(log, "conditional") }
    }
    afterEach { isolatedRecord(log, "afterEach") }
    afterAll { isolatedRecord(log, "afterAll") }
  }

  /// Examples with `await` work too
  @ExampleBuilder<AsyncMainCall>
  func asyncSearchGroup(_ log: Box<[String]>) -> ExampleGroup<AsyncMainCall> {
    beforeAll { isolatedRecord(log, "beforeAll") }
    it("sync") { isolatedRecord(log, "sync") }
    it("async") {
      await Task.yield()
      isolatedRecord(log, "async")
    }
    context("nested") {
      beforeEach { await Task.yield() }
      it("inner") { isolatedRecord(log, "inner") }
    }
    afterEach { isolatedRecord(log, "afterEach") }
    afterAll { isolatedRecord(log, "afterAll") }
  }
}

/// A namespace for groups that aren't tied to a test class
struct SharedGroups: MainActorSuite {
  @ExampleBuilder<SyncMainCall>
  func group(_ log: Box<[String]>) -> ExampleGroup<SyncMainCall> {
    context("namespace") {
      it("works") { isolatedRecord(log, "namespace") }
    }
  }
}

@MainActor
final class MainActorHelperGroupTests: Rundown.TestCase, SharedSearchGroups {
  /// The log that `searchGroup` should produce
  var expectedSearchLog: [String] {
    func wrapped(_ name: String) -> [String] {
      ["around>", "beforeEach", name, "afterEach", "<around"]
    }
    return ["beforeAll"]
      + ["first", "second", "loop 1", "loop 2", "conditional"].flatMap(wrapped)
      + ["afterAll"]
  }

  func testProtocolHelperGroupRuns() throws {
    let log = Box([String]())

    try searchGroup(log).run()
    XCTAssertEqual(log.wrappedValue, expectedSearchLog)
  }

  func testProtocolHelperGroupRunsAsXCTestActivities() throws {
    let log = Box([String]())

    try searchGroup(log).runActivity(under: self)
    XCTAssertEqual(log.wrappedValue, expectedSearchLog)
  }

  func testAsyncProtocolHelperGroupRuns() async throws {
    let log = Box([String]())

    try await asyncSearchGroup(log).run()
    XCTAssertEqual(log.wrappedValue,
                   ["beforeAll",
                    "sync", "afterEach",
                    "async", "afterEach",
                    "inner", "afterEach",
                    "afterAll"])
  }

  func testNamespaceGroupRuns() throws {
    let log = Box([String]())

    try SharedGroups().group(log).run()
    XCTAssertEqual(log.wrappedValue, ["namespace"])
  }

  /// A helper group can be a part of a bigger spec
  func testHelperGroupInsideASpec() throws {
    let log = Box([String]())

    try spec("outer") {
      beforeEach { isolatedRecord(log, "outer beforeEach") }
      searchGroup(log)
    }
    XCTAssertEqual(log.wrappedValue.first, "outer beforeEach")
    XCTAssertEqual(log.wrappedValue.last, "afterAll")
    XCTAssertEqual(log.wrappedValue.filter { $0 == "first" }.count, 1)
  }
}
