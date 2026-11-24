import XCTest
@testable import Rundown

@MainActor
private final class MainActorFixtureValue {
  var uses = 0
}

@MainActor
final class MainActorFixtureTests: Rundown.TestCase {
  func testSyncMainActorFixtureInXCTestActivities() throws {
    let log = Box([String]())
    let fixture = MainActorFixture {
      MainActor.preconditionIsolated()
      XCTAssertEqual(ExampleRunner.current?.description, "UI, nested, uses a main-actor fixture, fixture setup")
      log.note("setup")
      return MainActorFixtureValue()
    } cleanup: { value in
      MainActor.preconditionIsolated()
      XCTAssertEqual(value.uses, 1)
      XCTAssertEqual(ExampleRunner.current?.description, "UI, nested, uses a main-actor fixture, fixture cleanup")
      log.note("cleanup")
    }
    try spec("UI") {
      context("nested") {
        fIt("uses a main-actor fixture", using: fixture) { value in
          MainActor.preconditionIsolated()
          XCTAssertEqual(ExampleRunner.activity?.name, "uses a main-actor fixture")
          value.uses += 1
          log.note("body")
        }
        xIt("does not run when excluded", using: fixture) { _ in XCTFail("Excluded") }
        afterEachPeer { log.note("afterEachPeer") }
      }
    }
    XCTAssertEqual(log.wrappedValue, ["setup", "body", "cleanup", "afterEachPeer"])
  }

  func testAsyncMainActorLifecyclesAndSyncFactoriesInAsyncExamples() async throws {
    let log = Box([String]())
    let asyncFixture = AsyncMainActorFixture {
      await Task.yield()
      MainActor.preconditionIsolated()
      return MainActorFixtureValue()
    } cleanup: { value in
      await Task.yield()
      MainActor.preconditionIsolated()
      XCTAssertEqual(value.uses, 1)
      log.note("async cleanup")
    }
    let syncFixture = MainActorFixture { MainActorFixtureValue() } cleanup: { value in
      MainActor.preconditionIsolated()
      XCTAssertEqual(value.uses, 1)
      log.note("sync cleanup")
    }
    let ordinaryFixture = Fixture { 42 }
    let group: ExampleGroup<AsyncMainCall> = describe("UI") {
      it("cleans up an asynchronous main-actor fixture after failure", using: asyncFixture) { value in
        await Task.yield()
        MainActor.preconditionIsolated()
        value.uses += 1
        throw TestError(id: 1)
      }
      it("uses a synchronous main-actor fixture asynchronously", using: syncFixture) { value in
        await Task.yield()
        MainActor.preconditionIsolated()
        value.uses += 1
      }
      it("uses an ordinary fixture asynchronously", using: ordinaryFixture) { value in
        await Task.yield()
        MainActor.preconditionIsolated()
        XCTAssertEqual(value, 42)
      }
      it("uses an ordinary fixture synchronously", using: ordinaryFixture) { XCTAssertEqual($0, 42) }
    }
    do {
      try await group.run()
      XCTFail("Expected the body error")
    } catch {
      XCTAssertEqual(error as? TestError, TestError(id: 1))
    }
    XCTAssertEqual(log.wrappedValue, ["async cleanup", "sync cleanup"])
  }

  func testXCTestRecordsBodyAndCleanupErrorsSeparately() throws {
    let issues = Box([XCTIssue]())
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      guard issue.type == .uncaughtException,
            issue.compactDescription.hasPrefix("UI, reports example and cleanup failures ")
              || issue.compactDescription.hasPrefix("UI, reports example and cleanup failures, fixture cleanup ")
      else { return false }
      issues.wrappedValue.append(issue)
      return true
    }
    let fixture = MainActorFixture { MainActorFixtureValue() } cleanup: { _ in
      throw TestError(id: 2)
    }
    try XCTExpectFailure("Both lifecycle errors should be recorded", options: options) {
      try spec("UI") {
        it("reports example and cleanup failures", using: fixture) { _ in throw TestError(id: 1) }
      }
    }
    XCTAssertEqual(issues.wrappedValue.count, 2)
    XCTAssertEqual(issues.wrappedValue.map { $0.associatedError as? TestError }, [TestError(id: 1), TestError(id: 2)])
  }

  func testXCTestUnwrapInFactoryIsNotReportedTwice() throws {
    let issues = Box([XCTIssue]())
    let options = XCTExpectedFailure.Options()
    options.issueMatcher = { issue in
      guard issue.type == .assertionFailure,
            issue.compactDescription.hasPrefix("UI, reports a failed setup requirement, fixture setup ")
      else { return false }
      issues.wrappedValue.append(issue)
      return true
    }
    let fixture = MainActorFixture {
      try XCTUnwrap(nil as MainActorFixtureValue?)
    } cleanup: { _ in XCTFail("No value constructed") }
    try XCTExpectFailure("XCTUnwrap records its own failure", options: options) {
      try spec("UI") {
        it("reports a failed setup requirement", using: fixture) { _ in XCTFail("Setup failed") }
      }
    }
    XCTAssertEqual(issues.wrappedValue.count, 1)
  }
}
