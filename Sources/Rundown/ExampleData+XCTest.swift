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

extension ExampleGroup {
  /// Runs the example with each element run as an `XCTContext` activity.
  /// Call this version instead of `run()` when using `XCTest`.
  @MainActor
  public func runActivity() throws {
    try ExampleRun.runActivity(self)
  }
}

extension ExampleRun {
  @TaskLocal
  private static var activityBox: ActivityBox?
  
  /// The `XCTActivity` for the currently executing test element.
  @MainActor
  static var activity: XCTActivity? { activityBox?.activity }
  
  @MainActor
  public func runActivity(_ group: ExampleGroup) throws {
    func runHooks<P>(_ hooks: [Hook<P>]) throws {
      for hook in hooks {
        try withElementActivity(hook) {
          try hook.execute(in: self)
        }
      }
    }
    func runElement(_ element: some ExampleElement) throws {
      try withElementActivity(element) {
        switch element {
            case let subgroup as ExampleGroup:
              try runActivity(subgroup)
            case let within as Within:
              // Do the "within" logic manually to maintain @MainActor and
              // the use of runActivity
              try within.executor {
                try runActivity(within.group)
              }
            default:
                try element.execute(in: self)
        }
      }
    }
    
    try runHooks(group.beforeAll)
    if group.beforeEach.isEmpty && group.afterEach.isEmpty {
      for element in group.elements {
        try runElement(element)
      }
    }
    else {
      for element in group.elements {
        // Use XCTContext.runActivity, but not the ExampleRun version,
        // to group items in the output without affecting the description.
        try Self.withCurrentActivity(named: element.description) {
          try runHooks(group.beforeEach)
          try runElement(element)
          try runHooks(group.afterEach)
        }
      }
    }
    try runHooks(group.afterAll)
  }
  
  @MainActor
  func withElementActivity(_ element: some Element,
                           block: () throws -> Void) rethrows {
    try with(element) {
      try Self.withCurrentActivity(named: element.description, block: block)
    }
  }

  @MainActor
  public static func runActivity(_ group: ExampleGroup) throws {
    let run = ExampleRun()

    if let current {
      logger.error("running new element \"\(group.description)\" when already running \"\(current.description)\"")
    }
    try ExampleRun.$current.withValue(run) {
      try run.withElementActivity(group) {
        try run.runActivity(group)
      }
    }
  }
  
  @MainActor
  static func withCurrentActivity(named name: String, block: () throws -> Void) rethrows {
    try XCTContext.runActivity(named: name) { activity in
      try Self.$activityBox.withValue(.init(activity)) {
        try block()
      }
    }
  }
  
  /// Sendable container to hold an `XCTActivity` in task-local storage.
  /// Since `XCTContext.runActivity()` is a `@MainActor` function, the
  /// task-local variable will only ever be set on the main actor, so data
  /// race issues are ignored.
  class ActivityBox: @unchecked Sendable {
    let activity: XCTActivity
    init(_ activity: XCTActivity) { self.activity = activity }
  }
}
