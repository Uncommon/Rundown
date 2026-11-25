import XCTest
@testable import Rundown

final class DeclarationLocationTests: XCTestCase {
  func testDirectInitializersAndSyncToAsyncConversionKeepLocations() {
    let hookLine = #line + 1
    let hook = TestHook<BeforeAllPhase, SyncCall>("setup") {}
    let exampleLine = #line + 1
    let example = It<SyncCall>("direct") {}
    let arrayExampleLine = #line + 1
    let arrayExample = It<SyncCall>("array", [], execute: {})
    let group: ExampleGroup<SyncCall> = describe("original") {
      hook
      example
      context("nested") { arrayExample }
    }
    let sync = group.node
    let async = ExampleGroup<AsyncCall>(fromSync: group).named("converted").node

    XCTAssertEqual(sync.hooks(.beforeAll).first?.declarationLocation,
                   DeclarationLocation(fileID: #fileID, filePath: #filePath, line: hookLine, column: 50))
    XCTAssertEqual(sync.children[0].declarationLocation?.line, exampleLine)
    XCTAssertEqual(sync.children[1].children[0].declarationLocation?.line, arrayExampleLine)
    XCTAssertEqual(async.hooks(.beforeAll).first?.declarationLocation,
                   sync.hooks(.beforeAll).first?.declarationLocation)
    XCTAssertEqual(async.children[0].declarationLocation, sync.children[0].declarationLocation)
    XCTAssertEqual(async.children[1].children[0].declarationLocation,
                   sync.children[1].children[0].declarationLocation)
  }

  func testHookPromotionKeepsOriginalDeclaration() {
    let line = #line + 1
    let hook: TestHook<BeforeEachPhase, SyncCall> = beforeEach {}
    let group: ExampleGroup<AsyncCall> = describe("async") {
      hook
      it("async") { await Task.yield() }
    }
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.execution, .async)
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.declarationLocation?.line, line)
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.declarationLocation, hook.declarationLocation)
  }

  func testConvenienceExamplesForwardAllLocationComponents() {
    let group: ExampleGroup<SyncCall> = describe("shortcuts") {
      fIt("focused", fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9) {}
      xIt("excluded", fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9) {}
      it("array", [], fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9) {}
      fIt("fixture", using: Fixture({ 1 }), fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9) { _ in }
      xIt("excluded fixture", using: Fixture({ 1 }), fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9) { _ in }
    }
    for node in group.node.children {
      XCTAssertEqual(node.declarationLocation,
                     DeclarationLocation(fileID: "Client/Tests.swift", filePath: "/client/Tests.swift", line: 71, column: 9))
    }
  }
}

final class MainActorDeclarationLocationTests: XCTestCase, MainActorSuite {
  @MainActor
  func testMainActorHookPromotionKeepsOriginalDeclaration() {
    let line = #line + 1
    let hook: TestHook<BeforeEachPhase, SyncMainCall> = beforeEach {}
    let group: ExampleGroup<AsyncMainCall> = describe("async main") {
      hook
      it("async") { await Task.yield() }
    }
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.execution, .async)
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.declarationLocation?.line, line)
    XCTAssertEqual(group.node.hooks(.beforeEach).first?.declarationLocation, hook.declarationLocation)
  }
}
