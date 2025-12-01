import XCTest
@testable import Rundown


@MainActor
final class RundownExecutionTests: Rundown.TestCase {
  
  @TaskLocal static var taskLocal: Bool = false

  func testOneItFails() throws {
    try spec {
      it("fails") {
        let expectedDescription = "OneItFails, fails"
        
        XCTAssertEqual(ExampleRunner.current?.description, expectedDescription)
        XCTExpectFailure(strict: true) {
          $0.compactDescription.starts(with: expectedDescription)
        }
        XCTAssert(false)
      }
    }
  }
  
  @Example @ExampleBuilder<SyncCall>
  func oneItPeer() throws -> ExampleGroup<SyncCall> {
    it("works") {
      XCTAssert(true)
    }
  }

  func testAsyncIt() async throws {
    let ran = Box(false)

    try await Rundown.spec {
      it("does an async thing") {
        try await Task.sleep(for: .milliseconds(100))
        ran.set()
      }
    }

    XCTAssert(ran.wrappedValue)
  }

  func testMixedAsync() async throws {
    let ranBeforeAllAsync1 = Box(false)
    let ranBeforeAllAsync2 = Box(false)
    let ranBeforeAllSync1 = Box(false)
    let ranBeforeAllSync2 = Box(false)
    let ranAsync1 = Box(false)
    let ranSync1 = Box(false)
    let ranAsync2 = Box(false)
    let ranSync2 = Box(false)

    try await Rundown.spec {
      context("async then sync") {
        beforeAll("async before all") {
          try await Task.sleep(for: .milliseconds(100))
          ranBeforeAllAsync1.set()
        }
        beforeAll("sync before all") {
          ranBeforeAllSync1.set()
        }
        it("does an async thing") {
          try await Task.sleep(for: .milliseconds(100))
          ranAsync1.set()
        }
        it("does a sync thing") {
          ranSync1.set()
        }
      }
      context("sync then async") {
        beforeAll("sync before all") {
          ranBeforeAllSync2.set()
        }
        beforeAll("async before all") {
          try await Task.sleep(for: .milliseconds(100))
          ranBeforeAllAsync2.set()
        }
        it("does a sync thing") {
          ranSync2.set()
        }
        it("does an async thing") {
          try await Task.sleep(for: .milliseconds(100))
          ranAsync2.set()
        }
      }
    }

    XCTAssert(ranBeforeAllAsync1.wrappedValue, "beforeAll async 1 did not run")
    XCTAssert(ranBeforeAllAsync2.wrappedValue, "beforeAll async 2 did not run")
    XCTAssert(ranBeforeAllSync1.wrappedValue, "beforeAll sync 1 did not run")
    XCTAssert(ranBeforeAllSync2.wrappedValue, "beforeAll sync 2 did not run")
    XCTAssert(ranAsync1.wrappedValue, "it async 1 did not run")
    XCTAssert(ranAsync2.wrappedValue, "it async 2 did not run")
    XCTAssert(ranSync1.wrappedValue, "it sync 1 did not run")
    XCTAssert(ranSync2.wrappedValue, "it sync 2 did not run")
  }

  func testAsyncContext() async throws {
    let ran1 = Box(false)
    let ran2 = Box(false)
    
    try await Rundown.spec {
      context("two things") {
        it("does thing 1") {
          try await Task.sleep(for: .milliseconds(100))
          ran1.set()
        }
        it("does thing 2") {
          try await Task.sleep(for: .milliseconds(100))
          ran2.set()
        }
      }
    }
    
    XCTAssert(ran1.wrappedValue)
    XCTAssert(ran2.wrappedValue)
  }

  @Example @ExampleBuilder<AsyncCall>
  func oneItAsyncMacro() async throws -> ExampleGroup<AsyncCall> {
    it("works") {
      try await Task.sleep(nanoseconds: 500)
      XCTAssert(true)
    }
  }

  func testExecuteDescribe() throws {
    let executed = Box(false)

    try spec("Running the test") {
      it("works") {
        executed.set()
      }
    }
    XCTAssert(executed.wrappedValue)
  }
  
  func testDescriptions() throws {
    try spec("ExampleRunner") {
      context("first context") {
        it("has correct description") {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRunner, first context, has correct description")
        }
      }
      context("second context") {
        it("has correct description") {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRunner, second context, has correct description")
        }
      }
    }
  }

  func testBeforeAfterAll() throws {
    let didBefore = Box(false)
    let didIt = Box(false)
    let didAfter = Box(false)

    try describe("Running hooks") {
      beforeAll {
        didBefore.set()
      }

      it("works") {
        didIt.set()
      }

      afterAll {
        didAfter.set()
      }
    }.run()
    XCTAssert(didBefore.wrappedValue, "BeforeAll did not execute")
    XCTAssert(didIt.wrappedValue, "It did not execute")
    XCTAssert(didAfter.wrappedValue, "AfterAll did not execute")
  }

  func testSingleItForLoop() throws {
    let expected = 3
    let count = Box(0)

    try spec("For loop") {
      for _ in 1...expected {
        it("iterates") {
          count.bump()
        }
      }
    }
    XCTAssertEqual(count.wrappedValue, expected)
  }

  func testDoubleItForLoop() throws {
    let expected = 3
    let count1 = Box(0)
    let count2 = Box(0)

    try spec("For loop") {
      for _ in 1...expected {
        it("iterates 1") {
          count1.bump()
        }
        it("iterates 2") {
          count2.bump()
        }
      }
    }
    XCTAssertEqual(count1.wrappedValue, expected)
    XCTAssertEqual(count2.wrappedValue, expected)
  }

  func testHookForLoop() throws {
    let expected = 3
    let beforeCount = Box(0)
    let count1 = Box(0)
    let count2 = Box(0)
    let afterCount = Box(0)

    try describe("For loop") {
      for _ in 1...expected {
        beforeAll {
          beforeCount.bump()
        }
        it("iterates 1") {
          count1.bump()
        }
        it("iterates 2") {
          count2.bump()
        }
        afterAll {
          afterCount.bump()
        }
      }
    }.run()
    XCTAssertEqual(count1.wrappedValue, expected)
    XCTAssertEqual(count2.wrappedValue, expected)
    XCTAssertEqual(beforeCount.wrappedValue, expected)
    XCTAssertEqual(afterCount.wrappedValue, expected)
  }

  func testAroundEachAsync() async throws {
    let result = Box([String]())

    try await describe("ArounchEach") {
      aroundEach { (callback) in
        result.wrappedValue.append("around start")
        try await RundownExecutionTests.$taskLocal.withValue(true) {
          try await callback()
        }
        result.wrappedValue.append("around end")
      }
      
      it("works") {
        try await Task.sleep(nanoseconds: 500)
        result.wrappedValue.append("it")
      }
    }.run()
    
    XCTAssertEqual(result.wrappedValue,
                   ["around start", "it", "around end"])
  }

  func testAroundEachWithHooksAsync() async throws {
    let result = Box([String]())
    
    try await describe("ArounchEach") {
      beforeAll {
        result.wrappedValue.append("beforeAll")
      }
      aroundEach { (callback) in
        result.wrappedValue.append("around start")
        try await RundownExecutionTests.$taskLocal.withValue(true) {
          try await callback()
        }
        result.wrappedValue.append("around end")
      }
      beforeEach {
        result.wrappedValue.append("beforeEach")
      }
      
      it("works") {
        result.wrappedValue.append("it")
      }
      
      afterEach {
        result.wrappedValue.append("afterEach")
      }
    }.run()
    
    XCTAssertEqual(result.wrappedValue,
      ["beforeAll",
       "around start",
       "beforeEach", "it", "afterEach",
       "around end"])
  }
}
