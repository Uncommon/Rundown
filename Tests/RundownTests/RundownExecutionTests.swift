import XCTest
@testable import Rundown

@MainActor
final class RundownExecutionTests: Rundown.TestCase {

  func testOneItFails() throws {
    try spec {
      It("fails") {
        let expectedDescription = "OneItFails, fails"
        
        XCTAssertEqual(ExampleRun.current?.description, expectedDescription)
        XCTExpectFailure(strict: true) {
          $0.compactDescription.starts(with: expectedDescription)
        }
        XCTAssert(false)
      }
    }
  }
  
  @Example @ExampleBuilder
  func oneItPeer() throws -> ExampleGroup {
    It("works") {
      XCTAssert(true)
    }
  }

  func testExecuteDescribe() throws {
    var executed = false

    try Describe("Running the test") {
      It("works") {
        executed = true
      }
    }.run()
    XCTAssert(executed)
  }
  
  func testDescriptions() throws {
    try Describe("ExampleRun") {
      Context("first context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRun.current!.description,
                         "ExampleRun, first context, has correct description")
        }
      }
      Context("second context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRun.current!.description,
                         "ExampleRun, second context, has correct description")
        }
      }
    }.run()
  }

  func testBeforeAfterAll() throws {
    var didBefore = false
    var didIt = false
    var didAfter = false

    try Describe("Running hooks") {
      BeforeAll {
        didBefore = true
      }

      It("works") {
        didIt = true
      }

      AfterAll {
        didAfter = true
      }
    }.run()
    XCTAssert(didBefore, "BeforeAll did not execute")
    XCTAssert(didIt, "It did not execute")
    XCTAssert(didAfter, "AfterAll did not execute")
  }

  func testSingleItForLoop() throws {
    let expected = 3
    var count = 0

    try Describe("For loop") {
      for _ in 1...expected {
        It("iterates") {
          count += 1
        }
      }
    }.run()
    XCTAssertEqual(count, expected)
  }

  func testDoubleItForLoop() throws {
    let expected = 3
    var count1 = 0
    var count2 = 0

    try Describe("For loop") {
      for _ in 1...expected {
        It("iterates 1") {
          count1 += 1
        }
        It("iterates 2") {
          count2 += 1
        }
      }
    }.run()
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
  }

  func testHookForLoop() throws {
    let expected = 3
    var beforeCount = 0
    var count1 = 0
    var count2 = 0
    var afterCount = 0

    try Describe("For loop") {
      for _ in 1...expected {
        BeforeAll {
          beforeCount += 1
        }
        It("iterates 1") {
          count1 += 1
        }
        It("iterates 2") {
          count2 += 1
        }
        AfterAll {
          afterCount += 1
        }
      }
    }.run()
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
    XCTAssertEqual(beforeCount, expected)
    XCTAssertEqual(afterCount, expected)
  }
  
  func testWithin() throws {
    var executed = false

    try Describe("Within") {
      Within("inside a callback") { callback in
        try "".withCString { _ in
          try callback()
        }
      } example: {
        It("works") {
          executed = true
        }
      }
    }.run()
    
    XCTAssert(executed)
  }
  
  func testSkipOneOfTwo() throws {
    var ranBeforeAll = false
    var ranBeforeEach = false
    var ran1 = false
    var ran2 = false
    var ranAfterEach = false
    var ranAfterAll = false
    
    try Describe("Skip one of two") {
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
    }.run()
    
    XCTAssertTrue(ranBeforeAll)
    XCTAssertTrue(ranBeforeEach)
    XCTAssertFalse(ran1)
    XCTAssertTrue(ran2)
    XCTAssertTrue(ranAfterEach)
    XCTAssertTrue(ranAfterAll)
  }
  
  // No hooks should run if all elements are skipped
  func testSkipHooks() throws {
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

  func testFocusOneOfTwo() throws {
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
  
  func testDeepFocus() throws {
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
