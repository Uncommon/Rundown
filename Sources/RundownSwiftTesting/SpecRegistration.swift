#if RUNDOWN_DISCOVERY_PROTOTYPE && os(macOS) && compiler(>=6.4)
import os
import Rundown
import Testing

@attached(member, names: named(__rundownSpecRecord), named(__rundownSuiteRecord))
@attached(extension, conformances: Spec)
@attached(memberAttribute)
package macro Spec(_ unit: SpecDiscoveryUnit = .topLevel)
  = #externalMacro(module: "RundownMacros", type: "DiscoverySpecMacro")

package enum SpecDiscoveryUnit: Sendable {
  case topLevel, leaves
}

package protocol Spec: SendableMetatype {
  init()

  @ExampleBuilder<AsyncCall>
  var spec: ExampleGroup<AsyncCall> { get }
}

package enum SpecRegistration {
  // This macOS record always has an accessor. The nonoptional C function
  // pointer has the same layout and lets Swift emit the closure in @section.
  package typealias Accessor = @convention(c) (
    UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer?, UInt
  ) -> CBool

  package typealias Record = (
    kind: UInt32, reserved1: UInt32, accessor: Accessor, context: UInt, reserved2: UInt
  )

  package static func store<S: Spec>(
    _ spec: S.Type, unit: SpecDiscoveryUnit, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    Test.__store({
      Test.__function(
        named: "examples(unit:)", in: spec, xcTestCompatibleSelector: nil, traits: [],
        arguments: {
          let root = S().spec.named(String(describing: spec)).node
          let scope = Test.current?.traits.lazy.compactMap { $0 as? DiscoveryRootScope }
            .first { $0.owner == ObjectIdentifier(spec) }
          let cases = DiscoveryCase.makeCases(in: scope == nil ? root : root.withoutGroupHooks,
                                              unit: unit, path: [root.description], indices: [])
          if !cases.isEmpty {
            scope?.root.withLock { $0 = root }
          }
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

  package static func storeSuite<S: Spec>(
    _ spec: S.Type, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    Test.__store({
      let sourceBounds = bounds(at: sourceLocation)
      let suiteID = Test.__type(spec, traits: [], sourceBounds: sourceBounds).id
      let scope = DiscoveryRootScope(owner: ObjectIdentifier(spec), suiteID: suiteID)
      return Test.__type(spec, traits: [scope], sourceBounds: sourceBounds)
    }, into: outValue, asTypeAt: type)
  }

  private static func bounds(at location: SourceLocation) -> __SourceBounds {
    __SourceBounds(__uncheckedLowerBound: location, upperBound: (line: location.line, column: location.column))
  }
}

private final class DiscoveryRootScope: SuiteTrait, TestTrait, TestScoping {
  let owner: ObjectIdentifier
  let suiteID: Test.ID
  let root = OSAllocatedUnfairLock<ExampleNode?>(initialState: nil)
  var isRecursive: Bool { true }

  init(owner: ObjectIdentifier, suiteID: Test.ID) {
    self.owner = owner
    self.suiteID = suiteID
  }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> DiscoveryRootScope? {
    // Inherit the trait into planning, but only enter the owning suite's scope.
    test.id == suiteID ? self : nil
  }

  func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
    guard let root = root.withLock({ $0 }) else {
      try await function()
      return
    }
    try await withRundownAssertionPaths {
      var startedCases = false
      try await root.runDiscoveryRootHooks(with: SwiftTestingReporter(allowsConcurrency: true)) {
        startedCases = true
        try await function()
      }
      if !startedCases {
        // The reporter has already recorded the hook failure. End the native
        // suite before it can report cases whose bodies will never run.
        try Task.checkCancellation()
        try Test.cancel("Rundown root setup did not complete")
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
