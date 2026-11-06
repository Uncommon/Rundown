# Scoped issue handling in Swift Testing

Proposal notes prepared on November 6, 2026. The lead option is a public synchronous `IssueHandlingTrait.withScope` method. This is a starting point for a Swift Testing pitch, with the API spelling and scope semantics still open.

## Motivation

Rundown executes nested examples and hooks inside one Swift Testing `@Test`. When a closure throws, `SwiftTestingReporter` can record an issue with the full Rundown path. Native `#expect` and `#require` failures are recorded by Swift Testing at the assertion site, while that path is still available through `ExampleRunner.current`. `#expect` does not throw, and `#require` throws after recording its issue. Catching the error therefore cannot solve this for both macros, and recording `ExpectationFailedError` again would duplicate the issue. [Reporter](../Sources/RundownSwiftTesting/SwiftTestingReporter.swift) · [Suite entry points](../Sources/RundownSwiftTesting/SwiftTestingSuite.swift)

The desired call site is an ordinary synchronous test. A failure in this example should retain the original expectation, source location, and comment and add `Checkout, signed in, shows the total` to that same issue. The same capability would help retry, step, and fixture helpers attach context available only while a closure is running.

```swift
import RundownSwiftTesting
import Testing

struct CheckoutTests: SwiftTestingSuite {
  @Test func showsCheckout() throws {
    try spec("Checkout") {
      context("signed in") {
        it("shows the total") {
          let actualTotal = 41
          #expect(actualTotal == 42, "Includes tax")
        }
      }
    }
  }
}
```

## Precedent and current API

- David Catmull's ST-0010 exposed `ConditionTrait.evaluate()`. Evaluation previously lived inside `prepare(for:)`, which required a `Test` even though the evaluation logic could be used independently. The lifecycle method now delegates to the reusable operation. The original use case was applying Swift Testing traits to Rundown elements smaller than a test function. ST-0010 shipped in Swift 6.2. [Proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0010-evaluate-condition.md) · [Original pitch](https://forums.swift.org/t/pitch-introduce-conditiontrait-evaluate/77242)
- ST-0011 also shipped in Swift 6.2. It introduced `IssueHandlingTrait`, `.compactMapIssues`, and `.filterIssues`. The transform runs synchronously when the issue is recorded, so it can read the example's task-local path. `handleIssue(_:)` applies the transform to an issue the caller already has. The missing operation is installing that transform for a synchronous body that contains native assertions. ST-0011 discusses a standalone function under future directions. [ST-0011](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0011-issue-handling-traits.md#standalone-function)
- `IssueHandlingTrait.provideScope(for:testCase:performing:)` is public and async. It delegates to an internal helper that installs the transform using the current configuration. The helper does not need a `Test` or `Test.Case` argument. The configuration already has a synchronous `withCurrent` overload used by the handler to restore the outer configuration while running the transform. [IssueHandlingTrait source](https://github.com/swiftlang/swift-testing/blob/3b7adae97e9e8b9fe63f1bfe275e6cb44678a506/Sources/Testing/Traits/IssueHandlingTrait.swift#L90-L165) · [Configuration scope source](https://github.com/swiftlang/swift-testing/blob/3b7adae97e9e8b9fe63f1bfe275e6cb44678a506/Sources/Testing/Running/Runner.RuntimeState.swift#L66-L118)

## Proposed API

Add a synchronous instance method to `IssueHandlingTrait`. `Result` lets the scope return the body's result, and `rethrows` preserves errors from the body. A synchronous closure can execute inline on the caller's actor or thread. The trait factory and transform semantics can stay the same as in ST-0011.

```swift
// Proposed method on IssueHandlingTrait
public func withScope<Result>(
  _ body: () throws -> Result
) rethrows -> Result
```

Rundown could install the handler once around the spec run and read the current path for each assertion. Limiting the transform to `.expectationFailed` leaves thrown-error reporting to `SwiftTestingReporter` and avoids adding a second path to its issues.

```swift
let handler = IssueHandlingTrait.compactMapIssues { issue in
  guard case .expectationFailed = issue.kind,
        let path = ExampleRunner.current?.description else { return issue }
  var issue = issue
  issue.comments.append(Comment(rawValue: path))
  return issue
}

try handler.withScope {
  try runSpec()
}
```

`runSpec()` stands for Rundown's existing synchronous traversal. An async counterpart could provide a consistent spelling, although the existing public async `provideScope` already covers Rundown's async use case. A standalone `withIssueHandling(_:perform:)` is another spelling for the same scoped capability if the workgroup prefers a function over an instance method.

## Prototype evidence

Temporary probes ran against the installed Swift Testing library version 2403 in Xcode 27.2 (27B52), using Swift 6.4.2 on macOS. The source checkout used for inspection was `swiftlang/swift-testing` at `3b7adae97e9e8b9fe63f1bfe275e6cb44678a506`. The probes used deliberate failing assertions and checked the emitted issue count and path comments. They exercised existing Swift Testing APIs. The proposed synchronous method still needs an upstream prototype.

| Experiment | Observed result |
| --- | --- |
| Invoke `provideScope(for:testCase:performing:)` directly inside an async `@Test`, using `Test.current` and `Test.Case.current` | Both a failed `#expect` and a failed `#require` in separate examples of a concurrent group carried their full paths. Each produced one issue at the original assertion site. The test had no issue-handling trait attached. |
| Call the existing synchronous Rundown traversal from inside that async scope | A synchronous helper that called `try spec` also produced a path comment. The scope was entered by the async caller, so a wholly synchronous test still needs a synchronous entry point. |
| Attach the same handler once with `@Suite` and run a synchronous spec | The issue carried the full path. Swift Testing invoked the transform twice for one issue on this toolchain, producing two identical path comments. |
| Make the transform check for an existing path comment and combine the suite trait with direct async scoping | Each intended issue carried one path comment. An assertion outside `spec` carried no Rundown path. |

To reproduce the direct-scope probe, use the `handler` transform above in an async `@Test`. Replace the proposed `withScope` call with the current API and run a named spec with failing `#expect` and `#require` assertions in separate examples. Compare the resulting issue count, path comments, and source locations. Include one assertion after the scope to check its boundary. The temporary probes were removed after verification.

```swift
let test = try #require(Test.current)
try await handler.provideScope(for: test, testCase: Test.Case.current) {
  try await spec("Checkout") {
    it("checks the total") {
      await Task.yield()
      #expect(Bool(false), "Deliberate probe failure")
    }
  }
}
```

## Alternatives

| Option | Trade-off |
| --- | --- |
| A scoped comment API such as `withIssueComment(_:perform:)` | Smaller capability. It would let helpers annotate issues while keeping filtering and replacement in `IssueHandlingTrait`. Rundown could wrap each example and hook in a scope with its path. The API would need to define how comments from nested scopes combine. |
| Capture and re-emit using `TestingUtilities` | The November 2026 pitch proposes synchronous and async issue capture and an instance `Issue.record()` for re-emission. It treats general transformation and local traits as future work. A Rundown implementation would need to preserve the path at capture time and verify how replay interacts with original attribution, handler order, and known issues. Revisit after the pitch evolves. [Issue Capturing pitch](https://forums.swift.org/t/pitch-add-issue-capturing-test-utility-specific-module-to-swift-testing/90397) |
| A generic local trait API | Useful for more traits, with a larger design question about what cancellation, conditions, and activity scopes mean inside a running test. The existing discussion shows a generic async helper using `TestScoping`. A synchronous form would need a synchronous scoping capability. [Generic test scoping discussion](https://forums.swift.org/t/generic-utility-for-invoking-a-testscoping-trait/80043) |
| Rundown-specific fallback | Install the current async scope inside async `spec`, or offer an optional `@Suite(.rundownPaths)` for synchronous tests. One suite annotation covers its tests. A shared transform would need to avoid duplicate path comments when both scopes apply. Explicit comments on individual assertions are another fallback. |

## Questions for a formal proposal

1. Factor the configuration wrapping out of the existing async scope so both paths share handler ordering, validation, and recursion protection. Confirm that nested scopes compose with suite and test traits. The current recorder checks for known issues before it posts the issue event, so a matcher sees the original issue. Test that the new scope preserves that ordering. [Issue recording source](https://github.com/swiftlang/swift-testing/blob/3b7adae97e9e8b9fe63f1bfe275e6cb44678a506/Sources/Testing/Issues/Issue%2BRecording.swift#L16-L38)
2. Define behavior outside an active Swift Testing configuration. One candidate is to execute the body normally, which makes shared helpers usable outside a test. The existing internal async helper traps when its configuration is missing.
3. Define how the scope applies to child tasks and work that lacks Swift Testing's task-local context. The current configuration binder also registers the configuration in a list used as a fallback for events without a current configuration. Check whether a local scope should participate in that fallback and test concurrent host tests for cross-talk. Rundown already serializes sync `.concurrent` groups under Swift Testing because GCD workers lack the host test context. [Event dispatch source](https://github.com/swiftlang/swift-testing/blob/3b7adae97e9e8b9fe63f1bfe275e6cb44678a506/Sources/Testing/Events/Event.swift#L349-L367) · [Rundown suite entry points](../Sources/RundownSwiftTesting/SwiftTestingSuite.swift)
4. Prototype the synchronous method in Swift Testing with an ordinary `@Test` and a helper. Verify one original issue with its source location, comments and expectation details intact, no annotation on an assertion outside the scope, correct nested handler order, and normal return values and thrown errors from the body. Exercise `#expect` and `#require`, caller isolation, and concurrent tests.
5. Refresh the related upstream discussions before pitching. Lead with the synchronous Rundown example and the ST-0010 precedent. Ask for feedback on the method versus standalone function spelling and whether a comment-only scope would better fit the workgroup's direction.

## Rundown status

Roadmap task 6 remains open. The direct async scope is viable today with Swift Testing 6.2-era APIs or later. Synchronous assertion paths without suite annotations depend on an upstream capability. Rundown's manifest currently uses Swift tools 6.0, so any use of newer Swift Testing APIs needs a compatibility gate or a separately agreed minimum-version change. [Roadmap](Roadmap.md) · [Package manifest](../Package.swift)
