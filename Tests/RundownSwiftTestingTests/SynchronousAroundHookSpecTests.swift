import os
import RundownSwiftTesting
import Testing

private func synchronousWrappedHelper(peer: Bool) -> ExampleGroup<SyncCall> {
  if peer {
    return context("helper") {
      aroundEachPeer("scope", fileID: "Client/SyncHelper.swift", filePath: "/client/SyncHelper.swift", line: 41, column: 7) { run in
        Issue.record("Ran an incompatible peer wrapper")
        try run()
      }
      it("runs inside its scope") { Issue.record("Ran an incompatible helper") }
    }
  }
  return context("helper") {
    aroundEach("scope", fileID: "Client/SyncHelper.swift", filePath: "/client/SyncHelper.swift", line: 41, column: 7) { run in
      Issue.record("Ran an incompatible wrapper")
      try run()
    }
    it("runs inside its scope") { Issue.record("Ran an incompatible helper") }
  }
}

private enum CompositionIssueProbe {
  @TaskLocal static var issues: OSAllocatedUnfairLock<[Issue]>?

  static let capture = IssueHandlingTrait.compactMapIssues { issue in
    guard let issues, issue.error is SynchronousAroundHookError
    else { return issue }
    issues.withLock { $0.append(issue) }
    return nil
  }
}

struct SynchronousAroundHookSpecTests: SwiftTestingSuite {
  @Test(CompositionIssueProbe.capture, arguments: [false, true])
  func asyncSpecReportsTheWrapperDeclarationBeforeSetup(peer: Bool) async throws {
    let issues = OSAllocatedUnfairLock(initialState: [Issue]())
    try await CompositionIssueProbe.$issues.withValue(issues) {
      try await spec("Composition") {
        beforeAll { Issue.record("Ran setup before rejecting an incompatible helper") }
        it("runs before the helper") { Issue.record("Ran a sibling before rejecting the helper") }
        synchronousWrappedHelper(peer: peer)
        afterAll { Issue.record("Tore down a spec that never entered setup") }
      }
    }

    let recorded = issues.withLock { $0 }
    #expect(recorded.count == 1)
    let path = ["Composition", "helper", peer ? "around each peer: scope" : "around each: scope"]
    #expect((recorded.first?.error as? SynchronousAroundHookError)?.path == path)
    #expect(recorded.first?.comments.map(\.rawValue) == [path.joined(separator: ", ")])
    #expect(recorded.first?.sourceLocation?.fileID == "Client/SyncHelper.swift")
    #expect(recorded.first?.sourceLocation?.line == 41)
    #expect(recorded.first?.sourceLocation?.column == 7)
  }
}

#if canImport(Darwin) && compiler(>=6.4)
private struct ExpectSynchronousAroundHookIssue: SuiteTrait, TestScoping {
  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    try await withKnownIssue {
      try await function()
    } matching: { issue in
      (issue.error as? SynchronousAroundHookError)?.path == ["SynchronousDiscoveryCompositionSpec", "helper", "around each: scope"]
    }
  }
}

@Suite(ExpectSynchronousAroundHookIssue())
@Spec
struct SynchronousDiscoveryCompositionSpec {
  var spec: SpecBody {
    beforeAll { Issue.record("Ran root setup before rejecting an incompatible discovery case") }
    it("runs before the helper") { Issue.record("Ran a case before rejecting the helper") }
    synchronousWrappedHelper(peer: false)
    afterAll { Issue.record("Tore down a spec that never entered setup") }
  }
}
#endif
