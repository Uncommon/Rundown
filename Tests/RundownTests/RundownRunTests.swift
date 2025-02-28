import XCTest
@testable import Rundown

/// Tests that verify execution on both the regular and XCTest version
/// of the run method.
@MainActor
class RundownRunTests: XCTestCase {
  func plainRunner(group: ExampleGroup<SyncCall>) throws {
    try group.run()
  }

  func asyncRunner(group: ExampleGroup<AsyncCall>) async throws {
    let expectation = self.expectation(description: "run as task")

    Task {
      try await group.run()
      expectation.fulfill()
    }
    await fulfillment(of: [expectation])
  }
  
  func asyncRunner(group: ExampleGroup<SyncCall>) async throws {
    try await asyncRunner(group: .init(fromSync: group))
  }

  func xcTestRunner(group: ExampleGroup<SyncCall>) throws {
    try group.runActivity(under: self)
  }
  
  func useAllRunners(test: @MainActor ((ExampleGroup<SyncCall>) async throws -> Void) async throws -> Void) async throws {
    try await test(plainRunner)
    try await test(xcTestRunner)
    try await test(asyncRunner)
  }

  func testAsyncIt() async throws {
    let ran = Box(false)

    try await Rundown.spec {
      it("does an async thing") {
        try await Task.sleep(for: .milliseconds(100))
        ran.set()
      }
    }

    XCTAssert(ran.wrappedValue)
  }

  func testSkipOneOfTwo() async throws {
    try await useAllRunners { runner in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let describe = describe("Skip one of two") {
        beforeAll {
          ranBeforeAll.set()
        }
        beforeEach {
          ranBeforeEach.set()
        }
        it("one", .skipped) {
          ran1.set()
        }
        it("two") {
          ran2.set()
        }
        afterEach {
          ranAfterEach.set()
        }
        afterAll {
          ranAfterAll.set()
        }
      }
      
      try await runner(describe)

      XCTAssertTrue(ranBeforeAll.wrappedValue)
      XCTAssertTrue(ranBeforeEach.wrappedValue)
      XCTAssertFalse(ran1.wrappedValue)
      XCTAssertTrue(ran2.wrappedValue)
      XCTAssertTrue(ranAfterEach.wrappedValue)
      XCTAssertTrue(ranAfterAll.wrappedValue)
    }
  }
  
  // No hooks should run if all elements are skipped
  func testSkipHooks() async throws {
    try await useAllRunners { runner in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ranIt = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let group = describe("Skip hooks") {
        beforeAll { ranBeforeAll.set() }
        beforeEach { ranBeforeEach.set() }
        it("skips", .skipped) { ranIt.set() }
        afterEach { ranAfterEach.set() }
        afterAll { ranAfterAll.set() }
      }

      try await runner(group)
      XCTAssertFalse(ranBeforeAll.wrappedValue)
      XCTAssertFalse(ranBeforeEach.wrappedValue)
      XCTAssertFalse(ranIt.wrappedValue)
      XCTAssertFalse(ranAfterEach.wrappedValue)
      XCTAssertFalse(ranAfterAll.wrappedValue)
    }
  }

  func testFocusOneOfTwo() async throws {
    try await useAllRunners { runner in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let group = describe("Skip one of two") {
        beforeAll { ranBeforeAll.set() }
        beforeEach { ranBeforeEach.set() }
        it("one", .focused) { ran1.set() }
        it("two") { ran2.set() }
        afterEach { ranAfterEach.set() }
        afterAll { ranAfterAll.set() }
      }

      try await runner(group)

      XCTAssertTrue(ranBeforeAll.wrappedValue)
      XCTAssertTrue(ranBeforeEach.wrappedValue)
      XCTAssertTrue(ran1.wrappedValue)
      XCTAssertFalse(ran2.wrappedValue)
      XCTAssertTrue(ranAfterEach.wrappedValue)
      XCTAssertTrue(ranAfterAll.wrappedValue)
    }
  }
  
  func testDeepFocus() async throws {
    try await useAllRunners { runner in
      let ranBeforeAll1 = Box(false)
      let ranAfterAll1 = Box(false)
      let ranBeforeAll2 = Box(false)
      let ranAfterAll2 = Box(false)
      let beforeEachCount1 = Box(0)
      let afterEachCount1 = Box(0)
      let beforeEachCount2 = Box(0)
      let afterEachCount2 = Box(0)
      let ran2 = Box(false)

      let group = describe("Deep focus") {
        beforeAll { ranBeforeAll1.set() }
        beforeEach { beforeEachCount1.bump() }
        it("skips") { XCTFail("ran outer unfocused test") }
        describe("subgroup") {
          beforeAll { ranBeforeAll2.set() }
          beforeEach { beforeEachCount2.bump() }
          it("runs focused", .focused) { ran2.set() }
          it("skips") { XCTFail("ran inner unfocused test") }
          afterEach { afterEachCount2.bump() }
          afterAll { ranAfterAll2.set() }
        }
        afterEach { afterEachCount1.bump() }
        afterAll { ranAfterAll1.set() }
      }

      try await runner(group)

      XCTAssert(ranBeforeAll1.wrappedValue)
      XCTAssertEqual(beforeEachCount1.wrappedValue, 1)
      XCTAssert(ranBeforeAll2.wrappedValue)
      XCTAssertEqual(beforeEachCount2.wrappedValue, 1)
      XCTAssert(ran2.wrappedValue)
      XCTAssertEqual(afterEachCount2.wrappedValue, 1)
      XCTAssert(ranAfterAll2.wrappedValue)
      XCTAssertEqual(afterEachCount1.wrappedValue, 1)
      XCTAssert(ranAfterAll1.wrappedValue)
    }
  }
}
