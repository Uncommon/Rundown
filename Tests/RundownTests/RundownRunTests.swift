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
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      let describe = Describe("Skip one of two") {
        BeforeAll {
          ranBeforeAll.set()
        }
        BeforeEach {
          ranBeforeEach.set()
        }
        It("one", .skipped) {
          ran1.set()
        }
        It("two") {
          ran2.set()
        }
        AfterEach {
          ranAfterEach.set()
        }
        AfterAll {
          ranAfterAll.set()
        }
      }
      
      try runner(describe)
      
      XCTAssertTrue(ranBeforeAll.wrappedValue)
      XCTAssertTrue(ranBeforeEach.wrappedValue)
      XCTAssertFalse(ran1.wrappedValue)
      XCTAssertTrue(ran2.wrappedValue)
      XCTAssertTrue(ranAfterEach.wrappedValue)
      XCTAssertTrue(ranAfterAll.wrappedValue)
    }
  }
  
  // No hooks should run if all elements are skipped
  func testSkipHooks() throws {
    try useAllRunners { runner in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ranIt = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      try Describe("Skip hooks") {
        BeforeAll { ranBeforeAll.set() }
        BeforeEach { ranBeforeEach.set() }
        It("skips", .skipped) { ranIt.set() }
        AfterEach { ranAfterEach.set() }
        AfterAll { ranAfterAll.set() }
      }.run()
      
      XCTAssertFalse(ranBeforeAll.wrappedValue)
      XCTAssertFalse(ranBeforeEach.wrappedValue)
      XCTAssertFalse(ranIt.wrappedValue)
      XCTAssertFalse(ranAfterEach.wrappedValue)
      XCTAssertFalse(ranAfterAll.wrappedValue)
    }
  }

  func testFocusOneOfTwo() throws {
    try useAllRunners { runner in
      let ranBeforeAll = Box(false)
      let ranBeforeEach = Box(false)
      let ran1 = Box(false)
      let ran2 = Box(false)
      let ranAfterEach = Box(false)
      let ranAfterAll = Box(false)

      try Describe("Skip one of two") {
        BeforeAll { ranBeforeAll.set() }
        BeforeEach { ranBeforeEach.set() }
        It("one", .focused) { ran1.set() }
        It("two") { ran2.set() }
        AfterEach { ranAfterEach.set() }
        AfterAll { ranAfterAll.set() }
      }.run()
      
      XCTAssertTrue(ranBeforeAll.wrappedValue)
      XCTAssertTrue(ranBeforeEach.wrappedValue)
      XCTAssertTrue(ran1.wrappedValue)
      XCTAssertFalse(ran2.wrappedValue)
      XCTAssertTrue(ranAfterEach.wrappedValue)
      XCTAssertTrue(ranAfterAll.wrappedValue)
    }
  }
  
  func testDeepFocus() throws {
    try useAllRunners { runner in
      let ranBeforeAll1 = Box(false)
      let ranAfterAll1 = Box(false)
      let ranBeforeAll2 = Box(false)
      let ranAfterAll2 = Box(false)
      let beforeEachCount1 = Box(0)
      let afterEachCount1 = Box(0)
      let beforeEachCount2 = Box(0)
      let afterEachCount2 = Box(0)
      let ran2 = Box(false)

      try Describe("Deep focus") {
        BeforeAll { ranBeforeAll1.set() }
        BeforeEach { beforeEachCount1.bump() }
        It("skips") { XCTFail("ran outer unfocused test") }
        Describe("subgroup") {
          BeforeAll { ranBeforeAll2.set() }
          BeforeEach { beforeEachCount2.bump() }
          It("runs focused", .focused) { ran2.set() }
          It("skips") { XCTFail("ran inner unfocused test") }
          AfterEach { afterEachCount2.bump() }
          AfterAll { ranAfterAll2.set() }
        }
        AfterEach { afterEachCount1.bump() }
        AfterAll { ranAfterAll1.set() }
      }.run()
      
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
