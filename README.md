## Rundown

Rundown is a structured testing framework for XCTest and Swift Testing, based on the pattern used in testing libraries such as RSpec, where tests are organized into steps:

```swift
describe("this app feature") {
  context("in one context") {
    it("does one thing") {
      // perform tests
    }
  }
  context("in another context") {
    beforeAll {
      // set up the context
    }
    it("does another thing") {
      // perform tests
    }
    afterAll {
      // clean up
    }
  }
}
```

A Swift result builder is used to assemble the steps into an object that can be executed in a unit test. The result builder also ensures proper ordering of elements:

* `beforeAll`
* `aroundEach`
* `beforeEach`
* `describe`/`context`/`it`
* `afterEach`
* `afterAll`

Mis-ordered elements produce a compile-time error.

## Hooks and contexts

The `beforeEach`, `afterEach` and `aroundEach` hooks apply to the elements of the group they are declared in, and a nested `describe` or `context` counts as one element. They run once around the whole nested group, not around each example inside it. This is what lets a context group examples together under hooks of its own. To run something for every example in a context, declare it inside that context. Setup that several contexts need can come from a function that returns the hook.

## Loops and conditionals

`for` loops, `if`/`else`, `switch`, `if let` and `if #available` can generate examples and contexts, anywhere in a group:

```swift
describe("a feature") {
  beforeEach { /* ... */ }
  for input in inputs {
    it("handles \(input)") { /* ... */ }
  }
  if #available(macOS 14, *) {
    it("uses the new API") { /* ... */ }
  }
}
```

Each branch has to end with an example or context. An `if` without an `else` can't end with an `afterEach` or `afterAll`; put those after it. Hooks inside a loop or conditional belong to the whole enclosing group, wherever the loop or conditional appears.

## Focusing and excluding

The `.focused` trait limits a run to the focused elements (plus the hooks of their groups), and the `.excluded` trait leaves elements out. Both are for use while developing. There are shortcuts that add the trait: `fIt`, `fDescribe` and `fContext` to focus, and `xIt`, `xDescribe` and `xContext` to exclude.

## Finding the current example

While a spec runs, `ExampleRunner.current` is its runner, and its `path` is the descriptions of the elements being run, from the outermost group to the example or hook itself. Its `description` is the same thing as one string, such as `Spec, in a context, does a thing`. Code inside an example can use it to name a log entry or an attachment.

## Test framework support

The goal is for this library to be equally useful in either XCTest or Swift Testing.

XCTest support has the following features:

* Each test element is run using `XCTContext.runActivity()` so that the test structure is evident in the logs (unless the test is `async`).
* Using `XCTContext.runActivity()` with `async` tests is currently not supported. It is a `@MainActor` function, and thus doesn't work well with concurrency. 
* A subclass of `XCTestCase`, named `Rundown.TestCase`, is provided so that test failures include the full name of the test element, including enclosing `describe` and `context` elements.
* `XCTSkip` is handled, skipping the remaining steps at that level in the hierarchy.

Similar support for Swift Testing is planned, but the Swift Testing APIs do not yet provide for implementing those features. It is still possible to simply run the test elements, though. 

## Running tests

The main direct way to run tests looks like this:

``` swift
func testSomething() {
  try spec {
    it("works") {
      // ···
    }
  }
}
```

The `spec()` function creates an outer `describe` element, using either the name of the calling function or a provided string, and then executes it. This is a global function.

There is also an `async` version of `spec()`, so if your test function is `async` then just call `await spec { ··· }`, and then you can use `await` inside your test elements.

When working with `XCTest`, there is also `spec()` as a method of `XCTestCase` - or more precisely, a method of the subclass `Rundown.TestCase`. This subclass should always be used so that issues can be logged with the full test element description, and this version of `spec()` uses an `XCTActivity` for each test element (for non-`async` tests). An `XCTestCase` subclass should also be marked with `@MainActor` because test steps are tracked with `XCTContext.runActivity()`, which is `@MainActor`. Async tests don't use `XCTContext.runActivity()` because it is not async compatible.

The goal is to do something similar for Swift Testing, but it doesn't yet have an equivalent for `XCTActivity`.

## Errors and skips

An error never skips teardown or the remaining elements. Everything that can still run does, and then the first error is rethrown. (The XCTest runner instead records each error as an issue, with the full name of the element that threw it, so it can report more than one.)

* If `beforeAll` throws, the elements of the group are skipped, but its `afterAll` hooks still run.
* If `beforeEach` throws, that element is skipped, but its `afterEach` hooks still run.
* If an example or an `afterEach` hook throws, the group carries on with its next element.
* Every `afterEach` and `afterAll` hook runs, even if one before it threw.

`XCTSkip` is different: it means that something does not apply, so there is nothing to undo. A skip in `beforeAll` skips the whole group, including `afterAll`. A skip in `beforeEach` skips that element, including its `afterEach` hooks. A skip in an example still runs the `afterEach` hooks. A skip in an `afterEach`, `afterAll` or `aroundEach` hook is logged and ignored: the rest of the run carries on.

## MainActor tests

Tests that require `@MainActor` need to have the enclosing type conform to `Rundown.MainActorSuite`. For XCTest, the `Rundown.TestCase` class already does this.

The main actor versions of `describe`, `it` and the rest are members of `MainActorSuite`. That means if you have a helper function that builds a group for a `@MainActor` spec, it has to be a member of such a type as well. A free function would get the ordinary versions instead, which don't produce a `@MainActor` group, and the compiler will report an error.

For helpers shared between test classes, extend a protocol that inherits from `MainActorSuite`:

```swift
protocol SearchGroups: MainActorSuite {}

extension SearchGroups {
  @ExampleBuilder<SyncMainCall>
  func searchGroup() -> ExampleGroup<SyncMainCall> {
    beforeAll { setUpSearch() }
    context("by summary") {
      it("finds items") { /* ... */ }
    }
  }
}

final class SearchTests: Rundown.TestCase, SearchGroups {
  func testSearch() throws {
    try spec {
      searchGroup()
    }
  }
}
```

A small type that conforms to `MainActorSuite` works as a namespace for groups that don't belong to any test class.

## Goals and plans

* Compatibility with XCTest and Swift Testing, with an API that looks the same in either case
* Flexibility to use it or not for any given test (hence there is no custom test discovery; this may change in the future, especially if framework support improves)
* Minimal boilerplate at the use site
* Ease of use during development, such as running (or skipping) specific elements
