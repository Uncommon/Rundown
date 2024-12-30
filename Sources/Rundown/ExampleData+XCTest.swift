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
  
  @MainActor
  public func spec(@ExampleBuilder builder: () -> ExampleGroup,
                   function: String = #function) throws {
    let description = String(function.prefix { $0.isIdentifier })
      .droppingPrefix("test")
    try Describe(description, builder: builder).runActivity()
  }
  
  @MainActor
  public func spec(_ description: String,
                   @ExampleBuilder builder: () -> ExampleGroup) throws {
    try Describe(description, builder: builder).runActivity()
  }
}

extension Character {
  var isIdentifier: Bool {
    // Technically incomplete, but enough for most cases
    isLetter || isNumber || self == "_"
  }
}

/// Can serve as the principal class for a testing bundle in order to
/// register a `TestObserver` instance.
@MainActor
public class RundownPrincipal: NSObject {
  static var observer: TestObserver?
  
  public override init() {
    Self.registerObserver()
  }
  
  public static func registerObserver() {
    assert(Self.observer == nil, "Rundown.TestObserver already registered")
    let observer = TestObserver()
    
    XCTestObservationCenter.shared.addTestObserver(observer)
    Self.observer = observer
  }
}

final class TestObserver: NSObject, XCTestObservation {
  func testBundleWillStart(_ testBundle: Bundle) {
    // collect tests
  }
}

extension ExampleGroup {
  /// Runs the example with each element run as an `XCTContext` activity.
  /// Call this version instead of `run()` when using `XCTest`.
  @MainActor
  public func runActivity() throws {
    try ExampleRun.runActivity(self)
  }
  
  // Re-implementation of the original execute() because what needs to be
  // done with activities is too complex for a wrapper callback.
  @MainActor
  func executeActivity(in run: ExampleRun) throws {
    func executeHooks<P>(_ hooks: [Hook<P>]) throws {
      for hook in hooks {
        try run.withElementActivity(hook) { _ in
          try hook.execute()
        }
      }
    }
    func executeElement(_ element: some ExampleElement) throws {
      try run.withElementActivity(element) { _ in
        if let group = element as? ExampleGroup {
          try group.executeActivity(in: run)
        }
        else {
          try element.execute(in: run)
        }
      }
    }

    if beforeEach.isEmpty && afterEach.isEmpty {
      for element in elements {
        try executeElement(element)
      }
    }
    else {
      try executeHooks(beforeAll)
      for element in elements {
        // Use XCTContext.runActivity, but not the ExampleRun version,
        // to group items in the output without affecting the description.
        try XCTContext.runActivity(named: element.description) { _ in
          try executeHooks(beforeEach)
          try executeElement(element)
          try executeHooks(afterEach)
        }
      }
    }
    try executeHooks(afterAll)
  }
}

extension ExampleRun {
  // TODO: `It`s don't get logged
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
    try with(element) {
      try XCTContext.runActivity(named: element.description, block: block)
    }
  }
}
