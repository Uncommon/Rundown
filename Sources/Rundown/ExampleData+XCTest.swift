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
    let description = specDescription(forFunction: function)
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
  fileprivate static var activityBox: Box<XCTActivity>?

  /// The `XCTActivity` for the currently executing test element.
  @MainActor
  static var activity: XCTActivity? { activityBox?.wrappedValue }

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
  /// An `XCTSkip` means that something does not apply, and only ends the
  /// element that threw it:
  ///
  /// If an `XCTSkip` is caught while running `BeforeAll` hooks, the rest of
  /// the group is skipped, including any remaining `BeforeAll` and `AfterAll`
  /// hooks, since nothing was set up.
  ///
  /// If an `XCTSkip` is caught while running `BeforeEach` hooks, the rest of
  /// that element is skipped, including any remaining `BeforeEach` and
  /// `AfterEach` hooks. The group continues with its next element.
  ///
  /// If an `XCTSkip` is caught while running a test example, such as `It`,
  /// the corresponding `AfterEach` hooks will still run, and execution will
  /// continue with the next item in the group.
  ///
  /// If an `XCTSkip` is thrown in an `AfterEach`, `AfterAll` or `AroundEach`
  /// hook, it is logged and ignored, and the rest of the run carries on.
  ///
  /// `.concurrent` is ignored: the elements of a concurrent group run one
  /// after another.
  @MainActor
  public static func runActivity(_ group: ExampleGroup<SyncMainCall>, under test: XCTestCase) throws {
    try group.node.run(with: XCTestReporter(test: test))
  }
}

/// The reporter for `XCTest`: each node is an `XCTContext` activity, errors
/// are recorded as issues, and `XCTSkip` is a skip.
///
/// `XCTContext.runActivity()` takes a sync closure and only works on the main
/// thread, so this only works with the sync traversal, and from the main actor.
struct XCTestReporter: Reporter, @unchecked Sendable {
  // XCTestCase isn't Sendable. The reporter only uses it from the main actor.
  let test: XCTestCase

  var allowsConcurrency: Bool { false }

  func scope(for node: ExampleNode, _ body: () async -> Void) async {
    preconditionFailure("the XCTest reporter only works with the sync traversal")
  }

  func scope(for node: ExampleNode, _ body: () -> Void) {
    // The traversal's closure isn't Sendable, but this runs it right here, on
    // the same thread, so nothing is actually shared.
    withoutActuallyEscaping(body) { body in
      nonisolated(unsafe) let body = body

      MainActor.assumeIsolated {
        XCTContext.runActivity(named: node.description) { activity in
          ExampleRunner.$activityBox.withValue(.init(activity)) {
            body()
          }
        }
      }
    }
  }

  func classify(_ error: any Error) -> ErrorKind {
    error is XCTSkip ? .skip : .failure
  }

  /// Records an error as an issue on the test, with the full path of the
  /// element that threw. This is called while that element is still the
  /// current one, so that the path is right.
  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> Disposition {
    switch kind {
      case .skip:
        let message = (error as? XCTSkip)?.message.map { ": (\($0))" } ?? ""
        ExampleRunner.logger.info("Skipped \"\(ExampleRunner.current?.description ?? node.description)\"\(message)")
      case .failure:
        // It's not clear if this should be .thrownError or .uncaughtException
        let issue = XCTIssue(type: .uncaughtException,
                             compactDescription: "uncaught exception",
                             detailedDescription: error.localizedDescription,
                             sourceCodeContext: .init(),
                             associatedError: error)
        test.record(issue)
    }
    return .record
  }
}
#endif
