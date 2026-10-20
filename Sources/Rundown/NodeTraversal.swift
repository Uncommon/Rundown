import Foundation

// This is the one traversal of a spec. It runs every spec: `ExampleRunner.run()`
// and `ExampleGroup.run()` in all four call types go through it, with
// `PlainReporter`, and `runActivity()` for XCTest goes through it with
// `XCTestReporter`.
//
// Isolation is part of the closure types, so the traversal is written once as
// async and the sync version is generated from it with @DeAsyncRD. Both handle
// non-isolated and main-actor nodes. The parts that differ between the flavors
// are in the helpers at the bottom.

// MARK: Traversal

extension ExampleNode {
  /// Runs a group as the root of a run, in its own scope, with a runner of its
  /// own and a fresh path. Errors that the reporter propagates are thrown after
  /// everything has run.
  @DeAsyncRD
  func run(with reporter: any Reporter) async throws {
    await checkCanRun()
    if let current = ExampleRunner.current {
      ExampleRunner.logger.error("running new element \"\(name)\" when already running \"\(current.description)\"")
    }

    var thrown: (any Error)?
    await ExampleRunner.$current.withValue(ExampleRunner()) {
      await ExampleRunner.$elementStack.withValue([]) {
        await withPath {
          await reporter.scope(for: self) {
            do { try await traverse(reporter) }
            catch { thrown = error }
          }
        }
      }
    }
    if let thrown { throw thrown }
  }

  /// Runs `body` with this node on the path, so that code inside it can find
  /// out where it is through `ExampleRunner.current`.
  @DeAsyncRD
  fileprivate func withPath(_ body: () async -> Void) async {
    await ExampleRunner.$elementStack.withValue(ExampleRunner.elementStack + [self]) {
      await body()
    }
  }

  /// What happened to a node that ran in its own scope
  fileprivate enum Outcome {
    /// Ran to completion with no issues
    case completed
    /// A skip, in a place where a skip is not a failure
    case skipped
    /// An error stopped it. This holds the error to rethrow, or `nil` if the
    /// reporter recorded it.
    case failed((any Error)?)
  }

  /// The body of a group: its hooks and children, but not its scope.
  @DeAsyncRD
  fileprivate func traverse(_ reporter: any Reporter) async throws {
    let selected = selectedChildren
    guard !selected.isEmpty
    else { return }

    // Rejected up front: a beforeAll that had already run would never get its
    // matching afterAll.
    let concurrent = isConcurrent && reporter.allowsConcurrency
    if concurrent && isolation == .mainActor {
      throw ConcurrentDisallowedError()
    }

    var firstError: (any Error)?
    var setUpSucceeded = true

    for hook in selectedHooks(.beforeAll) {
      switch await hook.runLeaf(reporter) {
        case .completed:
          continue
        case .skipped:
          // Skip execution and teardown
          return
        case .failed(let error):
          firstError = error
          setUpSucceeded = false
      }
      break
    }
    if setUpSucceeded {
      let childError = await forEachChild(selected, concurrently: concurrent) { child in
        try await self.runAround(self.selectedHooks(.aroundEach)[...], reporter) {
          try await self.runElement(child, reporter)
        }
      }
      firstError = firstError ?? childError
    }
    // Teardown runs even if setup failed
    for hook in selectedHooks(.afterAll) {
      if case .failed(let error) = await hook.runLeaf(reporter) {
        firstError = firstError ?? error
      }
    }
    if let firstError {
      throw firstError
    }
  }

  @DeAsyncRD
  fileprivate func runElement(_ child: ExampleNode, _ reporter: any Reporter) async throws {
    var firstError: (any Error)?
    var setUpSuccessful = true

    for hook in selectedHooks(.beforeEach) {
      switch await hook.runLeaf(reporter) {
        case .completed:
          continue
        case .skipped:
          return
        case .failed(let error):
          // The element doesn't run, but afterEach still does
          firstError = error
          setUpSuccessful = false
      }
      break
    }
    if setUpSuccessful {
      let outcome = await child.runChild(reporter)
      // An example that skips is swallowed, and afterEach still runs
      if case .failed(let error) = outcome {
        firstError = error
      }
    }
    for hook in selectedHooks(.afterEach) {
      if case .failed(let error) = await hook.runLeaf(reporter) {
        firstError = firstError ?? error
      }
    }
    if let firstError {
      throw firstError
    }
  }

  /// A nested group or an example, in its own scope
  @DeAsyncRD
  fileprivate func runChild(_ reporter: any Reporter) async -> Outcome {
    guard isGroup
    else {
      return await runLeaf(reporter)
    }

    var outcome = Outcome.completed

    await withPath {
      await reporter.scope(for: self) {
        // Errors from inside a group have already been reported
        do { try await traverse(reporter) }
        catch { outcome = .failed(error) }
      }
    }
    return outcome
  }

  /// An example or hook: calls its body in its scope, and reports an error.
  @DeAsyncRD
  fileprivate func runLeaf(_ reporter: any Reporter) async -> Outcome {
    var outcome = Outcome.completed

    await withPath {
      await reporter.scope(for: self) {
        do {
          try await callBody()
        }
        catch {
          outcome = outcomeOf(error, reporter)
        }
      }
    }
    return outcome
  }

  private func outcomeOf(_ error: any Error, _ reporter: any Reporter) -> Outcome {
    let kind = reporter.classify(error)
    let disposition = reporter.report(error, kind: kind, at: self)

    // A skip ends only the node that threw it, whether that's a setup hook, an
    // example or a teardown hook. What follows is up to the caller.
    if kind == .skip {
      return .skipped
    }
    return .failed(disposition == .propagate ? error : nil)
  }

  /// Nests the `aroundEach` hooks, outermost first, around `inner`.
  ///
  /// A hook has no scope, but an error that it throws itself is reported. One
  /// that comes out of `inner` has been reported already, so it is only
  /// passed along. See `innerThrew` below for how the two are told apart.
  @DeAsyncRD
  fileprivate func runAround(_ hooks: ArraySlice<ExampleNode>,
                             _ reporter: any Reporter,
                             inner: @Sendable () async throws -> Void) async throws {
    guard let hook = hooks.first else { return try await inner() }

    // The hook gets a callback that runs everything inside it. If that
    // callback throws, the error goes up through the hook's own code, which
    // can let it pass or throw something else. When an error comes out of
    // `callAround`, there's nothing in it to say whether the hook made it or
    // the callback did. So the callback notes that it threw, in `innerThrew`,
    // which is a `Box` because the callback is `@Sendable`.
    let innerThrew = Box(false)
    do {
      try await hook.callAround {
        do { try await self.runAround(hooks.dropFirst(), reporter, inner: inner) }
        catch {
          innerThrew.set()
          throw error
        }
      }
    }
    catch {
      // If the callback threw, the error is assumed to be the one that came
      // out of it. It was reported where it happened, so reporting it again
      // here would count it twice. A hook that catches the callback's error
      // and throws a different one is treated the same, and that error isn't
      // reported.
      guard !innerThrew.wrappedValue
      else { throw error }

      // Otherwise the hook threw it, before calling the callback or after it
      // returned.
      let kind = reporter.classify(error)
      let disposition = reporter.report(error, kind: kind, at: hook)

      // A skip ends only the hook. Before the callback, that means the element
      // doesn't run and nothing needs undoing. After it, the element and its
      // teardown have already run.
      if kind != .skip && disposition == .propagate {
        throw error
      }
    }
  }
}

// MARK: Per-flavor helpers

/// Keeps the first error from a set of concurrent children.
private final class FirstError: @unchecked Sendable {
  private let lock = NSLock()
  private var error: (any Error)?

  func note(_ newError: any Error) {
    lock.withLock { error = error ?? newError }
  }

  var value: (any Error)? { lock.withLock { error } }
}

extension ExampleNode {
  /// Async: any body can be called. A main-actor body is awaited, which hops
  /// to the main actor and back.
  fileprivate func callBody() async throws {
    switch body {
      case .sync(let body): try body()
      case .async(let body): try await body()
      case .syncMain(let body): try await body()
      case .asyncMain(let body): try await body()
      case nil: preconditionFailure("node has no body")
    }
  }

  /// Sync: an async body can't be called. A main-actor body is called with
  /// `assumeIsolated`, which relies on the entry point for a main-actor group
  /// being `@MainActor`.
  fileprivate func callBody() throws {
    switch body {
      case .sync(let body): try body()
      case .syncMain(let body): try MainActor.assumeIsolated { try body() }
      case .async, .asyncMain: throw UnexpectedAsyncError()
      case nil: preconditionFailure("node has no body")
    }
  }

  fileprivate func callAround(_ inner: @Sendable () async throws -> Void) async throws {
    switch around {
      case .async(let around): try await around { try await inner() }
      case .asyncMain(let around): try await around { try await inner() }
      case .sync, .syncMain: throw UnexpectedAsyncError()
      case nil: preconditionFailure("node has no around body")
    }
  }

  fileprivate func callAround(_ inner: @Sendable () throws -> Void) throws {
    switch around {
      case .sync(let around): try around { try inner() }
      case .syncMain(let around): try MainActor.assumeIsolated { try around { try inner() } }
      case .async, .asyncMain: throw UnexpectedAsyncError()
      case nil: preconditionFailure("node has no around body")
    }
  }
}

extension ExampleNode {
  /// Async: any group can run from anywhere, because main-actor bodies are
  /// awaited.
  fileprivate func checkCanRun() async {}

  /// Sync: main-actor bodies are called with `assumeIsolated`, which traps if
  /// the code isn't on the main actor. This traps first, before anything has
  /// run and with a message that says why, instead of partway through, when a
  /// `beforeAll` has run and its `afterAll` never will.
  fileprivate func checkCanRun() {
    // A sync group can't mix isolations, so the root says what is inside
    if isolation == .mainActor {
      MainActor.preconditionIsolated("a group with main-actor nodes has to be run on the main actor")
    }
  }

  /// Runs `body` for each child, one after another or all at once, and returns
  /// the first error. An error doesn't stop the other children.
  ///
  /// Async: children run in a task group, and inherit the runner and the path.
  fileprivate func forEachChild(_ children: [ExampleNode],
                                concurrently: Bool,
                                _ body: @escaping @Sendable (ExampleNode) async throws -> Void) async -> (any Error)? {
    let first = FirstError()

    if concurrently {
      await withTaskGroup(of: Void.self) { group in
        for child in children {
          group.addTask {
            do { try await body(child) }
            catch { first.note(error) }
          }
        }
      }
    }
    else {
      for child in children {
        do { try await body(child) }
        catch { first.note(error) }
      }
    }
    return first.value
  }

  /// Sync: children run with `DispatchQueue.concurrentPerform()`. Its threads
  /// don't inherit task-locals, so the runner and the path are bound again.
  fileprivate func forEachChild(_ children: [ExampleNode],
                                concurrently: Bool,
                                _ body: @escaping @Sendable (ExampleNode) throws -> Void) -> (any Error)? {
    let first = FirstError()

    if concurrently {
      let runner = ExampleRunner.current
      let path = ExampleRunner.elementStack

      DispatchQueue.concurrentPerform(iterations: children.count) { index in
        ExampleRunner.$current.withValue(runner) {
          ExampleRunner.$elementStack.withValue(path) {
            do { try body(children[index]) }
            catch { first.note(error) }
          }
        }
      }
    }
    else {
      for child in children {
        do { try body(child) }
        catch { first.note(error) }
      }
    }
    return first.value
  }
}
