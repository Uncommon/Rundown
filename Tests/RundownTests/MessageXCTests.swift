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
  
  // The skip tests are split up so that a skip escaping from one scenario can't
  // end the test early and leave the other scenarios' assertions unchecked.

  func testSkipInIt() throws {
    let ranSecond = Box(false)

    try spec("Skip") {
      context("no hooks") {
        it("skips") {
          try XCTSkipIf(true, "skip It")
        }
        it("runs second thing") {
          ranSecond.set()
        }
      }
    }
    XCTAssert(ranSecond.wrappedValue, "second element did not run")
  }

  func testSkipInItRunsAfterHooks() throws {
    let ranAfterEach = Box(false)
    let ranAfterAll = Box(false)

    try spec("Skip") {
      context("skipping in It") {
        it("skips") {
          try XCTSkipIf(true, "skip It")
        }
        afterEach {
          ranAfterEach.set()
        }
        afterAll {
          ranAfterAll.set()
        }
      }
    }
    XCTAssert(ranAfterEach.wrappedValue, "AfterEach did not run")
    XCTAssert(ranAfterAll.wrappedValue, "AfterAll did not run")
  }

  func testSkipInBeforeAll() throws {
    try spec("Skip") {
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
          XCTFail("should not run AfterAll")
        }
      }
    }
  }

  // KNOWN BUG: an XCTSkip thrown from beforeEach is not caught by
  // runActivity() as documented, so it escapes spec() and the whole test is
  // reported as skipped. This asserts the documented behavior and expects it
  // to fail. Once the bug is fixed the strict expectation will start failing:
  // remove the XCTExpectFailure then.
  func testSkipInBeforeEach() throws {
    let ranAfterAll = Box(false)

    let expected = XCTExpectedFailure.Options()
    expected.isStrict = true
    expected.issueMatcher = {
      $0.compactDescription.contains("XCTSkip escaped")
        || $0.compactDescription.contains("AfterAll did not run")
    }
    XCTExpectFailure("XCTSkip in beforeEach escapes the XCTest runner",
                     options: expected)

    do {
      try spec("Skip") {
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
            ranAfterAll.set()
          }
        }
      }
    }
    catch let skip as XCTSkip {
      XCTFail("XCTSkip escaped spec(): \(skip)")
    }
    XCTAssert(ranAfterAll.wrappedValue, "AfterAll did not run")
  }
}
