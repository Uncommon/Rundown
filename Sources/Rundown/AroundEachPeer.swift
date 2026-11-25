/// Wraps each example or nested group in the same enclosing group.
public struct AroundEachPeer<Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    AroundEachPeerPhase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let declarationLocation: DeclarationLocation
  let block: Call.AroundCallback
}

/// For each peer (an example or nested group in the same enclosing group),
/// the given executor will be called. That executor will be given a callback
/// that runs the peer as well as any `beforeEachPeer`/`afterEachPeer` elements.
/// A nested group is wrapped once, including all of its hooks and examples.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
@DeAsyncRD
@_disfavoredOverload
public func aroundEachPeer(_ name: String = "",
                           _ traits: (any Trait)...,
                           fileID: String = #fileID,
                           filePath: String = #filePath,
                           line: Int = #line,
                           column: Int = #column,
                           executor: @escaping AsyncCall.AroundCallback)
  -> AroundEachPeer<AsyncCall> {
  .init(name: name, traits: traits,
        declarationLocation: .init(fileID: fileID, filePath: filePath, line: line, column: column),
        block: executor)
}

/// For each peer (an example or nested group in the same enclosing group),
/// the given executor will be called. That executor will be given a callback
/// that runs the peer as well as any `beforeEachPeer`/`afterEachPeer` elements.
/// A nested group is wrapped once, including all of its hooks and examples.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
@DeAsyncRD
@_disfavoredOverload
public func aroundEachPeer(_ traits: (any Trait)...,
                           fileID: String = #fileID,
                           filePath: String = #filePath,
                           line: Int = #line,
                           column: Int = #column,
                           executor: @escaping AsyncCall.AroundCallback)
  -> AroundEachPeer<AsyncCall> {
  .init(name: "", traits: traits,
        declarationLocation: .init(fileID: fileID, filePath: filePath, line: line, column: column),
        block: executor)
}
