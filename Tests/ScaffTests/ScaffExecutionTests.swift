import XCTest
import Scaff

final class ScaffExecutionTests: Scaff.TestCase {
  @TestExample
  func testOneIt() throws {
    It("works") {
      XCTAssert(true)
    }
  }

  @TestExample
  func testOneItFails() throws {
    It("fails") {
      XCTExpectFailure(strict: true) {
        $0.compactDescription.starts(with: "OneItFails, fails")
      }
      XCTAssert(false)
    }
  }

  func testExecuteDescribe() throws {
    var executed = false

    let test = Describe("Running the test") {
      It("works") {
        executed = true
      }
    }
    try ExampleRun.run(test)
    XCTAssert(executed)
  }

  func testBeforeAfterAll() throws {
    var didBefore = false
    var didIt = false
    var didAfter = false

    let test = Describe("Running hooks") {
      BeforeAll {
        didBefore = true
      }

      It("works") {
        didIt = true
      }

      AfterAll {
        didAfter = true
      }
    }

    try ExampleRun.run(test)
    XCTAssert(didBefore, "BeforeAll did not execute")
    XCTAssert(didIt, "It did not execute")
    XCTAssert(didAfter, "AfterAll did not execute")
  }

  func testBeforeAfterEach() throws {
    var beforeCount = 0
    var itCount = 0
    var afterCount = 0

    let test = Describe("Running each hooks") {
      BeforeEach {
        beforeCount += 1
      }

      It("runs first test") {
        XCTAssertEqual(beforeCount, 1)
        XCTAssertEqual(afterCount, 0)
        itCount += 1
      }

      It("runs second test") {
        XCTAssertEqual(beforeCount, 2)
        XCTAssertEqual(afterCount, 1)
        itCount += 1
      }

      AfterEach {
        afterCount += 1
      }
    }

    try ExampleRun.run(test)
    XCTAssertEqual(beforeCount, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount, 2, "AfterEach didn't run correctly")
  }

  func testSingleItForLoop() throws {
    let expected = 3
    var count = 0

    let test = Describe("For loop") {
      for _ in 1...expected {
        It("iterates") {
          count += 1
        }
      }
    }

    try ExampleRun.run(test)
    XCTAssertEqual(count, expected)
  }

  func testDoubleItForLoop() throws {
    let expected = 3
    var count1 = 0
    var count2 = 0

    let test = Describe("For loop") {
      for _ in 1...expected {
        It("iterates 1") {
          count1 += 1
        }
        It("iterates 2") {
          count2 += 1
        }
      }
    }

    try ExampleRun.run(test)
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
  }

  func testHookForLoop() throws {
    let expected = 3
    var beforeCount = 0
    var count1 = 0
    var count2 = 0
    var afterCount = 0

    let test = Describe("For loop") {
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
    }

    try ExampleRun.run(test)
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
    XCTAssertEqual(beforeCount, expected)
    XCTAssertEqual(afterCount, expected)
  }
}
