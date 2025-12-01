import XCTest
@testable import Rundown

@MainActor
final class RundownTests: Rundown.TestCase {
  
  func testDescriptions() throws {
    try spec("ExampleRun") {
      context("first context") {
        it("has correct description") {
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

  func testBeforeAfterEach() throws {
    let beforeCount = Box(0)
    let itCount = Box(0)
    let afterCount = Box(0)

    try spec("Running 'each' hooks") {
      beforeEach {
        beforeCount.bump()
      }

      it("runs first test") {
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

  @TaskLocal static var local: Int = 0
  
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
