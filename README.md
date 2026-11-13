# Rundown

Rundown helps you organize Swift tests by behavior. Using an RSpec-style DSL, you can give a feature a name, group examples by the conditions they run under, and share setup steps in a logical hierarchy. Rundown is compatible with both [Swift Testing](#in-swift-testing) and [XCTest](#in-xctest), using the native assertions from each.

## Get started

Rundown requires Swift 6.0 or later. The package targets macOS 15, iOS 17, tvOS 17, watchOS 10, and Mac Catalyst 17 or later.

Add `https://github.com/Uncommon/Rundown.git` as a package dependency in Xcode or in your `Package.swift`. Use the `main` branch to get the current version. Then add the product for your test framework to your test target.

- For Swift Testing, add `RundownSwiftTesting`.
- For XCTest, add `Rundown`.

### In Swift Testing

Conform your test type to `SwiftTestingSuite` and call `try spec` inside a regular `@Test` function. On Swift 6.2 or later, add `@Suite(.rundownPaths)` to include the full example path on failed assertions.

```swift
import RundownSwiftTesting
import Testing

@Suite(.rundownPaths)
struct CartTests: SwiftTestingSuite {
  @Test func calculatesTotal() throws {
    try spec("Cart total") {
      context("when the cart is empty") {
        it("is zero") {
          #expect(Cart().total == 0)
        }
      }

      context("when the cart has items") {
        it("adds the prices") {
          #expect(Cart(prices: [19, 23]).total == 42)
        }
      }
    }
  }
}

private struct Cart {
  var prices: [Int] = []
  var total: Int { prices.reduce(0, +) }
}
```

Run your tests as usual in Xcode or with `swift test`. Swift Testing sees one test per `@Test` function, and Rundown runs the examples inside it. With `.rundownPaths`, a failed assertion includes a comment like `Rundown path: Cart total, when the cart has items, adds the prices` alongside its original source location.

- `spec` names and runs the outer group inside your test function. You can omit its name to use the function name.
- `context` groups examples that share a condition. `describe` works the same way and often names a feature or operation. You can nest either group.
- `it` names one example and runs the assertions in its body. Read it with the group names to see what the test checks.

### In XCTest

For best results, subclass `Rundown.TestCase` to enable full paths in failure messages, and use synchronous tests to enable nested activity logging. Test functions should be `@MainActor`.

A full path would be, for example, "Cart total, with two items, adds the prices" for the first test in the example below.

Async tests are supported by calling `try await spec {}`, but test results will not display as nested results in Xcode. This feature relies on `XCTContext.runActivity()` which is not `async` compatible.

```swift
import Rundown
import XCTest

final class CartXCTests: Rundown.TestCase {
  @MainActor private var prices: [Int] = []

  @MainActor
  func testCartTotal() throws {
    try spec("Cart total") {
      context("with two items") {
        beforeEach {
          self.prices = [19, 23]
        }

        it("adds the prices") {
          XCTAssertEqual(self.prices.reduce(0, +), 42)
        }

        it("updates after removing an item") {
          self.prices.removeLast()
          XCTAssertEqual(self.prices.reduce(0, +), 19)
        }
      }
    }
  }
}
```

## Share setup and cleanup

Setup and cleanup blocks are called *hooks*. In the XCTest example, `beforeEach` gives both examples a fresh set of prices. Put hooks in the group whose examples need them.

| Hook | When it runs |
| --- | --- |
| `beforeAll` | Once before the group’s children run. |
| `aroundEach` | Wraps each child and its per-child hooks. Your code calls the supplied callback to run them, which lets you use APIs such as `TaskLocal.withValue`. |
| `beforeEach` | Before each direct child. |
| `afterEach` | After each direct child. |
| `afterAll` | Once after the group’s children finish. |

A nested group counts as one direct child. The parent’s per-child hooks wrap that group as a whole. Put a `beforeEach` inside the nested group when every example there needs its own setup.

Place setup hooks before the examples and cleanup hooks after them, in the order shown above. The ordering is checked at compile time. Use `for` loops to generate examples from input values and conditionals to include groups or examples when they apply.

## Rundown and Swift Testing traits

A trait is an option you attach to an example or group.

If any examples or groups are marked with the `.focused` trait, Rundown limits the run to those examples and groups, including the enclosing groups and their hooks. Inside each selected group, Rundown applies the same rule. If nothing inside is focused, its children run as usual.

Write `it("adds the prices", .focused) { … }` to focus an example, or use `.excluded` to leave it out. Both traits also work on `context` and `describe`. If a group has no selected children, its setup is skipped. In Swift Testing, use `.disabled` on `@Test` or `@Suite` to skip the whole test or suite.

Swift Testing discovers and filters the enclosing `@Test`. To narrow a SwiftPM run, use `swift test --filter` with the name of the test or suite. Rundown selects and schedules the examples inside each spec.

Groups run their children in order by default. Mark a group `.concurrent` to allow its children to overlap in an async Swift Testing spec. Use independent fixtures for children that run concurrently. The synchronous Swift Testing adapter and XCTest activity runner run children serially.

## Other Swift Testing entry points

### Assertion paths in synchronous specs

The `.rundownPaths` suite trait adds paths to failed `#expect` and `#require` assertions in synchronous specs. If your examples need `await`, use `try await spec { … }` in an async `@Test`. On Swift 6.2 or later, async specs add assertion paths automatically. Rundown reports thrown errors with their paths in both synchronous and asynchronous specs.

### Main-actor tests

Conform to `MainActorSwiftTestingSuite` when your examples or hooks use main-actor APIs. Declare the conformance with the type so Swift infers its isolation. Use `try spec {}` in synchronous tests or `try await spec {}` in async tests. Async main-actor groups require serial execution. To define helpers that return main-actor test elements like `context` or `describe`, make them members of a type or protocol that conforms to `MainActorSuite`.

### Optional `@Spec` macro

The experimental `@Spec` macro gives Swift Testing one case per selected top-level group or standalone example, following the pattern of SwiftUI's `View`. Use it when you want to rerun one of those groups in Xcode. It requires an Apple platform and Swift 6.4 or later.

```swift
import RundownSwiftTesting
import Testing

@Spec
struct CheckoutSpec {
  var spec: ExampleGroup<AsyncCall> {
    context("with two items") {
      it("adds the prices") {
        #expect([19, 23].reduce(0, +) == 42)
      }
    }

    it("starts a guest cart at zero") {
      let prices: [Int] = []
      #expect(prices.reduce(0, +) == 0)
    }
  }
}
```

Use a non-generic struct with a parameterless initializer and a computed `spec` property of type `ExampleGroup<AsyncCall>`. The macro adds the builder and conformance. Swift Testing reads the property while planning the cases, then runs those cases asynchronously. Inside the `it` and hook bodies, you can use synchronous code as shown above or call async APIs with `await`. Rundown adds assertion paths automatically. For a spec whose hooks and examples all need the main actor, conform to `MainActorSwiftTestingSuite`.

This example registers two cases. SwiftPM’s `swift test --filter 'CheckoutSpec/examples'` runs both.

To rerun one case with `xcodebuild`, build for testing and run the spec with `-resultBundlePath`. Use `xcrun xcresulttool get test-results tests --path <bundle>` to find the case’s `nodeIdentifierURL`. Pass that URL to `xcodebuild test-without-building` with `-only-testing`, using the same `.xctestrun` file and destination as the original run. Get a fresh case URL after reordering examples. This workflow was verified for specs declared at file scope on macOS with Xcode 27.2 and Swift 6.4.2.

## More details

- Use `ExampleRunner.current?.description` inside a hook or example to include its full path in a log entry or attachment.
- If setup fails, Rundown skips the affected work and still runs the corresponding cleanup hooks. A `beforeAll` failure skips the group’s children, while a `beforeEach` failure skips the child it was preparing.
- In a Swift Testing host test, `try Test.cancel("reason")` (Swift 6.3 or later) stops new setup and examples. Cleanup still runs for groups and examples already entered.
- Rundown is available under the [MIT license](LICENSE).
