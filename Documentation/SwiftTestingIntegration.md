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
- Swift Testing currently uses the generic `run()` / `spec()` path only. There is no direct `import Testing` dependency in the package.
- Rundown traits are currently neutral library concepts and are not coupled to Swift Testing traits.

That is a sound baseline. It keeps the DSL reusable, but it means Swift Testing currently gets less framework-native behavior than XCTest.

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
- `RundownTesting`
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
- The tree is internal. Making it, or the reporter, public or SPI for an adapter in a separate target is still undecided.

## Option A: Host-Test Swift Testing Adapter

This is the lowest-risk improvement and should be the first serious implementation target.

### Model

Users continue writing Swift Testing tests like this:

```swift
import Testing
import Rundown

struct FeatureTests: MainActorSuite {
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

Rundown still executes the whole spec as one host test, but a new Swift Testing-specific adapter improves what happens inside that run.

### What It Can Improve

- failure messages include the full Rundown path
- skips are reported with Rundown path context
- the current example path can be attached as comments or issue context
- built-in neutral traits can influence Swift Testing metadata where appropriate

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

This is still worth doing because it improves the normal user experience immediately without large architectural risk.

### Package and Type Shape

The implementation should live in a separate adapter target, for example:

- `RundownTesting`
  - imports the Rundown core module
  - imports `Testing`
  - defines the Swift Testing reporter
  - defines trait-bridge helpers
  - defines Swift Testing-specific `spec()` overloads

The minimum new internal types would likely be:

- `SwiftTestingReporter: Reporter`
- `SwiftTestingExecutionContext`
- `TraitBridgeContext`
- `SwiftTestingFailureFormatter`

The traversal already takes a reporter, so this is one more conformance to `Reporter`. That protocol is internal today, so an adapter in its own target needs it to be public or SPI.

The public API goal is that users still write `spec()`. Framework selection should come from the module/protocol overload set, not from a renamed entrypoint.

### Runtime Flow

The likely execution flow for host-test mode is:

1. User enters a normal Swift Testing `@Test`.
2. User calls a Swift Testing-specific `spec()` overload supplied by the adapter module.
3. The existing `spec()` / `run()` path builds the group and its node tree.
4. The traversal runs the tree with the Swift Testing reporter, as it does for the plain and XCTest reporters.
5. Reporter methods translate failures, skips, and path information into Swift Testing-friendly output.

This keeps the execution model familiar:

- Rundown still owns hook sequencing
- Rundown still owns focus / exclude semantics
- Rundown still owns its current concurrency model
- Swift Testing becomes the outer host and reporter sink, not the leaf scheduler

### API Surface Ideas

Keep `spec()` as the author-facing API.

For Swift Testing, the intended user shape should stay close to:

```swift
import Testing
import RundownTesting

struct FeatureTests: MainActorSuite {
  @Test func behavesCorrectly() async throws {
    try await spec {
      it("works") {
      }
    }
  }
}
```

For XCTest, the intended user shape should remain:

```swift
import RundownXCTest

@MainActor
final class FeatureTests: TestCase {
  func testBehavesCorrectly() throws {
    try spec {
      it("works") {
      }
    }
  }
}
```

Implementation options:

- keep a plain-runner global `spec()` in the framework-neutral core
- put XCTest activity/reporting behavior in member `spec()` overloads from the XCTest adapter
- put Swift Testing reporting behavior in global or member `spec()` overloads from the Swift Testing adapter
- prefer member `spec()` overloads on suite protocols where overload choice depends on isolation or framework context

This mirrors the technique already used by `MainActorSuite`: conformance changes which DSL helpers and `spec()` overloads are available in the test type.

### Suite Protocol Shape

If framework support is split into modules, adapter modules can define the suite-facing protocols that carry the right overload set.

Possible shape:

- core module
  - `MainActorIsolation` or similarly named marker protocol
  - plain global `spec()` overloads
  - no `Testing` or `XCTest` imports
- XCTest adapter module
  - `TestCase`
  - `MainActorSuite`
  - member `spec()` overloads that run XCTest activities
- Swift Testing adapter module
  - `Suite`
  - `MainActorSuite`
  - member `spec()` overloads that install a Swift Testing reporter before running

It is acceptable for the XCTest and Swift Testing adapter modules to expose protocols with the same short name if ordinary test targets import only one adapter module.

However, avoid requiring a target to import both adapters. If adapter modules both extend the same core protocol with identical `spec()` signatures, calls can become ambiguous. A cleaner design is:

- put shared isolation markers in the core with intentionally boring names
- put user-facing suite protocols and framework-aware `spec()` overloads in the adapter module
- make adapter modules re-export the DSL the user needs

That gives users one import and one `spec()` spelling per test framework.

### Failure and Skip Reporting Details

The reporter should preserve the existing high-value XCTest behavior: failures need the full Rundown path, not just the innermost leaf description.

Implementation details:

- use the current `ExampleRunner` stack as the source of truth for the path
- normalize path formatting in one place so XCTest and Swift Testing do not drift
- distinguish between:
  - assertion failures raised inside an example
  - skips raised inside hooks
  - unexpected thrown errors
- make skip reporting path-aware in the same way failure reporting is path-aware

The reporter only classifies an error as a failure or a skip, and records or propagates it. What a skip does to the rest of the run is decided once, in the traversal: a skip in a setup hook abandons that element or group without teardown, and a skip anywhere else ends only the node that threw it. Whatever error means "skip" under Swift Testing is recognized in the reporter's `classify`, and those rules then apply unchanged.

### Testing Strategy For Option A

Add adapter-focused tests that prove:

- a failing example under Swift Testing includes the full Rundown path
- a skip inside `beforeEach` or `beforeAll` is reported once with the correct path
- main-actor suites use the correct execution path
- no existing XCTest test behavior changes

Option A should be considered complete only if it adds value without requiring any semantic change to the current DSL.

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

The Swift Testing adapter can then provide a bridge from neutral Rundown traits to Swift Testing semantics.

### Proposed Shape

At the adapter layer, define something like:

```swift
protocol SwiftTestingBridgedTrait: Trait {
  func testingMetadata(
    context: TraitBridgeContext
  ) -> SwiftTestingMetadata
}
```

The exact API can vary, but the idea is:

- the core trait types do not import `Testing`
- the Swift Testing adapter can look at the plan and derive framework-native behavior

### Built-In Trait Mapping Ideas

`ExcludedTrait`

- Swift Testing host-test mode: no-op at framework level; Rundown omits execution as it does today
- Swift Testing leaf-native mode: can map to disabled leaf cases or omit them from discovery

`FocusedTrait`

- keep library-local at first
- in host-test mode, continue filtering inside Rundown
- in leaf-native mode, possibly omit non-focused leaves from discovery in development configurations

`ConcurrentTrait`

- host-test mode: keep current Rundown-managed concurrency semantics
- leaf-native mode: reconsider whether this should map to Swift Testing parallelization metadata, or whether the native test runner should own parallelism entirely

### Important Principle

Traits that affect discovery should be distinguished from traits that affect execution only.

That distinction is currently implicit. A deeper Swift Testing integration would benefit from making it explicit in the plan layer.

## Reporting Adapter Design

The XCTest adapter is a reporter, `XCTestReporter`:

- it renders structure as `XCTActivity`
- it enriches issues with full example paths
- it handles skips in a framework-aware way

Swift Testing needs an equivalent concept even if the rendering mechanism is different.

### The Reporter Protocol

The traversal talks to its host through `Reporter` (`Reporter.swift`):

```swift
protocol Reporter: Sendable {
  func scope(for node: ExampleNode, _ body: () async -> Void) async
  func scope(for node: ExampleNode, _ body: () -> Void)
  func classify(_ error: any Error) -> ErrorKind          // .failure or .skip
  func report(_ error: any Error, kind: ErrorKind, at node: ExampleNode) -> Disposition  // .record or .propagate
  var allowsConcurrency: Bool { get }
}
```

It is not a set of events (`willRunGroup`, `didFinishNode` and so on), which is what this document first sketched, because the XCTest reporter needs a *scope*. `XCTContext.runActivity()` takes a closure, so the reporter has to wrap the execution of each node, and the errors the node throws are reported inside that scope so that they are attached to it.

- `scope` is called around the root group, each nested group, each example and each hook except `aroundEach`. There are sync and async versions because the traversal is written once as async and the sync version is generated from it. The XCTest reporter only implements the sync one.
- `classify` exists because `XCTSkip` is a framework type that the traversal doesn't know.
- `report` is called once for each error that a node's own code throws. Its disposition says whether the error is recorded where it happened (XCTest) or propagated, so that the group keeps the first and rethrows it after teardown (the plain runners).
- `allowsConcurrency` lets the XCTest reporter keep running `.concurrent` groups serially, since `XCTContext` only works on the main thread.

The traversal owns everything else: the order of hooks, what an error or a skip does to the rest of the run (see the roadmap's "Error and skip rules"), concurrency, and the element path.

The reporter is `Sendable` because concurrent groups call it from several tasks or threads, and its methods are not actor-isolated. A reporter that needs the main actor does that inside its methods with `MainActor.assumeIsolated`.

### Swift Testing Reporter Goals

- prefix failures with the full Rundown path
- record skip reasons consistently
- preserve example hierarchy in some form, even if there is no `XCTActivity` equivalent
- attach path or context metadata where the framework makes that useful

This is likely the highest-value runtime improvement after the plan model split.

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
- make any future Swift Testing adapter understand main-actor plans directly rather than relying on incidental overload selection only

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

### Phase 1: Internal Cleanup For Extensibility (done)

- introduce an explicit plan/tree model (`ExampleNode`)
- extract reporting hooks from `ExampleRunner` (`Reporter`, with `PlainReporter` and `XCTestReporter`)
- one traversal for every way of running a spec (`NodeTraversal.swift`)
- behavior unchanged, except that a skip in an `afterEach`, `afterAll` or `aroundEach` hook now ends only that hook, instead of aborting the run under XCTest
- tests prove XCTest behavior remains identical (`ActivityStructureXCTests`, `MessageXCTests`, `MultiRunTests`)

### Phase 2: Swift Testing Runtime Adapter

- add an optional Swift Testing integration target
- implement a reporter for full-path failures and skips
- expose small helper APIs for use inside `@Test` functions
- keep discovery at the outer host-test level

### Phase 3: Trait Bridge

- bridge built-in Rundown traits to Swift Testing metadata where the mapping is obvious and safe
- leave ambiguous traits as Rundown-local semantics
- document which traits are execution-only vs metadata-capable

### Phase 4: Discovery Experiment

- prototype leaf-native Swift Testing discovery on a branch
- require no migration to XCTest users
- measure complexity of hook replay, naming, and trait inheritance

### Phase 5: Decide Whether Leaf-Native Is Worth It

Proceed only if the prototype delivers clear value:

- materially better filtering
- materially better reporting
- manageable implementation complexity

Otherwise keep the host-test adapter model and stop there.

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

- Is host-test Swift Testing integration already "good enough" once reporting and trait bridging improve?
- Is leaf-native discovery worth the required plan-model refactor?
- Should focus remain a purely local development feature, or should it participate in Swift Testing discovery?
- Should a future discovery bridge use macros, generated code, or runtime-discoverable test content?
- Is a package split worth doing early, or only once the Swift Testing adapter is real?

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
