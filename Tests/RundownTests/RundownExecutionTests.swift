import XCTest
import Rundown

@MainActor
final class RundownExecutionTests: Rundown.TestCase {
  @TestExample
  func testOneIt() throws {
    It("works") {
      XCTAssert(true)
    }
  }

  @TestExample
  func testOneItFails() throws {
    It("fails") {
      XCTExpectFailure(strict: true) {
        $0.compactDescription.starts(with: "OneItFails, fails")
      }
      XCTAssert(false)
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

  func testBeforeAfterEach() throws {
    var beforeCount = 0
    var itCount = 0
    var afterCount = 0

    try Describe("Running 'each' hooks") {
      BeforeEach {
        beforeCount += 1
      }

      It("runs first test") {
        XCTAssertEqual(beforeCount, 1, "BeforeEach missed")
        XCTAssertEqual(afterCount, 0, "AfterEach missed")
        itCount += 1
      }

      Context("in a context") {
        It("runs second test") {
          XCTAssertEqual(beforeCount, 2, "BeforeEach missed")
          XCTAssertEqual(afterCount, 1, "AfterEach missed")
          itCount += 1
        }
      }

      AfterEach {
        afterCount += 1
      }
    }.runActivity()
    XCTAssertEqual(beforeCount, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount, 2, "AfterEach didn't run correctly")
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
  
  @TaskLocal static var local: Int = 0
  
  func testWithinTaskLocal() throws {
    try Describe("Within") {
      for value in 1...2 {
        Within("with task local as \(value)") { callback in
          try Self.$local.withValue(value) {
            try callback()
          }
        } example: {
          It("has correct value") {
            XCTAssert(Self.$local.wrappedValue == value)
          }
        }
      }
    }.runActivity()
  }
}
