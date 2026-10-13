import Foundation
import OSLog

/// Tracks the execution of an example group in order to construct the full name
/// of the current element.
///
/// While a spec is running, `ExampleRunner.current` is the runner for it. That
/// is how code inside an example can find out which example it is in, such as to
/// name a log entry or an attachment.
public class ExampleRunner: @unchecked Sendable, CustomStringConvertible {
  // Manual lock for unchecked sendability
  private let lock = NSRecursiveLock()
  internal static let logger = Logger(subsystem: "Rundown", category: "ExampleRunner")

  /// The elements that are running, outermost first, for the current task. This
  /// is a task-local instead of a property of the runner so that examples that
  /// run concurrently each have their own path: a child task starts with the
  /// stack of the group that started it, and what it pushes stays its own.
  ///
  /// Code that runs on other threads, such as `DispatchQueue.concurrentPerform()`,
  /// has to bind it again explicitly.
  @TaskLocal
  static var elementStack: [any TestElement] = []

  /// The descriptions of the elements that are running, from the outermost
  /// group down to the innermost: the spec, any enclosing `describe` and
  /// `context` groups, and the example or hook itself.
  ///
  /// This is the path of whatever is running in the calling task, so in a group
  /// with the `.concurrent` trait each example sees its own.
  public var path: [String] {
    Self.elementStack.map { $0.description }
  }

  /// The elements in `path` joined into a single string, such as
  /// "Spec, in a context, does a thing".
  public var description: String {
    path.joined(separator: ", ")
  }

  /// The runner for the spec that is running, or `nil` outside of a spec.
  @TaskLocal
  public static var current: ExampleRunner? = nil

  internal init() {}

  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try block()
  }

  @DeAsyncRD
  func with(_ element: some TestElement, block: () async throws -> Void) async rethrows {
    try await Self.$elementStack.withValue(Self.elementStack + [element]) {
      try await block()
    }
  }

  @DeAsyncRD @MainActor
  func withMain(_ element: some TestElement, block: @MainActor () async throws -> Void) async rethrows {
    try await Self.$elementStack.withValue(Self.elementStack + [element]) {
      try await block()
    }
  }

  @DeAsyncRD
  func runHooks<P>(_ hooks: [TestHook<P, AsyncCall>]) async throws {
    for hook in filterExcluded(hooks) {
      try await with(hook) {
        try await hook.execute(in: self)
      }
    }
  }
  
  @DeAsyncRD @MainActor
  func runHooks<P>(_ hooks: [TestHook<P, AsyncMainCall>]) async throws {
    for hook in filterExcluded(hooks) {
      try await withMain(hook) {
        try await hook.execute(in: self)
      }
    }
  }

  /// Runs "after" hooks. Unlike `runHooks()`, a hook that throws does not stop
  /// the rest: teardown should always be attempted in full. The first error
  /// is rethrown once they have all run.
  @DeAsyncRD
  func runCleanupHooks<P>(_ hooks: [TestHook<P, AsyncCall>]) async throws {
    var firstError: (any Error)?

    for hook in filterExcluded(hooks) {
      do {
        try await with(hook) {
          try await hook.execute(in: self)
        }
      }
      catch {
        firstError = firstError ?? error
      }
    }
    if let firstError {
      throw firstError
    }
  }

  // MainActor version of the above runCleanupHooks
  @DeAsyncRD @MainActor
  func runCleanupHooks<P>(_ hooks: [TestHook<P, AsyncMainCall>]) async throws {
    var firstError: (any Error)?

    for hook in filterExcluded(hooks) {
      do {
        try await withMain(hook) {
          try await hook.execute(in: self)
        }
      }
      catch {
        firstError = firstError ?? error
      }
    }
    if let firstError {
      throw firstError
    }
  }

  @DeAsyncRD @Sendable @_disfavoredOverload
  func runSubElement<E: TestExample>(_ element: E,
                                     group: ExampleGroup<AsyncCall>,
                                     runInner: @Sendable (E) async throws -> Void) async throws {
    let aroundEachHooks = filterExcluded(group.aroundEachHooks)
    
    if aroundEachHooks.isEmpty {
      try await runInner(element)
    }
    else {
      try await runAround(hooks: aroundEachHooks, element: element, runInner: runInner)
    }
  }
  
  @DeAsyncRD(stripSendable: .function)
  @Sendable @MainActor @_disfavoredOverload
  func runSubElement<E: TestExample>(_ element: E,
                                     group: ExampleGroup<AsyncMainCall>,
                                     runInner: @MainActor (E) async throws -> Void) async throws {
    let aroundEachHooks = filterExcluded(group.aroundEachHooks)
    
    if aroundEachHooks.isEmpty {
      try await runInner(element)
    }
    else {
      try await runAround(hooks: aroundEachHooks, element: element, runInner: runInner)
    }
  }
  
  @DeAsyncRD(stripSendable: .function) @Sendable @_disfavoredOverload
  func runAround<E: TestExample>(hooks: [AroundEach<AsyncCall>],
                                 element: E,
                                 runInner: @Sendable (E) async throws -> Void) async throws {
    if let hook = hooks.first {
      try await hook.execute {
        try await runAround(hooks: Array(hooks.dropFirst()),
                            element: element,
                            runInner: runInner)
      }
    }
    else {
      try await runInner(element)
    }
  }

  @DeAsyncRD(stripSendable: .function)
  @Sendable @MainActor @_disfavoredOverload
  func runAround<E: TestExample>(hooks: [AroundEach<AsyncMainCall>],
                                 element: E,
                                 runInner: @MainActor (E) async throws -> Void) async throws {
    if let hook = hooks.first {
      try await hook.execute {
        try await runAround(hooks: Array(hooks.dropFirst()),
                            element: element,
                            runInner: runInner)
      }
    }
    else {
      try await runInner(element)
    }
  }
  
  /// Executes the elements of a group. This is managed by the runner instead of
  /// the group itself because the runner can have logic that it needs to apply
  /// at each step.
  ///
  /// An error does not skip teardown or the remaining elements:
  ///
  /// - If a `beforeAll` hook throws, the elements of the group are skipped but
  ///   its `afterAll` hooks still run.
  /// - If a `beforeEach` hook throws, that element is skipped but its
  ///   `afterEach` hooks still run.
  /// - If an element or an `afterEach` hook throws, the group carries on with
  ///   its next element.
  /// - Every `afterEach` and `afterAll` hook runs, even if one before it threw.
  ///
  /// Once everything has run, the first error is rethrown.
  public func run(_ group: ExampleGroup<SyncCall>) throws {
    @Sendable func runSubElementInner(_ element: some TestExample) throws {
      var firstError: (any Error)?

      do {
        try runHooks(group.beforeEachHooks)
        try with(element) {
          switch element {
            case let subgroup as ExampleGroup<SyncCall>:
              try run(subgroup)
            case let it as It<SyncCall>:
              try it.execute(in: self)
            case _ as ExampleGroup<AsyncCall>, _ as It<AsyncCall>:
              // TestBuilder<SyncCall> shouldn't accept any AsyncCall
              // elements, so this shouldn't happen.
              throw UnexpectedAsyncError()
            default:
              preconditionFailure("unexpected element type")
          }
        }
      }
      catch {
        firstError = error
      }
      // Undo what beforeEach did, even if it or the element failed
      do {
        try runCleanupHooks(group.afterEachHooks)
      }
      catch {
        firstError = firstError ?? error
      }
      if let firstError {
        throw firstError
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    var firstError: (any Error)?

    do {
      try runHooks(group.beforeAllHooks)
      if group.traits.contains(where: { $0 is ConcurrentTrait }) {
        // Foundation locks rather than Mutex, which needs iOS 18 and friends
        let elementError = Box<(any Error)?>(nil)
        // GCD threads don't inherit task-locals, so the runner and the path
        // have to be bound again for each element.
        let stack = Self.elementStack

        DispatchQueue.concurrentPerform(iterations: elements.count) {
          let element = elements[$0]

          Self.$current.withValue(self) {
            Self.$elementStack.withValue(stack) {
              do {
                try runSubElement(element, group: group, runInner: runSubElementInner)
              }
              catch let error {
                withLock {
                  if elementError.wrappedValue == nil {
                    elementError.wrappedValue = error
                  }
                }
              }
            }
          }
        }
        firstError = elementError.wrappedValue
      }
      else {
        for element in elements {
          do {
            try runSubElement(element, group: group, runInner: runSubElementInner)
          }
          catch {
            firstError = firstError ?? error
          }
        }
      }
    }
    catch {
      // beforeAll failed, so none of the elements ran
      firstError = error
    }
    do {
      try runCleanupHooks(group.afterAllHooks)
    }
    catch {
      firstError = firstError ?? error
    }
    if let firstError {
      throw firstError
    }
  }

  // Duplicated from the other non-async run(), with MainActor call types
  // and disallowing concurrent tests.
  /// Executes the elements of a group. This is managed by the runner instead of
  /// the group itself because the runner can have logic that it needs to apply
  /// at each step. See `run(_: ExampleGroup<SyncCall>)` for how errors are
  /// handled.
  @MainActor
  public func run(_ group: ExampleGroup<SyncMainCall>) throws {
    @MainActor func runSubElementInner(_ element: some TestExample) throws {
      var firstError: (any Error)?

      do {
        try runHooks(group.beforeEachHooks)
        try with(element) {
          switch element {
            case let subgroup as ExampleGroup<SyncMainCall>:
              try run(subgroup)
            case let it as It<SyncMainCall>:
              try it.execute(in: self)
            case _ as ExampleGroup<AsyncMainCall>, _ as It<AsyncMainCall>:
              // TestBuilder<SyncCall> shouldn't accept any AsyncCall
              // elements, so this shouldn't happen.
              throw UnexpectedAsyncError()
            default:
              preconditionFailure("unexpected element type")
          }
        }
      }
      catch {
        firstError = error
      }
      // Undo what beforeEach did, even if it or the element failed
      do {
        try runCleanupHooks(group.afterEachHooks)
      }
      catch {
        firstError = firstError ?? error
      }
      if let firstError {
        throw firstError
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    // Rejected up front: a beforeAll that had already run would never get its
    // matching afterAll.
    if group.traits.contains(where: { $0 is ConcurrentTrait }) {
      throw ConcurrentDisallowedError()
    }

    var firstError: (any Error)?

    do {
      try runHooks(group.beforeAllHooks)
      for element in elements {
        do {
          try runSubElement(element, group: group, runInner: runSubElementInner)
        }
        catch {
          firstError = firstError ?? error
        }
      }
    }
    catch {
      // beforeAll failed, so none of the elements ran
      firstError = error
    }
    do {
      try runCleanupHooks(group.afterAllHooks)
    }
    catch {
      firstError = firstError ?? error
    }
    if let firstError {
      throw firstError
    }
  }

  // Similar to the non-async version, except that runSubElementInner handles
  // both sync and async elements, and concurrency is implemented with tasks
  // instead of GCD.
  /// Executes the elements of a group. This is managed by the runner instead of
  /// the group itself because the runner can have logic that it needs to apply
  /// at each step. See `run(_: ExampleGroup<SyncCall>)` for how errors are
  /// handled.
  public func run(_ group: ExampleGroup<AsyncCall>) async throws {
    @Sendable func runSubElementInner(_ element: some TestExample) async throws {
      var firstError: (any Error)?

      do {
        try await runHooks(group.beforeEachHooks)
        try await with(element) {
          switch element {
            case let subgroup as ExampleGroup<AsyncCall>:
              try await run(subgroup)
            case let subgroup as ExampleGroup<SyncCall>:
              try run(subgroup)
            case let it as It<AsyncCall>:
              try await it.execute(in: self)
            case let it as It<SyncCall>:
              try it.execute(in: self)
            default:
              preconditionFailure("unexpected element type")
          }
        }
      }
      catch {
        firstError = error
      }
      // Undo what beforeEach did, even if it or the element failed
      do {
        try await runCleanupHooks(group.afterEachHooks)
      }
      catch {
        firstError = firstError ?? error
      }
      if let firstError {
        throw firstError
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    var firstError: (any Error)?

    do {
      try await runHooks(group.beforeAllHooks)
      if group.traits.contains(where: { $0 is ConcurrentTrait }) {
        // The children catch their own errors, rather than throwing out of the
        // task group, so that one failure doesn't cancel its siblings.
        let elementError = Box<(any Error)?>(nil)

        await withTaskGroup(of: Void.self) { taskGroup in
          for element in elements {
            taskGroup.addTask {
              do {
                try await self.runSubElement(element, group: group, runInner: runSubElementInner)
              }
              catch {
                self.withLock {
                  if elementError.wrappedValue == nil {
                    elementError.wrappedValue = error
                  }
                }
              }
            }
          }
        }
        firstError = elementError.wrappedValue
      }
      else {
        for element in elements {
          do {
            try await runSubElement(element, group: group, runInner: runSubElementInner)
          }
          catch {
            firstError = firstError ?? error
          }
        }
      }
    }
    catch {
      // beforeAll failed, so none of the elements ran
      firstError = error
    }
    do {
      try await runCleanupHooks(group.afterAllHooks)
    }
    catch {
      firstError = firstError ?? error
    }
    if let firstError {
      throw firstError
    }
  }

  // Duplicated from the other async run(), with MainActor call types
  // and disallowing concurrent tests.
  /// Executes the elements of a group. This is managed by the runner instead of
  /// the group itself because the runner can have logic that it needs to apply
  /// at each step. See `run(_: ExampleGroup<SyncCall>)` for how errors are
  /// handled.
  @MainActor
  public func run(_ group: ExampleGroup<AsyncMainCall>) async throws {
    @MainActor func runSubElementInner(_ element: some TestExample) async throws {
      var firstError: (any Error)?

      do {
        try await runHooks(group.beforeEachHooks)
        try await withMain(element) {
          switch element {
            case let subgroup as ExampleGroup<AsyncMainCall>:
              try await run(subgroup)
            case let subgroup as ExampleGroup<SyncMainCall>:
              try run(subgroup)
            case let it as It<AsyncMainCall>:
              try await it.execute(in: self)
            case let it as It<SyncMainCall>:
              try it.execute(in: self)
            default:
              preconditionFailure("unexpected element type")
          }
        }
      }
      catch {
        firstError = error
      }
      // Undo what beforeEach did, even if it or the element failed
      do {
        try await runCleanupHooks(group.afterEachHooks)
      }
      catch {
        firstError = firstError ?? error
      }
      if let firstError {
        throw firstError
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    // Rejected up front: a beforeAll that had already run would never get its
    // matching afterAll.
    if group.traits.contains(where: { $0 is ConcurrentTrait }) {
      throw ConcurrentDisallowedError()
    }

    var firstError: (any Error)?

    do {
      try await runHooks(group.beforeAllHooks)
      for element in elements {
        do {
          try await runSubElement(element, group: group, runInner: runSubElementInner)
        }
        catch {
          firstError = firstError ?? error
        }
      }
    }
    catch {
      // beforeAll failed, so none of the elements ran
      firstError = error
    }
    do {
      try await runCleanupHooks(group.afterAllHooks)
    }
    catch {
      firstError = firstError ?? error
    }
    if let firstError {
      throw firstError
    }
  }

  func filterExcluded<E: TestElement>(_ elements: [E]) -> [E] {
    elements.filter({ !$0.isExcluded })
  }
  
  func filterFocusSkip(_ elements: [any TestExample]) -> [any TestExample] {
    let nonSkipped = elements.filter { !$0.isExcluded }
    let focused = nonSkipped.filter(\.isDeepFocused)
    
    return focused.isEmpty ? nonSkipped : focused
  }

  @DeAsyncRD
  public static func run(_ element: ExampleGroup<AsyncCall>) async throws {
    let runner = ExampleRunner()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try await ExampleRunner.$current.withValue(runner) {
      // A new run has its own path, even if it was started from inside another
      try await ExampleRunner.$elementStack.withValue([]) {
        try await runner.with(element) {
          try await element.execute(in: runner)
        }
      }
    }
  }

  @DeAsyncRD @MainActor
  public static func run(_ element: ExampleGroup<AsyncMainCall>) async throws {
    let runner = ExampleRunner()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try await ExampleRunner.$current.withValue(runner) {
      // A new run has its own path, even if it was started from inside another
      try await ExampleRunner.$elementStack.withValue([]) {
        try await runner.withMain(element) {
          try await element.execute(in: runner)
        }
      }
    }
  }
}

