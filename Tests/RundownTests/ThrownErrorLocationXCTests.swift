import XCTest
import Rundown

private struct LocatedXCTestFailure: Error {
  let line: Int
}

@MainActor
final class ThrownErrorLocationXCTests: Rundown.TestCase {
  @ExampleBuilder<SyncMainCall>
  private func sharedFailures() -> ExampleGroup<SyncMainCall> {
    context("setup") {
      let line = #line + 1
      beforeAll { throw LocatedXCTestFailure(line: line) }
      it("skipped") { XCTFail("Ran after shared setup failed") }
    }
    let line = #line + 1
    it("throws") { throw LocatedXCTestFailure(line: line) }
  }

  func testThrownErrorsKeepDeclarationLocationsAndPaths() throws {
    let issues = Box([XCTIssue]())
    let trace = Box([String]())
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      guard issue.associatedError is LocatedXCTestFailure
      else { return false }
      issues.wrappedValue.append(issue)
      return true
    }

    try XCTExpectFailure("Deliberate thrown errors", options: options) {
      try spec("Locations") {
        context("setup") {
          let line = #line + 1
          beforeAll { throw LocatedXCTestFailure(line: line) }
          beforeAll { XCTFail("Ran remaining setup") }
          it("skipped") { XCTFail("Ran after failed setup") }
          let cleanupLine = #line + 1
          afterAll { throw LocatedXCTestFailure(line: cleanupLine) }
          afterAll { trace.note("cleanup") }
        }
        context("wrapper") {
          let line = #line + 1
          aroundEach { _ in throw LocatedXCTestFailure(line: line) }
          it("skipped") { XCTFail("Ran after failed wrapper") }
        }
        context("peer wrapper") {
          let line = #line + 1
          aroundEachPeer { _ in throw LocatedXCTestFailure(line: line) }
          it("skipped") { XCTFail("Ran after failed peer wrapper") }
        }
        sharedFailures().named("helper")
        let line = #line + 1
        it("throws", []) { throw LocatedXCTestFailure(line: line) }
        it("continues") { trace.note("sibling") }
      }
    }

    let recorded = issues.wrappedValue
    XCTAssertEqual(recorded.map(\.compactDescription), [
      "Locations, setup, before all uncaught exception",
      "Locations, setup, after all uncaught exception",
      "Locations, wrapper, around each uncaught exception",
      "Locations, peer wrapper, around each peer uncaught exception",
      "Locations, helper, setup, before all uncaught exception",
      "Locations, helper, throws uncaught exception",
      "Locations, throws uncaught exception",
    ])
    for issue in recorded {
      XCTAssertEqual(issue.sourceCodeContext.location?.fileURL.path, #filePath)
      XCTAssertEqual(issue.sourceCodeContext.location?.lineNumber,
                     (issue.associatedError as? LocatedXCTestFailure)?.line)
    }
    XCTAssertEqual(trace.wrappedValue, ["cleanup", "sibling"])
  }
}
