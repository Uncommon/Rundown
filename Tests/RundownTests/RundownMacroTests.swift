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
  "Example": ExampleMacro.self,
]
#endif

final class RundownMacroTests: XCTestCase {
  func testBodyMacro() throws {
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
          try Describe("Thing") {
            It("works") {
            }
          } .run()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testBodyMacroInClass() throws {
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
            try Describe("Thing") {
                It("works") {
                }
            } .run()
        }
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
  
  func testPeerMacro() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      class TestClass: XCTestCase {
        @Example @ExampleBuilder
        func thing() throws -> ExampleGroup {
          It("works") {
          }
        }
      }
      """,
      expandedSource: """
      class TestClass: XCTestCase {
        @ExampleBuilder
        func thing() throws -> ExampleGroup {
          It("works") {
          }
        }
      
        func testThing() throws {
          try thing().named("thing").run()
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
