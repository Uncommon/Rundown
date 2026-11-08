#if RUNDOWN_DISCOVERY_PROTOTYPE && os(macOS) && compiler(>=6.4)
import Rundown
import Testing

@attached(member, names: named(__rundownSpecRecord))
package macro Spec() = #externalMacro(module: "RundownMacros", type: "DiscoverySpecMacro")

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
    _ spec: S.Type, sourceLocation: SourceLocation,
    into outValue: UnsafeMutableRawPointer, asTypeAt type: UnsafeRawPointer
  ) -> CBool {
    Test.__store({
      let bounds = __SourceBounds(
        __uncheckedLowerBound: sourceLocation,
        upperBound: (line: sourceLocation.line, column: sourceLocation.column)
      )
      return Test.__function(
        named: "examples()", in: spec, xcTestCompatibleSelector: nil,
        traits: [], sourceBounds: bounds
      ) {
        let node = S().spec.named(String(describing: spec)).node
        try await withRundownAssertionPaths {
          try await node.run(with: SwiftTestingReporter(allowsConcurrency: true))
        }
      }
    }, into: outValue, asTypeAt: type)
  }
}
#endif
