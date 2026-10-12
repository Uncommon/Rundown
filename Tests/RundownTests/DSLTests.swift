import XCTest
import Rundown  // Not @testable, so these tests only see the public API

/// Tests of the DSL itself: what the builder accepts, and the helpers around it.
final class DSLTests: XCTestCase {
  // MARK: Conditionals

  func testIfWithoutElse() throws {
    for enabled in [true, false] {
      let log = Box([String]())

      try spec("if") {
        it("always") { log.note("always") }
        if enabled {
          it("sometimes") { log.note("sometimes") }
        }
      }
      XCTAssertEqual(log.wrappedValue,
                     enabled ? ["always", "sometimes"] : ["always"],
                     "enabled: \(enabled)")
    }
  }

  func testIfElse() throws {
    for enabled in [true, false] {
      let log = Box([String]())

      try spec("if else") {
        if enabled {
          it("a") { log.note("a") }
        }
        else {
          context("b") {
            it("inside b") { log.note("b") }
          }
        }
      }
      XCTAssertEqual(log.wrappedValue, [enabled ? "a" : "b"], "enabled: \(enabled)")
    }
  }

  func testElseIfAndSwitch() throws {
    for number in 0..<3 {
      let log = Box([String]())

      try spec("branches") {
        if number == 0 {
          it("if") { log.note("if") }
        }
        else if number == 1 {
          it("else if") { log.note("else if") }
        }
        else {
          it("else") { log.note("else") }
        }
        switch number {
          case 0: it("zero") { log.note("zero") }
          case 1: it("one") { log.note("one") }
          default: it("many") { log.note("many") }
        }
      }
      XCTAssertEqual(log.wrappedValue,
                     [["if", "zero"], ["else if", "one"], ["else", "many"]][number])
    }
  }

  func testIfLet() throws {
    for value in [nil, 42] as [Int?] {
      let log = Box([String]())

      try spec("if let") {
        if let value {
          it("has \(value)") { log.note("\(value)") }
        }
      }
      XCTAssertEqual(log.wrappedValue, value.map { ["\($0)"] } ?? [])
    }
  }

  func testIfAvailable() throws {
    let log = Box([String]())

    try spec("available") {
      if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
        it("is available") { log.note("available") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["available"])
  }

  func testConditionalKeepsOrder() throws {
    let log = Box([String]())

    try spec("order") {
      it("first") { log.note("first") }
      if Bool.random() || true {
        it("second") { log.note("second") }
        it("third") { log.note("third") }
      }
      it("fourth") { log.note("fourth") }
      if Bool.random() || true {
        context("fifth") { it("fifth") { log.note("fifth") } }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["first", "second", "third", "fourth", "fifth"])
  }

  func testNestedConditional() throws {
    let log = Box([String]())
    let outer = true
    let inner = false

    try spec("nested") {
      context("context") {
        if outer {
          it("outer") { log.note("outer") }
          if inner {
            it("inner") { log.note("inner") }
          }
        }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["outer"])
  }

  /// A group where every conditional is off has no examples, so it does nothing,
  /// hooks included.
  func testGroupWithNothingEnabledRunsNothing() throws {
    let enabled = Bool.random() && false
    let log = Box([String]())

    try spec("nothing") {
      beforeAll { log.note("beforeAll") }
      beforeEach { log.note("beforeEach") }
      if enabled {
        it("never") { log.note("never") }
      }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    }
    XCTAssertEqual(log.wrappedValue, [])
  }

  /// Hooks inside a conditional belong to the whole group, the same as hooks
  /// inside a loop.
  func testHooksInConditionalApplyToTheWholeGroup() throws {
    let log = Box([String]())

    try spec("hooks") {
      if true || Bool.random() {
        beforeEach { log.note("beforeEach") }
        it("inside") { log.note("inside") }
      }
      it("sibling") { log.note("sibling") }
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeEach", "inside", "beforeEach", "sibling"])
  }

  // MARK: Loops

  func testLoopAfterHooks() throws {
    let log = Box([String]())

    try spec("loop") {
      beforeAll { log.note("beforeAll") }
      beforeEach { log.note("beforeEach") }
      for index in 1...3 {
        it("iteration \(index)") { log.note("it \(index)") }
      }
      afterEach { log.note("afterEach") }
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeAll",
                    "beforeEach", "it 1", "afterEach",
                    "beforeEach", "it 2", "afterEach",
                    "beforeEach", "it 3", "afterEach"])
  }

  func testLoopBetweenExamples() throws {
    let log = Box([String]())

    try spec("loop") {
      it("first") { log.note("first") }
      for index in 1...2 {
        context("context \(index)") {
          it("inside \(index)") { log.note("inside \(index)") }
        }
      }
      it("last") { log.note("last") }
    }
    XCTAssertEqual(log.wrappedValue, ["first", "inside 1", "inside 2", "last"])
  }

  func testLoopAndConditionalTogether() throws {
    let log = Box([String]())

    try spec("both") {
      beforeEach { log.note("beforeEach") }
      for index in 1...2 {
        if index == 2 {
          it("only \(index)") { log.note("only \(index)") }
        }
      }
      if true || Bool.random() {
        for index in 3...4 {
          it("iteration \(index)") { log.note("it \(index)") }
        }
      }
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeEach", "only 2",
                    "beforeEach", "it 3",
                    "beforeEach", "it 4"])
  }

  // MARK: Async groups

  func testControlFlowInAsyncGroup() async throws {
    let log = Box([String]())
    let enabled = true

    try await spec("async") {
      beforeEach { log.note("beforeEach") }
      for index in 1...2 {
        it("sync \(index)") { log.note("sync \(index)") }
      }
      if enabled {
        it("async") {
          await Task.yield()
          log.note("async")
        }
      }
      else {
        it("never") { log.note("never") }
      }
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeEach", "sync 1", "beforeEach", "sync 2", "beforeEach", "async"])
  }

  /// A sync afterAll can follow a sync afterEach in an async group.
  func testSyncAfterHooksInAsyncGroup() async throws {
    let log = Box([String]())

    try await spec("async hooks") {
      beforeAll { log.note("beforeAll") }
      it("async") {
        await Task.yield()
        log.note("it")
      }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    }
    XCTAssertEqual(log.wrappedValue, ["beforeAll", "it", "afterEach", "afterAll"])
  }

  // MARK: Focus and exclude helpers

  func testFocusHelpers() throws {
    let log = Box([String]())

    try spec("focus") {
      it("not focused") { log.note("not focused") }
      fIt("focused") { log.note("focused") }
      fContext("focused context") {
        it("inside") { log.note("inside") }
      }
      fDescribe("focused describe", .concurrent) {
        it("also inside") { log.note("also inside") }
      }
      context("not focused") {
        it("skipped") { log.note("skipped") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["focused", "inside", "also inside"])
  }

  func testExcludeHelpers() throws {
    let log = Box([String]())

    try spec("exclude") {
      it("runs") { log.note("runs") }
      xIt("excluded") { log.note("excluded") }
      xContext("excluded context") {
        it("inside") { log.note("inside") }
      }
      xDescribe("excluded describe", .concurrent) {
        it("also inside") { log.note("also inside") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["runs"])
  }

  func testFocusAndExcludeHelpersInAsyncGroup() async throws {
    let log = Box([String]())

    try await spec("async helpers") {
      it("not focused") { log.note("not focused") }
      fIt("focused") {
        await Task.yield()
        log.note("focused")
      }
      xIt("excluded") {
        await Task.yield()
        log.note("excluded")
      }
      fContext("focused context") {
        it("inside") { log.note("inside") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["focused", "inside"])
  }

  // MARK: Example path

  func testExamplePath() throws {
    XCTAssertNil(ExampleRunner.current, "no runner outside of a spec")

    let paths = Box([[String]]())
    let descriptions = Box([String]())

    try spec("Path") {
      beforeEach {
        paths.wrappedValue.append(ExampleRunner.current?.path ?? [])
      }
      context("in a context") {
        it("works") {
          paths.wrappedValue.append(ExampleRunner.current?.path ?? [])
          descriptions.note(ExampleRunner.current?.description ?? "")
        }
      }
    }
    XCTAssertEqual(paths.wrappedValue,
                   [["Path", "before each"],
                    ["Path", "in a context", "works"]])
    XCTAssertEqual(descriptions.wrappedValue, ["Path, in a context, works"])
    XCTAssertNil(ExampleRunner.current, "no runner after a spec")
  }

  func testExamplePathInAsyncGroup() async throws {
    let paths = Box([[String]]())

    try await spec("Async path") {
      it("works") {
        await Task.yield()
        paths.wrappedValue.append(ExampleRunner.current?.path ?? [])
      }
    }
    XCTAssertEqual(paths.wrappedValue, [["Async path", "works"]])
  }
}

/// The same helpers and control flow in a main actor suite, which has its own
/// versions of the DSL functions.
@MainActor
final class MainActorDSLTests: Rundown.TestCase {
  func testControlFlow() throws {
    let log = Box([String]())
    let enabled = true
    let disabled = false

    try spec("main actor") {
      beforeEach { log.note("beforeEach") }
      for index in 1...2 {
        it("iteration \(index)") { log.note("it \(index)") }
      }
      if enabled {
        context("enabled") {
          it("inside") { log.note("inside") }
        }
      }
      if disabled {
        it("never") { log.note("never") }
      }
      if enabled {
        it("if") { log.note("if") }
      }
      else {
        it("else") { log.note("else") }
      }
    }
    XCTAssertEqual(log.wrappedValue,
                   ["beforeEach", "it 1", "beforeEach", "it 2",
                    "beforeEach", "inside", "beforeEach", "if"])
  }

  func testFocusHelpers() throws {
    let log = Box([String]())

    try spec("main actor focus") {
      it("not focused") { log.note("not focused") }
      fIt("focused") { log.note("focused") }
      fContext("focused context") {
        it("inside") { log.note("inside") }
      }
      fDescribe("focused describe") {
        it("also inside") { log.note("also inside") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["focused", "inside", "also inside"])
  }

  func testExcludeHelpers() throws {
    let log = Box([String]())

    try spec("main actor exclude") {
      it("runs") { log.note("runs") }
      xIt("excluded") { log.note("excluded") }
      xContext("excluded context") {
        it("inside") { log.note("inside") }
      }
      xDescribe("excluded describe") {
        it("also inside") { log.note("also inside") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["runs"])
  }

  func testAsyncControlFlowAndHelpers() async throws {
    let log = Box([String]())
    let enabled = true

    try await spec("async main actor") {
      beforeEach { log.note("beforeEach") }
      for index in 1...2 {
        it("iteration \(index)") { log.note("it \(index)") }
      }
      if enabled {
        fIt("focused") {
          await Task.yield()
          log.note("focused")
        }
      }
      xIt("excluded") {
        await Task.yield()
        log.note("excluded")
      }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    }
    XCTAssertEqual(log.wrappedValue, ["beforeEach", "focused", "afterEach", "afterAll"])
  }
}
