// This is the start of the single traversal that is meant to replace the
// five that exist now: the four `ExampleRunner.run()` variants and
// `runActivity()` for XCTest. Nothing in the library calls it yet. Only
// `NodeTraversalTests` do, and they run the same groups through this and
// through the existing runners to check that the calls, their order and the
// first error come out the same.
//
// What it lacks, and where it gets it (see the Phase 1 tasks in
// Documentation/Roadmap.md):
// - A reporter that wraps each node, classifies errors as failure or skip, and
//   decides whether to record or propagate them. At the moment the error
//   policy is the plain runners' (collect the first error and rethrow it), and
//   it is written into the traversal. That is task 3, then task 4.
// - The element path, `.concurrent`, and main-actor async. Task 4.
// - Focus and exclude resolved when the plan is built, instead of the filtering
//   here. Task 2.
//
// Then the XCTest runner (task 5) and the plain runners (task 6) move onto it
// and the old traversals are deleted.
//
// There are still separate versions for non-isolated and main-actor nodes,
// because isolation is part of the closure types.

extension ExampleNode {
  /// Focus and exclude, as `ExampleRunner.filterFocusSkip` does it
  fileprivate var selectedChildren: [ExampleNode] {
    let nonExcluded = children.filter { !$0.isExcluded }
    let focused = nonExcluded.filter(\.isDeepFocused)
    return focused.isEmpty ? nonExcluded : focused
  }

  fileprivate func activeHooks(_ kind: HookKind) -> [ExampleNode] {
    hooks(kind).filter { !$0.isExcluded }
  }
}

// MARK: Non-isolated, sync or async

extension ExampleNode {
  /// Runs a group whose nodes are `SyncCall` or `AsyncCall`, which is the
  /// same traversal for both because a sync body can be called from async code.
  func traverse() async throws {
    let selected = selectedChildren
    guard !selected.isEmpty else { return }

    var firstError: (any Error)?
    do {
      for hook in activeHooks(.beforeAll) { try await hook.callBody() }
      for child in selected {
        do {
          try await runAround(activeHooks(.aroundEach)[...]) { try await self.runElement(child) }
        }
        catch { firstError = firstError ?? error }
      }
    }
    catch { firstError = error }
    for hook in activeHooks(.afterAll) {
      do { try await hook.callBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  private func runElement(_ child: ExampleNode) async throws {
    var firstError: (any Error)?
    do {
      for hook in activeHooks(.beforeEach) { try await hook.callBody() }
      if child.isGroup { try await child.traverse() }
      else { try await child.callBody() }
    }
    catch { firstError = error }
    for hook in activeHooks(.afterEach) {
      do { try await hook.callBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  private func runAround(_ hooks: ArraySlice<ExampleNode>,
                         inner: @Sendable () async throws -> Void) async throws {
    guard let hook = hooks.first else { return try await inner() }
    guard case .async(let around) = hook.around else { throw UnexpectedAsyncError() }
    try await around { try await self.runAround(hooks.dropFirst(), inner: inner) }
  }

  fileprivate func callBody() async throws {
    switch body {
      case .sync(let body): try body()
      case .async(let body): try await body()
      default: preconditionFailure("main-actor node in a non-isolated run")
    }
  }
}

// MARK: Main actor, sync

extension ExampleNode {
  /// The same traversal again for `SyncMainCall`. Isolation is part of the
  /// closure types, so it can't share the code above.
  @MainActor
  func traverseOnMainActor() throws {
    let selected = selectedChildren
    guard !selected.isEmpty else { return }

    var firstError: (any Error)?
    do {
      for hook in activeHooks(.beforeAll) { try hook.callMainBody() }
      for child in selected {
        do {
          try runAroundMain(activeHooks(.aroundEach)[...]) { try self.runElementMain(child) }
        }
        catch { firstError = firstError ?? error }
      }
    }
    catch { firstError = error }
    for hook in activeHooks(.afterAll) {
      do { try hook.callMainBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  @MainActor
  private func runElementMain(_ child: ExampleNode) throws {
    var firstError: (any Error)?
    do {
      for hook in activeHooks(.beforeEach) { try hook.callMainBody() }
      if child.isGroup { try child.traverseOnMainActor() }
      else { try child.callMainBody() }
    }
    catch { firstError = error }
    for hook in activeHooks(.afterEach) {
      do { try hook.callMainBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  @MainActor
  private func runAroundMain(_ hooks: ArraySlice<ExampleNode>,
                             inner: @MainActor () throws -> Void) throws {
    guard let hook = hooks.first else { return try inner() }
    guard case .syncMain(let around) = hook.around else { preconditionFailure("not a SyncMainCall hook") }
    // The callback has to be @Sendable, which the traversal's own state isn't
    try withoutActuallyEscaping(inner) { inner in
      nonisolated(unsafe) let inner = inner
      try around { try self.runAroundMain(hooks.dropFirst(), inner: inner) }
    }
  }

  @MainActor
  fileprivate func callMainBody() throws {
    guard case .syncMain(let body) = body else { preconditionFailure("not a SyncMainCall node") }
    try body()
  }
}
