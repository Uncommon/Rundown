# Deeper Swift Testing Integration Ideas

## Purpose

This document outlines implementation options for making Rundown feel more native in Swift Testing while preserving the current XCTest experience and keeping existing XCTest/XCUITest-compatible consumers working.

The intent is not to pick a final design immediately. The goal is to make the tradeoffs explicit enough that the next implementation step can be chosen deliberately.

## Current State

Rundown already has three important properties that are worth preserving:

- The core DSL is framework-neutral: `describe`, `context`, `it`, hooks, traits, and `spec()` do not require a specific test framework.
- XCTest-specific behavior is already isolated in `Sources/Rundown/ExampleData+XCTest.swift`.
- Main actor support is already expressed in framework-neutral API surface via `MainActorSuite`.

Today, the integration split looks like this:

- `Rundown.TestCase` improves XCTest failures by prefixing issues with the full example path.
- XCTest behavior is a reporter on the shared traversal (`XCTestReporter`): each node runs as an `XCTContext` activity to show nested structure in the test log, errors are recorded as issues, and `XCTSkip` is classified as a skip. This is synchronous and main-actor only.
- A built spec can be viewed as a tree of `ExampleNode`s (`ExampleNode.swift`), which does not depend on the call type. All specs are run by one traversal over that tree (`NodeTraversal.swift`), which takes a `Reporter` (`Reporter.swift`). The plain runners use `PlainReporter`.
- The optional `RundownSwiftTesting` product supplies `SwiftTestingSuite` and `MainActorSwiftTestingSuite`. Their `spec()` methods use `SwiftTestingReporter` inside a Swift Testing `@Test`. The core `Rundown` target remains independent of `Testing`.
- Rundown traits are currently neutral library concepts and are not coupled to Swift Testing traits.

## Hard Constraints

Any deeper Swift Testing integration should preserve these invariants:

- Existing XCTest behavior must not regress.
- Existing `Rundown.TestCase`-based tests should continue to work without migration.
- Consumers that cannot import `Testing` must still be able to import Rundown.
- The core DSL should remain usable without requiring framework-specific annotations in normal use.
- Main actor support should remain explicit and predictable.

There is one especially important packaging constraint:

- Do not make the core `Rundown` target depend directly on `Testing` if that would make it unusable from existing XCTest/XCUITest-oriented targets.

## What "Deeper Integration" Should Mean

There are several different levels of Swift Testing integration. They are not all the same problem.

### Level 1: Better Runtime Reporting

The same Rundown execution model runs under Swift Testing, but failures, skips, and example paths are surfaced more naturally in Swift Testing output.

### Level 2: Native Trait Bridging

Built-in Rundown traits such as exclusion or concurrency can influence Swift Testing metadata or execution behavior when the test is run under Swift Testing.

### Level 3: Native Discovery

Swift Testing sees more than one outer host test. Ideally, individual Rundown examples become discoverable or at least visible as structured test content.

### Level 4: Native Execution Semantics

Rundown no longer just "runs inside" Swift Testing. Instead, Swift Testing becomes the scheduler and reporter for Rundown examples, and Rundown contributes structure, hooks, and semantics.

The recommended implementation order is Level 1 -> Level 2 -> Level 3. Level 4 should only happen if the return on complexity is clear.

## Recommended Architectural Direction

The cleanest long-term direction is:

- Keep the public authoring DSL shared across frameworks.
- Keep the execution core framework-neutral.
- Add optional framework adapters for richer behavior.

That implies an architecture closer to this:

- `RundownCore`
  - builder
  - example tree / plan model
  - runner
  - neutral traits
  - main actor abstractions
- `RundownXCTest`
  - `Rundown.TestCase`
  - `XCTContext.runActivity()` support
  - `XCTSkip` handling
  - XCTest issue formatting
- `RundownSwiftTesting`
  - Swift Testing reporter
  - trait bridge
  - optional discovery bridge

This does not necessarily mean public products must be renamed immediately. Internally splitting responsibilities is more important than immediately changing package-facing names.

## Key Internal Refactor: Separate Planning From Execution

If Rundown is going to integrate more deeply with Swift Testing, the most useful internal refactor is to introduce an explicit intermediate representation for a built spec.

Call it `ExamplePlan`, `ExampleTree`, or `ExecutionPlan`.

That plan should represent:

- groups
- leaf examples
- hook stacks
- traits
- actor isolation
- sync vs async execution mode
- source descriptions / display names

Today, the DSL mostly builds directly into execution-oriented structures. That is sufficient for "run this whole thing now", but it limits integration options. A distinct plan model would unlock several things:

- an XCTest renderer that turns plan nodes into `XCTActivity` nesting
- a Swift Testing renderer that records richer path information
- future leaf-native discovery for Swift Testing
- better trait routing without framework-specific logic leaking into the builder

Without this separation, deeper integration will tend to accumulate framework-specific branches inside `ExampleRunner`.

### Status

This is done, as `ExampleNode` and the traversal in `NodeTraversal.swift`. It differs from the sketch above in a few ways that matter for later phases:

- A node holds metadata *and* the closures to run, each in the call type it was written with (`sync`, `async`, `syncMain` or `asyncMain`). A tree without closures could not be traversed on its own, and the sync XCTest runner cannot run on type-erased async closures.
- Each-hooks stay attached to the group that declares them and wrap its child nodes, groups included. They are not flattened onto leaves (see "Hook Replay Order" under Option B).
- Focus and exclude are resolved when the tree is built, as `isSelected` on each node. Excluded nodes stay in the tree, so it still reflects the structure of the spec.
- Same-package adapters can obtain an `ExampleNode` from `ExampleGroup.node` for any of the four call types and run it with a reporter. Tree construction, traversal helpers and stored closures are internal to `Rundown`.

## Option A: Host-Test Swift Testing Adapter

This is the implemented adapter. See the [README](../README.md#swift-testing) for setup and usage.

### Model

Users continue writing Swift Testing tests like this:

```swift
import Testing
import RundownSwiftTesting

struct FeatureTests: SwiftTestingSuite {
  @Test func behavesCorrectly() async throws {
    try await spec {
      context("logged in") {
        it("loads the dashboard") {
          // assertions
        }
      }
    }
  }
}
```

Rundown executes the whole spec as one host test. `SwiftTestingSuite` supplies `spec()` overloads that report thrown errors to Swift Testing.

### Reporting

- Thrown failures include the full Rundown path.
- Native assertion failures can include a Rundown path comment on Swift 6.2 and later.
- Swift Testing reports host cancellation using the comment and source location passed to `Test.cancel`.

### Why This Is Attractive

- no code generation required
- no new mandatory macros
- preserves the current DSL intact
- keeps migration cost low
- does not require custom test discovery

### Limitations

- inner `it` examples are still not independently discoverable by Swift Testing
- filtering still happens at the outer test-function level
- per-example parallelization is still mostly Rundown-managed, not Swift Testing-managed

### Package and Type Shape

The optional `RundownSwiftTesting` product and target import `Rundown` and `Testing`. Both products use the deployment minimums in `Package.swift`. The adapter defines `SwiftTestingReporter` and the `spec` overloads for `SwiftTestingSuite` and `MainActorSwiftTestingSuite`. It re-exports the core DSL.

The traversal already takes a reporter, so this is one more conformance to `Reporter`. The protocol, its error types and both `run(with:)` overloads use `package` access, so an adapter target in the same package can use them with a regular `import Rundown`.

The public API goal is that users still write `spec()`. Framework selection should come from the module/protocol overload set, not from a renamed entrypoint.

### Runtime Flow

The adapter runs a spec as follows.

1. User enters a normal Swift Testing `@Test`.
2. User calls a Swift Testing-specific `spec()` overload supplied by the adapter module.
3. The existing builder constructs the group and its node tree.
4. The traversal runs the tree with the Swift Testing reporter, as it does for the plain and XCTest reporters.
5. The reporter records thrown failures with their paths and stops new work when Swift Testing cancels the host test or case.

This keeps the execution model familiar:

- Rundown still owns hook sequencing
- Rundown still owns focus / exclude semantics
- Rundown still owns its current concurrency model
- Swift Testing becomes the outer host and reporter sink, not the leaf scheduler

### API Surface

Keep `spec()` as the author-facing API.

A Swift Testing suite adopts `SwiftTestingSuite`.

```swift
import Testing
import RundownSwiftTesting

struct FeatureTests: SwiftTestingSuite {
  @Test func behavesCorrectly() async throws {
    try await spec {
      it("works") {
      }
    }
  }
}
```

An XCTest suite inherits from `Rundown.TestCase`.

```swift
import Rundown

@MainActor
final class FeatureTests: Rundown.TestCase {
  func testBehavesCorrectly() throws {
    try spec {
      it("works") {
      }
    }
  }
}
```

The core provides global `spec()` overloads for the plain runner. `Rundown.TestCase` supplies member overloads for XCTest activities, and `SwiftTestingSuite` supplies member overloads for Swift Testing reporting. Each host test type selects its runner through inheritance or protocol conformance, so both adapters can be used from the same target.

### Suite Protocol Shape

`SwiftTestingSuite` supports synchronous and asynchronous specs. Both can take an explicit name or derive one from the calling function using Rundown's existing naming rules. Synchronous specs run `.concurrent` groups serially so each example keeps the host test context. Asynchronous specs use task groups when `.concurrent` is present.

`MainActorSwiftTestingSuite` refines `MainActorSuite` and supplies the same four overloads with main-actor builders, hooks, and examples. It uses the Swift Testing reporter and assertion path handling in both sync and async specs. Sync specs run `.concurrent` groups serially, and async specs reject `.concurrent` on main-actor groups before running their hooks.

### Failure and Skip Reporting Details

The reporter should preserve the existing high-value XCTest behavior: failures need the full Rundown path, not just the innermost leaf description.

Implementation details:

- use the current `ExampleRunner` stack as the source of truth for the path
- normalize path formatting in one place so XCTest and Swift Testing do not drift
- distinguish between:
  - assertion failures raised inside an example
  - skips raised inside hooks
  - unexpected thrown errors

`SwiftTestingReporter` attaches the Rundown path to each newly recorded error. A failed `#require` has already recorded an issue, so the traversal handles its `ExpectationFailedError` as a failure without recording it again. The reporter treats Swift Testing cancellation as a skip and asks the traversal to stop starting new setup hooks and examples. The traversal still invokes teardown for groups and elements it entered. Swift Testing emits the cancellation event when `Test.cancel` is called. Include `ExampleRunner.current?.description` in the cancellation comment to show the hook or example path.

On Swift 6.2 and later, async `spec` installs an `IssueHandlingTrait` directly around traversal in the current Swift Testing test case. Sync specs use `@Suite(.rundownPaths)` to have Swift Testing install that handler before the test runs. Both scopes use the same transform. It adds a path comment only to native assertion failures with an active Rundown path and checks for an identical comment when scopes overlap. The transform preserves the original issue, including its source location. See the [README usage](../README.md#assertion-paths-in-synchronous-specs) and the [upstream proposal brief](SwiftTestingScopedIssueHandlingProposal.md).

### Testing Strategy For Option A

`RundownSwiftTestingTests` covers the following behaviors.

- Named and caller-named specs preserve Swift Testing reporting and the host test context in both execution modes.
- Thrown errors and native assertion failures include the full Rundown path when path handling is enabled.
- Cancelling in `beforeEach` or `beforeAll` supplies the active hook path, stops new work, and runs teardown.
- Main-actor tests, hooks, and examples run on the main actor.
- XCTest reports through `Rundown.TestCase` with both frameworks imported.

To check cancellation output on the Swift 6.4 toolchain, run `swift test --filter CancellationTests --event-stream-output-path /tmp/rundown-cancellation.jsonl`. The stream contains one `testCancelled` event for each setup-cancellation test. Each `testEnded` event shows the supplied comment with the full hook path. The SwiftPM tests check the path and teardown directly, and the event stream checks the host runner's output.

## Option B: Leaf-Native Swift Testing Execution

This is the ambitious path.

### Model

Each leaf `it(...)` becomes a Swift Testing test case, while Rundown continues to provide:

- grouping
- hooks
- path naming
- traits
- actor-isolation rules

### What This Buys

- individual examples become discoverable
- test filtering can target actual leaf examples
- trait application can become more native
- reporting becomes much closer to Swift Testing's preferred shape
- Swift Testing can control more of parallelization and scheduling

### What Makes It Hard

- Rundown must be able to enumerate leaf examples and hook stacks without simply executing the suite wholesale
- per-leaf execution needs deterministic reconstruction of enclosing hooks
- group-level traits must be inherited and flattened onto leaves
- each-hooks apply to the children of the group that declares them, not to each leaf, so they cannot be flattened onto leaves (see "Hook Replay Order")
- main actor and non-main actor examples need a coherent representation
- focus / exclude semantics need careful mapping

This option is attractive only after a separate plan model exists. Otherwise it will make `ExampleRunner` much more complex.

### Required Internal Representation

Leaf-native execution cannot be built directly on the node tree as it is. It needs a flattened view of the leaves, and the flattening has to keep each hook attached to the group it belongs to, because group-scoped hooks wrap whole child nodes, not leaves.

That view should look roughly like:

```swift
struct PlannedLeaf {
  let id: LeafID
  let fullPath: [String]
  let displayName: String
  let isolation: IsolationKind
  let effectiveTraits: [any Trait]
  /// Outermost group first
  let enclosingScopes: [PlannedScope]
  let example: AnyPlannedExample
}

struct PlannedScope {
  let group: GroupID
  /// The child of `group` that the leaf is in. This is a nested group, unless
  /// the leaf is a direct child.
  let child: NodeID
  let beforeAllHooks: [AnyHook]
  let aroundEachHooks: [AnyAroundEachHook]
  let beforeEachHooks: [AnyHook]
  let afterEachHooks: [AnyHook]
  let afterAllHooks: [AnyHook]
}
```

The exact type names are not important. The important point is that each leaf must carry enough information to replay the surrounding group semantics independently, and that the each-hooks of a scope apply once per `child`, not once per leaf.

### The Hardest Problem: `beforeAll` / `afterAll`

Leaf-native execution is hard because of anything that is scoped to a group instead of a leaf. That includes `beforeAll` and `afterAll`, and also the each-hooks of a group that has nested groups, since those wrap a whole nested group (see "Hook Replay Order").

If each leaf becomes a separate Swift Testing test, Rundown still has to preserve the current meaning of:

- `beforeAll`: run exactly once for the group before any leaf in that group executes
- `afterAll`: run exactly once for the group after all leaves in that group complete

That is easy in the current single-host execution model and difficult in a multi-test native model.

There are three possible approaches:

#### 1. Change the semantics

Treat `beforeAll` / `afterAll` as per-leaf setup and teardown in leaf-native mode.

This is not acceptable if compatibility with existing Rundown behavior matters.

#### 2. Introduce a group lifecycle coordinator

Use a shared actor or locked coordinator keyed by group identity.

Each discovered leaf would:

- enter the coordinator for each enclosing group
- let the coordinator run `beforeAll` once for the first entrant
- run the leaf
- notify the coordinator on exit
- let the coordinator run `afterAll` once for the final exiting leaf

This preserves semantics, but it introduces a substantial amount of coordination logic.

The coordinator must also cache:

- whether `beforeAll` already succeeded
- whether it skipped
- whether it failed
- how remaining leaves in the group should react to that outcome

#### 3. Serialize all leaves in a group

Force all leaves sharing a group-scoped lifecycle to run through a serialized adapter scheduler.

This is simpler than full coordinator-based concurrency but gives up some of the benefit of leaf-native execution.

If Option B is pursued, the lifecycle coordinator is the most faithful design, but it must be treated as a real subsystem, not incidental glue.

### Hook Replay Order

The replay order is not per leaf. Each-hooks (`beforeEach`, `afterEach` and `aroundEach`) apply to the elements of the group that declares them, and a nested `context` is one element. They run once around the whole nested group, not around each example in it.

For a nested group `N` in `Root`, where both declare every kind of hook, the order for `N` as an element of `Root` is:

1. `Root`'s `aroundEach` hooks, outer to inner
2. `Root`'s `beforeEach` hooks
3. `N` runs as a whole:
   1. `N`'s `beforeAll` hooks
   2. for each child of `N`: `N`'s `aroundEach` hooks, `N`'s `beforeEach` hooks, the child, `N`'s `afterEach` hooks, then the `aroundEach` hooks unwind
   3. `N`'s `afterAll` hooks
4. `Root`'s `afterEach` hooks
5. `Root`'s `aroundEach` hooks unwind

So `Root`'s each-hooks run once for `N`, however many examples it has, and they enclose `N`'s `beforeAll` and `afterAll`. The order within a group is the same as it was.

This is what the runner does, and it is intended. It has consequences for leaf-native execution:

- Replaying each-hooks per leaf would run `Root`'s hooks once per example in `N`, which users can observe (counters, logs, resources).
- `Root`'s `aroundEach` cannot wrap several separate tests at all, because its callback is a single scope that has to contain all of `N`.
- Outer `beforeEach` and `afterEach` hooks would need the same lifecycle coordinator as `beforeAll` and `afterAll`: run before the first leaf of `N`, and after the last.
- `aroundEach` has no workable form in a multi-test model. It would work only if the leaves of the group it wraps run serialized inside one test.

That makes Option B harder than it first looks, and it supports the recommendation below: do the host-test adapter first, and treat leaf-native discovery as an experiment.

That order needs dedicated tests, since even small mistakes here would be user-visible regressions.

### Concurrency and Isolation

Leaf-native execution should not simply inherit the current `.concurrent` behavior blindly.

Questions that must be answered explicitly:

- if Swift Testing already wants to schedule leaf tests in parallel, should `ConcurrentTrait` become a no-op?
- should main-actor leaves always bypass leaf-native parallelization?
- do nested concurrent groups create more concurrency than Swift Testing should be asked to manage?

The likely answer is:

- let Swift Testing own leaf scheduling
- treat Rundown's concurrency trait as metadata or as a compatibility layer only where native scheduling is not available
- forbid combinations that would require conflicting isolation guarantees

### Testing Strategy For Option B

Option B needs a separate compatibility suite proving that leaf-native execution still matches host-test semantics for:

- nested `beforeAll` / `afterAll`
- each-hooks of a group that has nested groups, which run once per nested group, including `aroundEach`
- skip in `beforeAll`
- skip in `beforeEach`
- failure in `beforeAll`
- nested focus / exclude
- main actor execution
- groups with loops and dynamically built children

Without those tests, the risk of subtle semantic drift is high.

## Option C: Discovery Bridge

There are two broad ways to improve Swift Testing discovery:

- keep user-authored `@Test` functions and improve only runtime behavior
- add a Rundown-specific discovery bridge that emits native Swift Testing-visible tests

The second option should be considered only after deciding whether leaf-native discovery is a real goal.

Possible forms:

- an optional macro in a separate target
- a discovery helper module that turns a Rundown plan into Swift Testing-visible test content
- a code-generation or plugin-based bridge outside the core runtime

The key point is that this should be optional and should not contaminate the core `Rundown` target with a hard `Testing` dependency.

### Discovery Bridge Goals

Option C should only exist to solve one of two concrete problems:

- make Rundown leaves discoverable without manually writing a Swift Testing `@Test` wrapper for each host spec
- make leaf-native Option B practical without hand-written boilerplate

If it does not solve one of those problems, it is probably unnecessary.

### Candidate Implementation Paths

#### 1. Macro-based discovery

An adapter macro could generate Swift Testing entrypoints for a static Rundown spec declaration.

This is appealing because it looks ergonomic, but Rundown's builder model makes it a poor default choice:

- specs may contain loops
- specs may contain conditionals
- specs may call helper functions that return examples
- some interesting structure is only knowable after evaluating Swift code, not by inspecting syntax

That means syntax-only expansion is only reliable for a subset of specs.

Macro-based discovery is therefore best treated as:

- optional
- limited to static specs
- never the only path to deeper integration

#### 2. Runtime-discoverable test content

If Swift Testing's discovery model allows third-party test content to be emitted from a helper module, that is a much better fit for Rundown than syntax-only macro expansion.

Why it fits better:

- Rundown can build the actual plan first
- loops and helper-generated examples are already resolved
- trait inheritance and leaf naming can use the real execution model
- the same plan can feed both host-test and leaf-native execution strategies

This would likely be the best long-term discovery bridge if the surrounding Swift Testing APIs are stable enough.

#### 3. Generated source via build tooling

A build tool plugin or standalone generator could:

- evaluate or inspect a static description of the Rundown suite
- emit Swift source containing `@Test` wrappers
- add that generated source to the test target

This is more operationally complex than runtime discovery but has one advantage: the output is ordinary Swift test code that can be inspected during debugging.

This path is attractive only if runtime discovery is not feasible and macro-based discovery proves too limited.

### Recommendation For Option C

Treat discovery as a separate experiment with its own success criteria.

Implementation order should be:

1. host-test adapter first
2. plan model second
3. discovery prototype third

Do not commit the architecture to macros or generated code before testing whether a runtime-discovery bridge is viable.

### Validation Cases For Option C

Any discovery bridge must be validated against specs that include:

- nested groups
- loops
- conditionals
- helper-built subtrees
- mixed sync / async examples
- main actor suites
- traits inherited from outer groups

If a discovery mechanism cannot represent those cases correctly, it is not a general Rundown solution.

## Trait Bridging Design

The core trait model should stay neutral.

That means the core library should continue to define:

- `Trait`
- `ExampleTrait`
- built-in Rundown traits such as `FocusedTrait`, `ExcludedTrait`, and `ConcurrentTrait`

The Swift Testing adapter can interpret neutral traits when it has a Swift Testing node or scheduling scope that matches the Rundown node.

### Current Rundown trait behavior

The DSL accepts `any Trait` on groups, examples, and hooks. `ExampleNode` keeps those declarations on their original nodes. `ExampleTrait` is a marker protocol, so the effective scope comes from where Rundown reads each built-in trait. [Trait declarations](../Sources/Rundown/Trait.swift) · [Node construction and selection](../Sources/Rundown/ExampleNode.swift)

| Trait | Nodes where it takes effect | Effect |
|---|---|---|
| `.excluded` | Examples, child groups, and all five hook kinds | The parent omits excluded children from execution. Excluded hooks are omitted individually, including `aroundEach`. |
| `.focused` | Examples and groups | Within each group, focus selects branches and filters out their unfocused siblings. |
| `.concurrent` | Groups, including an explicitly run root | Schedules the group's selected direct children together when the reporter permits it. Each child group determines its own scheduling. |

**Selection is local to each group.** When the tree is built, each group removes directly excluded children from its candidates. If any candidate is focused or contains focus, only candidates with focus are selected. Otherwise every candidate is selected. A focused group can make its parent select that branch while its own children are still selected by the same local rule. Hook selection depends only on each hook's `.excluded` trait. [Node selection tests](../Tests/RundownTests/ExampleNodeTests.swift)

**The tree retains every node.** Traversal follows selected branches from the root, even when an unselected branch contains descendants locally marked `isSelected`. An explicitly run root stays selected even if it carries `.excluded`, since it has no parent to filter it. A group with zero selected children runs none of its own hooks. Its parent can still run each-hooks around it if the group itself is selected. Each invocation of an each-hook wraps one selected direct child, and a nested group counts as one child. [Shared traversal](../Sources/Rundown/NodeTraversal.swift) · [Execution tests](../Tests/RundownTests/MultiRunTests.swift)

**Focus inside an excluded subtree can affect an ancestor.** The deep-focus check walks the stored tree without filtering excluded descendants. In `testFocusInsideExcludedSubtreeStillCountsAsFocus`, the root selects the holder group because it contains a focused example inside an excluded subgroup. Inside the holder, the excluded subgroup is dropped from the candidates and the plain example runs. This is the baseline for the separate [focus and exclusion cleanup](Roadmap.md#cleanup). [Baseline test](../Tests/RundownTests/ExampleNodeTests.swift)

**Concurrency is gated when a group runs.** `NodeTraversal` checks `isConcurrent && reporter.allowsConcurrency` after checking that there is work to run. An active concurrent group runs `beforeAll` before scheduling children and waits for the children and their each-hooks before running `afterAll`. If the group is main-actor isolated and concurrency is enabled, the traversal throws `ConcurrentDisallowedError` before that group's hooks. [Shared traversal](../Sources/Rundown/NodeTraversal.swift)

| Entry point | Reporter permits concurrency | Effect on a `.concurrent` group with selected children |
|---|---|---|
| Plain sync or async run | Yes | Uses `DispatchQueue.concurrentPerform` in the sync traversal or a task group in the async traversal. Main-actor groups are rejected. |
| XCTest `runActivity()` | No | Runs its children serially. |
| Swift Testing sync `spec` | No | Runs its children serially to preserve the host test context. |
| Swift Testing async `spec` | Yes | Uses a task group. Main-actor groups are rejected. |

The Swift Testing entry points choose the reporter gate for the entire traversal. A sync group inside an async spec follows the async traversal's scheduling. All three built-ins are currently local to Rundown execution inside the host test. [Swift Testing entry points](../Sources/RundownSwiftTesting/SwiftTestingSuite.swift) · [Main-actor entry points](../Sources/RundownSwiftTesting/MainActorSwiftTestingSuite.swift)

### Swift Testing metadata timing probe

The probe ran on macOS with Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403. It used a parameterized `@Test` with two async `spec` calls and a deliberate known assertion failure in each spec and in the host body. A trait attached to the first spec's group attempted to append native traits to a copy of `Test.current` while the builder ran. The probe compared the console, `swift test list`, and the JSON Lines event stream from `swift test --parallel --event-stream-output-path …`.

| API | On the host `@Test` | Inside the running host |
|---|---|---|
| `Test.traits` and `.tags` | The declared tag appeared in `Test.current.tags` and the host's discovery record. The declared `TestTrait.prepare(for:)` marker ran during planning. | The added tag appeared on the local `Test` copy only. The running host retained its declared tag in both specs. The appended preparation marker never ran, and the discovery record had no added tag. |
| `ConditionTrait` and `.disabled` | The disabled host was listed and emitted `testSkipped` without entering its body. | Appending `.disabled` to the copy left the host running. `evaluate()` returned `false` without cancelling the host, so the caller can use the result for its own control flow. Calling `prepare(for:)` directly in a separate running host cancelled that task and emitted `testCancelled`. |
| `ParallelizationTrait` and `.serialized` | The host's two Swift Testing cases ran serially with parallel testing enabled. Rundown's two `.concurrent` children still overlapped within each case. | Explicitly wrapping the first spec in `.serialized.provideScope` still let the Rundown children overlap. In the control, removing `.serialized` from `@Test` while keeping the runtime scope let the two host cases overlap. |
| `IssueHandlingTrait.provideScope` | Swift Testing can install an issue handler declared on the test or suite. | A handler wrapping only the first spec added its comment to that spec's assertion. The second spec's assertion had its usual Rundown path, and the assertion outside both specs had neither added comment. All three issues shared the host's test ID. |

The CLI listed the three probe functions, including the disabled host. The event stream attributed the assertions from both specs and the host body to the same test ID. A runtime scope can affect work within a spec while reporting through the existing host test. [Swift Testing scoping API](https://developer.apple.com/documentation/testing/testscoping/providescope%28for%3Atestcase%3Aperforming%3A%29)

The declared traits and mutable `Test.traits` are present in Swift 6.0. Custom `TestScoping` arrived in Swift 6.1. Swift 6.2 added `ConditionTrait.evaluate()`, `IssueHandlingTrait`, and the public scoping implementation on `ParallelizationTrait`. These are API availability checks from the published sources. The runtime and CLI observations above were verified on Swift 6.4.2. [Swift 6.0 `Test` source](https://github.com/swiftlang/swift-testing/blob/swift-6.0-RELEASE/Sources/Testing/Test.swift) · [Swift 6.1 release notes](https://www.swift.org/blog/swift-6.1-released/) · [ST-0010](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0010-evaluate-condition.md) · [ST-0011](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0011-issue-handling-traits.md) · [Swift 6.2 parallelization source](https://github.com/swiftlang/swift-testing/blob/swift-6.2-RELEASE/Sources/Testing/Traits/ParallelizationTrait.swift)

### Phase 3 trait decisions

All three built-ins are execution-only in host-test mode. `RundownSwiftTesting` builds the tree after Swift Testing has selected the host test and delegates selection and scheduling to the shared traversal. Phase 3 defers a bridge API until discovery exposes a matching Swift Testing scope. [Host-test probe](#swift-testing-metadata-timing-probe)

| Rundown trait | Host-test decision | Candidate for native discovery |
|---|---|---|
| `.excluded` | Omit the example, child group, or hook locally. A spec with all children excluded returns without running its hooks, and the host can continue. Use native `.disabled` when the whole host test or suite should be skipped. | Omit excluded nodes and their subtrees from generated test content. This preserves temporary omission. Use native `.disabled` for a discoverable test intended to appear as skipped. |
| `.focused` | Resolve focus within the spec using Rundown's branch selection. The documented focus-inside-exclusion behavior is the baseline for the separate cleanup. | Focus stays a development-time execution control by default. If Phase 4 tests an opt-in discovery mode for focused examples, derive its selection from the resolved tree and keep the IDs of the tests it includes. |
| `.concurrent` | Rundown schedules the group's children. Native `.serialized` on a parameterized host test controls its Swift Testing cases. Rundown runs sync groups serially under the sync adapter, uses task groups in async specs, and rejects concurrent async main-actor groups before their hooks. | Consider native scheduling only at a boundary that represents a group's selected siblings. Test `.serialized` for boundaries that need sequential execution and allow Swift Testing parallelism where the Rundown group permits it. Verify hook lifetimes and main-actor isolation at that boundary. |

If the discovery prototype exposes a top-level group as a single case, Rundown still owns its internal hooks and child scheduling. Apply discovery choices to the nodes or cases the prototype actually emits. [View-shaped `Spec` research notes](SwiftTestingSpecDiscoveryResearch.md)

## Reporting Adapter Design

The XCTest adapter is a reporter, `XCTestReporter`:

- it renders structure as `XCTActivity`
- it enriches issues with full example paths
- it handles skips in a framework-aware way

Swift Testing needs an equivalent concept even if the rendering mechanism is different.

### The Reporter Protocol

The traversal talks to its host through `Reporter` (`Reporter.swift`):

```swift
package protocol Reporter: Sendable {
  func scope(for node: ExampleNode, _ body: () async -> Void) async
  func scope(for node: ExampleNode, _ body: () -> Void)
  func classify(_ error: any Error) -> ErrorKind          // .failure, .alreadyReported, or .skip
  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> ErrorHandlingDecision  // .record or .propagate
  var allowsConcurrency: Bool { get }
  var shouldStop: Bool { get }
}
```

It is not a set of events (`willRunGroup`, `didFinishNode` and so on), which is what this document first sketched, because the XCTest reporter needs a *scope*. `XCTContext.runActivity()` takes a closure, so the reporter has to wrap the execution of each node, and the errors the node throws are reported inside that scope so that they are attached to it.

- `scope` is called around the root group, each nested group, each example and each hook except `aroundEach`. There are sync and async versions because the traversal is written once as async and the sync version is generated from it. The XCTest reporter only implements the sync one.
- `classify` exists because `XCTSkip` is a framework type that the traversal doesn't know.
- `report` is called for new failures and skips thrown by a node's own code. Its decision says whether the error is recorded where it happened or propagated, so that the group keeps the first and rethrows it after teardown. The traversal handles already reported failures directly.
- `allowsConcurrency` keeps `.concurrent` groups serial under XCTest because `XCTContext` only works on the main thread. Swift Testing can use concurrency in the async traversal, where child tasks inherit the host test context.
- `shouldStop` lets the Swift Testing reporter stop new work while the traversal unwinds scopes it has entered.

The traversal owns hook order, [error and skip rules](Roadmap.md#error-and-skip-rules), concurrency, and the element path. The completed adapter notes describe [cancellation and teardown](CompletedPhases.md#cancellation-and-teardown).

The reporter is `Sendable` because concurrent groups call it from several tasks or threads, and its methods are not actor-isolated. A reporter that needs the main actor does that inside its methods with `MainActor.assumeIsolated`.

### Swift Testing Reporter Behavior

- Record thrown errors with the full Rundown path as an issue comment.
- Stop new setup and examples on cancellation. Swift Testing reports the reason supplied by the caller.
- Keep the hierarchy in path comments within the host test's results.

## Main Actor and Isolation Strategy

`MainActorSuite` already shows the right direction: actor isolation should be part of the framework-neutral model, not a framework-specific special case.

Deeper Swift Testing integration should preserve that.

### Recommended Rules

- actor isolation is carried in the plan (`ExampleNode.isolation`)
- adapters choose the correct execution path based on that isolation
- main-actor examples do not participate in any execution mode that conflicts with serialized main-actor execution

In practical terms:

- keep `MainActorSuite`
- keep `Rundown.TestCase` conforming to it
- use `MainActorSwiftTestingSuite` to build and run main-actor plans under Swift Testing

## Packaging Strategy

The packaging strategy matters as much as the API strategy because compatibility with existing XCTest-oriented targets is a requirement.

### Recommended Packaging Direction

Short term:

- keep the existing `Rundown` target as the default entrypoint
- do not add `Testing` as a dependency of that target
- add a separate optional adapter target for Swift Testing-specific integration if needed

Medium term:

- extract an internal core target if the adapter logic starts to crowd the current target
- keep XCTest support additive and source-compatible

### Avoid

- making the main `Rundown` product depend directly on `Testing`
- changing core trait protocols to inherit from Swift Testing protocols
- mixing Swift Testing-specific execution behavior into the builder in a way that makes XCTest behavior harder to reason about

## Phased Plan

The [completed phases](CompletedPhases.md) record the shared node traversal, the Swift Testing host-test adapter, the trait decisions, and the discovery experiment.

### Phase 4: Discovery Experiment

Phase 4 compared top-level and leaf cases with the existing host adapter and recorded the hook, trait, filtering, and reporting behavior of each mode. [Phase 4 results](CompletedPhases.md#phase-4--swift-testing-discovery-experiment) · [Discovery research](SwiftTestingSpecDiscoveryResearch.md)

### Phase 5 — Opt-in top-level discovery

Phase 5 keeps the host adapter as the supported baseline and develops opt-in top-level cases for Xcode reruns. Leaf discovery is deferred pending coordination of shared intermediate hooks and scheduling. [Phase 5 handoff](CompletedPhases.md#phase-5-handoff) · [Roadmap](Roadmap.md#phase-5--opt-in-top-level-swift-testing-discovery)

## Acceptance Criteria

The work should be considered successful if all of these hold:

- existing XCTest tests continue to pass without changes
- `Rundown.TestCase` remains supported
- Swift Testing users can opt into richer integration without rewriting the DSL
- the core package can still be used by targets that cannot import `Testing`
- failure output under Swift Testing includes the full Rundown path
- main-actor behavior remains explicit and reliable
- no built-in trait loses its existing meaning under XCTest

## Open Questions

- **What should opt-in `@Spec` expose and support?** The prototype is package-scoped and requires Darwin and Swift 6.4 or later. Decide what authoring API to expose, which toolchains and platforms to support, and whether to accept the prototype's underscored Swift Testing APIs and handwritten Mach-O records or require a stable registration API. [Registration and compatibility results](SwiftTestingSpecDiscoveryResearch.md#compatibility-and-cost)
- **How should top-level cases preserve Rundown's scheduling and hook behavior?** The prototype lets Swift Testing schedule top-level siblings, and `@Suite(.serialized)` restored declaration order in the probe. Decide how to preserve Rundown's default serial order and where `.concurrent` allows overlap. Verify root hook lifetimes, setup failure reporting, and cancellation-aware teardown in full runs and single-case reruns. [Scheduling results](SwiftTestingSpecDiscoveryResearch.md#scheduling-and-isolation) · [Hook lifetimes](SwiftTestingSpecDiscoveryResearch.md#hook-lifetimes)
- **Which rerun workflows should `@Spec` support?** Xcode reran individual cases in a top-level suite, while the tested nested suite had function-level filtering and its case selectors failed. SwiftPM filtering selected the generated function, and changing tree positions can change case IDs. Define the supported rerun workflows and document when case IDs can change. [Filtering and case identities](SwiftTestingSpecDiscoveryResearch.md#discovery-units-and-identities)

## Recommendation

The most defensible path is:

1. Keep the DSL shared.
2. Keep the core target free of `Testing`.
3. Introduce a plan model and reporter abstraction (done).
4. Add an optional Swift Testing adapter target with host-test integration first.
5. Treat leaf-native discovery as an experiment, not the baseline plan.

That path preserves existing XCTest compatibility, keeps XCUITest-oriented consumers safe, and still creates room for much deeper Swift Testing integration later.

## External References

- [Swift Testing overview](https://developer.apple.com/xcode/swift-testing)
- [swiftlang/swift-testing](https://github.com/swiftlang/swift-testing)
