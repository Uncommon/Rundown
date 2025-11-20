import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(RundownMacros)
import RundownMacros

@MainActor fileprivate let testMacros: [String: Macro.Type] = [
  "DeAsync": DeAsyncMacro.self,
  "DeAsyncRD": DeAsyncMacro.self,
]
#endif

@MainActor
final class DeAsyncMacroTests: XCTestCase {
  func testSimpleAsync() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync
      func thing() async {
          await something()
      }
      """,
      expandedSource: """
      func thing() async {
          await something()
      }
      
      func thing() {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testDisfavoredOverload() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync
      @_disfavoredOverload
      func thing() async {
          await something()
      }
      """,
      expandedSource: """
      @_disfavoredOverload
      func thing() async {
          await something()
      }
      
      func thing() {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testThrows() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync
      func thing() async throws {
          try await something()
      }
      """,
      expandedSource: """
      func thing() async throws {
          try await something()
      }
      
      func thing() throws {
          try something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testAsyncBlock() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync
      func thing(block: () async -> Void) async throws {
          try await block()
      }
      """,
      expandedSource: """
      func thing(block: () async -> Void) async throws {
          try await block()
      }
      
      func thing(block: () -> Void) throws {
          try block()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testWhereCallType() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync(replacing: [AsyncCall.self], with: [SyncCall.self])
      func thing() async where Call == AsyncCall {
          await something()
      }
      """,
      expandedSource: """
      func thing() async where Call == AsyncCall {
          await something()
      }
      
      func thing() where Call == SyncCall {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testWhereCallTypeRD() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD
      func thing() async where Call == AsyncCall {
          await something()
      }
      """,
      expandedSource: """
      func thing() async where Call == AsyncCall {
          await something()
      }
      
      func thing() where Call == SyncCall {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testGenericParameterType() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync(replacing: [AsyncCall.self], with: [SyncCall.self])
      func thing(param: X<AsyncCall>) async {
          await something()
      }
      """,
      expandedSource: """
      func thing(param: X<AsyncCall>) async {
          await something()
      }
      
      func thing(param: X<SyncCall>) {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
  
  func testStripSendable() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD(stripSendable: true)
      func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async {
          await something()
      }
      """,
      expandedSource: """
      func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async {
          await something()
      }
      
      func spec(@ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) {
          something()
      }
      """,
      macros: testMacros
    )
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
}
