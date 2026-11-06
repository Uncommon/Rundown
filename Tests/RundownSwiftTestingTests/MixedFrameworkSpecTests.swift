import Rundown
import RundownSwiftTesting
import Testing
import XCTest

private struct ExampleFailure: Error {}

struct SwiftTestingWithXCTestImported: SwiftTestingSuite {
  @Test func namedSyncSpecRecordsTheFullPath() throws {
    try withKnownIssue {
      try spec("Named sync spec") {
        context("nested group") {
          it("throws") { throw ExampleFailure() }
        }
      }
    } matching: { issue in
      issue.error is ExampleFailure
        && issue.comments.map(\.rawValue) == ["Named sync spec, nested group, throws"]
    }
  }

  @Test func namedAsyncSpecRecordsTheFullPath() async throws {
    try await withKnownIssue {
      try await spec("Named async spec") {
        context("nested group") {
          it("throws") {
            await Task.yield()
            throw ExampleFailure()
          }
        }
      }
    } matching: { issue in
      issue.error is ExampleFailure
        && issue.comments.map(\.rawValue) == ["Named async spec, nested group, throws"]
    }
  }
}

@MainActor
final class XCTestWithSwiftTestingImported: Rundown.TestCase {
  func testSpecReportsToXCTest() throws {
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      issue.associatedError is ExampleFailure
        && issue.compactDescription.hasPrefix("XCTest spec, throws ")
    }
    XCTExpectFailure("The XCTest runner records the thrown error", options: options)

    try spec("XCTest spec") {
      it("throws") { throw ExampleFailure() }
    }
  }
}
