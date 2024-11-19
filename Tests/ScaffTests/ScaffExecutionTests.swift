import XCTest
import Scaff

final class ScaffExecutionTests: XCTestCase {
  @TestExample
  func testOneIt() throws {
    It("works") {
      XCTAssert(true)
    }
  }
}
