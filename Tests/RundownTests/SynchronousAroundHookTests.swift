import XCTest
import Rundown

final class SynchronousAroundHookTests: XCTestCase {
  private func helper(_ events: Box<[String]>, peer: Bool) -> ExampleGroup<SyncCall> {
    if peer {
      return describe("helper") {
        beforeAll { events.note("helper setup") }
        aroundEachPeer("scope") { run in
          events.note("enter")
          try run()
          events.note("exit")
        }
        it("records its execution") { events.note("body") }
        afterAll { events.note("helper cleanup") }
      }
    }
    return describe("helper") {
      beforeAll { events.note("helper setup") }
      aroundEach("scope") { run in
        events.note("enter")
        try run()
        events.note("exit")
      }
      it("records its execution") { events.note("body") }
      afterAll { events.note("helper cleanup") }
    }
  }

  func testExplicitConversionRejectsRootAndNestedWrappers() {
    for peer in [false, true] {
      let events = Box([String]())
      let group = helper(events, peer: peer)
      let nested: ExampleGroup<SyncCall> = describe("root") { group }
      let hook = peer ? "around each peer: scope" : "around each: scope"
      for (source, path) in [(group, ["helper", hook]), (nested, ["root", "helper", hook])] {
        XCTAssertThrowsError(try ExampleGroup<AsyncCall>(fromSync: source)) { error in
          XCTAssertEqual((error as? SynchronousAroundHookError)?.path, path)
          XCTAssertTrue(error.localizedDescription.contains("try await"))
        }
      }
      XCTAssertTrue(events.wrappedValue.isEmpty)
    }
  }

  func testExplicitConversionRejectsWrappersEvenInExcludedGroups() {
    let group: ExampleGroup<SyncCall> = describe("excluded", .excluded) {
      helper(Box([]), peer: false)
    }
    XCTAssertThrowsError(try ExampleGroup<AsyncCall>(fromSync: group)) { error in
      XCTAssertEqual((error as? SynchronousAroundHookError)?.path,
                     ["excluded", "helper", "around each: scope"])
    }
  }

  func testAsyncRunRejectsWrappersBeforeSetupOrExamples() async throws {
    for peer in [false, true] {
      let events = Box([String]())
      let group: ExampleGroup<AsyncCall> = describe("root") {
        beforeAll { events.note("root setup") }
        it("runs before the helper") { events.note("sibling") }
        helper(events, peer: peer)
        afterAll { events.note("root cleanup") }
      }

      do {
        try await group.run()
        XCTFail("Accepted a synchronous around hook in an async group")
      }
      catch let error as SynchronousAroundHookError {
        XCTAssertEqual(error.path, ["root", "helper", peer ? "around each peer: scope" : "around each: scope"])
      }
      XCTAssertTrue(events.wrappedValue.isEmpty)
      XCTAssertNil(ExampleRunner.current)
    }
  }

  func testSyncRunKeepsWrappersAndTheirScopes() throws {
    for peer in [false, true] {
      let events = Box([String]())
      try helper(events, peer: peer).run()
      XCTAssertEqual(events.wrappedValue, ["helper setup", "enter", "body", "exit", "helper cleanup"])
    }
  }

  func testAsyncValidationIgnoresUnselectedGroupsAndExcludedHooks() async throws {
    for focused in [false, true] {
      let events = Box([String]())
      let allowed: ExampleGroup<SyncCall> = describe("excluded wrappers") {
        aroundEachPeer(.excluded) { _ in XCTFail("Ran an excluded peer wrapper") }
        aroundEach(.excluded) { _ in XCTFail("Ran an excluded wrapper") }
        it("runs without excluded wrappers") { events.note("allowed") }
      }
      let group: ExampleGroup<AsyncCall> = describe("root") {
        if focused {
          helper(events, peer: true)
          fIt("runs when selected") { events.note("selected") }
        }
        else {
          xContext("excluded group") { helper(events, peer: false) }
          allowed
        }
      }
      try await group.run()
      XCTAssertEqual(events.wrappedValue, focused ? ["selected"] : ["allowed"])
    }
  }
}

final class MainActorSynchronousAroundHookTests: XCTestCase, MainActorSuite {
  @MainActor
  func testAsyncMainActorRunRejectsSyncWrappersBeforeSetup() async throws {
    var events: [String] = []
    let helper: ExampleGroup<SyncMainCall> = describe("helper") {
      aroundEach { run in
        events.append("enter")
        try run()
      }
      it("records its execution") { events.append("body") }
    }
    let group: ExampleGroup<AsyncMainCall> = describe("root") {
      beforeAll { events.append("setup") }
      helper
      afterAll { events.append("cleanup") }
    }

    do {
      try await group.run()
      XCTFail("Accepted a synchronous main-actor around hook in an async group")
    }
    catch let error as SynchronousAroundHookError {
      XCTAssertEqual(error.path, ["root", "helper", "around each"])
    }
    XCTAssertTrue(events.isEmpty)
  }
}
