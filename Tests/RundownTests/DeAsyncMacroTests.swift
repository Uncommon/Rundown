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
      macros: testMacros)
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
      macros: testMacros)
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
      macros: testMacros)
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
      macros: testMacros)
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
      macros: testMacros)
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
      macros: testMacros)
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
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  /// Using @DeAsyncRD on a line with multiple annotations should be recognized
  func testRDMultipleAnnotations() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD @Sendable
      func thing(param: X<AsyncCall>) async {
          await something()
      }
      """,
      expandedSource: """
      @Sendable
      func thing(param: X<AsyncCall>) async {
          await something()
      }
      
      @Sendable
      func thing(param: X<SyncCall>) {
          something()
      }
      """,
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testStripSendable() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD(stripSendable: .parameters)
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
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testStripSendableFunction() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD(stripSendable: .function) @Sendable @MainActor
      func thing() async {
          await something()
      }
      """,
      expandedSource: """
      @Sendable @MainActor
      func thing() async {
          await something()
      }
      
      @MainActor
      func thing() {
          something()
      }
      """,
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testReplacementsCombineWithEveryStripSendableOption() throws {
#if canImport(RundownMacros)
    for option in ["none", "parameters", "function", "all"] {
      let functionAttribute = ["function", "all"].contains(option) ? "" : "@Sendable\n"
      let parameterAttribute = ["parameters", "all"].contains(option) ? "" : "@Sendable "
      assertMacroExpansion(
        """
        @DeAsync(replacing: [AsyncCall.self], with: [SyncCall.self], stripSendable: .\(option))
        @Sendable
        func thing(_ value: AsyncCall, block: @Sendable () async -> Void) async -> AsyncCall {
            await block()
            return value
        }
        """,
        expandedSource: """
        @Sendable
        func thing(_ value: AsyncCall, block: @Sendable () async -> Void) async -> AsyncCall {
            await block()
            return value
        }

        \(functionAttribute)func thing(_ value: SyncCall, block: \(parameterAttribute)() -> Void) -> SyncCall {
            block()
            return value
        }
        """,
        macros: testMacros)
    }
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testWhereClauseIsPreservedWithoutTypeReplacements() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync(stripSendable: .parameters)
      func thing<T>(_ value: T, block: @Sendable () async -> Void) async -> T where T: Equatable {
          await block()
          return value
      }
      """,
      expandedSource: """
      func thing<T>(_ value: T, block: @Sendable () async -> Void) async -> T where T: Equatable {
          await block()
          return value
      }

      func thing<T>(_ value: T, block: () -> Void) -> T where T: Equatable {
          block()
          return value
      }
      """,
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testReplacementsHandleQualifiedAndCompoundTypes() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsync(replacing: [Source.Value.self, [ Source.Value ].self], with: [Destination.Value.self, Set<Destination.Value>.self], stripSendable: .none)
      func thing<T>(_ value: Source.Value, values: [Source.Value], box: Box<Source.Value>) async -> [Source.Value] where T == Source.Value {
          return await something()
      }
      """,
      expandedSource: """
      func thing<T>(_ value: Source.Value, values: [Source.Value], box: Box<Source.Value>) async -> [Source.Value] where T == Source.Value {
          return await something()
      }

      func thing<T>(_ value: Destination.Value, values: Set<Destination.Value>, box: Box<Destination.Value>) -> Set<Destination.Value> where T == Destination.Value {
          return something()
      }
      """,
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testInvalidReplacementArgumentsProduceDiagnostics() throws {
#if canImport(RundownMacros)
    let countMismatch = "@DeAsync requires 'replacing' and 'with' to contain the same number of types."
    let invalidArray = "@DeAsync replacement arguments must be array literals of types such as [Value.self]."
    let invalidType = "@DeAsync replacement types must use Type.self syntax."
    let invalidStrip = "@DeAsync requires 'stripSendable' to be .none, .parameters, .function, or .all."
    let cases = [
      ("@DeAsync(replacing: [AsyncCall.self], with: [], stripSendable: .all)", countMismatch),
      ("@DeAsync(replacing: [AsyncCall.self])", countMismatch),
      ("@DeAsync(with: [SyncCall.self])", countMismatch),
      ("@DeAsync(replacing: types, with: [])", invalidArray),
      ("@DeAsync(replacing: [], with: types)", invalidArray),
      ("@DeAsync(replacing: [AsyncCall.other], with: [SyncCall.self])", invalidType),
      ("@DeAsync(replacing: [42.self], with: [SyncCall.self])", invalidType),
      ("@DeAsync(stripSendable: option)", invalidStrip),
    ]
    for (attribute, message) in cases {
      assertMacroExpansion(
        """
        \(attribute)
        func thing() async {}
        """,
        expandedSource: """
        func thing() async {}
        """,
        diagnostics: [.init(message: message, line: 1, column: 1)],
        macros: testMacros)
    }
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }

  func testRDReplacementsCombineWithDefaultsAndStripSendable() throws {
#if canImport(RundownMacros)
    assertMacroExpansion(
      """
      @DeAsyncRD(replacing: [CustomAsync.self], with: [CustomSync.self], stripSendable: .parameters)
      func thing(_ value: CustomAsync, block: @Sendable (AsyncCall) async -> AsyncMainCall) async where Call == AsyncCall {
          await something()
      }
      """,
      expandedSource: """
      func thing(_ value: CustomAsync, block: @Sendable (AsyncCall) async -> AsyncMainCall) async where Call == AsyncCall {
          await something()
      }

      func thing(_ value: CustomSync, block: (SyncCall) -> SyncMainCall) where Call == SyncCall {
          something()
      }
      """,
      macros: testMacros)
#else
    throw XCTSkip("macros are only supported when running tests for the host platform")
#endif
  }
}
