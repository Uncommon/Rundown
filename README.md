## Rundown

Rundown is based on the pattern used in testing libraries such as RSpec, where tests are organized into steps:

```swift
Describe("this app feature") {
  Context("in one context") {
    It("does one thing") {
      // perform tests
    }
  }
  Context("in another context") {
    BeforeAll {
      // set up the context
    }
    It("does another thing") {
      // perform tests
    }
    AfterAll {
      // clean up
    }
  }
}
```

A Swift result builder is used to assemble the steps into an object that can be executed in a unit test. The result builder also ensures proper ordering of elements:

* `BeforeAll`
* `BeforeEach`
* `Describe`/`Context`/`It`
* `AfterEach`
* `AfterAll`

Mis-ordered elements produce a compile-time error.

## Test framework support

The goals is for this library to be equally useful in either XCTest or Swift Testing.

XCTest support has the following features:

* Each test element is run using `XCTContext.runActivity()` so that the test structure is evident in the logs.
* A sub class of `XCTestCase`, named `Rundown.TestCase`, is provided so that test failures include the full name of the test element, including enclosing `Describe` and `Context` elements.
* `XCTSkip` is handled so that only the remaining elements at that level are skipped.

Similar support for Swift Testing is planned, but the Swift Testing APIs do not yet provide for implementing those features. It is still possible to simply run the test elements, though. 

## Running tests

There are currently a few experimental ways to run the tests:

``` swift
spec {
  It("works") {
    // ···
  }
}
```

The `spec()` function creates an outer `Describe` element, using either the name of the calling function or a provided string, and then executes it. This is a global function.

When working with `XCTest`, there is also `spec()` as a method of `XCTestCase` - or more precisely, a method of the subclass `Rundown.TestCase`. This subclass should always be used so that issues can be logged with the full test element description, and this version of `spec()` uses an `XCTActivity` for each test element. 

The goal is to do something similar for Swift Testing, but it doesn't yet have an equivalent for `XCTActivity`.


``` swift
Describe("this thing") {
  // ···
}.run()
```

This is what `spec()` does internally. Call `runActivity()` to get the `XCTActivity` behavior.

``` swift
@TestExample
func testSomething() throws {
  It("works") {
    // ···
  }
}
```

`@TestExample` is a function body macro, which is clean and simple but has the drawback that source code locations - test failures, compile time errors, and breakpoints - are relative to the macro-generated code, not the original.

``` swift
@Example @ExampleBuilder
func something() throws -> ExampleGroup {
  It("works") {
    // ···
  }
}
```

`@Example` is a peer macro that generates another function prefixed with "test" so that it's discoverable by XCTest. This doesn't have the drawbacks of the body macro, but it does require the additional boilerplate of explicitly specifying the `@ExampleBuilder` result builder and the `ExampleGroup` result type.

## Goals and plans

* Compatibility with XCTest and Swift Testing, with an API that looks the same in either case
* Flexibility to use it or not for any given test (hence there is no custom test discovery; this may change in the future, especially if framework support improves)
* Minimal boilerplate at the use site
* Ease of use during development, such as running (or skipping) specific elements
