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
}
