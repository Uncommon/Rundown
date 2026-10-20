// This is the start of the single traversal that is meant to replace the
// five that exist now: the four `ExampleRunner.run()` variants and
// `runActivity()` for XCTest. Nothing in the library calls it yet. Only
// `NodeTraversalTests` do, and they run the same groups through this and
// through the existing runners to check that the calls, their order and the
// first error come out the same.
//
// What it lacks, and where it gets it (see the Phase 1 tasks in
// Documentation/Roadmap.md):
// - The element path and `.concurrent`. Task 4.
// - The rest of the skip rules. A skip in a setup hook or an example follows
//   "Error and skip rules" in the roadmap, but a skip in a teardown hook or an
//   `aroundEach` hook is treated like a failure for now, because the XCTest
//   behavior there (it aborts the whole run) is a quirk that is undecided.
//
// Then the XCTest runner (task 5) and the plain runners (task 6) move onto it
// and the old traversals are deleted.
//
// Isolation is part of the closure types, so the traversal is written once as
// async and the sync version is generated from it with @DeAsyncRD. Both handle
// non-isolated and main-actor nodes. The parts that differ between the flavors
// are in the helpers at the bottom.

// MARK: Traversal

extension ExampleNode {
  /// Runs a group as the root of a run, in its own scope. Errors that the
  /// reporter propagates are thrown after everything has run.
  @DeAsyncRD
  func run(with reporter: any Reporter) async throws {
    var thrown: (any Error)?
    await reporter.scope(for: self) {
      do { try await traverse(reporter) }
      catch { thrown = error }
    }
    if let thrown {
      throw thrown
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
      for child in selected {
        do {
          try await runAround(selectedHooks(.aroundEach)[...], reporter) {
            try await self.runElement(child, reporter)
          }
        }
        catch { firstError = firstError ?? error }
      }
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
    
    await reporter.scope(for: self) {
      // Errors from inside a group have already been reported
      do { try await traverse(reporter) }
      catch { outcome = .failed(error) }
    }
    return outcome
  }

  /// An example or hook: calls its body in its scope, and reports an error.
  @DeAsyncRD
  fileprivate func runLeaf(_ reporter: any Reporter) async -> Outcome {
    var outcome = Outcome.completed
    
    await reporter.scope(for: self) {
      do {
        try await callBody()
      }
      catch {
        outcome = outcomeOf(error, reporter)
      }
    }
    return outcome
  }

  private func outcomeOf(_ error: any Error, _ reporter: any Reporter) -> Outcome {
    let kind = reporter.classify(error)
    let disposition = reporter.report(error, kind: kind, at: self)
    let isTeardown = self.kind == .hook(.afterEach) || self.kind == .hook(.afterAll)

    if kind == .skip && !isTeardown {
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
      if reporter.report(error, kind: kind, at: hook) == .propagate {
        throw error
      }
    }
  }
}

// MARK: Per-flavor helpers

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
