#if canImport(Darwin) && compiler(>=6.4)
import Foundation
import os
import RundownSwiftTesting
import Testing

private struct DiscoverySelectionFixture: Sendable {
  private let focused = ProcessInfo.processInfo.environment["RUNDOWN_DISCOVERY_SELECTION_UNFOCUSED"] != "1"
  private let executed = OSAllocatedUnfairLock(initialState: Set<String>())

  var expected: Set<String> {
    focused ? ["Chosen", "Holder example"]
      : ["Chosen", "Holder example", "Unfocused nested example", "Unfocused root example"]
  }

  var examples: Set<String> { executed.withLock { $0 } }

  @ExampleBuilder<AsyncCall>
  func build() -> ExampleGroup<AsyncCall> {
    beforeAll("excluded", .excluded) { Issue.record("Ran an excluded beforeAll") }
    aroundEachPeer(.excluded) { _ in
      Issue.record("Ran an excluded aroundEachPeer")
    }
    beforeEachPeer("excluded", .excluded) { Issue.record("Ran an excluded beforeEachPeer") }

    it("Unfocused root example") { record("Unfocused root example") }
    context("Nested focus") {
      it("Unfocused nested example") { record("Unfocused nested example") }
      it("Chosen", focused ? [.focused] : []) { record("Chosen") }
      it("Excluded focused example", focused ? [.excluded, .focused] : [.excluded]) {
        Issue.record("Ran an excluded focused example")
      }
      afterEachPeer("excluded", .excluded) { Issue.record("Ran an excluded nested afterEachPeer") }
    }
    context("Holder") {
      it("Holder example") { record("Holder example") }
      xContext("Excluded nested branch") {
        it("Hidden focus", focused ? [.focused] : []) {
          Issue.record("Ran inside an excluded nested branch")
        }
      }
    }
    xContext("Excluded root branch") {
      beforeAll { Issue.record("Set up an excluded branch") }
      it("Excluded descendant") { Issue.record("Ran inside an excluded root branch") }
    }
    afterEachPeer("excluded", .excluded) { Issue.record("Ran an excluded afterEachPeer") }
    afterAll("excluded", .excluded) { Issue.record("Ran an excluded afterAll") }
    afterAll {
      print("discovery selection \(ExampleRunner.current?.path.first ?? "unknown"): \(examples.sorted().joined(separator: ", "))")
    }
  }

  private func record(_ name: String) {
    #expect(expected.contains(name))
    _ = executed.withLock { $0.insert(name) }
  }
}

@Spec
struct DiscoverySelectionSpec {
  var spec: SpecBody { return DiscoverySelectionFixture().build() }
}

@Spec(.leaves)
struct DiscoverySelectionLeafSpec {
  var spec: SpecBody { return DiscoverySelectionFixture().build() }
}

struct DiscoverySelectionTests: SwiftTestingSuite {
  @Test func hostSelectionBaseline() async throws {
    let fixture = DiscoverySelectionFixture()
    try await spec("Host selection baseline", builder: fixture.build)
    #expect(fixture.examples == fixture.expected)
  }
}
#endif
