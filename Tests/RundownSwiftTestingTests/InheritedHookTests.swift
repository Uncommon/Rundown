import os
import RundownSwiftTesting
import Testing

struct InheritedHookTests: SwiftTestingSuite {
  @Test
  func inheritedHooksKeepConcurrentBranchesSeparate() async throws {
    let insideRoot = TaskLocal(wrappedValue: false)
    let insideNested = TaskLocal(wrappedValue: false)
    let events = OSAllocatedUnfairLock(initialState: [String]())
    let fixture = AsyncFixture {
      #expect(insideRoot.get())
      #expect(insideNested.get())
      await Task.yield()
      return 42
    } cleanup: { _ in
      #expect(insideRoot.get())
      #expect(insideNested.get())
    }

    try await spec("root") {
      aroundEach { run in
        #expect(!insideRoot.get())
        try await insideRoot.withValue(true) { try await run() }
        #expect(!insideRoot.get())
      }
      beforeEach {
        #expect(insideRoot.get())
        #expect(insideNested.get())
        events.withLock { $0.append("root before") }
      }
      context("workers", .concurrent) {
        beforeAll { #expect(!insideRoot.get()) }
        aroundEach { run in
          #expect(insideRoot.get())
          #expect(!insideNested.get())
          try await insideNested.withValue(true) { try await run() }
        }
        beforeEach { events.withLock { $0.append("nested before") } }
        for index in 0..<12 {
          context("worker \(index)") {
            it("runs inherited hooks in its concurrent branch", using: fixture) { value in
              #expect(value == 42)
              await Task.yield()
              #expect(ExampleRunner.current?.path == ["root", "workers", "worker \(index)", "runs inherited hooks in its concurrent branch"])
              events.withLock { $0.append("body") }
            }
          }
        }
        afterEach {
          #expect(insideRoot.get())
          #expect(insideNested.get())
          events.withLock { $0.append("nested after") }
        }
        afterAll { #expect(!insideRoot.get()) }
      }
      afterEach { events.withLock { $0.append("root after") } }
    }

    for event in ["root before", "nested before", "body", "nested after", "root after"] {
      #expect(events.withLock { $0.filter { $0 == event }.count } == 12)
    }
    #expect(!insideRoot.get())
    #expect(!insideNested.get())
  }
}

#if canImport(Darwin) && compiler(>=6.4)
@ExampleBuilder<AsyncCall>
private func inheritedDiscoveryBody() -> SpecBody {
  let insideRoot = TaskLocal(wrappedValue: false)
  let trace = OSAllocatedUnfairLock(initialState: [String]())
  beforeAll { trace.withLock { $0.append("all>") } }
  aroundEach { run in
    trace.withLock { $0.append("around>") }
    defer { trace.withLock { $0.append("<around") } }
    try await insideRoot.withValue(true) { try await run() }
  }
  beforeEach {
    #expect(insideRoot.get())
    trace.withLock { $0.append("before") }
  }
  context("nested") {
    beforeAll { #expect(!insideRoot.get()) }
    it("one") {
      #expect(insideRoot.get())
      trace.withLock { $0.append("body") }
    }
    context("deeper") {
      it("two") {
        await Task.yield()
        #expect(insideRoot.get())
        trace.withLock { $0.append("body") }
      }
    }
    afterAll { #expect(!insideRoot.get()) }
  }
  it("sibling") {
    #expect(insideRoot.get())
    trace.withLock { $0.append("body") }
  }
  afterEach { trace.withLock { $0.append("after") } }
  afterAll {
    let events = trace.withLock { $0 }
    let count = events.filter { $0 == "body" }.count
    #expect(count > 0)
    #expect(events.first == "all>")
    #expect(events.filter { $0 == "all>" }.count == 1)
    // Generated leaf cases may overlap; task-local assertions above check
    // each execution's wrapper scope without assuming a global event order.
    for event in ["around>", "before", "after", "<around"] {
      #expect(events.filter { $0 == event }.count == count)
    }
  }
}

@Spec
struct InheritedHookDiscoverySpec {
  var spec: SpecBody { return inheritedDiscoveryBody() }
}

@Spec(.leaves)
struct InheritedHookLeafDiscoverySpec {
  var spec: SpecBody { return inheritedDiscoveryBody() }
}
#endif
