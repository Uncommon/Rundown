import XCTest
@testable import Rundown

final class ExampleNodeTests: XCTestCase {
  func testSyncGroupShape() {
    let group = describe("Root") {
      beforeAll("setup") {}
      aroundEach("wrap") { callback in try callback() }
      beforeEach {}
      beforeEach("second") {}
      it("first") {}
      context("nested", .concurrent) {
        beforeEach {}
        it("inner") {}
        xIt("excluded") {}
      }
      afterEach {}
      afterAll {}
    } as ExampleGroup<SyncCall>

    let node = group.node
    XCTAssertEqual(node.kind, .group)
    XCTAssertEqual(node.name, "Root")
    XCTAssertEqual(node.isolation, .nonisolated)
    XCTAssertEqual(node.execution, .sync)
    XCTAssertEqual(node.children.map(\.name), ["first", "nested"])
    XCTAssertEqual(node.children.map(\.kind), [.example, .group])

    XCTAssertEqual(node.hooks(.beforeAll).map(\.name), ["before all: setup"])
    XCTAssertEqual(node.hooks(.aroundEach).map(\.name), ["around each: wrap"])
    XCTAssertEqual(node.hooks(.beforeEach).map(\.name),
                   ["before each", "before each: second"])
    XCTAssertEqual(node.hooks(.afterEach).map(\.name), ["after each"])
    XCTAssertEqual(node.hooks(.afterAll).map(\.name), ["after all"])
    XCTAssertEqual(node.hooks(.beforeEach).map(\.kind),
                   [.hook(.beforeEach), .hook(.beforeEach)])

    // Hooks stay with the group that declares them
    let nested = node.children[1]
    XCTAssertTrue(nested.isConcurrent)
    XCTAssertFalse(node.isConcurrent)
    XCTAssertEqual(nested.hooks(.beforeEach).count, 1)
    XCTAssertEqual(nested.hooks(.beforeAll).count, 0)
    XCTAssertEqual(nested.children.map(\.name), ["inner", "excluded"])
    XCTAssertEqual(nested.children.map(\.isExcluded), [false, true])
  }

  func testExamplesAndHooksHaveNoChildren() {
    let node = (describe("Root") {
      beforeEach {}
      it("example") {}
    } as ExampleGroup<SyncCall>).node

    for leaf in [node.children[0], node.hooks(.beforeEach)[0]] {
      XCTAssertTrue(leaf.children.isEmpty)
      XCTAssertTrue(leaf.hooks.isEmpty)
    }
  }

  func testAsyncGroup() {
    let node = (describe("Async") {
      beforeAll { await Task.yield() }
      it("awaits") { await Task.yield() }
    } as ExampleGroup<AsyncCall>).node

    XCTAssertEqual(node.isolation, .nonisolated)
    XCTAssertEqual(node.execution, .async)
    XCTAssertEqual(node.children[0].execution, .async)
    XCTAssertEqual(node.hooks(.beforeAll)[0].execution, .async)
  }

  func testFocusAndExcludedTraits() {
    let node = (describe("Root") {
      it("plain") {}
      context("deep") {
        fIt("focused") {}
      }
      xContext("out") {
        it("inside") {}
      }
    } as ExampleGroup<SyncCall>).node

    XCTAssertTrue(node.isDeepFocused)
    XCTAssertFalse(node.isFocused)
    XCTAssertEqual(node.children.map(\.isDeepFocused), [false, true, false])
    XCTAssertEqual(node.children.map(\.isExcluded), [false, false, true])
    XCTAssertTrue(node.children[1].children[0].isFocused)
  }

  func testSelectionKeepsExcludedNodesInTheTree() {
    let node = (describe("Root") {
      it("a") {}
      xIt("b") {}
      xContext("c") { it("inside") {} }
      context("d") {
        beforeEach("skipped", .excluded) {}
        beforeEach("kept") {}
        it("e") {}
      }
    } as ExampleGroup<SyncCall>).node

    // Everything is still there
    XCTAssertEqual(node.children.map(\.name), ["a", "b", "c", "d"])
    XCTAssertEqual(node.children.map(\.isSelected), [true, false, false, true])
    XCTAssertEqual(node.selectedChildren.map(\.name), ["a", "d"])
    // The children of an excluded group are kept and still resolve on their own
    XCTAssertEqual(node.children[2].children.map(\.name), ["inside"])
    XCTAssertEqual(node.children[2].children.map(\.isSelected), [true])

    let hooks = node.children[3].hooks(.beforeEach)
    XCTAssertEqual(hooks.map(\.isSelected), [false, true])
    XCTAssertEqual(node.children[3].selectedHooks(.beforeEach).map(\.name),
                   ["before each: kept"])
  }

  func testFocusSelectsOnlyFocusedBranches() {
    let node = (describe("Root") {
      it("plain") {}
      context("holds focus") {
        it("not focused") {}
        fIt("focused") {}
      }
      fContext("focused group") {
        it("inside") {}
      }
      xIt("excluded") {}
    } as ExampleGroup<SyncCall>).node

    XCTAssertEqual(node.children.map(\.isSelected), [false, true, true, false])
    // Focus applies within each group
    let holder = node.children[1]
    XCTAssertEqual(holder.children.map(\.isSelected), [false, true])
    // A focused group's own children aren't narrowed by it
    XCTAssertEqual(node.children[2].children.map(\.isSelected), [true])
  }

  func testRootIsAlwaysSelected() {
    let node = (describe("Root", .excluded) {
      it("a") {}
    } as ExampleGroup<SyncCall>).node
    XCTAssertTrue(node.isSelected)
    XCTAssertTrue(node.isExcluded)
  }

  /// The node tree agrees with what the group itself reports
  func testMatchesGroupFocus() {
    let group = describe("Root") {
      it("a") {}
      fContext("b") { it("c") {} }
    } as ExampleGroup<SyncCall>
    XCTAssertEqual(group.node.isDeepFocused, group.isDeepFocused)
  }
}

// The main-actor DSL functions are members of MainActorSuite, which would
// shadow the free functions above, so these live in their own class.
final class ExampleNodeMainActorTests: XCTestCase, MainActorSuite {
  @MainActor
  func testMainActorGroups() {
    let sync = (describe("Main") {
      aroundEach { callback in try callback() }
      it("runs") {}
    } as ExampleGroup<SyncMainCall>).node
    let async = (describe("Main async") {
      it("awaits") { await Task.yield() }
    } as ExampleGroup<AsyncMainCall>).node

    for node in [sync, async] {
      XCTAssertEqual(node.isolation, .mainActor)
      XCTAssertEqual(node.children[0].isolation, .mainActor)
    }
    XCTAssertEqual(sync.execution, .sync)
    XCTAssertEqual(async.execution, .async)
    XCTAssertEqual(sync.hooks(.aroundEach)[0].isolation, .mainActor)
  }
}

// MARK: - Traversal

/// The traversal over nodes should behave like the existing runners:
/// same calls in the same order, and the same first error.
final class NodeTraversalTests: XCTestCase {
  enum Scenario: CaseIterable {
    case clean, failingExample, failingBeforeEach, failingAfterEach
    case failingBeforeAll, failingAfterAll, focused
    case allExcluded, excludedHook, focusedInsideExcluded
  }

  func group(_ scenario: Scenario, _ log: Box<[String]>) -> ExampleGroup<AsyncCall> {
    @Sendable func maybeFail(_ failing: Bool, _ id: Int) throws {
      if failing { throw TestError(id: id) }
    }
    return describe("Root") {
      beforeAll { log.note("beforeAll"); try maybeFail(scenario == .failingBeforeAll, 1) }
      aroundEach("outer") { callback in
        log.note("outer>"); try await callback(); log.note("<outer")
      }
      aroundEach("inner") { callback in
        log.note("inner>"); try await callback(); log.note("<inner")
      }
      beforeEach { log.note("beforeEach"); try maybeFail(scenario == .failingBeforeEach, 2) }
      it("first") { log.note("first"); try maybeFail(scenario == .failingExample, 3) }
      xIt("excluded") { log.note("excluded") }
      context("nested") {
        beforeEach { log.note("nested beforeEach") }
        it("second") { log.note("second"); await Task.yield() }
        if scenario == .focused {
          fIt("focused") { log.note("focused") }
        }
        afterEach { log.note("nested afterEach") }
      }
      if scenario == .allExcluded {
        context("all excluded") {
          beforeAll { log.note("hooks of an empty group") }
          xIt("x") { log.note("x") }
          afterAll { log.note("hooks of an empty group") }
        }
      }
      if scenario == .excludedHook {
        context("hooked") {
          beforeEach("skipped", .excluded) { log.note("excluded hook") }
          it("h") { log.note("h") }
        }
      }
      if scenario == .focusedInsideExcluded {
        context("holder") {
          it("plain") { log.note("plain") }
          xContext("out") { fIt("focused but out") { log.note("out") } }
        }
      }
      afterEach { log.note("afterEach"); try maybeFail(scenario == .failingAfterEach, 4) }
      afterAll { log.note("afterAll"); try maybeFail(scenario == .failingAfterAll, 5) }
    }
  }

  func testAsyncNodesMatchRunner() async throws {
    for scenario in Scenario.allCases {
      let expected = Box([String]())
      let actual = Box([String]())
      var expectedError: (any Error)?
      var actualError: (any Error)?

      do { try await group(scenario, expected).run() }
      catch { expectedError = error }
      do { try await group(scenario, actual).node.traverse() }
      catch { actualError = error }

      XCTAssertEqual(actual.wrappedValue, expected.wrappedValue, "\(scenario)")
      XCTAssertEqual((actualError as? TestError)?.id, (expectedError as? TestError)?.id,
                     "\(scenario)")
      XCTAssertFalse(expected.wrappedValue.isEmpty)
    }
  }
}

final class NodeTraversalMainActorTests: XCTestCase, MainActorSuite {
  @MainActor
  func group(failing: Bool, _ log: Box<[String]>) -> ExampleGroup<SyncMainCall> {
    describe("Root") {
      beforeAll { log.note("beforeAll") }
      aroundEach { callback in
        MainActor.assertIsolated()
        log.note("around>"); try callback(); log.note("<around")
      }
      beforeEach { log.note("beforeEach") }
      it("first") { log.note("first"); if failing { throw TestError(id: 3) } }
      context("nested") {
        it("second") { log.note("second") }
      }
      afterEach { log.note("afterEach") }
      afterAll { log.note("afterAll") }
    }
  }

  @MainActor
  func testMainActorNodesMatchRunner() throws {
    for failing in [false, true] {
      let expected = Box([String]())
      let actual = Box([String]())
      var expectedError: (any Error)?
      var actualError: (any Error)?

      do { try group(failing: failing, expected).run() }
      catch { expectedError = error }
      do { try group(failing: failing, actual).node.traverseOnMainActor() }
      catch { actualError = error }

      XCTAssertEqual(actual.wrappedValue, expected.wrappedValue, "failing: \(failing)")
      XCTAssertEqual((actualError as? TestError)?.id, (expectedError as? TestError)?.id)
      XCTAssertFalse(expected.wrappedValue.isEmpty)
    }
  }
}
