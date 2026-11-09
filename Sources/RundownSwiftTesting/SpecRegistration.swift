#if RUNDOWN_DISCOVERY_PROTOTYPE && os(macOS) && compiler(>=6.4)
import Rundown
import Testing

@attached(member, names: named(__rundownSpecRecord))
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
      let bounds = __SourceBounds(
        __uncheckedLowerBound: sourceLocation,
        upperBound: (line: sourceLocation.line, column: sourceLocation.column)
      )
      return Test.__function(
        named: "examples(unit:)", in: spec, xcTestCompatibleSelector: nil, traits: [],
        arguments: {
          let root = S().spec.named(String(describing: spec)).node
          return DiscoveryCase.makeCases(in: root, unit: unit, path: [root.description], indices: [])
        },
        sourceBounds: bounds,
        parameters: [(firstName: "unit", secondName: nil, type: DiscoveryCase.self)]
      ) { discoveryCase in
        try await withRundownAssertionPaths {
          try await discoveryCase.root.run(with: SwiftTestingReporter(allowsConcurrency: true))
        }
      }
    }, into: outValue, asTypeAt: type)
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
