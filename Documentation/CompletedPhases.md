# Completed Phases

Implementation notes and findings from completed phases of the Swift Testing integration. See the [roadmap](Roadmap.md) for current work.

## Phase 1 — Node model and shared traversal

Rundown introduced the `ExampleNode` tree and a shared traversal in `NodeTraversal.swift`. The traversal delegates framework behavior to `Reporter`, with `PlainReporter` and `XCTestReporter` as the original implementations. XCTest skips in `afterEach`, `afterAll`, and `aroundEach` became local to their hook so the rest of the run could proceed. `ActivityStructureXCTests`, `MessageXCTests`, and `MultiRunTests` cover XCTest compatibility. See the [node model design](SwiftTestingIntegration.md#planning-and-execution) and [error and skip rules](Roadmap.md#error-and-skip-rules).

## Phase 2 — Swift Testing host-test adapter

Phase 2 delivered [Option A](SwiftTestingIntegration.md#option-a-host-test-swift-testing-adapter). A normal `@Test` calls `spec`, and Rundown executes the whole spec inside that host test. Swift Testing discovery and filtering operate at the host-test level. [The README](../README.md#in-swift-testing) shows how to adopt the adapter and filter tests.

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

## Phase 3 — Swift Testing trait bridge

Phase 3 mapped where `.excluded`, `.focused`, and `.concurrent` take effect in the shared traversal. The inventory records nested selection, the focus-inside-exclusion baseline, and each runner's concurrency gate. [Trait inventory](SwiftTestingIntegration.md#current-rundown-trait-behavior)

The host-test probe on Swift 6.4.2 showed that declared Swift Testing traits apply at the host level. Changing a copy of `Test.current` affected that copy, while a runtime issue handler could wrap one `spec` call and report through the existing host. [Metadata timing probe](SwiftTestingIntegration.md#swift-testing-metadata-timing-probe)

All three built-ins stay local to Rundown execution in host tests. `.excluded` omits nodes, `.focused` selects branches, and `.concurrent` schedules a group's children through the reporter's concurrency gate. The bridge API is deferred until discovery exposes a matching scope. Phase 4 tested which of these rules carry over to discovered cases. The focus and exclusion behavior change remains a separate cleanup item. [Trait behavior by entry point](SwiftTestingIntegration.md#trait-behavior-by-entry-point) · [Cleanup backlog](Roadmap.md#cleanup)

All 146 runtime tests passed, including nested selection, excluded hooks, concurrency, failure paths, and cancellation. The original README example verified that an all-excluded spec skips setup and its host continues to a second spec. The sandbox blocked the compile-failure fixture's nested build, and a direct build produced all 20 expected diagnostics. [Current trait usage](../README.md#rundown-and-swift-testing-traits)

## Phase 4 — Swift Testing discovery experiment

The experiment merged into `main` at `1eaea07`. On Darwin with Swift 6.4 or later, the package-scoped `@Spec` registers one Swift Testing function with a case for each selected top-level child. `@Spec(.leaves)` registers one case for each selected leaf. Listing leaves the getter unevaluated. Planning builds the tree once, including loops and helper-built groups, and both modes use Rundown's existing focus and exclusion rules. Cases and repetitions can share the planned fixture. A new runner invocation builds fresh state. The DSL also gained computed trait arrays for `it()` and inline excluded `aroundEach` hooks in async builders. [Registration](SwiftTestingSpecDiscoveryResearch.md#prototype-registration) · [Selection](SwiftTestingSpecDiscoveryResearch.md#selection-at-the-discovery-boundary) · [Fixture lifetime](SwiftTestingSpecDiscoveryResearch.md#plan-and-fixture-lifetime)

Root group hooks run once around the selected cases in the generated function's scope. This gives Xcode a function to associate with a root hook issue and avoids the XCTest harness crash on suite-level issues. The final checks passed 158 macOS SwiftPM runtime tests and matched 20 compile-failure diagnostics. All 33 adapter tests passed in Xcode on macOS, iOS 17.5 and 27.2 simulators, watchOS 27.2 Simulator, and Mac Catalyst. The tvOS evidence covers compilation and Mach-O records. [Hook lifetimes](SwiftTestingSpecDiscoveryResearch.md#hook-lifetimes) · [Platform checks](SwiftTestingSpecDiscoveryResearch.md#runtime-checks-without-the-macos-guard)

### Phase 5 handoff

| Approach | Verified filtering and reporting | Lifecycle and maintenance |
|---|---|---|
| Host `@Test` calling `spec` | SwiftPM and Xcode can select and rerun the whole host test. Issue paths identify the failing example within it. | Rundown owns all hooks and scheduling. Supports sync, async, and main-actor specs through the existing adapter and uses standard Swift Testing registration. |
| Top-level `@Spec` | Xcode reran a selected top-level child by argument URL, including all examples inside that child. Failures attach to the case, with a Rundown path to the inner example. SwiftPM filters the generated function. | Root hooks wrap the selected cases once. Rundown preserves hook boundaries and scheduling inside each case. Swift Testing schedules siblings across cases. |
| `@Spec(.leaves)` | Xcode reran one failing leaf in a top-level suite, even when another leaf had the same name. SwiftPM filters the generated function. | Shares the top-level mode's registration and root scope. Each case replays intermediate group hooks, and flattening transfers sibling scheduling to Swift Testing. Preserving shared group lifetimes would require a coordinator for the selected leaves. |

Each mode reported one issue per failure. `#expect` and `#require` kept their source locations, and thrown errors pointed to the reporter with the full Rundown path. Discovery adds case-level attribution. The tested nested Swift suite could be filtered at the function level, while its individual argument selectors failed. Case IDs are stable for the same declaration and tree positions. Inserting or reordering children can shift them. [Filtering and identities](SwiftTestingSpecDiscoveryResearch.md#discovery-units-and-identities) · [Reporting and reruns](SwiftTestingSpecDiscoveryResearch.md#reporting-and-reruns)

#### Limits to carry into the decision

- **Scheduling and isolation.** Swift Testing's parallel runner can overlap ordinary siblings across cases. Native `.serialized` restored case order in the probe while Rundown still honored `.concurrent` inside a top-level case. Both discovery modes require an `AsyncCall` root. Root setup cancellation stops the cases and reaches teardown with a cancelled task. This path emits no native cancellation event. [Scheduling and isolation](SwiftTestingSpecDiscoveryResearch.md#scheduling-and-isolation) · [Hook lifetimes](SwiftTestingSpecDiscoveryResearch.md#hook-lifetimes)
- **Registration and lifecycle cost.** Both discovery modes share about 272 source lines for macro registration, function scoping, and node projection, plus shared traversal changes and the reporter's root cancellation handling. They rely on underscored Swift Testing entry points and a handwritten Mach-O test record. The leaf experiment's footprint excludes the coordination needed to preserve intermediate hooks, cancellation, and scheduling across leaves. [Registration implementation](../Sources/RundownSwiftTesting/SpecRegistration.swift) · [Leaf coordination design](SwiftTestingIntegration.md#the-hardest-problem-beforeall--afterall)
- **Compile cost.** The 60-context host median rose from 3.69 s to 6.80 s after the inline-wrapper builder change with discovery disabled. The same-getter control measured 3.66 s with an explicit builder and 3.74 s with `@Spec`, with overlapping samples. Track the shared builder regression separately when weighing discovery. [Compile comparison](SwiftTestingSpecDiscoveryResearch.md#60-context-compile-comparison)

#### Decision for Phase 5

Keep the host adapter as the supported baseline and pursue opt-in top-level discovery for Xcode group reruns. Individual leaf reruns remain the longer-term goal. The leaf mode stays in the package as a prototype while shared intermediate hooks and sibling scheduling across leaf cases remain unresolved. [Phase 5 results](#phase-5--opt-in-top-level-swift-testing-discovery)

## Phase 5 — Opt-in top-level Swift Testing discovery

- **Discovery granularity.** Phase 5 delivered opt-in top-level cases and kept the leaf prototype for future research. [Phase 5 handoff](#phase-5-handoff)
- **Opt-in API and support boundary.** Public, experimental `@Spec` keeps the computed getter shape and requires Swift 6.4 on Darwin. A separate client package verified discovery and a single group rerun. [API and support boundary](SwiftTestingIntegration.md#opt-in-api-and-support-boundary)
- **Scheduling and hooks.** Top-level cases run serially unless the root is `.concurrent` and the runner allows parallelism. Full runs and a single-case Xcode rerun verified root hook lifetimes. Setup failure reporting and cancellation-aware teardown passed. [Scheduling and hook checks](SwiftTestingSpecDiscoveryResearch.md#top-level-scheduling-policy)
- **Filtering and compatibility.** Xcode reran one failed group from a client package with all three failure paths intact. SwiftPM filtered by function, nested Xcode argument selectors failed, and an inserted excluded sibling shifted the case IDs. The host adapter, plain-runner, and XCTest suites passed. [Filtering and compatibility checks](SwiftTestingSpecDiscoveryResearch.md#phase-5-filtering-and-compatibility)
- **Opt-in workflow.** The README shows when to use `@Spec` or a host test, how to rerun a group in Xcode, and the filtering, isolation, and cancellation boundaries. The original example passed in an external package, and the Xcode rerun selected only the documented group. [Opt-in discovery guide](../README.md#optional-spec-macro)
