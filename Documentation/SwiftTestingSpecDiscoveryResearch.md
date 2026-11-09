# A `Spec` type shaped like `View`

The prototype represented each spec as a type with one computed property, modeled on SwiftUI's `View`. It explored what Swift Testing could discover from that shape, especially whether Rundown groups could appear as nested suites. These findings inform the [Phase 4 discovery experiment](SwiftTestingIntegration.md#phase-4-discovery-experiment).

The probe used the Swift Testing source in `~/Developer/swift-testing`, a scratch protocol and macro in `RundownMacros`, and hand-written test content records. It ran with Xcode's Swift 6.4 toolchain. After the scratch code was removed, all 124 tests passed.

## Findings

- *The protocol shape compiles.* `protocol Spec { init(); @ExampleBuilder<AsyncCall> var spec: ExampleGroup<AsyncCall> { get } }`. The builder attribute on the requirement is inherited by the witnesses, so `var spec: ExampleGroup<AsyncCall> { describe… it… hooks… for-loops }` type-checks like the closure of `spec { }`, with no `some` and no erasure, because the builder already returns a concrete group. The root is `spec.named(String(describing: Self.self)).node`, and `node.run(with:)` runs it unchanged. A `@MainActor protocol MainActorSpec: MainActorSuite` with `@ExampleBuilder<AsyncMainCall>` compiled too, and its hook and example ran main-actor isolated (checked by hand, not through the macro).
- *Tests can be registered without `@Test` or `@Suite`.* A global or static `@section("__DATA_CONST,__swift5_tests") @used let record: Testing.__TestContentRecord = (0x74657374, 0, { out, type, hint, reserved in Test.__store(generator, into: out, asTypeAt: type) }, 0, 0)` was discovered and ran. `@section` and `@used` need no feature flag in 6.4. The generator builds its `Test` with the public but underscored `Test.__function(named:in:…)` and `Test.__type(_:traits:sourceBounds:)`; the record format is documented in swift-testing's `Documentation/ABI/TestContent.md`. Those helpers are marked "used to implement the macros, do not call directly", and the installed signatures differ from the source tree: 6.4 takes `sourceBounds: __SourceBounds` (built with `__SourceBounds(__uncheckedLowerBound:upperBound:)`), and older `sourceLocation:` forms exist only as internal `@abi` shims. The ABI document also says to define your own copy of the record tuple type, not to use `__TestContentRecord`, which the scratch macro did.
- *A macro cannot hand the work to `@Test`.* A member macro that emits `@Test(arguments:) func …` fails: the nested `@Test` expansion does not see the enclosing type, so it emits instance-member record storage and the compiler rejects it ("properties with attribute @section must be static"), with or without `static` on the function. The macro has to emit the `@section` records itself, as Swift Testing's own macros do. It uses `Testing` names, so it belongs in the adapter module, not the core.
- *One record is one `Test`.* `Test.all` takes a generator from each record and each generator returns a single `Test`. The plan then builds the suite tree from `Test.ID`, and a suite's identity is the reflected name of its containing type, split on `.`. A test function's name can be any string, but a suite has to be a real type. So a `describe` or `context` that exists only after the spec is evaluated cannot become a suite.
- *Types created at run time do not get around that.* Classes made with `objc_allocateClassPair` and named like `RundownTests.ZZSpec.logged in` reflect with exactly those components, but they cannot be passed to `__type` and `__function`, which are generic over `S.Type`: implicit existential opening bound `S` to `NSObject`, and `_openExistential` crashed SILGen. It would be Darwin-only anyway. A pool of pre-declared marker types would work but is capped and ugly. Not recommended.
- *Examples can be dynamic, as test cases.* `__function(…arguments:…)` evaluates its closure when the plan is built, so the leaves of `Self().spec.node` become cases, including those from `for` loops. Each case is labelled by a `CustomTestStringConvertible` argument, here the full path ("FeatureSpec, logged in, throws"), and an issue is attributed to its case. A thrown error recorded by the reporter carried the path as a comment as well; a failed `#expect` did not (see below). `swift test list` shows only `Type/examples`, and `--filter` matches test IDs, not cases (`--filter "loop example"` ran nothing).
- *Nested `@Spec` types are nested suites.* With the macro on both, `OuterSpec { @Spec struct InnerSpec }` listed as `OuterSpec/examples` and `OuterSpec/InnerSpec/examples`, and ran as nested suites. This is the only nesting available, and it follows the source declaration, not the `describe` structure.
- *One case per leaf repeats group hooks.* Each case ran its own copy of every enclosing hook: with 7 leaves, the root `beforeAll` ran 7 times, concurrently, and the `logged in` group's `beforeAll` and `afterAll` ran 3 times each. This is the Option B problem, shown.
- *One case per top-level child, with the root's `beforeAll` and `afterAll` in a suite trait, matches the traversal.* A `SuiteTrait & TestScoping` on the suite's `Test.__type` is entered once around everything in it, and nests (outer suite, inner suite, tests). Running the root's `beforeAll` and `afterAll` there, and giving each case the root minus those hooks and with one child, gave: root `beforeAll` once before, root `afterAll` once after, `logged in`'s hooks once around its group, and the root's `beforeEach` once per top-level child, as `traverse` does. A test-level trait's scope is entered once per case, not once around the test.
- *Cases run in parallel.* The cases of one test ran concurrently, so sibling elements overlap where the traversal runs them one after another.

## Further probes

- Try the protocol-conformance discovery listed in the 6.4 interface (`__TestContentRecordContainer` and `@_alwaysEmitConformanceMetadata`). It needs an accessor that knows `Self`, which a `@convention(c)` accessor cannot capture.
- Check the section names Swift Testing's macros emit for ELF, COFF, and Wasm.
- Check how Xcode displays cases and nested suites.
- Run the 60-context compile benchmark with the macro.
- Check a failing or skipping root `beforeAll`. The scratch trait left the cases runnable.

## Implications

- Discovery by type evaluates the `spec` property normally, so loops, conditionals, and helper-built subtrees work. Each type needs an attribute such as `@Spec` to emit its registration record. [Discovery bridge design](SwiftTestingIntegration.md#option-c-discovery-bridge)
- Leaves as cases (Option B) needs the lifecycle coordinator. The workable granularity is one case per top-level child, with the root's `beforeAll` and `afterAll` in a suite trait and everything below a top-level child running whole through the existing traversal. Groups keep their exact semantics, each-hooks included, at the price of case labels that name the top-level child, not the leaf.
- Nested suites are real only for nested types. A `describe` stays a path in the case label. If real suites per group are wanted, each would need to be a declared type, and the outer each-hooks would then wrap a suite, which is the unsolved part of Option B.
- Failed `#expect`s inside a nested group are attributed to the top-level child's case. A Rundown path comment can identify the leaf within that case.
- `Self()` is made for the plan, for the suite scope and for each case, so state kept in stored properties is not shared between a `beforeAll` and the examples.
- `.serialized` on the suite would give the traversal's sequential order back, and `.concurrent` could map to leaving it off. Not tried.
- The probe depends on underscored APIs whose signatures already differed between the source tree and the toolchain. That approach would need checks against each supported toolchain. See the [possible upstream proposal](#possible-upstream-proposal).
- `Spec` types would be opt-in alongside the existing `@Test` and `spec` entry points. If the experiment goes ahead, update `SwiftTestingIntegration.md` with what it established about Option C.

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

On `codex/swift-testing-discovery`, the package-scoped `@Spec` macro and `Spec` protocol are available in `RundownSwiftTesting` on macOS with Swift 6.4 or later when `RUNDOWN_DISCOVERY_PROTOTYPE` is defined. The prototype was verified with Xcode 27.2 (27B52), Swift 6.4.2, and Swift Testing 2403 on Apple Silicon. [Adapter implementation](../Sources/RundownSwiftTesting/SpecRegistration.swift) · [Registered fixture](../Tests/RundownSwiftTestingTests/DiscoveryRegistrationSpec.swift)

The macro emits one Mach-O `__DATA_CONST,__swift5_tests` record with kind `0x74657374`. It uses a local copy of the record layout with a nonoptional C accessor because Swift 6.4.2 rejected the optional accessor literal in `@section`. The layouts matched at a 32-byte stride and 8-byte alignment on the tested toolchain. The accessor passes the runtime type pointer to `Test.__store`, and its generator uses `Test.__function` with `__SourceBounds` derived from the spec declaration. Swift Testing synthesizes the containing suite from the test ID. [Swift Testing test content ABI](https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/TestContent.md)

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

The argument collection builds the tree during planning and carries a projected tree into each case. A top-level case keeps its subtree intact, and a leaf case keeps only its ancestor chain and leaf. Each projection retains its ancestor hooks, so running several cases can repeat ancestor setup and teardown. The plan lifetime and hook tasks will compare that behavior with the host baseline.

```sh
SWT_EXPERIMENTAL_EVENT_STREAM_FIELDS_ENABLED=1 \
  swift test -Xswiftc -DRUNDOWN_DISCOVERY_PROTOTYPE --disable-xctest \
  --filter DiscoveryRegistration --event-stream-output-path /tmp/rundown-discovery-units.jsonl
swift test -Xswiftc -DRUNDOWN_DISCOVERY_PROTOTYPE list --skip-build --disable-xctest
```

For the Xcode comparison, build `Rundown-Package` for testing with `OTHER_SWIFT_FLAGS='$(inherited) -DRUNDOWN_DISCOVERY_PROTOTYPE'`. Use the resulting `.xctestrun` with `xcodebuild test-without-building -enumerate-tests`, then run the discovery suites into a result bundle. `xcresulttool get test-results tests` reports each argument's `nodeIdentifierURL`, which can be passed to `xcodebuild test-without-building -only-testing:<url>`.

## Original scratch probe

A macro can be probed without a new package: put the macro in `Sources/RundownMacros`, register it in `RundownPlugin`, and declare it in a `ZZ…` test file with `#externalMacro(module: "RundownMacros", type: …)`. Revert the plugin list afterward. `ExampleNode.children` is `private(set)`, so a probe that edits a tree needs a temporary extension in `ExampleNode.swift`. Swift Testing starts its test generators concurrently, so a probe that creates shared state in them needs a lock. `swift test list` shows what was discovered, and `swift build` compiling a hand-written record proves nothing until the test appears there.

## Possible upstream proposal

The discovery probe emitted `@section` records by hand and called the underscored `Test.__function`, `Test.__type`, and `Test.__store`, whose signatures vary between releases. A public, stable registration function would give spec libraries and table-driven generators a supported route. Allowing a generator to return several `Test` values would also make runtime-defined suites and their children possible. That would change discovery and planning enough to warrant a separate proposal. Check earlier Swift Forums and Swift Evolution discussions before pitching either idea.
