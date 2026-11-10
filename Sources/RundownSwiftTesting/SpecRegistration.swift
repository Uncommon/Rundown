#if canImport(Darwin) && compiler(>=6.4)
import os
import Rundown
import Testing

/// Registers one Swift Testing case for each selected top-level child of a spec.
///
/// Apply this experimental macro to a non-generic struct with a computed
/// `spec` property and a parameterless initializer. The macro supplies the
/// result builder and `Spec` conformance.
///
/// Top-level cases run in declaration order by default. Return a root group
/// with `.concurrent` to allow Swift Testing to schedule them in parallel.
@attached(member, names: named(__rundownSpecRecord), named(__rundownSuiteRecord))
@attached(extension, conformances: Spec)
@attached(memberAttribute)
public macro Spec()
  = #externalMacro(module: "RundownMacros", type: "DiscoverySpecMacro")

@attached(member, names: named(__rundownSpecRecord), named(__rundownSuiteRecord))
@attached(extension, conformances: Spec)
@attached(memberAttribute)
package macro Spec(_ unit: SpecDiscoveryUnit)
  = #externalMacro(module: "RundownMacros", type: "DiscoverySpecMacro")

package enum SpecDiscoveryUnit: Sendable {
  case topLevel, leaves
}

/// The conformance synthesized by `@Spec`.
public protocol Spec: SendableMetatype {
  init()

  @ExampleBuilder<AsyncCall>
  var spec: ExampleGroup<AsyncCall> { get }
}

/// Registration entry points used by expansions of `@Spec`.
public enum _SpecRegistration {
  // This Mach-O record always has an accessor. The nonoptional C function
  // pointer has the same layout and lets Swift emit the closure in @section.
  public typealias Accessor = @convention(c) (
    UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer?, UInt
  ) -> CBool

  public typealias Record = (
    kind: UInt32, reserved1: UInt32, accessor: Accessor, context: UInt, reserved2: UInt
  )

  public static func store<S: Spec>(
    _ spec: S.Type, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    store(spec, unit: .topLevel, sourceLocation: sourceLocation, into: outValue, asTypeAt: type)
  }

  package static func store<S: Spec>(
    _ spec: S.Type, unit: SpecDiscoveryUnit, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    Test.__store({
      let scope = DiscoveryRootScope(unit: unit)
      return Test.__function(
        named: "examples(unit:)", in: spec, xcTestCompatibleSelector: nil, traits: [scope],
        arguments: {
          let root = S().spec.named(String(describing: spec)).node
          let cases = DiscoveryCase.makeCases(in: root.withoutGroupHooks,
                                              unit: unit, path: [root.description], indices: [])
          scope.root.withLock { $0 = cases.isEmpty ? nil : root }
          return cases
        },
        sourceBounds: bounds(at: sourceLocation),
        parameters: [(firstName: "unit", secondName: nil, type: DiscoveryCase.self)]
      ) { discoveryCase in
        try await withRundownAssertionPaths {
          try await discoveryCase.root.run(with: SwiftTestingReporter(allowsConcurrency: true))
        }
      }
    }, into: outValue, asTypeAt: type)
  }

  public static func storeSuite<S: Spec>(
    _ spec: S.Type, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    Test.__store({
      Test.__type(spec, traits: [], sourceBounds: bounds(at: sourceLocation))
    }, into: outValue, asTypeAt: type)
  }

  private static func bounds(at location: SourceLocation) -> __SourceBounds {
    __SourceBounds(__uncheckedLowerBound: location, upperBound: (line: location.line, column: location.column))
  }
}

private final class DiscoveryRootScope: TestTrait, TestScoping {
  let root = OSAllocatedUnfairLock<ExampleNode?>(initialState: nil)
  private let unit: SpecDiscoveryUnit

  init(unit: SpecDiscoveryUnit) {
    self.unit = unit
  }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> DiscoveryRootScope? {
    // Xcode's XCTest bridge requires issues to be attributed to a function.
    testCase == nil ? self : nil
  }

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    guard let root = root.withLock({ $0 }) else {
      try await function()
      return
    }
    try await withRundownAssertionPaths {
      let reporter = SwiftTestingReporter(allowsConcurrency: true, cancelsTaskOnSkip: true)
      try await root.runDiscoveryRootHooks(with: reporter) {
        // Top-level cases are the root's selected siblings. Apply their
        // scheduling policy here, after planning has built the root.
        if unit == .topLevel && !root.isConcurrent {
          try await ParallelizationTrait.serialized.provideScope(for: test, testCase: testCase, performing: function)
        } else {
          try await function()
        }
      }
    }
  }
}

private struct DiscoveryCase: CustomTestArgumentEncodable, CustomTestStringConvertible {
  let path: [String]
  let indices: [Int]
  let root: ExampleNode

  var testDescription: String {
    let position = indices.map(String.init).joined(separator: ".")
    return "\(path.joined(separator: " / ")) [\(position)]"
  }

  func encodeTestArgument(to encoder: some Encoder) throws {
    try indices.encode(to: encoder)
  }

  static func makeCases(in node: ExampleNode, unit: SpecDiscoveryUnit,
                        path: [String], indices: [Int]) -> [Self] {
    node.indexedSelectedChildren.flatMap { index, child in
      let childPath = path + [child.description]
      let childIndices = indices + [index]
      if unit == .leaves, child.isGroup {
        return makeCases(in: child, unit: unit, path: childPath, indices: childIndices).map { leaf in
          Self(path: leaf.path, indices: leaf.indices, root: node.retainingOnly(leaf.root))
        }
      }
      return [Self(path: childPath, indices: childIndices, root: node.retainingOnly(child))]
    }
  }
}
#endif
