import XCTest
@testable import Rundown

final class ExampleNodeTests: XCTestCase {
  func testSyncGroupShape() {
    let group = describe("Root") {
      beforeAll("setup") {}
      aroundEachPeer("wrap") { callback in try callback() }
      beforeEachPeer {}
      beforeEachPeer("second") {}
      it("first") {}
      context("nested", .concurrent) {
        beforeEachPeer {}
        it("inner") {}
        xIt("excluded") {}
      }
      afterEachPeer {}
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
    XCTAssertEqual(node.hooks(.aroundEachPeer).map(\.name), ["around each peer: wrap"])
    XCTAssertEqual(node.hooks(.beforeEachPeer).map(\.name),
                   ["before each peer", "before each peer: second"])
    XCTAssertEqual(node.hooks(.afterEachPeer).map(\.name), ["after each peer"])
    XCTAssertEqual(node.hooks(.afterAll).map(\.name), ["after all"])
    XCTAssertEqual(node.hooks(.beforeEachPeer).map(\.kind),
                   [.hook(.beforeEachPeer), .hook(.beforeEachPeer)])

    // Hooks stay with the group that declares them
    let nested = node.children[1]
    XCTAssertTrue(nested.isConcurrent)
    XCTAssertFalse(node.isConcurrent)
    XCTAssertEqual(nested.hooks(.beforeEachPeer).count, 1)
    XCTAssertEqual(nested.hooks(.beforeAll).count, 0)
    XCTAssertEqual(nested.children.map(\.name), ["inner", "excluded"])
    XCTAssertEqual(nested.children.map(\.isExcluded), [false, true])
  }

  func testExamplesAndHooksHaveNoChildren() {
    let node = (describe("Root") {
      beforeEachPeer {}
      it("example") {}
    } as ExampleGroup<SyncCall>).node

    for leaf in [node.children[0], node.hooks(.beforeEachPeer)[0]] {
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
        beforeEachPeer("skipped", .excluded) {}
        beforeEachPeer("kept") {}
        it("e") {}
      }
    } as ExampleGroup<SyncCall>).node

    // Everything is still there
    XCTAssertEqual(node.children.map(\.name), ["a", "b", "c", "d"])
    XCTAssertEqual(node.children.map(\.isSelected), [true, false, false, true])
    XCTAssertEqual(node.selectedChildren.map(\.name), ["a", "d"])
    // The children of an excluded group stay in the tree but are not selected
    XCTAssertEqual(node.children[2].children.map(\.name), ["inside"])
    XCTAssertEqual(node.children[2].children.map(\.isSelected), [false])

    let hooks = node.children[3].hooks(.beforeEachPeer)
    XCTAssertEqual(hooks.map(\.isSelected), [false, true])
    XCTAssertEqual(node.children[3].selectedHooks(.beforeEachPeer).map(\.name),
                   ["before each peer: kept"])
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

  func testFocusInsideExcludedSubtreeDoesNotSuppressSiblings() {
    let group = describe("Root") {
      it("runs as a sibling") {}
      context("holder") {
        it("runs without focus") {}
        xContext("out") {
          fIt("stays excluded despite focus") {}
        }
      }
    } as ExampleGroup<SyncCall>
    let node = group.node

    XCTAssertFalse(group.isDeepFocused)
    XCTAssertFalse(node.isDeepFocused)
    XCTAssertEqual(node.children.map(\.isSelected), [true, true])
    XCTAssertEqual(node.children[1].children.map(\.isSelected), [true, false])
    XCTAssertFalse(node.children[1].children[1].children[0].isSelected)
  }

  func testExcludedRootDeselectsEveryDescendantAndHook() {
    let group = describe("Root", .excluded, .focused) {
      beforeAll {}
      context("nested") {
        beforeEach {}
        fIt("stays excluded with its root") {}
        afterEachPeer {}
      }
      afterAll {}
    } as ExampleGroup<SyncCall>
    let node = group.node

    XCTAssertFalse(node.isSelected)
    XCTAssertTrue(node.isExcluded)
    XCTAssertFalse(group.isDeepFocused)
    XCTAssertFalse(node.isDeepFocused)
    XCTAssertTrue(node.selectedChildren.isEmpty)
    XCTAssertTrue(node.selectedHooks(.beforeAll).isEmpty)
    XCTAssertTrue(node.selectedHooks(.afterAll).isEmpty)
    let nested = node.children[0]
    XCTAssertFalse(nested.isSelected)
    XCTAssertFalse(nested.children[0].isSelected)
    XCTAssertTrue(nested.selectedHooks(.beforeEach).isEmpty)
    XCTAssertTrue(nested.selectedHooks(.afterEachPeer).isEmpty)
    XCTAssertEqual(node.excludedFocusPaths(), [["Root"], ["Root", "nested", "stays excluded with its root"]])
  }

  func testExcludedFocusedElementsDoNotContributeFocus() {
    let group = describe("Root") {
      it("runs without focus") {}
      fIt("stays excluded despite focus", .excluded) {}
      fContext("excluded group", .excluded) { it("stays excluded with its group") {} }
    } as ExampleGroup<SyncCall>
    let node = group.node

    XCTAssertFalse(group.isDeepFocused)
    XCTAssertFalse(group.elements[1].isDeepFocused)
    XCTAssertFalse(group.elements[2].isDeepFocused)
    XCTAssertFalse(node.isDeepFocused)
    XCTAssertEqual(node.children.map(\.isSelected), [true, false, false])
    XCTAssertFalse(node.children[2].children[0].isSelected)
  }

  func testUnfocusedBranchesDeselectTheirDescendantsAndHooks() {
    let node = (describe("Root") {
      context("unfocused") {
        beforeAll {}
        context("nested") { it("stays unselected with its group") {} }
        afterAll {}
      }
      fIt("runs when selected") {}
    } as ExampleGroup<SyncCall>).node

    let unfocused = node.children[0]
    XCTAssertFalse(unfocused.isSelected)
    XCTAssertFalse(unfocused.children[0].isSelected)
    XCTAssertFalse(unfocused.children[0].children[0].isSelected)
    XCTAssertTrue(unfocused.selectedHooks(.beforeAll).isEmpty)
    XCTAssertTrue(unfocused.selectedHooks(.afterAll).isEmpty)
  }

  func testExcludedFocusDiagnosticsIncludeHiddenAndDirectFocus() {
    let node = (describe("Root") {
      fIt("runs when selected") {}
      context("unselected holder") {
        xContext("excluded") {
          fContext("focused group") { fIt("stays excluded with its group") {} }
        }
      }
      fIt("stays directly excluded", .excluded) {}
    } as ExampleGroup<SyncCall>).node

    XCTAssertFalse(node.children[1].isSelected)
    XCTAssertEqual(node.excludedFocusPaths(), [
      ["Root", "unselected holder", "excluded", "focused group"],
      ["Root", "unselected holder", "excluded", "focused group", "stays excluded with its group"],
      ["Root", "stays directly excluded"],
    ])
  }

  func testExcludedFocusDiagnosticsIgnoreValidFocusAndUnfocusedExclusions() {
    let node = (describe("Root") {
      fContext("active") { it("runs with its focused group") {} }
      xContext("excluded") { xIt("stays excluded") {} }
    } as ExampleGroup<SyncCall>).node

    XCTAssertTrue(node.excludedFocusPaths().isEmpty)
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
      aroundEachPeer { callback in try callback() }
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
    XCTAssertEqual(sync.hooks(.aroundEachPeer)[0].isolation, .mainActor)
  }
}
