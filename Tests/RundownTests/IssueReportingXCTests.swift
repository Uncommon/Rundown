import XCTest
@testable import Rundown

@MainActor
final class IssueReportingXCTests: Rundown.TestCase {
  func testWarningKeepsSeverityAndMetadataInNestedExample() throws {
    let issue = makeIssue(type: .system, severity: .warning)
    let recorded = try captureIssue(issue, inExample: true)

    XCTAssertEqual(recorded.compactDescription,
                   "Reporting, outer, inner, preserves the diagnostic \(issue.compactDescription)")
    XCTAssertEqual(recorded.severity, .warning)
    XCTAssertFalse(recorded.isFailure)
    assertMetadata(recorded, matches: issue)
  }

  func testErrorKeepsSeverityAndMetadataInNestedExample() throws {
    let issue = makeIssue(type: .assertionFailure, severity: .error)
    let recorded = try captureIssue(issue, inExample: true)

    XCTAssertEqual(recorded.compactDescription,
                   "Reporting, outer, inner, preserves the diagnostic \(issue.compactDescription)")
    XCTAssertEqual(recorded.severity, .error)
    XCTAssertTrue(recorded.isFailure)
    assertMetadata(recorded, matches: issue)
  }

  func testIssuesPassThroughOutsideAnExample() throws {
    for severity: XCTIssue.Severity in [.warning, .error] {
      let issue = makeIssue(type: .system, severity: severity)
      let recorded = try captureIssue(issue, inExample: false)

      XCTAssertEqual(recorded.compactDescription, issue.compactDescription)
      assertMetadata(recorded, matches: issue)
    }
  }

  func testAbsentMetadataStaysAbsentInNestedExample() throws {
    let issue = XCTIssue(type: .thrownError,
                         compactDescription: "A diagnostic without optional metadata",
                         sourceCodeContext: XCTSourceCodeContext(callStack: [], location: nil))
    let recorded = try captureIssue(issue, inExample: true)

    XCTAssertEqual(recorded.compactDescription,
                   "Reporting, outer, inner, preserves the diagnostic \(issue.compactDescription)")
    assertMetadata(recorded, matches: issue)
  }

  private func makeIssue(type: XCTIssue.IssueType, severity: XCTIssue.Severity) -> XCTIssue {
    let location = XCTSourceCodeLocation(filePath: #filePath, lineNumber: #line)
    let symbol = XCTSourceCodeSymbolInfo(imageName: "DiagnosticFixture",
                                         symbolName: "publishChanges",
                                         location: location)
    let frame = XCTSourceCodeFrame(address: 0x1234, symbolInfo: symbol)
    let attachment = XCTAttachment(string: "Diagnostic attachment")
    attachment.name = "Runtime warning context"
    attachment.lifetime = .keepAlways
    attachment.userInfo = ["origin": "SwiftUI"]
    return XCTIssue(type: type,
                    compactDescription: "Publishing changes from within view updates is not allowed, this will cause undefined behavior.",
                    detailedDescription: "Additional diagnostic details",
                    sourceCodeContext: XCTSourceCodeContext(callStack: [frame], location: location),
                    associatedError: NSError(domain: "IssueReportingXCTests", code: 42,
                                             userInfo: [NSLocalizedDescriptionKey: "Underlying diagnostic",
                                                        "context": "view update"]),
                    attachments: [attachment],
                    severity: severity)
  }

  private func captureIssue(_ issue: XCTIssue, inExample: Bool) throws -> XCTIssue {
    let issues = Box([XCTIssue]())
    let originalDescription = issue.compactDescription
    let options = XCTExpectedFailure.Options()
    // XCTest matches warnings as well as errors. Capture either severity so
    // a regression is asserted below without making the diagnostic fail the suite.
    options.issueMatcher = { recorded in
      guard recorded.compactDescription.hasSuffix(originalDescription)
      else { return false }
      issues.wrappedValue.append(recorded)
      return true
    }

    try XCTExpectFailure("Deliberate diagnostic for reporting regression coverage", options: options) {
      if inExample {
        try spec("Reporting") {
          context("outer") {
            context("inner") {
              it("preserves the diagnostic") { self.record(issue) }
            }
          }
        }
      }
      else {
        XCTAssertNil(ExampleRunner.current)
        record(issue)
      }
    }

    XCTAssertEqual(issues.wrappedValue.count, 1)
    XCTAssertEqual(issue.compactDescription, originalDescription, "Recording must not mutate the original issue")
    return try XCTUnwrap(issues.wrappedValue.first)
  }

  private func assertMetadata(_ recorded: XCTIssue, matches original: XCTIssue,
                              file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(recorded.type, original.type, file: file, line: line)
    XCTAssertEqual(recorded.severity, original.severity, file: file, line: line)
    XCTAssertEqual(recorded.isFailure, original.isFailure, file: file, line: line)
    XCTAssertEqual(recorded.detailedDescription, original.detailedDescription, file: file, line: line)
    // Keeping the context object preserves both the location and symbolicated stack.
    XCTAssertTrue(recorded.sourceCodeContext === original.sourceCodeContext, file: file, line: line)
    XCTAssertEqual(recorded.associatedError as NSError?, original.associatedError as NSError?, file: file, line: line)
    XCTAssertEqual(recorded.attachments.count, original.attachments.count, file: file, line: line)
    for (actual, expected) in zip(recorded.attachments, original.attachments) {
      // Identity also preserves the payload, name, lifetime, and userInfo.
      XCTAssertTrue(actual === expected, file: file, line: line)
    }
  }
}
