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
  
  @Example @ExampleBuilder
  func oneItPeer() throws -> ExampleGroup {
    It("works") {
      XCTAssert(true)
    }
  }

  func testExecuteDescribe() throws {
    var executed = false

    try Describe("Running the test") {
      It("works") {
        executed = true
      }
    }.run()
    XCTAssert(executed)
  }
  
  func testDescriptions() throws {
    try Describe("ExampleRun") {
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
    }.run()
  }

  func testBeforeAfterAll() throws {
    var didBefore = false
    var didIt = false
    var didAfter = false

    try Describe("Running hooks") {
      BeforeAll {
        didBefore = true
      }

      It("works") {
        didIt = true
      }

      AfterAll {
        didAfter = true
      }
    }.run()
    XCTAssert(didBefore, "BeforeAll did not execute")
    XCTAssert(didIt, "It did not execute")
    XCTAssert(didAfter, "AfterAll did not execute")
  }

  func testSingleItForLoop() throws {
    let expected = 3
    var count = 0

    try Describe("For loop") {
      for _ in 1...expected {
        It("iterates") {
          count += 1
        }
      }
    }.run()
    XCTAssertEqual(count, expected)
  }

  func testDoubleItForLoop() throws {
    let expected = 3
    var count1 = 0
    var count2 = 0

    try Describe("For loop") {
      for _ in 1...expected {
        It("iterates 1") {
          count1 += 1
        }
        It("iterates 2") {
          count2 += 1
        }
      }
    }.run()
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
  }

  func testHookForLoop() throws {
    let expected = 3
    var beforeCount = 0
    var count1 = 0
    var count2 = 0
    var afterCount = 0

    try Describe("For loop") {
      for _ in 1...expected {
        BeforeAll {
          beforeCount += 1
        }
        It("iterates 1") {
          count1 += 1
        }
        It("iterates 2") {
          count2 += 1
        }
        AfterAll {
          afterCount += 1
        }
      }
    }.run()
    XCTAssertEqual(count1, expected)
    XCTAssertEqual(count2, expected)
    XCTAssertEqual(beforeCount, expected)
    XCTAssertEqual(afterCount, expected)
  }
  
  func testWithin() throws {
    var executed = false

    try Describe("Within") {
      Within("inside a callback") { callback in
        try "".withCString { _ in
          try callback()
        }
      } example: {
        It("works") {
          executed = true
        }
      }
    }.run()
    
    XCTAssert(executed)
  }
}
