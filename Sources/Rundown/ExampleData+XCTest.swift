import XCTest
import OSLog

/// This subclass of `XCTestCase` is necessary in order to include the full
/// example description when recording an issue.
open class TestCase: XCTestCase {
  let logger = Logger(subsystem: "Rundown", category: "TestCase")

  /// Adds the full test element description to the issue before recording
  public override func record(_ issue: XCTIssue) {
    guard let run = ExampleRun.current
    else {
      logger.warning("issue logged when no ExampleRun is set")
      super.record(issue)
      return
    }
    let description = run.description

    let newIssue = XCTIssue(
      type: issue.type,
      compactDescription: "\(description) \(issue.compactDescription)",
      detailedDescription: issue.description,
      sourceCodeContext: issue.sourceCodeContext,
      associatedError: issue.associatedError,
      attachments: issue.attachments)

    super.record(newIssue)
  }
}

extension ExampleGroup {
  /// Runs the example with each element run as an `XCTContext` activity.
  /// Call this version instead of `run()` when using `XCTest`.
  @MainActor
  public func runActivity() throws {
    try ExampleRun.runActivity(self)
  }
  
  @MainActor
  func executeActivity(in run: ExampleRun) throws {
    try execute {
      element in
      try run.withElementActivity(element) { _ in
        switch element {
          case let group as ExampleGroup:
            try group.executeActivity(in: run)
          case let example as ExampleElement:
            try example.execute(in: run)
          default:
            try element.execute()
        }
      }
    }
  }
}

extension ExampleRun {
  @MainActor
  public static func runActivity(_ element: ExampleGroup) throws {
    let run = ExampleRun()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try ExampleRun.$current.withValue(run) {
      try run.withElementActivity(element) { _ in
        try element.executeActivity(in: run)
      }
    }
  }
  
  @MainActor
  func withElementActivity(_ element: some Element,
                           block: (XCTActivity) throws -> Void) rethrows {
    try withElement(element) {
      try XCTContext.runActivity(named: element.description, block: block)
    }
  }
}
