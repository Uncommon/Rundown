import XCTest
@testable import Rundown

@MainActor
final class RundownTests: Rundown.TestCase {
  
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

  func testBeforeAfterEach() throws {
    var beforeCount = 0
    var itCount = 0
    var afterCount = 0

    try spec("Running 'each' hooks") {
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
    }
    XCTAssertEqual(beforeCount, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount, 2, "AfterEach didn't run correctly")
  }

  @TaskLocal static var local: Int = 0
  
  func testWithinTaskLocal() throws {
    try spec("Within") {
      for value in 1...2 {
        Within("with task local as \(value)") { callback in
          try Self.$local.withValue(value) {
            try callback()
          }
        } example: {
          It("has correct value") {
            XCTAssert(Self.$local.wrappedValue == value)
            XCTAssertEqual(ExampleRun.activity?.name, "has correct value")
            XCTAssertEqual(ExampleRun.current?.description,
                           "Within, with task local as \(value), has correct value")
          }
        }
      }
    }
  }
  
  func testSkip() throws {
    var ranSecond = false
    var ranAfterEach = false
    var ranAfterAll1 = false
    var ranAfterAll2 = false

    try spec {
      Context("no hooks") {
        It("skips") {
          try XCTSkipIf(true, "skip It")
        }
        It("runs second thing") {
          ranSecond = true
        }
      }
      Context("skipping in BeforeAll") {
        BeforeAll {
          try XCTSkipIf(true, "skip BeforeAll")
        }
        BeforeEach {
          XCTFail("should not run BeforeEach")
        }
        It("skips elements") {
          XCTFail("should not run It")
        }
        AfterEach {
          XCTFail("should not run AfterEach")
        }
        AfterAll {
          XCTFail("should not run AfterEach")
        }
      }
      Context("skipping in BeforeEach") {
        BeforeEach {
          XCTAssertEqual(ExampleRun.current!.description,
                         "Skip, skipping in BeforeEach, before each")
          try XCTSkipIf(true, "skip BeforeEach")
        }
        It("skips elements") {
          XCTFail("should not run It")
        }
        AfterEach {
          XCTFail("should not run AfterEach")
        }
        AfterAll {
          ranAfterAll1 = true
        }
      }
      Context("skipping in It") {
        It("skips") {
          try XCTSkipIf(true, "skip It")
        }
        AfterEach {
          ranAfterEach = true
        }
        AfterAll {
          ranAfterAll2 = true
        }
      }
    }
    XCTAssert(ranSecond, "second element did not run")
    XCTAssert(ranAfterEach, "AfterEach did not run")
    XCTAssert(ranAfterAll1, "AfterAll did not run")
    XCTAssert(ranAfterAll2, "AfterAll did not run")
  }
}
