import XCTest
import OSLog

/// This subclass of `XCTestCase` is necessary in order to include the full
/// example description when recording an issue.
open class TestCase: XCTestCase {
  let logger = Logger(subsystem: "Rundown", category: "TestCase")

  /// Adds the full test element description to the issue before recording
  public override func record(_ issue: XCTIssue) {
    guard let runner = ExampleRunner.current
    else {
      logger.warning("issue logged when no ExampleRunner is set")
      super.record(issue)
      return
    }
    let description = runner.description

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
    try Describe(description, builder: builder).runActivity(under: self)
  }
  
  @MainActor
  public func spec(_ description: String,
                   @ExampleBuilder builder: () -> ExampleGroup) throws {
    try Describe(description, builder: builder).runActivity(under: self)
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
  ///
  /// See `ExampleRunner.runActivity()` for more details.`
  @MainActor
  public func runActivity(under test: XCTestCase) throws {
    try ExampleRunner.runActivity(self, under: test)
  }
}

extension ExampleRunner {
  @TaskLocal
  private static var activityBox: ActivityBox?
  
  /// The `XCTActivity` for the currently executing test element.
  @MainActor
  static var activity: XCTActivity? { activityBox?.activity }
  
  /// Runs the elements of the given group, with each executing inside
  /// `XCTContext.runActivity()`.
  ///
  /// If an `XCTSkip` is caught while running `BeforeAll` hooks, the rest of
  /// the group is skipped, including any remaining `BeforeAll` and `AfterAll`
  /// hooks.
  ///
  /// If an `XCTSkip` is caught while running `BeforeEach` hooks, the rest of
  /// that element is skipped, including any remaining `BeforeEach` and
  ///  `AfterEach` hooks.
  ///
  /// If an `XCTSkip` is caught while running a test example, such as `It`,
  /// the corresponding `AfterEach` hooks will still run, and execution will
  /// continue with the next item in the group.
  ///
  /// Throwing `XCTSkip` in `AfterEach` or `AfterAll` hooks will not be caught.
  @MainActor
  public func runActivity(_ group: ExampleGroup, under test: XCTestCase) throws {
    func runHooks<P>(_ hooks: [TestHook<P>]) throws {
      for hook in filterSkip(hooks) {
        try withElementActivity(hook) {
          try hook.execute(in: self)
        }
      }
    }
    func runElement(_ element: some TestExample) throws {
      try withElementActivity(element) {
        switch element {
          case let subgroup as ExampleGroup:
            try runActivity(subgroup, under: test)
          //case let within as Within:
          //  // Do the "within" logic manually to maintain @MainActor and
          //  // the use of runActivity
          //  try within.executor.call(.sync {
          //    try runActivity(within.group, under: test)
          //  })
          default:
            do {
              try element.execute(in: self)
            }
            catch let skip as XCTSkip {
              logSkip(skip, element: element)
            }
            catch let error {
              // It's not clear if this should be .thrownError or .uncaughtException
              let issue = XCTIssue(type: .uncaughtException,
                                   compactDescription: "uncaught exception",
                                   detailedDescription: error.localizedDescription,
                                   sourceCodeContext: .init(),
                                   associatedError: error)
              test.record(issue)
            }
        }
      }
    }

    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    do {
      try runHooks(group.beforeAll)
    }
    catch let skip as XCTSkip {
      logSkip(skip, element: group)
      return
    }
    if group.beforeEach.isEmpty && group.afterEach.isEmpty {
      for element in group.elements {
        try runElement(element)
      }
    }
    else {
      for element in elements {
        // Use XCTContext.runActivity, but not the ExampleRunner version,
        // to group items in the output without affecting the description.
        try Self.withCurrentActivity(named: element.description) {
          do {
            try runHooks(group.beforeEach)
          }
          catch let skip as XCTSkip {
            logSkip(skip, element: element)
            return // from withCurrentActivity()
          }
          try runElement(element)
          try runHooks(group.afterEach)
        }
      }
    }
    try runHooks(group.afterAll)
  }
  
  @MainActor
  func logSkip(_ skip: XCTSkip, element: TestElement) {
    let message = skip.message.map { ": (\($0))" } ?? ""
    
    ExampleRunner.logger.info("Skipped \"\(ExampleRunner.current!.description)\"\(message)")
  }
  
  @MainActor
  func withElementActivity(_ element: some TestElement,
                           block: () throws -> Void) rethrows {
    try with(element) {
      try Self.withCurrentActivity(named: element.description, block: block)
    }
  }

  @MainActor
  public static func runActivity(_ group: ExampleGroup, under test: XCTestCase) throws {
    let runner = ExampleRunner()

    if let current {
      logger.error("running new element \"\(group.description)\" when already running \"\(current.description)\"")
    }
    try ExampleRunner.$current.withValue(runner) {
      try runner.withElementActivity(group) {
        try runner.runActivity(group, under: test)
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
