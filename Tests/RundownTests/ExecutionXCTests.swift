import XCTest
import Rundown

final class ExecutionXCTests: Rundown.TestCase {
  
  @MainActor func mainThing() {}
  
  @MainActor
  func testHookBeforeContext() throws {
    let ranBeforeAll = Box(false)
    let ranIt = Box(false)
    
    try spec { @MainActor in
      beforeAll { @MainActor in
        self.mainThing()
        ranBeforeAll.set()
      }
      
      context("Search by summary") { @MainActor in
        it("finds items") { @MainActor in
          ranIt.set()
        }
      }
    }

    XCTAssert(ranBeforeAll.wrappedValue, "BeforeAll did not run")
    XCTAssert(ranIt.wrappedValue, "It did not run")
  }

  @MainActor
  func testBeforeAfterEach() throws {
    let beforeCount = Box(0)
    let itCount = Box(0)
    let afterCount = Box(0)

    try spec("Running 'each' hooks") {
      beforeEach {
        self.mainThing()
        beforeCount.bump()
      }

      it("runs first test") {
        MainActor.assertIsolated("MainActor isolation failed")
        XCTAssertEqual(beforeCount.wrappedValue, 1, "BeforeEach missed")
        XCTAssertEqual(afterCount.wrappedValue, 0, "AfterEach missed")
        itCount.bump()
      }

      context("in a context") {
        it("runs second test") {
          XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEach missed")
          XCTAssertEqual(afterCount.wrappedValue, 1, "AfterEach missed")
          itCount.bump()
        }
      }

      afterEach {
        afterCount.bump()
      }
    }
    XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount.wrappedValue, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount.wrappedValue, 2, "AfterEach didn't run correctly")
  }
}
