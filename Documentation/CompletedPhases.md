# Completed Phases

Implementation notes and findings from completed phases of the Swift Testing integration. See the [roadmap](Roadmap.md) for current work.

## Phase 1 — Node model and shared traversal

Rundown introduced the `ExampleNode` tree and a shared traversal in `NodeTraversal.swift`. The traversal delegates framework behavior to `Reporter`, with `PlainReporter` and `XCTestReporter` as the original implementations. XCTest skips in `afterEach`, `afterAll`, and `aroundEach` became local to their hook so the rest of the run could proceed. `ActivityStructureXCTests`, `MessageXCTests`, and `MultiRunTests` cover XCTest compatibility. See the [node model design](SwiftTestingIntegration.md#status) and [error and skip rules](Roadmap.md#error-and-skip-rules).

## Phase 2 — Swift Testing host-test adapter

Phase 2 delivered [Option A](SwiftTestingIntegration.md#option-a-host-test-swift-testing-adapter). A normal `@Test` calls `spec`, and Rundown executes the whole spec inside that host test. Swift Testing discovery and filtering operate at the host-test level. [The README](../README.md#swift-testing) shows how to adopt the adapter and filter tests.

### Toolchain probes

The initial probes used Xcode's Swift 6.4 toolchain.

- **Assertion paths.** A handler built with `IssueHandlingTrait.compactMapIssues` appended the Rundown path to failed native assertions. Async `spec` installs it directly through `provideScope(for:testCase:performing:)`. Synchronous specs use `@Suite(.rundownPaths)` so Swift Testing installs the handler before they run. The handler is available with Swift 6.2 and later and adds each path comment once, even when scopes overlap. [Synchronous assertion paths](../README.md#assertion-paths-in-synchronous-specs)
- **Required assertions.** `#require` recorded an issue and threw the public `ExpectationFailedError` through `spec`. Swift Testing ignored the thrown error, leaving one issue. A reporter that records errors must recognize `ExpectationFailedError` as already reported to avoid a duplicate. `PlainReporter` needs no special handling.
- **Host cancellation.** In the initial probe, `try Test.cancel("...")` in an example threw `SkipInfo`. The next example still ran with `Task.isCancelled == true`, its `Task.sleep` threw `CancellationError`, and `afterAll` ran. Swift Testing reported the test as cancelled with the supplied comment. Its runner treated `SkipInfo` and a `CancellationError` thrown in a cancelled task as skips.
- **`SkipInfo` visibility.** The type was marked `@_spi(ForToolsIntegrationOnly)` in the Swift Testing source, but the Xcode toolchain's `Testing` module could not resolve it even with that SPI import. The probe fell back to comparing `"\(type(of: error))"` with `"SkipInfo"`.
- **Sync concurrency.** Only the `DispatchQueue.concurrentPerform` iteration on the calling thread saw `Test.current`. Rundown rebound its own runner and path on worker threads, where Swift Testing issues reached every registered handler and escaped `withKnownIssue` and issue-handling traits. The probe reported 11 issues from six failing examples, one of them known. In async traversal, task-group children inherited the host test context.
- **Observing issues.** An issue handler can capture a transformed issue and return `nil` so a `@Test` can inspect it without failing. `withKnownIssue(matching:)` sees the original issue before the trait adds the path comment.

### Shipped adapter

- `SwiftTestingSuite` provides named and caller-named `spec` overloads. Sync overloads pass `allowsConcurrency: false` to the reporter, and async overloads pass `true`. Swift Testing suites and `Rundown.TestCase` subclasses can call their respective overloads in the same target.
- `MainActorSwiftTestingSuite` provides the same overloads for main-actor builders, hooks, and examples. Tests verify isolation and full error paths in both sync and async specs.
- `SwiftTestingReporter` runs both scope closures inline and records thrown failures with the full Rundown path as an issue comment. It classifies `ExpectationFailedError` as already reported. It classifies `Testing.SkipInfo` by qualified type name and treats it and `CancellationError` in a cancelled task as skips.
- The adapter boundary uses Swift `package` access. A separate module in the package ran all four call types through `ExampleGroup.node` and `ExampleNode.run(with:)`, including the macro-generated sync overload. The compiler rejected access from a different package.
- The optional `RundownSwiftTesting` product imports `Rundown` and the toolchain's `Testing` module. At completion, the package minimums were macOS 15, iOS 17, tvOS 17, watchOS 10, and Mac Catalyst 17. In Xcode 27.2, `Testing` supported macOS 14 and later. Its watchOS simulator and `arm64_32` device slices supported watchOS 10 and later, and its `arm64` and `arm64e` device slices started at watchOS 26. Use `@available` for adapter APIs that need a later version than the package minimum.
- `RundownSwiftTestingTests` covers all four `SwiftTestingSuite` overloads, concurrency, failure paths, cancellation, main-actor isolation, and XCTest reporting with both frameworks imported. [Adapter testing strategy](SwiftTestingIntegration.md#testing-strategy-for-option-a)

### Cancellation and teardown

Cancellation stops new setup hooks and examples. If cancellation happens in `beforeAll` or `beforeEach`, the traversal skips the remaining setup and runs the corresponding teardown. In-flight examples may finish, and entered `aroundEach` hooks can unwind. Teardown runs in the existing task and observes its cancellation state. `SwiftTestingReporter.shouldStop` observes task cancellation and shares any cancellation caught by a child across the spec run.

`CancellationTests` covers host test cancellation and cancellation caught in a concurrent child. The tests pass the current setup hook path to `Test.cancel` and check that teardown runs.

### Compile-time benchmark

Direct `swiftc -typecheck` runs with Swift 6.4.2 on 60-context specs took a median of 1.40 s with the core and 1.44 s with the adapter for async specs. Sync specs took 2.24 s and 2.27 s. Each median comes from three timed runs after warming the compiler cache. The first version of the adapter took 2.66 s for the async spec. `@_disfavoredOverload` on the sync overloads restored the async timing while preserving sync calls.

### Upstream follow-ups from Phase 2

These proposals came from the adapter experiments. The original ranking weighed usefulness to Rundown against likelihood of acceptance. Check earlier Swift Forums and Swift Evolution discussions before drafting a pitch.

1. **A public way to recognize a cancellation or skip error.** A retry helper, step runner, or spec library that catches user errors needs to distinguish cancellation control flow from a failure. The probe had to compare the type name of the error thrown by `Test.cancel`, while `ExpectationFailedError` was already public. One option would be to expose `SkipInfo` or add a predicate such as `Test.isCancellation(_:)`.
2. **Scoped issue transformation without a suite annotation.** An async caller can invoke `IssueHandlingTrait.provideScope` directly. A public synchronous scope would let Rundown annotate native assertions inside sync specs. [Proposal brief and prototype results](SwiftTestingScopedIssueHandlingProposal.md)
3. **Carrying the test context across threads.** `Test.current`, `Test.Case.current`, and the configuration are task-local. A capturable value such as `Test.Context` with `perform { }` could restore them for code dispatched to another thread, so assertions, issue handling, and `Test.cancel` could use the host test's context. An open design question is what state to carry.
4. **Named steps.** A nested scope like `XCTContext.runActivity` could appear in results, collect issues, and potentially support a skip that ends only the step. It could represent Rundown's reporter scopes and help XCTest users who rely on activities. This would need new events, JSON ABI and tool changes, and a Swift Evolution proposal.
