import XCTest
import Synchronization
@testable import Rundown

/// Tests that verify execution on the regular, XCTest, and async versions
/// of the run method.
@MainActor
class RundownMultiRunTests: XCTestCase {
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
      let ranBeforeEach = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let describe = describe("Exclude one of two") {
        beforeAll {
          ranBeforeAll.set()
        }
        beforeEach {
          ranBeforeEach.set()
        }
        it("one", .excluded) {
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

      XCTAssertTrue(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranBeforeEach.wrappedValue, "\(type) failure")
      XCTAssertFalse(ran1.wrappedValue, "\(type) failure")
      XCTAssertTrue(ran2.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterEach.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }
  
  // No hooks should run if all elements are excluded
  func testExcludeHooks() async throws {
    try await useAllRunners { (runner, type) in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ranIt = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let group = describe("Skip hooks") {
        beforeAll { ranBeforeAll.set() }
        beforeEach { ranBeforeEach.set() }
        it("excludes", .excluded) { ranIt.set() }
        afterEach { ranAfterEach.set() }
        afterAll { ranAfterAll.set() }
      }

      try await runner(group)
      XCTAssertFalse(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranBeforeEach.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranIt.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranAfterEach.wrappedValue, "\(type) failure")
      XCTAssertFalse(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }

  func testFocusOneOfTwo() async throws {
    try await useAllRunners { (runner, type) in
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

      XCTAssertTrue(ranBeforeAll.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranBeforeEach.wrappedValue, "\(type) failure")
      XCTAssertTrue(ran1.wrappedValue, "\(type) failure")
      XCTAssertFalse(ran2.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterEach.wrappedValue, "\(type) failure")
      XCTAssertTrue(ranAfterAll.wrappedValue, "\(type) failure")
    }
  }
  
  func testDeepFocus() async throws {
    try await useAllRunners { (runner, type) in
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

      XCTAssert(ranBeforeAll1.wrappedValue, "\(type) failure")
      XCTAssertEqual(beforeEachCount1.wrappedValue, 1, "\(type) failure")
      XCTAssert(ranBeforeAll2.wrappedValue, "\(type) failure")
      XCTAssertEqual(beforeEachCount2.wrappedValue, 1, "\(type) failure")
      XCTAssert(ran2.wrappedValue, "\(type) failure")
      XCTAssertEqual(afterEachCount2.wrappedValue, 1, "\(type) failure")
      XCTAssert(ranAfterAll2.wrappedValue, "\(type) failure")
      XCTAssertEqual(afterEachCount1.wrappedValue, 1, "\(type) failure")
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
  
  func testAroundEach() async throws {
    // aroundEach can't be converted from sync to async, so the async runner
    // doesn't work
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      
      let group = describe("around each") {
        aroundEach { (callback) in
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
      
      XCTAssertEqual(
        result.wrappedValue,
        ["outer before", "inner before", "it", "inner after", "outer after"],
        "\(type) failure"
      )
    }
  }

  func testExcludedAroundEach() async throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      
      let group = describe("around each") {
        aroundEach(.excluded) { (callback) in
          result.wrappedValue.append("around")
          try callback()
        }
        it("works") {
          result.wrappedValue.append("it")
        }
      }
      
      try runner(group)
      
      XCTAssertEqual(
        result.wrappedValue,
        ["it"],
        "\(type) failure"
      )
    }
  }

  /// A second aroundEach should be executed inside the callback of the first
  func testDoubleAroundEach() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        aroundEach { (callback) in
          result.wrappedValue.append("around 1 start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around 1 end")
        }

        aroundEach { (callback) in
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
  
  func testAroundEachWithHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        beforeAll {
          result.wrappedValue.append("beforeAll")
        }
        aroundEach { (callback) in
          result.wrappedValue.append("around start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around end")
        }
        beforeEach {
          result.wrappedValue.append("beforeEach")
        }
        
        it("works") {
          result.wrappedValue.append("it")
        }
        
        afterEach {
          result.wrappedValue.append("afterEach")
        }
        afterAll {
          result.wrappedValue.append("afterAll")
        }
      }
      
      try runner(group)
      
      XCTAssertEqual(result.wrappedValue,
                     ["beforeAll",
                      "around start",
                      "beforeEach", "it", "afterEach",
                      "around end",
                      "afterAll",
                     ],
                     "\(type) failure")
    }
  }

  func testAroundEachOnlyAllHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        beforeAll {
          result.wrappedValue.append("beforeAll")
        }
        aroundEach { (callback) in
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

  func testAroundEachOnlyEachHooks() throws {
    try useSyncRunners { (runner, type) in
      let result = Box([String]())
      let group = describe("ArounchEach") {
        aroundEach { (callback) in
          result.wrappedValue.append("around start")
          try "".withCString { _ in
            try callback()
          }
          result.wrappedValue.append("around end")
        }
        beforeEach {
          result.wrappedValue.append("beforeEach")
        }

        it("works") {
          result.wrappedValue.append("it")
        }

        afterEach {
          result.wrappedValue.append("afterEach")
        }
      }
      
      try runner(group)

      XCTAssertEqual(result.wrappedValue,
                     ["around start",
                      "beforeEach", "it", "afterEach",
                      "around end",
                     ],
                     "\(type) failure")
    }
  }
}
