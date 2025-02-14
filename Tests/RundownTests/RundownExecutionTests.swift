import XCTest
@testable import Rundown


@MainActor
final class RundownExecutionTests: Rundown.TestCase {

  func testOneItFails() throws {
    try spec {
      It("fails") {
        let expectedDescription = "OneItFails, fails"
        
        XCTAssertEqual(ExampleRun.current?.description, expectedDescription)
        XCTExpectFailure(strict: true) {
          $0.compactDescription.starts(with: expectedDescription)
        }
        XCTAssert(false)
      }
    }
  }
  
  @Example @ExampleBuilder<SyncCall>
  func oneItPeer() throws -> ExampleGroup<SyncCall> {
    It("works") {
      XCTAssert(true)
    }
  }

  func testExecuteDescribe() throws {
    let executed = Box(false)

    try spec("Running the test") {
      It("works") {
        executed.set()
      }
    }
    XCTAssert(executed.wrappedValue)
  }
  
  func testDescriptions() throws {
    try spec("ExampleRun") {
      Context("first context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRun.current!.description,
                         "ExampleRun, first context, has correct description")
        }
      }
      Context("second context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRun.current!.description,
                         "ExampleRun, second context, has correct description")
        }
      }
    }
  }

  func testBeforeAfterAll() throws {
    let didBefore = Box(false)
    let didIt = Box(false)
    let didAfter = Box(false)

    try Describe("Running hooks") {
      beforeAll {
        didBefore.set()
      }

      It("works") {
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
        It("iterates") {
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
        It("iterates 1") {
          count1.bump()
        }
        It("iterates 2") {
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

    try Describe("For loop") {
      for _ in 1...expected {
        beforeAll {
          beforeCount.bump()
        }
        It("iterates 1") {
          count1.bump()
        }
        It("iterates 2") {
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

  #if false
  func testWithin() throws {
    let executed = Box(false)

    try Describe("Within") {
      Within("inside a callback") { callback in
        try "".withCString { _ in
          try callback.call()
        }
      } example: {
        It("works") {
          executed.set()
        }
      }
    }.run()
    
    XCTAssert(executed.wrappedValue)
  }
  #endif
}
