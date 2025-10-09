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
* `beforeEach`
* `describe`/`context`/`it`/`within`
* `afterEach`
* `afterAll`

Mis-ordered elements produce a compile-time error.

`within` is a new element type for tests that need to run inside a callback, such as `TaskLocal.withValue()`.

## Test framework support

The goal is for this library to be equally useful in either XCTest or Swift Testing.

XCTest support has the following features:

* Each test element is run using `XCTContext.runActivity()` so that the test structure is evident in the logs.
* A subclass of `XCTestCase`, named `Rundown.TestCase`, is provided so that test failures include the full name of the test element, including enclosing `describe` and `context` elements.
* `XCTSkip` is handled, skipping the remaining steps at that level in the hierarchy.
* Using `XCTContext.runActivity()` with `async` tests is currently not supported. It is a `@MainActor` function, and thus doesn't work well with concurrency. 

Similar support for Swift Testing is planned, but the Swift Testing APIs do not yet provide for implementing those features. It is still possible to simply run the test elements, though. 

## Running tests

The main way to run tests looks like this:

``` swift
spec {
  it("works") {
    // ···
  }
}
```

The `spec()` function creates an outer `describe` element, using either the name of the calling function or a provided string, and then executes it. This is a global function.

There is also an `async` version of `spec()`, so if your test function is `async` then just call `await spec { ··· }`, and then you can use `await` inside your test elements.

When working with `XCTest`, there is also `spec()` as a method of `XCTestCase` - or more precisely, a method of the subclass `Rundown.TestCase`. This subclass should always be used so that issues can be logged with the full test element description, and this version of `spec()` uses an `XCTActivity` for each test element. 

The goal is to do something similar for Swift Testing, but it doesn't yet have an equivalent for `XCTActivity`.

## Goals and plans

* Compatibility with XCTest and Swift Testing, with an API that looks the same in either case
* Flexibility to use it or not for any given test (hence there is no custom test discovery; this may change in the future, especially if framework support improves)
* Minimal boilerplate at the use site
* Ease of use during development, such as running (or skipping) specific elements
