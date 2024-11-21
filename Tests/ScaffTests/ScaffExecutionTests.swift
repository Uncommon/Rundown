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
}
