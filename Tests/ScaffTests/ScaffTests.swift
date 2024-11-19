import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(ScaffMacros)
import ScaffMacros

let testMacros: [String: Macro.Type] = [
  "TestExample": TestExampleMacro.self,
]
#endif

final class ScaffTests: XCTestCase {
  func testMacro() throws {
#if canImport(ScaffMacros)
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
          try _test.execute()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
}
