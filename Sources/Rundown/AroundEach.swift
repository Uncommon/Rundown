/// Wraps every selected example in this group and its nested groups.
public struct AroundEach<Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    AroundEachPhase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let declarationLocation: DeclarationLocation
  let block: Call.AroundCallback
}

/// Wraps every selected example in this group and its nested groups,
/// including all inherited `beforeEach`/`afterEach` hooks and its fixture.
/// Enclosing groups' wrappers surround nested groups' wrappers.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
@DeAsyncRD
@_disfavoredOverload
public func aroundEach(_ name: String = "",
                       _ traits: (any Trait)...,
                       fileID: String = #fileID,
                       filePath: String = #filePath,
                       line: Int = #line,
                       column: Int = #column,
                       executor: @escaping AsyncCall.AroundCallback)
  -> AroundEach<AsyncCall> {
  .init(name: name, traits: traits,
        declarationLocation: .init(fileID: fileID, filePath: filePath, line: line, column: column),
        block: executor)
}

/// Wraps every selected example in this group and its nested groups,
/// including all inherited `beforeEach`/`afterEach` hooks and its fixture.
/// Enclosing groups' wrappers surround nested groups' wrappers.
///
/// This allows for callback-based setup and teardown, such as
/// Swift's various "with" functions like `TaskLocal.withValue()`.
@DeAsyncRD
@_disfavoredOverload
public func aroundEach(_ traits: (any Trait)...,
                       fileID: String = #fileID,
                       filePath: String = #filePath,
                       line: Int = #line,
                       column: Int = #column,
                       executor: @escaping AsyncCall.AroundCallback)
  -> AroundEach<AsyncCall> {
  .init(name: "", traits: traits,
        declarationLocation: .init(fileID: fileID, filePath: filePath, line: line, column: column),
        block: executor)
}
