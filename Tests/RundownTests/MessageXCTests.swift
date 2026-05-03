import XCTest
@testable import Rundown

@MainActor
final class MessageXCTests: Rundown.TestCase {
  
  @MainActor func mainThing() {}
  
  func testDescriptions() throws {
    try spec("ExampleRun") {
      context("first context") {
        it("has correct description") {
          self.mainThing()
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRun, first context, has correct description")
        }
      }
      context("second context") {
        it("has correct description") {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRun, second context, has correct description")
        }
      }
    }
  }
  
  func testSkip() throws {
    let ranSecond = Box(false)
    let ranAfterEach = Box(false)
    let ranAfterAll1 = Box(false)
    let ranAfterAll2 = Box(false)

    try spec {
      context("no hooks") {
        it("skips") {
          try XCTSkipIf(true, "skip It")
        }
        it("runs second thing") {
          ranSecond.set()
        }
      }
      context("skipping in BeforeAll") {
        beforeAll {
          try XCTSkipIf(true, "skip BeforeAll")
        }
        beforeEach {
          XCTFail("should not run BeforeEach")
        }
        it("skips elements") {
          XCTFail("should not run It")
        }
        afterEach {
          XCTFail("should not run AfterEach")
        }
        afterAll {
          XCTFail("should not run AfterEach")
        }
      }
      context("skipping in BeforeEach") {
        beforeEach {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "Skip, skipping in BeforeEach, before each")
          try XCTSkipIf(true, "skip BeforeEach")
        }
        it("skips elements") {
          XCTFail("should not run It")
        }
        afterEach {
          XCTFail("should not run AfterEach")
        }
        afterAll {
          ranAfterAll1.set()
        }
      }
      context("skipping in It") {
        it("skips") {
          try XCTSkipIf(true, "skip It")
        }
        afterEach {
          ranAfterEach.set()
        }
        afterAll {
          ranAfterAll2.set()
        }
      }
    }
    XCTAssert(ranSecond.wrappedValue, "second element did not run")
    XCTAssert(ranAfterEach.wrappedValue, "AfterEach did not run")
    XCTAssert(ranAfterAll1.wrappedValue, "AfterAll did not run")
    XCTAssert(ranAfterAll2.wrappedValue, "AfterAll did not run")
  }
}
