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
  @DeAsyncRD
  func traverse() async throws {
    let selected = selectedChildren
    guard !selected.isEmpty else { return }

    var firstError: (any Error)?
    do {
      for hook in selectedHooks(.beforeAll) { try await hook.callBody() }
      for child in selected {
        do {
          try await runAround(selectedHooks(.aroundEach)[...]) { try await self.runElement(child) }
        }
        catch { firstError = firstError ?? error }
      }
    }
    catch { firstError = error }
    for hook in selectedHooks(.afterAll) {
      do { try await hook.callBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  @DeAsyncRD
  private func runElement(_ child: ExampleNode) async throws {
    var firstError: (any Error)?
    do {
      for hook in selectedHooks(.beforeEach) { try await hook.callBody() }
      if child.isGroup { try await child.traverse() }
      else { try await child.callBody() }
    }
    catch { firstError = error }
    for hook in selectedHooks(.afterEach) {
      do { try await hook.callBody() }
      catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
  }

  @DeAsyncRD
  private func runAround(_ hooks: ArraySlice<ExampleNode>,
                         inner: @Sendable () async throws -> Void) async throws {
    guard let hook = hooks.first else { return try await inner() }
    try await hook.callAround { try await self.runAround(hooks.dropFirst(), inner: inner) }
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
