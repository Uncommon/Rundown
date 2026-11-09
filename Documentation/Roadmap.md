# Rundown Roadmap

Open work and design notes from the 2026-10-12 review of the library. Implementation records live in [Completed Phases](CompletedPhases.md).

## Phase 4 — Swift Testing discovery experiment

Prototype opt-in discovery on a branch and compare it with an equivalent `@Test` that calls `spec`. Use the first `Spec` registration probe as a starting point. Keep the experiment in the Swift Testing adapter so host-test, plain-runner, and XCTest users can keep their current entry points. [Discovery design](SwiftTestingIntegration.md#option-c-discovery-bridge) · [View-shaped `Spec` research notes](SwiftTestingSpecDiscoveryResearch.md)

- [x] **Set up a comparison fixture.** Two reusable builders exercise the host adapter and main-actor isolation. The [host-test baseline](SwiftTestingSpecDiscoveryResearch.md#host-test-baseline) records SwiftPM discovery, filtering, issue output, and hook order.
- [x] **Register one `Spec` type.** The macOS prototype emits an opt-in test record and runs the spec through `ExampleNode`. SwiftPM listed and ran `examples()` alongside the conventional host baseline. [Registration results and reproduction commands](SwiftTestingSpecDiscoveryResearch.md#prototype-registration)
- [x] **Compare discovery units and identities.** SwiftPM filters generated functions. Xcode reran individual cases in top-level suites, while the nested suite could be filtered at the function level. Both variants produced stable IDs across repeated runs. [Discovery comparison](SwiftTestingSpecDiscoveryResearch.md#discovery-units-and-identities)
- [x] **Verify plan and fixture lifetime.** Listing leaves the tree unevaluated, and each selected spec builds once during planning. Cases can share fixture state within a runner invocation. A second invocation gets fresh state, while case repetitions within a run reuse it. [Lifetime probe](SwiftTestingSpecDiscoveryResearch.md#plan-and-fixture-lifetime)
- [x] **Validate hook lifetimes.** The generated suite runs the root hooks once around its selected cases. The top-level cases matched the host trace, including the parent's each-hooks around a nested group. Xcode subset selection, an empty spec, and setup failure and cancellation were checked. [Hook lifetime results](SwiftTestingSpecDiscoveryResearch.md#hook-lifetimes)
- [x] **Apply selection at the discovery boundary.** Both discovery variants match the host adapter's resolved selection. Excluded branches stay out of the case list, excluded hooks stay out of execution, and retained case IDs match with focus enabled and disabled. [Selection results](SwiftTestingSpecDiscoveryResearch.md#selection-at-the-discovery-boundary)
- [x] **Verify scheduling and isolation.** Native `.serialized` restored declaration order for discovered cases while Rundown still honored `.concurrent` inside a top-level case. Host tests verified main-actor isolation and rejection of concurrent async main-actor groups. Discovered specs currently require `AsyncCall`. [Scheduling and isolation results](SwiftTestingSpecDiscoveryResearch.md#scheduling-and-isolation)
- [x] **Compare reporting and reruns.** Both runners recorded one issue per failure with a full Rundown path. Assertions kept their source lines, and thrown errors pointed to the reporter. SwiftPM reran the generated function, while Xcode also reran a failed top-level group case or an individual leaf case. [Reporting and rerun results](SwiftTestingSpecDiscoveryResearch.md#reporting-and-reruns)
- [x] **Pass computed traits through `it`.** Sync, async, and main-actor builders accept computed trait arrays, including empty arrays. The selection fixture now uses `it()` and produced the same selected examples and case IDs with focus enabled and disabled.
- [x] **Write excluded `aroundEach` hooks inline.** The builder infers the wrapper's call type even when the closure ignores its callback. The selection and composition fixtures verify that the inline hooks are skipped. The 60-context async type-check median rose from 1.95 s to 3.50 s on Swift 6.4.2.
- [x] **Measure compatibility and cost.** The host, plain-runner, and XCTest suites passed with discovery enabled and disabled. Mach-O registration was verified at runtime on arm64 and at compile time on x86_64. The host type-check slowdown was already present with discovery disabled after the inline-wrapper builder change. [Compatibility, benchmark, and implementation size](SwiftTestingSpecDiscoveryResearch.md#compatibility-and-cost)
- [ ] **Write the Phase 5 handoff.** Compare filtering, reporting, and implementation complexity with the host adapter. Separate verified improvements from remaining limitations so Phase 5 can decide whether to pursue leaf-native discovery, keep a coarser discovery model, or stay with host tests.

## Error and skip rules

The table describes failures and XCTest's local skips. `ReporterTests`, `MessageXCTests` and `MultiRunTests` cover these rules.

A **failure** is any error other than a skip. XCTest treats `XCTSkip` as a local skip. The plain runners treat it as an ordinary error.

| Thrown in | Failure | Skip (XCTest only) |
|---|---|---|
| `beforeAll` | Later `beforeAll` hooks and all the elements are skipped. `afterAll` hooks still run. | The rest of the group is skipped, including later `beforeAll` hooks and every `afterAll` hook. The group returns normally. |
| `beforeEach` | Later `beforeEach` hooks and the element are skipped. `afterEach` hooks still run. The group carries on with its next element. | The element is skipped, including later `beforeEach` hooks and every `afterEach` hook. The group carries on with its next element. |
| An example | `afterEach` hooks run. The group carries on. | Logged and swallowed. `afterEach` hooks run. The group carries on. |
| A nested group | Handled inside that group, by these same rules. | Nothing comes out: skips end at their own node. |
| `afterEach` | Every `afterEach` hook runs. | Logged and swallowed. The remaining `afterEach` hooks run. |
| `afterAll` | Every `afterAll` hook runs. | Logged and swallowed. The remaining `afterAll` hooks run. |
| `aroundEach` | The element may not run (if it fails before calling its callback). The group carries on. | Logged and swallowed. Before the callback, the element doesn't run and nothing needs undoing. After it, the element and its teardown have already run. |

A group whose elements are all excluded runs no hooks at all.

**What happens to a failure** depends on the runner, not on where it was thrown:

- **Plain runners:** propagate. The group keeps the *first* error, carries on, and rethrows it after `afterAll`. A parent group sees a nested group's error as that element's error. In a `.concurrent` group, the first error across elements wins.
- **XCTest runner:** record. Each failure becomes an `XCTIssue` of type `.uncaughtException` with the full path of the node that threw, and the run continues. Nothing is rethrown, except skips as above. The recording has to happen while the node that threw is still the current one.

### What this means for the design

- The traversal's flow is the same for both runners except for skips. The reporter decides whether to `record` or `propagate` a failure. The table's "failure" column describes what the traversal does.
- A local setup skip abandons the element or group. A local skip in an example or teardown hook ends that node. The reporter can also ask the traversal to stop the run, which still invokes teardown for scopes that were entered.

### Behavior changes

Skips are local to their node. This changed the XCTest runner, which used to let a skip in an `afterEach`, `afterAll` or `aroundEach` hook escape and abort the whole run. That skipped the remaining elements and the `afterAll` hooks of every group above, so their setup was never undone, and XCTest marked the whole test as skipped. `ReporterTests` and `MessageXCTests` cover the new behavior, and the README and the `runActivity()` doc comment describe it.

Not changed:

- The plain runners don't handle skips. An `XCTSkip` is just an error there: it doesn't stop the rest of the run, and if it is the first error, it is rethrown at the end, which makes XCTest mark the whole test skipped after everything else has run.

## Constraints for the node model

Each-hooks (`beforeEach`, `afterEach`, `aroundEach`) apply to the elements of the group they are declared in, and a nested `context` is one element. They run once around the whole context, not around each example inside it. This is intended, and it has consequences for the Swift Testing design:

- The node model must keep each-hooks attached to their group and applied around its child nodes, groups included. It must not flatten them onto leaves.
- That makes leaf-native execution (the doc's Option B) harder than it first looks. If each leaf became its own Swift Testing test, an outer `beforeEach` or `afterEach` would run once per leaf instead of once per nested group, and an outer `aroundEach` could not wrap several tests at all, because its callback is a single scope. Outer each-hooks would need the same lifecycle coordinator as `beforeAll`/`afterAll`, and `aroundEach` has no workable form. `SwiftTestingIntegration.md` ("Hook Replay Order" and the Option B discussion) now says this. It supports the doc's recommendation to start with the host-test adapter (Option A) and treat leaf-native discovery as an experiment.

## Cleanup

Small items, none urgent.

- [ ] Remove or repurpose `RundownClient`. It is template leftover (`let a = 17`) but is still exported as a product.
- [ ] Add CI. A GitHub Actions workflow on a macOS runner with a Swift 6 Xcode, running `swift build` and `swift test`, with `.build` cached. Open choices: which Xcode to pin, whether to commit `Package.resolved` (it is in `.gitignore`) or key the cache on `Package.swift`, and whether to add `xcodebuild` platform builds and a ThreadSanitizer job. The compile-failure tests shell out to `swift build` in fixture packages with their own `.build`, so those need caching too.
- [ ] Cover the `.concurrent` trait and `aroundEach` in the README.
- [ ] Make an excluded group exclude everything inside it, regardless of focus. Today a focused node inside an excluded subtree makes the groups around it count as focused: with `xContext { fIt }` inside a group, the group's siblings are left out, though nothing in the group will run. `ExampleNode.isDeepFocused` and the public `TestExample.isDeepFocused` both do this, and `testFocusInsideExcludedSubtreeStillCountsAsFocus` pins it. The change: a node counts as focused only if it isn't excluded; make `isSelected` mean that the node will run, by marking the whole subtree of an excluded node as not selected; and either make the public `isDeepFocused` agree or remove it, since nothing in the library uses it. This is a behavior change for the plain runners, so it should be its own commit. Also log a warning when an excluded node has a focused node at or below it, since that is probably not what the author meant. Detection is a small walk at the start of `ExampleNode.run(with:)`, kept as a pure function so it can be tested.
- [ ] The XCTest runner (`runActivity()`) doesn't implement `.concurrent`, so concurrent groups run serially there.

## Ideas, not planned

- **Opt-in module for main-actor free functions.** Main-actor groups can't be built in free functions (the compiler says so, with a pointer to `MainActorSuite`), because the main-actor DSL functions are members of `MainActorSuite`. Global overloads would fix that but double compile time for every spec. A separate module (say `RundownMainActor`) holding them would let only the files that import it pay. It would be a new product.
- **Nest a sync group in an async one instead of converting it.** `ExampleGroup.init(fromSync:)` drops `aroundEach` hooks, on purpose, and it is documented. Running a sync group as the single element of an async group would avoid conversion entirely, if the wrapper's entry in `ExampleRunner.path` can be made clean.

## Notes

- **SwiftPM diagnostics (Swift 6.4).** `swift build` prints compiler diagnostics to stderr, in color even when piped. Any test that shells out to it must read both streams and strip `ESC[…m`.
- **Probing without network.** A fresh scratch package can't resolve swift-syntax in the sandbox. To check behavior, add a temporary `ZZProbeTmp.swift` to `Tests/RundownTests` and run `swift test --filter ZZProbeTmp`. To check the public API surface, add one to `Sources/RundownClient` and run `swift build --target RundownClient`. Delete it afterward. Probes that compile many cases at once can pass for the wrong reason: check that the build completed, or that every error was attributed to a case.
- **Checking platforms without Xcode projects.** `xcrun swiftc -typecheck -swift-version 6 -package-name rundown -module-name Rundown` over `Sources/Rundown`, with `-sdk`, `-target`, `-F <platform>/Developer/Library/Frameworks`, `-I <platform>/Developer/usr/lib` and `-load-plugin-executable .build/arm64-apple-macosx/debug/RundownMacros-tool#RundownMacros`. Mac Catalyst (`-target arm64-apple-ios17.0-macabi`) also needs the SDK's `iOSSupport` framework directory, passed to clang as well (`-Xcc -iframework -Xcc <dir>`) so XCTest can find UIKit. Validate any such harness against known-bad code first. Earlier core-only probes type-checked on iOS 14, tvOS 14, watchOS 7, and Mac Catalyst 14. The current package minimums are in `Package.swift`, with macOS at 15 because the tests use `Atomic`.
- **Adding DSL overloads costs compile time.** Every extra overload of `it`, `describe`, `context` or a hook multiplies what the type checker explores for every statement of every spec. Measure a large synthetic spec (60 contexts, about 540 statements; about 5.3 s today) before and after. Global main-actor overloads took it to 11.9 s. The `buildPartialBlock` overloads that only produce diagnostics are free; overloads of the DSL functions are not.
- **Overload selection for closures.** An unannotated closure prefers the non-main-actor overload, and a `@MainActor` async closure can still convert to a non-main-actor async function type, so a main-actor overload can't reliably win by being added alongside. A disfavored hand-written overload made it worse.
- **Sanitizers.** `swift test --sanitize=thread --scratch-path <dir>` works for the concurrent tests. Plant a deliberate race in a throwaway test to prove the sanitizer is live before trusting a clean result.
- **How the traversal is built (`NodeTraversal.swift`).** Nodes carry their closures, each in the call type it was written with (`sync`, `async`, `syncMain`, `asyncMain`), because a tree without closures can't be traversed on its own and the XCTest runner has to stay sync on the main thread. Isolation is part of the closure types, so the traversal is written once as async and the sync version is generated from it with `@DeAsyncRD`. The async version awaits main-actor bodies, which hops to the main actor and back. The sync version calls them with `MainActor.assumeIsolated`, after checking at the entry point. Only three things differ per flavor, in small hand-written helpers: how a body and an `aroundEach` hook are called, how children run (a task group, or `concurrentPerform` with the runner and path bound again), and the entry check. A sync `aroundEach` can't wrap an async callback, so the async traversal rejects it (`UnexpectedAsyncError`), the same limit as `ExampleGroup.init(fromSync:)`. An async group can hold sync elements, so building a node accepts any call type for a child. The 60-context compile benchmark is unchanged by all of this (about 5.0 s).
