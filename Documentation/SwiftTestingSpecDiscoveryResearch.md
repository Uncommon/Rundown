# A `Spec` type shaped like `View`

The prototype represented each spec as a type with one computed property, modeled on SwiftUI's `View`. It explored what Swift Testing could discover from that shape, especially whether Rundown groups could appear as nested suites. These probes support the [Phase 4 results and Phase 5 handoff](CompletedPhases.md#phase-4--swift-testing-discovery-experiment).

The probe used the Swift Testing source in `~/Developer/swift-testing`, a scratch protocol and macro in `RundownMacros`, and hand-written test content records. It ran with Xcode's Swift 6.4 toolchain. After the scratch code was removed, all 124 tests passed.

## Initial findings

- *The protocol shape compiles.* `protocol Spec { init(); @ExampleBuilder<AsyncCall> var spec: ExampleGroup<AsyncCall> { get } }`. The builder attribute on the requirement is inherited by the witnesses, so `var spec: ExampleGroup<AsyncCall> { describe… it… hooks… for-loops }` type-checks like the closure of `spec { }`, with no `some` and no erasure, because the builder already returns a concrete group. The root is `spec.named(String(describing: Self.self)).node`, and `node.run(with:)` runs it unchanged. A `@MainActor protocol MainActorSpec: MainActorSuite` with `@ExampleBuilder<AsyncMainCall>` compiled too, and its hook and example ran main-actor isolated (checked by hand, not through the macro).
- *Tests can be registered without `@Test` or `@Suite`.* A global or static `@section("__DATA_CONST,__swift5_tests") @used let record: Testing.__TestContentRecord = (0x74657374, 0, { out, type, hint, reserved in Test.__store(generator, into: out, asTypeAt: type) }, 0, 0)` was discovered and ran. `@section` and `@used` need no feature flag in 6.4. The generator builds its `Test` with the public but underscored `Test.__function(named:in:…)` and `Test.__type(_:traits:sourceBounds:)`; the record format is documented in swift-testing's `Documentation/ABI/TestContent.md`. Those helpers are marked "used to implement the macros, do not call directly", and the installed signatures differ from the source tree: 6.4 takes `sourceBounds: __SourceBounds` (built with `__SourceBounds(__uncheckedLowerBound:upperBound:)`), and older `sourceLocation:` forms exist only as internal `@abi` shims. The ABI document also says to define your own copy of the record tuple type, not to use `__TestContentRecord`, which the scratch macro did.
- *A macro cannot hand the work to `@Test`.* A member macro that emits `@Test(arguments:) func …` fails: the nested `@Test` expansion does not see the enclosing type, so it emits instance-member record storage and the compiler rejects it ("properties with attribute @section must be static"), with or without `static` on the function. The macro has to emit the `@section` records itself, as Swift Testing's own macros do. It uses `Testing` names, so it belongs in the adapter module, not the core.
- *One record is one `Test`.* `Test.all` takes a generator from each record and each generator returns a single `Test`. The plan then builds the suite tree from `Test.ID`, and a suite's identity is the reflected name of its containing type, split on `.`. A test function's name can be any string, but a suite has to be a real type. So a `describe` or `context` that exists only after the spec is evaluated cannot become a suite.
- *Types created at run time do not get around that.* Classes made with `objc_allocateClassPair` and named like `RundownTests.ZZSpec.logged in` reflect with exactly those components, but they cannot be passed to `__type` and `__function`, which are generic over `S.Type`: implicit existential opening bound `S` to `NSObject`, and `_openExistential` crashed SILGen. It would be Darwin-only anyway. A pool of pre-declared marker types would work but is capped and ugly. Not recommended.
- *Examples can be dynamic, as test cases.* `__function(…arguments:…)` evaluates its closure when the plan is built, so the leaves of `Self().spec.node` become cases, including those from `for` loops. Each case is labelled by a `CustomTestStringConvertible` argument, here the full path ("FeatureSpec, logged in, throws"), and an issue is attributed to its case. A thrown error recorded by the reporter carried the path as a comment as well; a failed `#expect` did not (see below). `swift test list` shows only `Type/examples`, and `--filter` matches test IDs, not cases (`--filter "loop example"` ran nothing).
- *Nested `@Spec` types are nested suites.* With the macro on both, `OuterSpec { @Spec struct InnerSpec }` listed as `OuterSpec/examples` and `OuterSpec/InnerSpec/examples`, and ran as nested suites. This is the only nesting available, and it follows the source declaration, not the `describe` structure.
- *One case per leaf repeats group hooks.* Each case ran its own copy of every enclosing hook: with 7 leaves, the root `beforeAll` ran 7 times, concurrently, and the `logged in` group's `beforeAll` and `afterAll` ran 3 times each. This is the Option B problem, shown.
- *One case per top-level child preserves the traversal's hook order when the root hooks wrap the cases.* The original probe used a suite trait to run root `beforeAll` and `afterAll` once. Each case kept the root's each-hooks and one child, so the nested group's hooks still ran around the whole group. The adapter uses the [generated function's scope](#hook-lifetimes).
- *Cases run in parallel.* The cases of one test ran concurrently, so sibling elements overlap where the traversal runs them one after another.

## Remaining probes

- Try the protocol-conformance discovery listed in the 6.4 interface (`__TestContentRecordContainer` and `@_alwaysEmitConformanceMetadata`). It needs an accessor that knows `Self`, which a `@convention(c)` accessor cannot capture.
- Verify the documented test-content sections on ELF, COFF, and Wasm. The Rundown prototype has been checked on Mach-O. [Swift Testing record format](https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/TestContent.md)

## Implications

- Discovery by type evaluates the `spec` property normally, so loops, conditionals, and helper-built subtrees work. Each type needs an attribute such as `@Spec` to emit its registration record. [Discovery bridge design](SwiftTestingIntegration.md#option-c-discovery-bridge)
- Leaves as cases (Option B) needs a lifecycle coordinator. A top-level case keeps its subtree intact and uses the existing traversal for everything below the root. The root's `beforeAll` and `afterAll` wrap the selected cases once. The case label names the top-level child.
- Nested suites are real only for nested types. A `describe` stays a path in the case label. If real suites per group are wanted, each would need to be a declared type, and the outer each-hooks would then wrap a suite, which is the unsolved part of Option B.
- Failed `#expect`s inside a nested group are attributed to the top-level child's case. A Rundown path comment can identify the leaf within that case.
- The current registration builds the tree once during planning and shares its captured fixture state across cases and root hooks. [Plan and fixture lifetime](#plan-and-fixture-lifetime)
- Ordinary top-level cases run serially. A concurrent root lets Swift Testing schedule its cases, and Rundown schedules children within each case. [Top-level scheduling policy](#top-level-scheduling-policy)
- The probe depends on underscored APIs whose signatures already differed between the source tree and the toolchain. That approach would need checks against each supported toolchain. See the [possible upstream proposal](#possible-upstream-proposal).
- Public experimental `@Spec` opts a type into top-level discovery alongside the host adapter. [Opt-in discovery guide](../README.md#opt-in-discovery-with-spec)

## Host-test baseline

The comparison fixtures ran on macOS with Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403. Both expose a builder that the prototype can reuse. The ordinary fixture has a helper-built nested group with a loop and conditional. It produces a synchronous and an asynchronous example with the same label and full path, followed by a required assertion and a thrown error. The root also has an independent example. The main-actor fixture checks isolation in the builder and its callbacks, including an example that suspends before recording its trace. [Comparison fixtures](../Tests/RundownSwiftTestingTests/DiscoveryComparisonTests.swift)

```sh
swift test --disable-xctest --filter DiscoveryComparisonTests \
  --event-stream-output-path /tmp/rundown-discovery-baseline.jsonl
swift test list --skip-build --disable-xctest
swift test --skip-build --disable-xctest --filter 'DiscoveryComparisonTests/hostAdapterBaseline'
swift test --skip-build --disable-xctest --filter 'Repeated discovery label'
```

The listing contained these two entries for the fixtures.

```text
RundownSwiftTestingTests.DiscoveryComparisonTests/hostAdapterBaseline()
RundownSwiftTestingTests.MainActorDiscoveryComparisonTests/mainActorBaseline()
```

The host filter ran one test, including every example in its spec. Filtering for `Repeated discovery label` returned `No matching test cases were run`. The event stream attributed all three deliberate known issues to `hostAdapterBaseline()`, with one `issueRecorded` event per failure.

| Failure | Path comment | Source location in the result |
|---|---|---|
| Failed `#expect` | `Rundown path: Discovery comparison, Generated group, Repeated discovery label` | The assertion in `DiscoveryComparisonTests.swift` |
| Failed `#require` | `Rundown path: Discovery comparison, Generated group, Required assertion` | The assertion in `DiscoveryComparisonTests.swift` |
| Thrown `ExampleFailure` | `Discovery comparison, Generated group, Thrown error` | The `Issue.record` call in `SwiftTestingReporter.swift` |

The ordinary trace shows root `beforeAll` and `afterAll` once each. Root `aroundEach`, `beforeEach`, and `afterEach` wrap the whole generated group once and the independent example once. Inside the generated group, `beforeAll` and `afterAll` bracket all four examples, and `beforeEach` and `afterEach` run for each example, including the failing ones. Both tests assert the full traces in the fixture source.

## Prototype registration

Phase 4 introduced the package-scoped `@Spec` prototype on Apple platforms with Swift 6.4 or later. The initial prototype was verified with Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403 on Apple Silicon. Phase 5 made the zero-argument macro public for top-level discovery and kept the leaf overload package-scoped. [API and support boundary](SwiftTestingIntegration.md#opt-in-api-and-support-boundary) · [Registered fixture](../Tests/RundownSwiftTestingTests/DiscoveryRegistrationSpec.swift)

Apply `@Spec` to a struct that provides the computed `spec` property. The macro adds the `Spec` conformance, applies the result builder to a DSL getter, and emits the registration record. A getter can also return a prebuilt group explicitly.

The macro emits Mach-O `__DATA_CONST,__swift5_tests` records with kind `0x74657374`. It uses a local copy of the record layout with a nonoptional C accessor because Swift 6.4.2 rejected the optional accessor literal in `@section`. The layouts matched at a 32-byte stride and 8-byte alignment on the tested toolchain. The accessor passes the runtime type pointer to `Test.__store`, and the generators use `Test.__function` and `Test.__type` with `__SourceBounds` derived from the spec declaration. [Swift Testing test content ABI](https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/TestContent.md)

The initial registration at `1070563` evaluated the computed `spec` property at execution time and ran its named `ExampleNode` tree with the existing reporter. SwiftPM listed `DiscoveryRegistrationSpec/examples()` alongside `DiscoveryComparisonTests/hostAdapterBaseline()`, and both tests passed in the same run. The flag-off build listed the conventional host baseline. The parameterized prototype below builds on that registration.

## Discovery units and identities

On the same Swift 6.4.2 toolchain, `@Spec` now registers `examples(unit:)` with one parameterized case per selected top-level child. `@Spec(.leaves)` uses one case per selected leaf. Both use the same fixture tree. It yields two top-level cases and three leaf cases, including two leaves with the same full Rundown path. The excluded example sits between the two selected root children and its position is retained in the numbering. [Comparison fixtures](../Tests/RundownSwiftTestingTests/DiscoveryRegistrationSpec.swift)

Each case encodes its zero-based child indices with `CustomTestArgumentEncodable`. The label includes the path and index, so the repeated items are distinguishable as `[0.0]` and `[0.1]`. All eight case IDs, scoped to their generated test function, matched across two runs. The IDs are stable for the same tree and declaration. Inserting or reordering nodes can shift the positional IDs. [Swift Testing argument encoding](https://developer.apple.com/documentation/testing/customtestargumentencodable)

| Check | SwiftPM | Xcode 27.2 command-line runner |
|---|---|---|
| Listing | `swift test list` shows one function per declared type. Case labels appear during execution. | `-enumerate-tests` shows the functions and the declared `Leaves` suite. The result bundle shows an `Arguments` row and a case URL for each case. |
| Filtering a function | Filtering for the top-level function ran its two cases. Filtering for the nested leaf function ran its three cases. | The target-relative nested suite and function selectors ran the three nested leaf cases. |
| Rerunning one case | `--filter` returned zero matches for the leaf label, its position, and a regex containing the case's argument hash. | `-only-testing` with the result's case URL reran just `Registered group [0]` in the top-level case fixture and just `Repeated item [0.1]` in the separate top-level leaf fixture. The nested leaf's full case URL returned “There are no test bundles available to test.” The target-relative nested selector with `?args=` exited successfully with zero tests. |

The declared `DiscoveryRegistrationSpec.Leaves` type appears as a nested Swift Testing suite. `Registered group` appears in the case labels, with no suite entry. The top-level `DiscoveryRegistrationLeafSpec` controls for nesting by registering the same leaf cases in a separate top-level suite.

The argument collection builds the tree during planning and carries a projected tree into each case. A top-level case keeps its subtree intact, and a leaf case keeps only its ancestor chain and leaf. The generated function's scope owns the root group hooks.

```sh
SWT_EXPERIMENTAL_EVENT_STREAM_FIELDS_ENABLED=1 \
  swift test --disable-xctest \
  --filter DiscoveryRegistration --event-stream-output-path /tmp/rundown-discovery-units.jsonl
swift test list --skip-build --disable-xctest
```

For the Xcode comparison, build `Rundown-Package` for testing on macOS. Use the resulting `.xctestrun` with `xcodebuild test-without-building -enumerate-tests`, then run the discovery suites into a result bundle. `xcresulttool get test-results tests` reports each argument's `nodeIdentifierURL`, which can be passed to `xcodebuild test-without-building -only-testing:<url>`.

## Plan and fixture lifetime

The Swift 6.4.2 scratch probe used the current `@Spec` adapter and an explicit native `@Suite` with a nonrecursive `TestScoping` trait. Two specs built the same helper-generated group with a loop, a conditional exclusion, and an independent example. The leaf variant exposed `item-1 [0.0]`, `item-3 [0.2]`, and `Tail [1]`. The top-level variant exposed `Generated [0]` and `Tail [1]`. The five names and case IDs matched across runs.

- **Listing and filtering.** Swift Testing's `--list-tests` entry point listed both generated functions without initializing their `Spec` instances or evaluating either getter. Filtering to one function initialized and built only that spec. The getter ran with the generated `Test.current` during planning, before the suite entered its execution scope. [Lazy argument evaluation](https://developer.apple.com/documentation/testing/parameterizedtesting)
- **Sharing during execution.** The projected cases held the same state captured by their planned tree. Each suite's scope initialized a separate task-local fixture, which its cases inherited and updated. The getter saw no suite fixture during planning. Setup can share state with running cases through that scope, and setup that needs the exact planned tree must receive it from planning. [Swift Testing execution scopes](https://developer.apple.com/documentation/testing/testscoping/providescope%28for%3Atestcase%3Aperforming%3A%29)
- **Repeating a case and rerunning a plan.** With `--repetitions 2` at Swift Testing's entry point, each case's counter went from one to two in both its plan fixture and its suite fixture. Two complete runner invocations in the same process each built fresh state and restarted those counters. The two specs had distinct state throughout. For hook coordination, keep the root with its plan and give each execution scope a fresh lifetime.

## Hook lifetimes

`@Spec` attaches a scoping trait to the generated `examples(unit:)` function. Planning gives that trait the original root tree when it has cases. The trait wraps the function once around its selected cases, so root `beforeAll` and `afterAll` run with the function as the current test. Projected cases keep the root's each-hooks and their own subtree hooks. An explicit `@Suite` keeps its own suite record and traits, with the same function-level root hook lifetime. [Scope implementation](../Sources/RundownSwiftTesting/SpecRegistration.swift)

| Scenario | Observed behavior |
|---|---|
| Full run with serial case scheduling | The generated spec and the host adapter produced the same trace. Root setup and teardown ran once. The parent's `aroundEach`, `beforeEach`, and `afterEach` wrapped the whole nested group once, including both of its examples, then wrapped the tail example once. |
| Xcode rerun of `Nested [0]` | Root setup and teardown ran once, the parent each-hooks wrapped only the nested group, and the tail case did not start. |
| All examples excluded | Swift Testing skipped the function with `No test cases found.` The root hooks and example were untouched. |
| Root setup throws | The generated function received one issue with the `FailingSetup, before all: open` path. Root teardown ran with the task still active. No cases started. |
| Root setup calls `Test.cancel` | The root hook reporter cancelled the function scope's task when it caught the skip. Root teardown saw a cancelled task. No cases started. |
| Root teardown fails an assertion | The generated function received one issue after its cases, with the original assertion location and root hook path. |

`Test.cancel` throws in a parameterized function scope without a current case. Rundown cancels the scope's task when that error reaches the root hook reporter, so teardown sees cancellation. This path emits no native cancellation event, and separately declared child suites run independently. Leaf cases still replay hooks of intermediate groups. Preserving those lifetimes would require coordinating the selected leaves of each shared group, especially when an each-hook wraps a whole nested group. [Hook fixtures](../Tests/RundownSwiftTestingTests/DiscoveryHookLifetimeTests.swift)

```sh
swift test --disable-xctest --no-parallel \
  --filter DiscoveryHook --event-stream-output-path /tmp/rundown-discovery-hooks.jsonl
```

## Selection at the discovery boundary

The prototype already projects cases from `ExampleNode.indexedSelectedChildren`. Both case modes use the selection Rundown resolves for the host adapter, and case IDs use child positions from before filtering. The ordinary `.focused` trait therefore controls selection in the opt-in `@Spec` experiment. [Selection fixture](../Tests/RundownSwiftTestingTests/DiscoverySelectionTests.swift) · [Trait behavior by entry point](SwiftTestingIntegration.md#trait-behavior-by-entry-point)

| Fixture | Focus enabled | Focus disabled |
|---|---|---|
| Top-level cases | `Nested focus [1]`, `Holder [2]` | The same cases plus `Unfocused root example [0]` |
| Leaf cases | `Nested focus / Chosen [1.1]`, `Holder / Holder example [2.0]` | The same cases plus `Unfocused root example [0]` and `Nested focus / Unfocused nested example [1.0]` |
| Examples executed in either discovery mode and in the host | `Chosen`, `Holder example` | The same examples plus `Unfocused nested example` and `Unfocused root example` |

The `Holder` branch is selected because focus inside an excluded subgroup still counts toward its ancestor's focus. Rundown omits that subgroup from the holder's own children and runs `Holder example`. This matches the existing node selection baseline. The excluded root branch, nested branch, and explicitly excluded leaf produced no cases, and excluded hooks of all five kinds produced no issues. [Focus baseline test](../Tests/RundownTests/ExampleNodeTests.swift)

All four retained case IDs matched across the two runs on Swift 6.4.2. A retained group case can cover a different set of leaves when focus changes while keeping its own ID.

```sh
for without_focus in 0 1; do
  RUNDOWN_DISCOVERY_SELECTION_UNFOCUSED="$without_focus" SWT_EXPERIMENTAL_EVENT_STREAM_FIELDS_ENABLED=1 \
    swift test --disable-xctest \
    --filter DiscoverySelection --event-stream-output-path "/tmp/rundown-selection-$without_focus.jsonl"
done
```

## Scheduling and isolation

On Swift 6.4.2 with Swift Testing 2403, temporary fixtures compared the host adapter, `@Spec`, and `@Spec(.leaves)` in SwiftPM runs with `--parallel` and `--no-parallel`. Serial probes checked that the first body finished before the second began, even after a suspension. Overlap probes required both bodies to reach a rendezvous before either could finish. The event stream confirmed the start and end order of the native cases.

| Boundary | Observed scheduling |
|---|---|
| Host adapter | Ordinary siblings ran in declaration order. Two children of an async `.concurrent` group overlapped. |
| Top-level cases | With `--parallel`, ordinary root siblings overlapped across native cases. An explicit `@Suite(.serialized)` ran cases in declaration order even with `--parallel`. |
| Children inside a top-level case | Ordinary siblings stayed serial. A `.concurrent` subgroup still overlapped under both `@Suite(.serialized)` and `--no-parallel`. |
| Leaf cases | With `--parallel`, two leaves from an ordinary serial group overlapped. Under `@Suite(.serialized)`, two leaves from a `.concurrent` group ran in declaration order. |

`--no-parallel` also put the default top-level and leaf cases in declaration order. In Phase 4, the generated function applied no scheduling policy of its own. A top-level case preserved Rundown's scheduling within its subtree. A flat leaf list shared one native scheduling policy across groups with potentially different Rundown traits. The explicit `@Suite(.serialized)` probe had no root group hooks.

The host main-actor fixture checked the builder, hooks, and example after suspension with `MainActor.preconditionIsolated()`. The concurrent async main-actor host test caught `ConcurrentDisallowedError` before the group's own hooks and verified that a valid sibling and the root teardown still ran. A compile probe for an `@Spec` with an `ExampleGroup<AsyncMainCall>` getter failed because both the generated builder and the `Spec` requirement use `AsyncCall`. The host adapter remains the entry point for main-actor group semantics. [Main-actor fixture](../Tests/RundownSwiftTestingTests/DiscoveryComparisonTests.swift) · [Concurrent main-actor check](../Tests/RundownSwiftTestingTests/MainActorSpecTests.swift) · [Registration](../Sources/RundownSwiftTesting/SpecRegistration.swift)

### Top-level scheduling policy

Phase 5 applies Swift Testing's `.serialized` scope around the cases of a top-level spec whose root has ordinary serial scheduling. The adapter reads the root after planning builds it. Returning a root group with `.concurrent`, for example `return describe("Checkout", .concurrent) { … }`, lets Swift Testing use the surrounding runner's parallelization policy. A native `@Suite(.serialized)` or `--no-parallel` still serializes those outer cases. Rundown schedules children within each case and honors a nested group's `.concurrent` trait there. The experimental leaf mode retains native outer scheduling. [Scheduling scope](../Sources/RundownSwiftTesting/SpecRegistration.swift)

SwiftPM event streams verified that ordinary top-level cases completed in declaration order with `--parallel`. Two cases of an explicitly concurrent root reached a rendezvous before either finished. They ran serially under `--no-parallel` and under an explicit native `@Suite(.serialized)`. Children of a nested `.concurrent` group still reached their rendezvous with native parallelism disabled.

The hook fixture checks the complete trace, including root setup and teardown and the each-hooks around each selected child. It passed in a full SwiftPM run and in Xcode's full adapter run. Rerunning only `Nested [0]` in Xcode kept one root setup and teardown and ran only that child's hooks and examples. Setup failure recorded one issue before any cases started, and setup cancellation skipped the cases and reached teardown with a cancelled task. [Hook fixture](../Tests/RundownSwiftTestingTests/DiscoveryHookLifetimeTests.swift)

## Reporting and reruns

On Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403, three temporary wrappers ran the same `DiscoveryComparisonFixture.build()` tree. A plain async `@Test` called `spec` without `withKnownIssue`. Top-level `@Spec` and `@Spec(.leaves)` types returned the same builder's group. This exposed actual failures for Xcode's rerun comparison. [Shared fixture](../Tests/RundownSwiftTestingTests/DiscoveryComparisonTests.swift)

SwiftPM emitted nine `issueRecorded` events, one per failure in each mode. Xcode's `xcresulttool get test-results tests` returned the same nine failure messages. Its summary counted three failed functions and showed one representative message per function. The detailed results kept the individual messages under the test or its argument row.

| Failure | Full path suffix after the spec name | Location in both results |
|---|---|---|
| Failed `#expect` | `Generated group, Repeated discovery label` | Original assertion in `DiscoveryComparisonTests.swift:36` |
| Failed `#require` | `Generated group, Required assertion` | Original assertion in `DiscoveryComparisonTests.swift:47` |
| Thrown `ExampleFailure` | `Generated group, Thrown error` | Reporter call in `SwiftTestingReporter.swift:50`, with the leaf identified by its path |

The native assertion issues kept their original messages and gained a `Rundown path:` comment. The thrown error carried the same full path as a comment. Each `#require` produced one issue.

| Mode | Issue attribution | Rerun in the Xcode command-line runner |
|---|---|---|
| Host adapter | All three issues belonged to `reporting()`. | The target-relative function selector reran the whole spec and reproduced all three issues. The full host `nodeIdentifierURL` selected zero tests on this toolchain. |
| Top-level cases | All three issues belonged to `Generated group [0]`. The independent case passed. | The argument's `nodeIdentifierURL` reran only the group case and reproduced all three issues. |
| Leaf cases | The issues belonged to `Repeated discovery label [0.1]`, `Required assertion [0.2]`, and `Thrown error [0.3]` respectively. The same-label leaf at `[0.0]` passed. | The failed duplicate's `nodeIdentifierURL` reran only `[0.1]` and reproduced just the failed `#expect`. |

SwiftPM's experimental event fields (`SWT_EXPERIMENTAL_EVENT_STREAM_FIELDS_ENABLED=1`) exposed the argument labels and IDs. Filtering by the generated leaf function reran all five cases and reproduced all three issues. Filters for the required assertion's label, position, and argument hash each matched zero tests. Xcode case reruns used `test-without-building -only-testing:<nodeIdentifierURL>` with the URLs from the detailed test tree. This probe used top-level Swift types for both discovery modes. The [discovery units probe](#discovery-units-and-identities) records the separate limitation for a case inside a nested Swift suite.

### Phase 5 filtering and compatibility

A temporary copy of the external client fixture used public `@Spec` with the final top-level scheduling policy. The probe ran on macOS arm64 with Xcode 27.2, Swift 6.4.2, and Swift Testing 2403. The tree contained `Saved card [0]`, an excluded sibling at index 1, and `Guest checkout [2]`. [External fixture](../Tests/ExternalSpecFixture/Tests/ExternalSpecFixtureTests/CheckoutSpec.swift)

| Check | Result |
|---|---|
| Xcode failed group rerun | The full run failed `Saved card [0]` and passed the guest case. The failed group's `nodeIdentifierURL` reran only that group and reproduced the same three issues. The failed `#expect`, failed `#require`, and thrown error each carried the path through `FilteringProbeSpec, Saved card, Returning customer` to the leaf. Both assertions kept their original source lines. The thrown error pointed to `SwiftTestingReporter`. |
| SwiftPM filtering | Filtering by the generated function ran both cases. The saved-card label, position, and argument hash each matched zero tests. The nested spec's function filter also ran both of its cases. |
| Xcode nested suite | A public top-level-case `@Spec` nested inside a native `@Suite` ran both cases with a target-relative function selector. The full argument URL reported that there were no test bundles available. The target-relative selector with `?args=` exited successfully with zero tests. |
| Positional identity | Case IDs matched across unchanged runs, and the saved-card argument hash matched between SwiftPM and Xcode. Inserting an excluded sibling before the two cases shifted their positions to `[1]` and `[3]` and changed both IDs, even though the selected groups were the same. |
| Existing suites | All 158 macOS runtime tests passed, including the host adapter, plain runner, XCTest, and discovery tests. A separate build of the invalid-sequences fixture matched all 20 expected diagnostics. |

## Compatibility and cost

The prototype branch was checked with Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403. SwiftPM ran on Apple Silicon with macOS 27.0.1, the macOS 27.2 SDK, and the package's macOS 15 deployment target. The flag-on and flag-off rows record measurements from before the custom build flag was removed.

| Check | Result |
|---|---|
| macOS with the discovery flag off | 125 XCTest and 23 Swift Testing tests passed, with 16 expected known issues. The host comparison appeared in test listing and generated discovery tests were absent. |
| macOS with the discovery flag on | 125 XCTest and 32 Swift Testing tests passed, with 17 expected known issues. The suite includes the plain-runner, XCTest, and Swift Testing host tests alongside the discovery fixtures. |
| Compile-failure fixture | A separate SwiftPM build of `Tests/InvalidSequencesFixture` produced all 20 expected diagnostics. |
| Other Apple targets | With the discovery flag defined, both library modules compiled for iOS 17 and tvOS 17 device and simulator, watchOS 10 arm64_32 device and arm64 simulator, and Mac Catalyst 17 arm64. At that point the guard still limited discovery itself to macOS. |
| Test content objects | The arm64 registration fixture emitted six 32-byte records aligned to eight bytes in Mach-O `__DATA_CONST,__swift5_tests`. An x86_64 macOS compile-only probe emitted the same layout with two records for one spec. Runtime discovery was verified on arm64. ELF, PE/COFF, and Wasm remain unverified. |

After the flag was removed, the same 157 macOS runtime tests passed and SwiftPM listed both discovery modes with its default build. In a separate compile-only probe with the macOS guard removed, the registration code compiled for the iOS, tvOS, watchOS, and Mac Catalyst targets above. A minimal `@Spec` emitted the same Mach-O section, record size, and alignment as a native `@Suite` with one `@Test` on each target, including 20-byte records with four-byte alignment on watchOS arm64_32.

The host adapter uses Swift Testing's normal `@Test` registration and leaves the spec lifecycle to Rundown's traversal. It uses the toolchain's public issue scoping when available. Both modes share the reporter's reflected `Testing.SkipInfo` name check for cancellation. The prototype additionally depends on `@used` and `@section`, the test content record layout and kind and context values, and the underscored `Test.__store`, `Test.__function`, `Test.__type`, and `__SourceBounds` APIs. Those entry points and the record ABI are toolchain dependencies. The public `TestScoping` trait and case argument APIs handle scope and identity after registration. [Host reporter](../Sources/RundownSwiftTesting/SwiftTestingReporter.swift) · [Registration macro](../Sources/RundownMacros/DiscoverySpecMacro.swift) · [Registration adapter](../Sources/RundownSwiftTesting/SpecRegistration.swift)

### Runtime checks without the macOS guard

In a scratch copy with the guard removed, Xcode 27.2 discovered and ran six selected test functions on both iOS 17.5 and iOS 27.2 simulators. The passing fixtures covered top-level and leaf cases, selection, root hook lifetime, and setup cancellation.

The full iOS 27.2 run failed when the root setup failure fixture recorded a suite-level issue. Swift Testing reported the expected known issue, then Xcode's XCTest harness trapped with `Recording issues for suites is not supported`. Xcode on macOS reproduced the crash with the same fixture and with a native `@Suite` whose `TestScoping` trait recorded a known issue. SwiftPM on macOS completed the Rundown fixture with the expected known issue.

Moving the [root hooks into the generated function's scope](#hook-lifetimes) gives setup and teardown issues a function identity that the Xcode bridge accepts. Discovery now uses a Darwin import check and the Swift 6.4 compiler check. [Root hook fixtures](../Tests/RundownSwiftTestingTests/DiscoveryHookLifetimeTests.swift)

All 33 Swift Testing adapter tests passed in Xcode on macOS, iOS 17.5 and 27.2 simulators, watchOS 27.2 Simulator, and Mac Catalyst. Separate unexpected setup and teardown failures produced a failed Xcode result without crashing. Rerunning one discovered group in Xcode ran root setup and teardown once around just that group. The tvOS checks covered compilation and object layout, with device and simulator records matching native sizes and alignment.

### 60-context compile comparison

Each declaration used the same 60 contexts with nine DSL statements apiece, including four hooks and five examples. One example in each context suspended. **Current host** means the conventional adapter from the discovery branch at `acc9e96`. An async `@Test` in a type conforming to `SwiftTestingSuite` calls `try await spec("60 contexts") { … }`. Both host rows compile that same test, with the flag controlling whether the package also compiles in the discovery prototype. Both discovery declarations use an `ExampleGroup<AsyncCall>` getter with the macro-supplied builder. [Host adapter](../Sources/RundownSwiftTesting/SwiftTestingSuite.swift)

Each median is from three fresh `swiftc -typecheck` runs in rotated order after a warm-up, using separately compiled package modules, Swift 6 mode, and the same arm64 macOS 15 target. These measurements include macro expansion and type checking of the consumer, excluding object generation, linking, and runtime discovery.

| Configuration | Median |
|---|---:|
| Host before discovery (`d3e22ae`) | 3.63 s |
| Host before inline-wrapper inference (`c99eafc`, discovery flag off) | 3.69 s |
| Current host, discovery flag off | 6.80 s |
| Current host, discovery flag on | 7.00 s |
| Current `@Spec` with top-level cases | 3.64 s |
| Current `@Spec(.leaves)` | 3.82 s |

With discovery disabled, the host median rose from 3.69 s to 6.80 s. The only library source change between those revisions was the inline-wrapper inference fix in `ExampleBuilder`. It added overloaded `buildExpression` methods so the builder can give `aroundEach` its expected call type before Swift resolves the closure. The benchmark contains zero `aroundEach` calls, but the new expression step applies to ordinary hooks, examples, and nested contexts too. Even the pass-through overloads likely add constraint-solving work across the large body. The host call also has sync and async overloads, whereas the discovery getter fixes the builder to `AsyncCall` at its declaration. That difference may help explain the faster getter timings. The benchmark measured total type-check time, so the cost of individual overload decisions remains unknown. [Builder implementation](../Sources/Rundown/Builder.swift)

A separate interleaved run used the same getter with an explicit `@ExampleBuilder<AsyncCall>` and omitted registration. Its median was 3.66 s versus 3.74 s for the macro-supplied builder and registration. The samples overlapped. This control isolates the additional type-check cost of `@Spec` from the difference between a getter and a call to the host adapter.

### Implementation size

These counts describe the suite-scoped prototype before the Xcode workaround. They use physical source lines, including comments and blanks, and exclude tests and documentation.

| Approach | Registration and lifecycle code |
|---|---|
| Host adapter | 111 lines for the ordinary and main-actor `spec` entry points, plus 93 shared lines for reporting and assertion paths. The host's `@Test` registers the function and the existing traversal owns all group hooks. |
| Top-level discovery | Reuses the reporter, assertion paths, and traversal. The prototype adds about 295 lines across the macro and plugin entry (116), adapter registration, suite scope, and cases (144), and guarded node projection and root hooks (35). It also extracts shared root scope and group hook helpers in the traversal and adds the adapter's macro target dependency. |
| Leaf discovery | Uses the same registration, case IDs, and root suite scope. The projection recurses through groups and replays intermediate hooks per leaf. The measured footprint covers that experiment. A coordinator that preserves intermediate hook lifetimes and scheduling remains unimplemented. |

## Original scratch probe

A macro can be probed without a new package: put the macro in `Sources/RundownMacros`, register it in `RundownPlugin`, and declare it in a `ZZ…` test file with `#externalMacro(module: "RundownMacros", type: …)`. Revert the plugin list afterward. `ExampleNode.children` is `private(set)`, so a probe that edits a tree needs a temporary extension in `ExampleNode.swift`. Swift Testing starts its test generators concurrently, so a probe that creates shared state in them needs a lock. `swift test list` shows what was discovered, and `swift build` compiling a hand-written record proves nothing until the test appears there.

## Possible upstream proposal

The discovery probe emitted `@section` records by hand and called the underscored `Test.__function`, `Test.__type`, and `Test.__store`, whose signatures vary between releases. A public, stable registration function would give spec libraries and table-driven generators a supported route. Allowing a generator to return several `Test` values would also make runtime-defined suites and their children possible. That would change discovery and planning enough to warrant a separate proposal. Check earlier Swift Forums and Swift Evolution discussions before pitching either idea.
