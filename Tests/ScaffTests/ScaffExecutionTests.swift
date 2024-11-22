import XCTest
import Scaff

final class ScaffExecutionTests: XCTestCase {
  @TestExample
  func testOneIt() throws {
    It("works") {
      XCTAssert(true)
    }
  }

  func testExecuteDescribe() throws {
    var executed = false

    let test = Describe("Running the test") {
      It("works") {
        executed = true
      }
    }
    try test.execute()
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

    try test.execute()
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

    try test.execute()
    XCTAssertEqual(beforeCount, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount, 2, "AfterEach didn't run correctly")
  }
}
