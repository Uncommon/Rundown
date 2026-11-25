import os
import RundownSwiftTesting
import Testing

struct SelectionTests: SwiftTestingSuite {
  private func build(_ events: OSAllocatedUnfairLock<[String]>, activeFocus: Bool) -> ExampleGroup<SyncCall> {
    describe("Selection") {
      beforeAll { events.withLock { $0.append("setup") } }
      it("runs as a sibling") { events.withLock { $0.append("sibling") } }
      context("holder") {
        it("runs without focus") { events.withLock { $0.append("plain") } }
        xContext("excluded") {
          beforeAll { Issue.record("Set up an excluded group") }
          fIt("stays excluded despite focus") { Issue.record("Ran excluded focus") }
          afterAll { Issue.record("Tore down an excluded group") }
        }
      }
      it("runs when selected", activeFocus ? [.focused] : []) { events.withLock { $0.append("chosen") } }
      fIt("stays directly excluded", .excluded) { Issue.record("Ran an excluded example") }
      afterAll { events.withLock { $0.append("cleanup") } }
    }
  }

  @Test(arguments: [false, true], [false, true])
  func excludedFocusDoesNotSuppressSiblings(activeFocus: Bool, asynchronous: Bool) async throws {
    let events = OSAllocatedUnfairLock(initialState: [String]())
    if asynchronous {
      try await spec { build(events, activeFocus: activeFocus) }
    }
    else {
      try runSync(events, activeFocus: activeFocus)
    }

    let expected = activeFocus ? ["setup", "chosen", "cleanup"]
      : ["setup", "sibling", "plain", "chosen", "cleanup"]
    #expect(events.withLock { $0 } == expected)
  }

  // Keep overload resolution in a synchronous function so this exercises the
  // sync adapter even though the parameterized host test is async.
  private func runSync(_ events: OSAllocatedUnfairLock<[String]>, activeFocus: Bool) throws {
    try spec { build(events, activeFocus: activeFocus) }
  }
}
