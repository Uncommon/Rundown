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

  func testSkipInBeforeEach() throws {
    let beforeEachCount = Box(0)
    let ranAfterAll = Box(false)

    try spec("Skip") {
      context("skipping in BeforeEach") {
        beforeEach {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "Skip, skipping in BeforeEach, before each")
          beforeEachCount.bump()
          try XCTSkipIf(true, "skip BeforeEach")
        }
        it("skips first element") {
          XCTFail("should not run It")
        }
        it("skips second element") {
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
    XCTAssertEqual(beforeEachCount.wrappedValue, 2,
                   "a skip should only skip its own element")
    XCTAssert(ranAfterAll.wrappedValue, "AfterAll did not run")
  }

  // A skip ends only the node that threw it. Each scenario has its own test so
  // that a skip that escapes can't end the test early and leave the other
  // scenarios' assertions unchecked.

  func testSkipInAfterEachDoesNotAbortTheRun() throws {
    let log = Box([String]())

    try spec("Skip") {
      context("skipping in AfterEach") {
        it("first") { log.note("first") }
        afterEach("skips") { throw XCTSkip("skip AfterEach") }
        afterEach("next") { log.note("afterEach") }
      }
      it("second") { log.note("second") }
      afterAll { log.note("afterAll") }
    }
    XCTAssertEqual(log.wrappedValue, ["first", "afterEach", "second", "afterAll"])
  }

  func testSkipInAfterAllDoesNotAbortTheRun() throws {
    let log = Box([String]())

    try spec("Skip") {
      context("skipping in AfterAll") {
        it("first") { log.note("first") }
        afterAll("skips") { throw XCTSkip("skip AfterAll") }
        afterAll("next") { log.note("afterAll") }
      }
      it("second") { log.note("second") }
    }
    XCTAssertEqual(log.wrappedValue, ["first", "afterAll", "second"])
  }

  func testSkipInAroundEachDoesNotAbortTheRun() throws {
    let log = Box([String]())

    try spec("Skip") {
      context("skipping in AroundEach") {
        aroundEach("skips") { callback in
          log.note("around")
          throw XCTSkip("skip AroundEach")
        }
        it("not run") { XCTFail("should not run It") }
      }
      it("second") { log.note("second") }
    }
    XCTAssertEqual(log.wrappedValue, ["around", "second"])
  }

  /// An error is recorded where it happens, so the issue carries the full path
  /// including the name of the hook.
  func testErrorInBeforeEachIncludesPath() throws {
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = {
      $0.type == .uncaughtException
        && $0.compactDescription.hasPrefix("Errors, in context, before each ")
    }
    XCTExpectFailure("the error is recorded as an issue", options: options)

    try spec("Errors") {
      context("in context") {
        beforeEach {
          throw TestError(id: 1)
        }
        it("never runs") {
          XCTFail("should not run It")
        }
      }
    }
  }
}
