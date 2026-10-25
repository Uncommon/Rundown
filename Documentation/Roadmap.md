# Rundown Roadmap

Open work from the 2026-10-12 review of the library. Delete items as they land.

## Next: Phase 2, the host-test Swift Testing adapter

Phase 1 (the node model, the reporter and the single traversal) is done. Phase 2 is Option A of `SwiftTestingIntegration.md`: a user writes a normal `@Test` that calls `spec`, Rundown runs the whole spec inside that one test, and an adapter makes what happens inside it feel native to Swift Testing. Individual examples are still not separately discoverable or filterable, which is what Option B and C would add.

What the installed Swift Testing (Xcode's Swift 6.4 toolchain) offers, from reading its `Testing.swiftinterface`, none of it tried yet: `Issue.record(_:_:sourceLocation:)`, including a form that takes an `Error`; `Issue.Severity` with a `.warning`; `Test.current` and `Test.Case.current`; `IssueHandlingTrait`, which can transform issues; and `Test.cancel(_:)`, which ends the running test. The last one matters, because a Swift Testing cancellation ends the whole test, and Rundown's skips are local to a node.

What a throwaway test under Swift Testing found (reading its source first, then running the node traversal inside `@Test` functions with Xcode's Swift 6.4 toolchain; the test is deleted):

- *Issues with a path: works, with a trait.* A custom trait that wraps `IssueHandlingTrait.compactMapIssues` and appends `ExampleRunner.current?.description` to `issue.comments` put the full path on a failed `#expect` inside an example ("Root, ctx, fails an expectation"). A custom trait can delegate to `IssueHandlingTrait` through its public `provideScope(for:testCase:performing:)`. The cost is that the user must apply the trait to the `@Test` or `@Suite` (say `.rundown`), because `Configuration.withCurrent` is internal. Errors that the traversal catches don't need the trait: a reporter calling `Issue.record(error, Comment(path))` put the path on them too. Name clash: Rundown has its own `Trait` protocol, so the adapter must write `Testing.Trait`.
- *`#require` inside an example: needs a rule.* It records its own issue and throws `ExpectationFailedError` (public), which came out of `spec` and was ignored by the runner. Exactly one issue was recorded. A reporter that records errors must skip `ExpectationFailedError`, or it will report the failure twice. With `PlainReporter` nothing needs doing.
- *Cancelling: works, but only a whole test.* `try Test.cancel("...")` in an example threw a `SkipInfo`, and the traversal carried on: the next example ran with `Task.isCancelled == true`, a cancellation-aware `await` in it (`Task.sleep`) threw `CancellationError`, and `afterAll` ran. The test was reported as *cancelled* with the comment, not as failed. Swift Testing's runner treats both `SkipInfo` and a `CancellationError` thrown while the task is cancelled as a skip, so the reporter should too.
- *`SkipInfo` is not available.* It is `@_spi(ForToolsIntegrationOnly)` in the source, but it is not in the Xcode toolchain's `Testing` module at all: `@_spi(ForToolsIntegrationOnly) import Testing` still gives "cannot find type 'SkipInfo'". The probe recognized it by type name (`"\(type(of: error))" == "SkipInfo"`), which is fragile. There is no public way to ask whether an error is a cancellation, which is why the first upstream proposal in "Ideas" matters.
- *`.concurrent` in the sync traversal does not work under Swift Testing.* In `DispatchQueue.concurrentPerform`, the iteration that runs on the calling thread sees `Test.current`, and the others see `nil`. Rundown's own runner and path are re-bound for those threads, but Swift Testing's context cannot be. Issues from the worker threads were recorded *twice* each (the event goes to every registered handler), were not covered by `withKnownIssue` or an issue-handling trait, and failed the test (11 issues from 6 failing examples, 1 of them known). The async traversal is fine: task-group children inherit the context, and `Test.current` was set in all of them.
- *Observing issues in tests.* The trait approach doubles as the test technique: a trait whose handler records the transformed issue and returns `nil` lets a `@Test` examine issues without failing. `withKnownIssue(matching:)` sees an issue *before* any trait transforms it, so it can't be used to check the path comment.

What this decides for the tasks:

- The Swift Testing reporter's `allowsConcurrency` must be false for the sync traversal. The reporter protocol has no way to say that for one flavor yet. Either make it a property of the flavor (a parameter on `allowsConcurrency`), or have the adapter's sync `spec` always run `.concurrent` groups serially and document it.
- A skip under Swift Testing means "stop": finish teardown, run no more examples. Running on in a cancelled task is wrong, and the test is already marked cancelled. The traversal needs a way for a reporter to say so, such as a `Disposition` or a flag that the traversal checks before each element. Settle the shape in task 7.
- The adapter classifies `ExpectationFailedError` as already reported, and `SkipInfo` or `CancellationError` while cancelled as a skip.

Tasks, in order. Each step should end green and could be its own commit.

- [ ] **2. Decide visibility, and make it so.** The adapter is a separate target in this package, so Swift's `package` access level probably works (a public API would not be needed). Check that it does, including for the macro-generated sync functions. If not, use SPI. The things the adapter needs to see: `Reporter`, `ErrorKind`, `Disposition`, `ExampleNode`, `.node`, and `run(with:)`. The existing tests must pass unchanged and the core must still build without importing `Testing`.
- [ ] **3. Add the target.** `RundownTesting` (the name is open), importing `Rundown` and `Testing`, as an optional product. Check the platform minimums against what `Testing` requires, as in the platform note below, and put `@available` where they differ from the package's. Nothing in the `Rundown` target may depend on `Testing`.
- [ ] **4. `SwiftTestingReporter`.** Conforms to `Reporter`: `report` records through `Issue.record` with the full path as the comment, `classify` follows the findings above (`ExpectationFailedError` is already reported; `SkipInfo` or `CancellationError` while cancelled is a skip), `scope` is either empty or tracks `Test.Case.current`, and it implements the async scope, which XCTest's reporter does not. `allowsConcurrency` is true. It must be `Sendable`.
- [ ] **5. `spec` overloads.** Following the design doc, put them on a suite protocol in the adapter module, as `MainActorSuite` does, and keep a target that imports both adapters from becoming ambiguous. This is the compile-time risk of the phase: extra overloads can multiply type checking for every statement of a spec. Measure the 60-context benchmark (about 5.0 s) before and after, and back out or restructure if it moves.
- [ ] **6. Paths for assertion failures inside examples.** The `.rundown` trait described above, which wraps `IssueHandlingTrait`.
- [ ] **7. Skips.** A skip means stop: add the traversal support described above, so that a reporter can end the run of examples while teardown still happens. The traversal's existing rules for the XCTest reporter stay as they are.
- [ ] **8. Main-actor specs.** A `@MainActor` suite with sync and async specs, checked for the right isolation inside hooks and examples.
- [ ] **9. Tests for the adapter.** The design doc's list: a failing example includes the full path; a skip in `beforeEach` or `beforeAll` is reported once with the right path; main-actor suites run on the right actor; no existing XCTest behavior changes. Testing Swift Testing from inside Swift Testing needs a way to observe issues without failing the run: probably `withKnownIssue` with a matcher, or an issue-handling trait on the test under test. The trait technique in the findings above does this.
- [ ] **10. Docs.** A README section for Swift Testing: how to write the `@Test`, what is and isn't supported (no per-example discovery or filtering). Update `SwiftTestingIntegration.md` and this roadmap.

Dependencies: 2 and 3 first, in either order. 4 needs both. 5 needs 3. 6 and 7 need 4. 8 and 9 come last.

Done when, from the design doc's acceptance criteria: the existing XCTest tests pass without changes, `Rundown.TestCase` is still supported, the core builds without `Testing`, a failure under Swift Testing includes the full path, main-actor behavior is explicit, no built-in trait loses its meaning under XCTest, and the compile benchmark is unchanged.

Not in this phase: bridging Rundown traits to Swift Testing metadata (design doc Phase 3), and the discovery experiment (Phases 4 and 5).

## Error and skip rules

What the traversal (`NodeTraversal.swift`) does, which is what the plain and XCTest runners did, except for skips in teardown and `aroundEach` hooks (see "Behavior changes"). Covered by `ReporterTests`, `MessageXCTests` and `MultiRunTests`.

A **failure** is any error other than a skip. Only the XCTest runner has **skips**, which are `XCTSkip`. The plain runners treat it as an ordinary error.

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

- The traversal's flow is the same for both runners except for skips. Failures differ only in disposition, so `record` or `propagate` belongs to the reporter, and the table's "failure" column to the traversal.
- Skips need a rule per phase, in the traversal: a *setup skip* abandons the element or group without teardown, and a skip anywhere else (an example, a teardown hook, an `aroundEach` hook) is swallowed and ends only the node that threw it. The reporter only classifies an error as failure or skip, and logs it. It does not decide what a skip does.

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

- **Proposals to Swift Testing that would help Rundown.** From reading its source and from the experiment in Phase 2. Ranked by how useful they are to Rundown against how likely they are to be accepted. I could not look at the Swift forums or evolution repository from here, so search them for earlier pitches before writing anything.
  1. *A public way to recognize a cancellation or skip error.* Today only `SkipInfo` says that an error thrown by `Test.cancel` is control flow and not a failure, and it is SPI that does not even exist in the Xcode toolchain's `Testing` module, so the experiment had to compare the error's type name. `ExpectationFailedError`, the other control-flow error, is already public. Anything that catches errors thrown by user closures (a retry helper, a step runner, a spec library like this one) needs to tell them apart. A small shape: promote `SkipInfo`, or add something like `Test.isCancellation(_ error:)`. Small, matches existing API, and easy to justify.
  2. *Scoped issue transformation without a trait.* `IssueHandlingTrait` can already rewrite issues, but only for a whole test, and only as a trait. A function in the style of `withKnownIssue`, say `withIssueHandling(_ transform:, perform:)`, sync and async, built on the same mechanism, would let helper libraries add context to issues recorded in a region of code. For Rundown it would remove the need for users to apply a trait. A reasonable pitch, but the maintainers may prefer to keep it a trait.
  3. *Carrying the test context across threads.* `Test.current`, `Test.Case.current` and the configuration are task-locals, `nil` on threads like `concurrentPerform` workers. A value such as `Test.Context` that can be captured and then restored with `perform { }` on another thread would make `#expect`, issue handling and `Test.cancel` work from there. In the experiment, issues from `concurrentPerform` workers were recorded twice, escaped `withKnownIssue`, and failed the test. Any code that moves work onto GCD, dispatch queues or `Thread` needs this, not only Rundown. Probably needs some design discussion about what is captured.
  4. *Steps.* `XCTContext.runActivity` has no Swift Testing counterpart: a named, nested scope inside a test case that shows up in the output and the results, with issues recorded inside it attributed to it, and perhaps a skip that ends only the step. Rundown's whole `scope` concept maps onto it, and so does every XCTest user's use of activities, which makes it the most useful of the four. It is also by far the largest: new events, changes to the JSON ABI and to tools like Xcode and SwiftPM, and a full evolution proposal. Worth raising on the forums as a pitch before investing.


## Notes

- **SwiftPM diagnostics (Swift 6.4).** `swift build` prints compiler diagnostics to stderr, in color even when piped. Any test that shells out to it must read both streams and strip `ESC[…m`.
- **Probing without network.** A fresh scratch package can't resolve swift-syntax in the sandbox. To check behavior, add a temporary `ZZProbeTmp.swift` to `Tests/RundownTests` and run `swift test --filter ZZProbeTmp`. To check the public API surface, add one to `Sources/RundownClient` and run `swift build --target RundownClient`. Delete it afterward. Probes that compile many cases at once can pass for the wrong reason: check that the build completed, or that every error was attributed to a case.
- **Checking platforms without Xcode projects.** `xcrun swiftc -typecheck -swift-version 6 -module-name Rundown` over `Sources/Rundown`, with `-sdk`, `-target`, `-F <platform>/Developer/Library/Frameworks`, `-I <platform>/Developer/usr/lib` and `-load-plugin-executable .build/arm64-apple-macosx/debug/RundownMacros-tool#RundownMacros`. Mac Catalyst (`-target arm64-apple-ios16.0-macabi`) also needs the SDK's `iOSSupport` framework directory, passed to clang as well (`-Xcc -iframework -Xcc <dir>`); `-F <dir>` alone fails to find UIKit for XCTest. Validate any such harness against known-bad code first. The lowest versions that typecheck are iOS 14, tvOS 14, watchOS 7 and Catalyst 14; the package declares 16, 16, 9 and 16, with macOS at 15 because the tests use `Atomic`.
- **Adding DSL overloads costs compile time.** Every extra overload of `it`, `describe`, `context` or a hook multiplies what the type checker explores for every statement of every spec. Measure a large synthetic spec (60 contexts, about 540 statements; about 5.3 s today) before and after. Global main-actor overloads took it to 11.9 s. The `buildPartialBlock` overloads that only produce diagnostics are free; overloads of the DSL functions are not.
- **Overload selection for closures.** An unannotated closure prefers the non-main-actor overload, and a `@MainActor` async closure can still convert to a non-main-actor async function type, so a main-actor overload can't reliably win by being added alongside. A disfavored hand-written overload made it worse.
- **Sanitizers.** `swift test --sanitize=thread --scratch-path <dir>` works for the concurrent tests. Plant a deliberate race in a throwaway test to prove the sanitizer is live before trusting a clean result.
- **Swift Testing design doc (`SwiftTestingIntegration.md`).** Its recommended path is to keep the DSL shared and the core free of `Testing`, add a plan model and reporter abstraction (done), then a host-test Swift Testing adapter. Leaf-native discovery is treated as an experiment.
- **How the traversal is built (`NodeTraversal.swift`).** Nodes carry their closures, each in the call type it was written with (`sync`, `async`, `syncMain`, `asyncMain`), because a tree without closures can't be traversed on its own and the XCTest runner has to stay sync on the main thread. Isolation is part of the closure types, so the traversal is written once as async and the sync version is generated from it with `@DeAsyncRD`. The async version awaits main-actor bodies, which hops to the main actor and back. The sync version calls them with `MainActor.assumeIsolated`, after checking at the entry point. Only three things differ per flavor, in small hand-written helpers: how a body and an `aroundEach` hook are called, how children run (a task group, or `concurrentPerform` with the runner and path bound again), and the entry check. A sync `aroundEach` can't wrap an async callback, so the async traversal rejects it (`UnexpectedAsyncError`), the same limit as `ExampleGroup.init(fromSync:)`. An async group can hold sync elements, so building a node accepts any call type for a child. The 60-context compile benchmark is unchanged by all of this (about 5.0 s).
