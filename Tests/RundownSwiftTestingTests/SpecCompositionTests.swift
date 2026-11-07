import os
import RundownSwiftTesting
import Testing

struct SpecCompositionTests: SwiftTestingSuite {
  @TaskLocal private static var fixture: String?

  private func selectedGroup(_ trace: OSAllocatedUnfairLock<[String]>,
                             values: [Int]) -> ExampleGroup<AsyncCall> {
    context("generated group") {
      beforeAll { trace.withLock { $0.append("group setup") } }
      let excludedWrapper: AroundEach<AsyncCall> = aroundEach(.excluded) { _ in
        Issue.record("Entered an excluded wrapper")
      }
      excludedWrapper
      aroundEach { run in
        #expect(Self.fixture == "root")
        try await Self.$fixture.withValue("nested") { try await run() }
        #expect(Self.fixture == "root")
      }
      beforeEach {
        #expect(Self.fixture == "nested")
        trace.withLock { $0.append("example setup") }
      }
      for value in values {
        if value.isMultiple(of: 2) {
          let example: It<SyncCall> = fIt("value \(value)") {
            #expect(Self.fixture == "nested")
            #expect(ExampleRunner.current?.path == ["Composition", "generated group", "value \(value)"])
            trace.withLock { $0.append("value \(value)") }
          }
          example
        }
        else {
          it("unfocused \(value)") { Issue.record("Ran an unfocused example") }
        }
      }
      fIt("excluded despite focus", .excluded) { Issue.record("Ran an excluded example") }
      afterEach {
        #expect(Self.fixture == "nested")
        trace.withLock { $0.append("example teardown") }
      }
      afterAll { trace.withLock { $0.append("group teardown") } }
    }
  }

  @Test func asyncSpecComposesAHelperGroupWithMixedElementsAndSelection() async throws {
    let trace = OSAllocatedUnfairLock(initialState: [String]())

    try await spec("Composition") {
      beforeAll { trace.withLock { $0.append("root setup") } }
      aroundEach { run in
        trace.withLock { $0.append("root wrapper enter") }
        try await Self.$fixture.withValue("root") { try await run() }
        #expect(Self.fixture == nil)
        trace.withLock { $0.append("root wrapper exit") }
      }
      beforeEach { trace.withLock { $0.append("root element setup") } }
      it("unfocused sibling") { Issue.record("Ran an unfocused sibling") }
      selectedGroup(trace, values: [1, 2, 3, 4])
      xContext("excluded group") {
        beforeAll { Issue.record("Set up an excluded group") }
        fIt("focused descendant") { Issue.record("Ran an excluded descendant") }
        afterAll { Issue.record("Tore down an excluded group") }
      }
      fIt("async sibling") {
        await Task.yield()
        #expect(Self.fixture == "root")
        trace.withLock { $0.append("async sibling") }
      }
      afterEach { trace.withLock { $0.append("root element teardown") } }
      afterAll { trace.withLock { $0.append("root teardown") } }
    }

    #expect(ExampleRunner.current == nil)
    #expect(trace.withLock { $0 } == [
      "root setup",
      "root wrapper enter", "root element setup", "group setup",
      "example setup", "value 2", "example teardown",
      "example setup", "value 4", "example teardown",
      "group teardown", "root element teardown", "root wrapper exit",
      "root wrapper enter", "root element setup", "async sibling",
      "root element teardown", "root wrapper exit", "root teardown",
    ])
  }
}
