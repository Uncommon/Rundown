import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(RundownMacros)
import RundownMacros

let testMacros: [String: Macro.Type] = [
  "TestExample": TestExampleMacro.self,
]
#endif

final class RundownTests: XCTestCase {
  func testMacro() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @TestExample
      func testThing() throws {
        It("works") {
        }
      }
      """,
      expandedSource: """
      func testThing() throws {
          let _test = Describe("Thing") {
            It("works") {
            }
          }
          let run = ExampleRun()
          try _test.execute(in: run)
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testInClass() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      class TestClass: XCTestCase {
        @TestExample
        func testThing() throws {
          It("works") {
          }
        }
      }
      """,
      expandedSource: """
      class TestClass: XCTestCase {
        func testThing() throws {
            let _test = Describe("Thing") {
                It("works") {
                }
            }
            try execute(_test)
        }
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
}