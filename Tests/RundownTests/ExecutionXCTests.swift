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
  func testBeforeAfterEachPeer() throws {
    let beforeCount = Box(0)
    let itCount = Box(0)
    let afterCount = Box(0)

    try spec("Running 'each' hooks") {
      beforeEachPeer {
        self.mainThing()
        beforeCount.bump()
      }

      it("runs first test") {
        MainActor.assertIsolated("MainActor isolation failed")
        XCTAssertEqual(beforeCount.wrappedValue, 1, "BeforeEachPeer missed")
        XCTAssertEqual(afterCount.wrappedValue, 0, "AfterEachPeer missed")
        itCount.bump()
      }

      context("in a context") {
        it("runs second test") {
          XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEachPeer missed")
          XCTAssertEqual(afterCount.wrappedValue, 1, "AfterEachPeer missed")
          itCount.bump()
        }
      }

      afterEachPeer {
        afterCount.bump()
      }
    }
    XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEachPeer didn't run correctly")
    XCTAssertEqual(itCount.wrappedValue, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount.wrappedValue, 2, "AfterEachPeer didn't run correctly")
  }
}
