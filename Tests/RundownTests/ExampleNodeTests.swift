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

  /// Unintended, probably, but kept from the old `filterFocusSkip` so that
  /// behavior doesn't change: a focused node inside an excluded subtree makes
  /// the groups around it count as focused, so their siblings are left out.
  func testFocusInsideExcludedSubtreeStillCountsAsFocus() {
    let node = (describe("Root") {
      it("sibling") {}
      context("holder") {
        it("plain") {}
        xContext("out") {
          fIt("focused but out") {}
        }
      }
    } as ExampleGroup<SyncCall>).node

    XCTAssertEqual(node.children.map(\.isSelected), [false, true])
    // Inside the holder nothing that runs is focused, so everything that
    // isn't excluded runs
    XCTAssertEqual(node.children[1].children.map(\.isSelected), [true, false])
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
