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

A result builder is used to assemble the steps into an object that can be executed in a unit test. The result builder also ensures proper ordering of elements: `BeforeAll`, `BeforeEach`, `Describe`/`Context`/`It`, `AfterEach`, `AfterAll`. Mis-ordered elements produce a compile-time error.

## Running tests

There are currently three experimental ways to run the tests:

``` swift
Describe("this thing") {
  // ···
}.run()
```

Simply calling `run()` will execute the test steps. When running under `XCTest`, calling `runActivity()` instead will use `XCTContext.runActivity()` to log the steps as a hierarachy. The goal is to do something similar for Swift Testing, but it doesn't yet have an equivalent for `runActivity()`.

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

### Goals and plans

* Compatibility with XCTest and Swift Testing - *Swift Testing needs more flexibility in test discovery, which is hopefully coming soon*
* Minimal boilerplate at the use site
* Ease of use during development, such as running (or skipping) specific elements
