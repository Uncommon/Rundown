import XCTest
@testable import Rundown

@MainActor
final class RundownTests: Rundown.TestCase {
  
  func testDescriptions() throws {
    try spec("ExampleRunner") {
      Context("first context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRun, first context, has correct description")
        }
      }
      Context("second context") {
        It("has correct description") {
          XCTAssertEqual(ExampleRunner.current!.description,
                         "ExampleRun, second context, has correct description")
        }
      }
    }
  }

  func testBeforeAfterEach() throws {
    let beforeCount = Box(0)
    let itCount = Box(0)
    let afterCount = Box(0)

    try spec("Running 'each' hooks") {
      BeforeEach {
        beforeCount.bump()
      }

      It("runs first test") {
        XCTAssertEqual(beforeCount.wrappedValue, 1, "BeforeEach missed")
        XCTAssertEqual(afterCount.wrappedValue, 0, "AfterEach missed")
        itCount.bump()
      }

      Context("in a context") {
        It("runs second test") {
          XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEach missed")
          XCTAssertEqual(afterCount.wrappedValue, 1, "AfterEach missed")
          itCount.bump()
        }
      }

      AfterEach {
        afterCount.bump()
      }
    }
    XCTAssertEqual(beforeCount.wrappedValue, 2, "BeforeEach didn't run correctly")
    XCTAssertEqual(itCount.wrappedValue, 2, "Its didn't run correctly")
    XCTAssertEqual(afterCount.wrappedValue, 2, "AfterEach didn't run correctly")
  }

  @TaskLocal static var local: Int = 0
  
  func testWithinTaskLocal() throws {
    try spec("Within") {
      for value in 1...2 {
        Within("with task local as \(value)",
               local: Self.$local, value) {
          It("has correct value") {
            // TODO: Can this assumeIsolated be made unneccessary?
            MainActor.assumeIsolated {
              XCTAssert(Self.local == value)
              XCTAssertEqual(ExampleRunner.activity?.name, "has correct value")
              XCTAssertEqual(ExampleRunner.current?.description,
                             "Within, with task local as \(value), has correct value")
            }
          }
        }
      }
    }
  }
  
  func testSkip() throws {
    let ranSecond = Box(false)
    let ranAfterEach = Box(false)
    let ranAfterAll1 = Box(false)
    let ranAfterAll2 = Box(false)

    try spec {
      Context("no hooks") {
        It("skips") {
          try XCTSkipIf(true, "skip It")
        }
        It("runs second thing") {
          ranSecond.set()
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
          XCTAssertEqual(ExampleRunner.current!.description,
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
          ranAfterAll1.set()
        }
      }
      Context("skipping in It") {
        It("skips") {
          try XCTSkipIf(true, "skip It")
        }
        AfterEach {
          ranAfterEach.set()
        }
        AfterAll {
          ranAfterAll2.set()
        }
      }
    }
    XCTAssert(ranSecond.wrappedValue, "second element did not run")
    XCTAssert(ranAfterEach.wrappedValue, "AfterEach did not run")
    XCTAssert(ranAfterAll1.wrappedValue, "AfterAll did not run")
    XCTAssert(ranAfterAll2.wrappedValue, "AfterAll did not run")
  }
}
