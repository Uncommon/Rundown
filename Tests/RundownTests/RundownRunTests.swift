import XCTest
@testable import Rundown

/// Tests that verify execution on both the regular and XCTest version
/// of the run method.
@MainActor
class RundownRunTests: XCTestCase {
  func plainRunner(group: ExampleGroup) throws {
    try group.run()
  }
  
  func xcTestRunner(group: ExampleGroup) throws {
    try group.runActivity(under: self)
  }
  
  func useAllRunners(test: ((ExampleGroup) throws -> Void) throws -> Void) throws {
    try test(plainRunner)
    try test(xcTestRunner)
  }
  
  func testSkipOneOfTwo() throws {
    try useAllRunners { runner in
      var ranBeforeAll = false
      var ranBeforeEach = false
      var ran1 = false
      var ran2 = false
      var ranAfterEach = false
      var ranAfterAll = false
      
      let describe = Describe("Skip one of two") {
        BeforeAll {
          ranBeforeAll = true
        }
        BeforeEach {
          ranBeforeEach = true
        }
        It("one", .skipped) {
          ran1 = true
        }
        It("two") {
          ran2 = true
        }
        AfterEach {
          ranAfterEach = true
        }
        AfterAll {
          ranAfterAll = true
        }
      }
      
      try runner(describe)
      
      XCTAssertTrue(ranBeforeAll)
      XCTAssertTrue(ranBeforeEach)
      XCTAssertFalse(ran1)
      XCTAssertTrue(ran2)
      XCTAssertTrue(ranAfterEach)
      XCTAssertTrue(ranAfterAll)
    }
  }
  
  // No hooks should run if all elements are skipped
  func testSkipHooks() throws {
    try useAllRunners { runner in
      var ranBeforeAll = false
      var ranBeforeEach = false
      var ranIt = false
      var ranAfterEach = false
      var ranAfterAll = false
      
      try Describe("Skip hooks") {
        BeforeAll { ranBeforeAll = true }
        BeforeEach { ranBeforeEach = true }
        It("skips", .skipped) { ranIt = true }
        AfterEach { ranAfterEach = true }
        AfterAll { ranAfterAll = true }
      }.run()
      
      XCTAssertFalse(ranBeforeAll)
      XCTAssertFalse(ranBeforeEach)
      XCTAssertFalse(ranIt)
      XCTAssertFalse(ranAfterEach)
      XCTAssertFalse(ranAfterAll)
    }
  }

  func testFocusOneOfTwo() throws {
    try useAllRunners { runner in
      var ranBeforeAll = false
      var ranBeforeEach = false
      var ran1 = false
      var ran2 = false
      var ranAfterEach = false
      var ranAfterAll = false
      
      try Describe("Skip one of two") {
        BeforeAll { ranBeforeAll = true }
        BeforeEach { ranBeforeEach = true }
        It("one", .focused) { ran1 = true }
        It("two") { ran2 = true }
        AfterEach { ranAfterEach = true }
        AfterAll { ranAfterAll = true }
      }.run()
      
      XCTAssertTrue(ranBeforeAll)
      XCTAssertTrue(ranBeforeEach)
      XCTAssertTrue(ran1)
      XCTAssertFalse(ran2)
      XCTAssertTrue(ranAfterEach)
      XCTAssertTrue(ranAfterAll)
    }
  }
  
  func testDeepFocus() throws {
    try useAllRunners { runner in
      var ranBeforeAll1 = false
      var ranAfterAll1 = false
      var ranBeforeAll2 = false
      var ranAfterAll2 = false
      var beforeEachCount1 = 0
      var afterEachCount1 = 0
      var beforeEachCount2 = 0
      var afterEachCount2 = 0
      var ran2 = false
      
      try Describe("Deep focus") {
        BeforeAll { ranBeforeAll1 = true }
        BeforeEach { beforeEachCount1 += 1 }
        It("skips") { XCTFail("ran outer unfocused test") }
        Describe("subgroup") {
          BeforeAll { ranBeforeAll2 = true }
          BeforeEach { beforeEachCount2 += 1 }
          It("runs focused", .focused) { ran2 = true }
          It("skips") { XCTFail("ran inner unfocused test") }
          AfterEach { afterEachCount2 += 1}
          AfterAll { ranAfterAll2 = true}
        }
        AfterEach { afterEachCount1 += 1 }
        AfterAll { ranAfterAll1 = true }
      }.run()
      
      XCTAssert(ranBeforeAll1)
      XCTAssertEqual(beforeEachCount1, 1)
      XCTAssert(ranBeforeAll2)
      XCTAssertEqual(beforeEachCount2, 1)
      XCTAssert(ran2)
      XCTAssertEqual(afterEachCount2, 1)
      XCTAssert(ranAfterAll2)
      XCTAssertEqual(afterEachCount1, 1)
      XCTAssert(ranAfterAll1)
    }
  }
}
