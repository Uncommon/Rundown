#if canImport(XCTest)
import XCTest
import OSLog

/// This subclass of `XCTestCase` is necessary in order to include the full
/// example description when recording an issue.
open class TestCase: XCTestCase, MainActorSuite {
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
  
  /// Runs the given test steps using `XCTContext.runActivity()`.
  ///
  /// There is no `async` version of this function because
  /// `XCTContext` only supports using `runActivity()` on the main
  /// thread.
  @MainActor
  public func spec(@ExampleBuilder<SyncMainCall> builder: () -> ExampleGroup<SyncMainCall>,
                   function: String = #function) throws {
    let description = String(function.prefix { $0.isIdentifier })
      .droppingPrefix("test")
    let group: ExampleGroup<SyncMainCall> = describe(description, builder: builder)
      
    try group.runActivity(under: self)
  }
  
  /// Runs the given test steps using `XCTContext.runActivity()`.
  ///
  /// There is no `async` version of this function because
  /// `XCTContext` only supports using `runActivity()` on the main
  /// thread.
  @MainActor
  public func spec(_ description: String,
                   @ExampleBuilder<SyncMainCall> builder: () -> ExampleGroup<SyncMainCall>) throws {
    let group: ExampleGroup<SyncMainCall> = describe(description, builder: builder)
      
    try group.runActivity(under: self)
  }
}

extension ExampleGroup<SyncMainCall> {
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
  private static var activityBox: Box<XCTActivity>?
  
  /// The `XCTActivity` for the currently executing test element.
  @MainActor
  static var activity: XCTActivity? { activityBox?.wrappedValue }
  
  /// How a series of "before" hooks ended
  enum SetupResult {
    case completed
    /// A hook threw `XCTSkip`
    case skipped
    /// A hook threw some other error, which was recorded as an issue
    case failed
  }

  /// Records an error as an issue on the test, in the same way for hooks as
  /// for examples. This has to be called while the element that threw is still
  /// the current one, so that the issue gets its full path.
  @MainActor
  func recordUncaught(_ error: any Error, under test: XCTestCase) {
    // It's not clear if this should be .thrownError or .uncaughtException
    let issue = XCTIssue(type: .uncaughtException,
                         compactDescription: "uncaught exception",
                         detailedDescription: error.localizedDescription,
                         sourceCodeContext: .init(),
                         associatedError: error)
    test.record(issue)
  }

  // Like runHooks() but uses withElementActivity, and stops at the first hook
  // that skips or fails.
  @MainActor
  private func runSetupHooksXC<P>(_ hooks: [TestHook<P, SyncMainCall>],
                                  under test: XCTestCase) -> SetupResult {
    for hook in filterExcluded(hooks) {
      var result = SetupResult.completed

      withElementActivity(hook) {
        do {
          try hook.execute(in: self)
        }
        catch let skip as XCTSkip {
          logSkip(skip, element: hook)
          result = .skipped
        }
        catch {
          recordUncaught(error, under: test)
          result = .failed
        }
      }
      if result != .completed {
        return result
      }
    }
    return .completed
  }

  // Like runCleanupHooks() but uses withElementActivity. Every hook runs, and
  // failures are recorded as issues. An XCTSkip is not caught.
  @MainActor
  private func runCleanupHooksXC<P>(_ hooks: [TestHook<P, SyncMainCall>],
                                    under test: XCTestCase) throws {
    for hook in filterExcluded(hooks) {
      try withElementActivity(hook) {
        do {
          try hook.execute(in: self)
        }
        catch let skip as XCTSkip {
          throw skip
        }
        catch {
          recordUncaught(error, under: test)
        }
      }
    }
  }

  /// Runs the elements of the given group, with each executing inside
  /// `XCTContext.runActivity()`.
  ///
  /// Errors are recorded as issues, with the full path of the element that
  /// threw, and the run carries on: an error in a hook or an example does not
  /// skip teardown or the remaining elements.
  ///
  /// - If a `BeforeAll` hook fails, the elements of the group are skipped but
  ///   its `AfterAll` hooks still run.
  /// - If a `BeforeEach` hook fails, that element is skipped but its
  ///   `AfterEach` hooks still run.
  /// - Every `AfterEach` and `AfterAll` hook runs, even if one before it failed.
  ///
  /// An `XCTSkip` means that something does not apply, so there is nothing to
  /// undo:
  ///
  /// If an `XCTSkip` is caught while running `BeforeAll` hooks, the rest of
  /// the group is skipped, including any remaining `BeforeAll` and `AfterAll`
  /// hooks.
  ///
  /// If an `XCTSkip` is caught while running `BeforeEach` hooks, the rest of
  /// that element is skipped, including any remaining `BeforeEach` and
  ///  `AfterEach` hooks. The group continues with its next element.
  ///
  /// If an `XCTSkip` is caught while running a test example, such as `It`,
  /// the corresponding `AfterEach` hooks will still run, and execution will
  /// continue with the next item in the group.
  ///
  /// Throwing `XCTSkip` in `AfterEach` or `AfterAll` hooks will not be caught.
  @MainActor
  public func runActivity(_ group: ExampleGroup<SyncMainCall>, under test: XCTestCase) throws {
    let testBox = Box(test)
    
    @Sendable
    func runSubElementInner(_ element: some TestExample) throws {

      try MainActor.assumeIsolated {
        let currentTest = testBox.wrappedValue
        let setup = runSetupHooksXC(group.beforeEachHooks, under: currentTest)

        // Nothing was set up for a skipped element, so there is nothing to undo
        guard setup != .skipped
        else { return }

        if setup == .completed {
          try withElementActivity(element) {
            switch element {
              case let subgroup as ExampleGroup<SyncMainCall>:
                try runActivity(subgroup, under: currentTest)
              case let it as It<SyncMainCall>:
                do {
                  try it.execute(in: self)
                }
                catch let skip as XCTSkip {
                  logSkip(skip, element: element)
                }
                catch let error {
                  recordUncaught(error, under: currentTest)
                }
              default:
                preconditionFailure("unexpected element type")
            }
          }
        }
        try runCleanupHooksXC(group.afterEachHooks, under: currentTest)
      }
    }

    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    switch runSetupHooksXC(group.beforeAllHooks, under: test) {
      case .completed:
        break
      case .skipped:
        return
      case .failed:
        // The elements can't run, but whatever beforeAll managed to set up
        // still has to be undone.
        try runCleanupHooksXC(group.afterAllHooks, under: test)
        return
    }
    for element in elements {
      do {
        try runSubElement(element, group: group) { element in
          try MainActor.assumeIsolated {
            try runSubElementInner(element)
          }
        }
      }
      catch let skip as XCTSkip {
        // Only an AfterEach hook gets here, and those aren't caught
        throw skip
      }
      catch {
        // An aroundEach hook failed
        recordUncaught(error, under: test)
      }
    }
    try runCleanupHooksXC(group.afterAllHooks, under: test)
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
  public static func runActivity(_ group: ExampleGroup<SyncMainCall>, under test: XCTestCase) throws {
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
}
#endif
