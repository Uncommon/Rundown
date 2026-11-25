# Rundown

Rundown helps you organize Swift tests by behavior. Using an RSpec-style DSL, you can give a feature a name, group examples by the conditions they run under, and share setup steps in a logical hierarchy. Rundown is compatible with both [Swift Testing](#in-swift-testing) and [XCTest](#in-xctest), using the native assertions from each.

## Get started

Rundown requires Swift 6.2 or later and Xcode 26 or later. The package targets macOS 15, iOS 17, tvOS 17, watchOS 10, and Mac Catalyst 17 or later.

Add `https://github.com/Uncommon/Rundown.git` as a package dependency in Xcode or in your `Package.swift`. Use the `main` branch to get the current version. Then add the product for your test framework to your test target.

- For Swift Testing, add `RundownSwiftTesting`.
- For XCTest, add `Rundown`.

### In Swift Testing

Conform your test type to `SwiftTestingSuite` and call `try spec` inside a regular `@Test` function. Add `@Suite(.rundownPaths)` to include the full example path on failed assertions.

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

Setup and cleanup blocks are called *hooks*. The comments show when each message prints:

```swift
try spec("Hook order") {
  beforeAll { print("before all") }              // 1
  aroundEachPeer { run in
    print("enter peer")                          // 2
    defer { print("leave peer") }                // 17
    try run()
  }
  aroundEach { run in
    print("enter example")                       // 5, 10
    defer { print("leave example") }             // 9, 14
    try run()
  }
  beforeEachPeer { print("prepare peer") }       // 3
  beforeEach { print("prepare example") }        // 6, 11

  context("a nested group") {
    beforeAll { print("before group") }          // 4
    it("inherits the hooks") { print("first") }  // 7
    it("gets fresh setup") { print("second") }   // 12
    afterAll { print("after group") }            // 15
  }

  afterEach { print("clean up example") }        // 8, 13
  afterEachPeer { print("clean up peer") }       // 16
  afterAll { print("after all") }                // 18
}
```

`beforeAll` and `afterAll` run once for their group. `beforeEach` and `afterEach` run for every example, including nested examples. Their `Peer` versions treat an immediate nested group as one unit, so the peer setup and cleanup above surround both examples together.

The `around` hooks receive a callback that runs the corresponding "before" setup, example or group, and "after" cleanup. This lets you keep them inside a single scope, such as `TaskLocal.withValue`.

## Pass a fixture into each example

A `Fixture` functions as a factory providing each example its own instance of a value or test object. Thus the examples cannot accidentally affect each other by changing the value.

```swift
import RundownSwiftTesting
import Testing

final class Counter {
  var value = 0

  func increment() {
    value += 1
  }
}

struct CounterTests: SwiftTestingSuite {
  @Test func incrementsCounter() throws {
    let counter = Fixture { Counter() }

    try spec("Counter") {
      it("increments its value", using: counter) { counter in
        counter.increment()
        #expect(counter.value == 1)
      }
      it("supports repeated increments", using: counter) { counter in
        counter.increment()
        counter.increment()
        #expect(counter.value == 2)
      }
    }
  }
}
```

Both examples modify their counter, but each starts at zero.

The factory is invoked once per example execution, including reruns, and is not invoked for examples that do not run.

Supply optional cleanup with a second trailing closure:

```swift
let directory = Fixture {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
} cleanup: { url in
  try FileManager.default.removeItem(at: url)
}
```

In the above example, creating and deleting the temporary directory could also be done with `beforeEach`/`afterEach`, but the fixture gives a way to pass the URL to an example without having to store it in an optional variable from an outer scope. Fixtures are invoked after `beforeEach` and cleaned up before `afterEach`. 

Different types of fixture must be used depending on whether the test is `async` or `@MainActor`: `Fixture<Value>`, `AsyncFixture<Value>`, `MainActorFixture<Value>` or `AsyncMainActorFixture<Value>`.

## Rundown and Swift Testing traits

A trait is an option you attach to an example or group.

If any examples or groups are marked with the `.focused` trait, Rundown limits the run to those examples and groups, including the enclosing groups and their hooks. Inside each selected group, Rundown applies the same rule. If nothing inside is focused, its children run as usual.

Write `it("adds the prices", .focused) { … }` to focus an example, or use `.excluded` to leave it out. Both traits also work on `context` and `describe`. If a group has no selected children, its setup is skipped. In Swift Testing, use `.disabled` on `@Test` or `@Suite` to skip the whole test or suite.

Swift Testing discovers and filters the enclosing `@Test`. To narrow a SwiftPM run, use `swift test --filter` with the name of the test or suite. Rundown selects and schedules the examples inside each spec.

Groups run their children in order by default. Mark a group `.concurrent` to allow its children to overlap in an async Swift Testing spec. Use independent fixtures for children that run concurrently. The synchronous Swift Testing adapter and XCTest activity runner run children serially.

## Other Swift Testing entry points

### Assertion paths in synchronous specs

The `.rundownPaths` suite trait adds paths to failed `#expect` and `#require` assertions in synchronous specs. If your examples need `await`, use `try await spec { … }` in an async `@Test`. Async specs add assertion paths automatically. Rundown reports thrown errors with their paths in both synchronous and asynchronous specs.

### Main-actor tests

Conform to `MainActorSwiftTestingSuite` when your examples or hooks use main-actor APIs. Declare the conformance with the type so Swift infers its isolation. Use `try spec {}` in synchronous tests or `try await spec {}` in async tests. Async main-actor groups require serial execution. To define helpers that return main-actor test elements like `context` or `describe`, make them members of a type or protocol that conforms to `MainActorSuite`.

### Optional `@Spec` macro

The experimental `@Spec` macro gives Swift Testing one case per selected top-level group or standalone example, following the pattern of SwiftUI's `View`. It requires an Apple platform and Swift 6.4 or later.

```swift
import RundownSwiftTesting
import Testing

@Spec
struct CheckoutSpec {
  var spec: SpecBody {
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

Use a non-generic struct with a parameterless initializer and a computed `spec` property of type `SpecBody`. The macro adds the builder and conformance. Swift Testing reads the property while planning the cases, then runs those cases asynchronously. Inside the `it` and hook bodies, you can use synchronous code as shown above or call async APIs with `await`. Rundown adds assertion paths automatically. For a spec whose hooks and examples all need the main actor, conform to `MainActorSwiftTestingSuite`.

This example registers two cases. SwiftPM’s `swift test --filter 'CheckoutSpec/examples'` runs both.

In Xcode, `@Spec` tests do not appear in the test navigator sidebar, but they are included when you run the whole test target, and their results do show in the log.

To rerun one case with `xcodebuild`, build for testing and run the spec with `-resultBundlePath`. Use `xcrun xcresulttool get test-results tests --path <bundle>` to find the case’s `nodeIdentifierURL`. Pass that URL to `xcodebuild test-without-building` with `-only-testing`, using the same `.xctestrun` file and destination as the original run. Get a fresh case URL after reordering examples. This workflow was verified for specs declared at file scope on macOS with Xcode 27.2 and Swift 6.4.2.

## More details

- Use `ExampleRunner.current?.description` inside a hook or example to include its full path in a log entry or attachment.
- If setup fails, Rundown skips the affected work and still runs the corresponding cleanup hooks. A `beforeAll` failure skips the group’s children, while a `beforeEach` failure skips only the example it was preparing. Its inherited `afterEach` hooks still run, including after a skip in setup. A `beforeEachPeer` failure skips the whole peer; a skip in peer setup also skips its peer cleanup.
- In a Swift Testing host test, `try Test.cancel("reason")` (Swift 6.3 or later) stops new setup and examples. Cleanup still runs for groups and examples already entered.
- Rundown is available under the [MIT license](LICENSE).
