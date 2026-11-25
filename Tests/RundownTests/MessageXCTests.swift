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

  func testUnwrapFailureIsRecordedOnceAndContinues() throws {
    let log = Box([String]())
    let issues = Box([XCTIssue]())
    let unwrapLine = Box(0)
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      guard issue.type == .assertionFailure,
            issue.compactDescription.hasPrefix("Unwrap, fails ")
      else { return false }
      issues.wrappedValue.append(issue)
      return true
    }

    try XCTExpectFailure("XCTUnwrap records its own failure", options: options) {
      try spec("Unwrap") {
        it("fails") {
          unwrapLine.wrappedValue = #line + 1
          _ = try XCTUnwrap(nil as Int?)
          log.note("after unwrap")
        }
        it("continues") { log.note("next example") }
        afterEachPeer { log.note("afterEachPeer") }
        afterAll { log.note("afterAll") }
      }
    }
    XCTAssertEqual(issues.wrappedValue.count, 1)
    XCTAssertEqual(issues.wrappedValue.first?.sourceCodeContext.location?.fileURL.path, #filePath)
    XCTAssertEqual(issues.wrappedValue.first?.sourceCodeContext.location?.lineNumber,
                   unwrapLine.wrappedValue)
    XCTAssertEqual(log.wrappedValue, ["afterEachPeer", "next example", "afterEachPeer", "afterAll"])
  }

  func testUnwrapFailureInBeforeAllRunsTeardownAndContinues() throws {
    let log = Box([String]())
    let recorded = Box(0)
    let issues = Box([XCTIssue]())
    let unwrapLine = Box(0)
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      guard issue.type == .assertionFailure,
            issue.compactDescription.hasPrefix("Unwrap, context, before all ")
      else { return false }
      recorded.bump()
      issues.wrappedValue.append(issue)
      return true
    }

    try XCTExpectFailure("XCTUnwrap records its own setup failure", options: options) {
      try spec("Unwrap") {
        context("context") {
          beforeAll {
            unwrapLine.wrappedValue = #line + 1
            _ = try XCTUnwrap(nil as Int?)
            log.note("after unwrap")
          }
          it("never runs") { log.note("never runs") }
          afterAll { log.note("context afterAll") }
        }
        it("continues") { log.note("next example") }
        afterAll { log.note("afterAll") }
      }
    }
    XCTAssertEqual(recorded.wrappedValue, 1)
    XCTAssertEqual(issues.wrappedValue.first?.sourceCodeContext.location?.fileURL.path, #filePath)
    XCTAssertEqual(issues.wrappedValue.first?.sourceCodeContext.location?.lineNumber,
                   unwrapLine.wrappedValue)
    XCTAssertEqual(log.wrappedValue, ["context afterAll", "next example", "afterAll"])
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
    let ranAfterEachPeer = Box(false)
    let ranAfterAll = Box(false)

    try spec("Skip") {
      context("skipping in It") {
        it("skips") {
          try XCTSkipIf(true, "skip It")
        }
        afterEachPeer {
          ranAfterEachPeer.set()
        }
        afterAll {
          ranAfterAll.set()
        }
      }
    }
    XCTAssert(ranAfterEachPeer.wrappedValue, "AfterEachPeer did not run")
    XCTAssert(ranAfterAll.wrappedValue, "AfterAll did not run")
  }

  func testSkipInBeforeAll() throws {
    try spec("Skip") {
      context("skipping in BeforeAll") {
        beforeAll {
          try XCTSkipIf(true, "skip BeforeAll")
        }
        beforeEachPeer {
          XCTFail("should not run BeforeEachPeer")
        }
        it("skips elements") {
          XCTFail("should not run It")
        }
        afterEachPeer {
          XCTFail("should not run AfterEachPeer")
        }
        afterAll {
          XCTFail("should not run AfterAll")
        }
      }
    }
  }

  func testSkipInBeforeEachPeer() throws {
    let beforeEachPeerCount = Box(0)
    let ranAfterAll = Box(false)

    try spec("Skip") {
      context("skipping in BeforeEachPeer") {
        beforeEachPeer {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "Skip, skipping in BeforeEachPeer, before each peer")
          beforeEachPeerCount.bump()
          try XCTSkipIf(true, "skip BeforeEachPeer")
        }
        it("skips first element") {
          XCTFail("should not run It")
        }
        it("skips second element") {
          XCTFail("should not run It")
        }
        afterEachPeer {
          XCTFail("should not run AfterEachPeer")
        }
        afterAll {
          ranAfterAll.set()
        }
      }
    }
    XCTAssertEqual(beforeEachPeerCount.wrappedValue, 2,
                   "a skip should only skip its own element")
    XCTAssert(ranAfterAll.wrappedValue, "AfterAll did not run")
  }

  // A skip ends only the node that threw it. Each scenario has its own test so
  // that a skip that escapes can't end the test early and leave the other
  // scenarios' assertions unchecked.

  func testSkipInAfterEachPeerDoesNotAbortTheRun() throws {
    let log = Box([String]())

    try spec("Skip") {
      context("skipping in AfterEachPeer") {
        it("first") { log.note("first") }
        afterEachPeer("skips") { throw XCTSkip("skip AfterEachPeer") }
        afterEachPeer("next") { log.note("afterEachPeer") }
      }
      it("second") { log.note("second") }
      afterAll { log.note("afterAll") }
    }
    XCTAssertEqual(log.wrappedValue, ["first", "afterEachPeer", "second", "afterAll"])
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

  func testSkipInAroundEachPeerDoesNotAbortTheRun() throws {
    let log = Box([String]())

    try spec("Skip") {
      context("skipping in AroundEachPeer") {
        aroundEachPeer("skips") { callback in
          log.note("around")
          throw XCTSkip("skip AroundEachPeer")
        }
        it("not run") { XCTFail("should not run It") }
      }
      it("second") { log.note("second") }
    }
    XCTAssertEqual(log.wrappedValue, ["around", "second"])
  }

  /// An error is recorded where it happens, so the issue carries the full path
  /// including the name of the hook.
  func testErrorInBeforeEachPeerIncludesPath() throws {
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = {
      $0.type == .uncaughtException
        && $0.compactDescription.hasPrefix("Errors, in context, before each peer ")
    }
    XCTExpectFailure("the error is recorded as an issue", options: options)

    try spec("Errors") {
      context("in context") {
        beforeEachPeer {
          throw TestError(id: 1)
        }
        it("never runs") {
          XCTFail("should not run It")
        }
      }
    }
  }
}
