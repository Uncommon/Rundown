public struct TestHook<Phase: HookPhase, Call: CallType>: TestElement, Sendable {
  public let name: String
  public var description: String {
    Phase.phaseName + (name.isEmpty ? "" : ": \(name)")
  }
  public let traits: [any Trait]
  let declarationLocation: DeclarationLocation
  let block: Call.Callback
}

extension TestHook where Call == SyncCall {
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              fileID: String = #fileID,
              filePath: String = #filePath,
              line: Int = #line,
              column: Int = #column,
              execute: @escaping Call.Callback) {
    self.init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
  }

  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              fileID: String = #fileID,
              filePath: String = #filePath,
              line: Int = #line,
              column: Int = #column,
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.declarationLocation = .init(fileID: fileID, filePath: filePath, line: line, column: column)
    self.block = execute
  }
}

extension TestHook where Call: AsyncConvertibleCallType {
  init(_ name: String = "",
       _ traits: [any Trait],
       fileID: String = #fileID,
       filePath: String = #filePath,
       line: Int = #line,
       column: Int = #column,
       execute: Call.Callback) {
    self.name = name
    self.traits = traits
    self.declarationLocation = .init(fileID: fileID, filePath: filePath, line: line, column: column)
    self.block = execute
  }

  init(fromSync other: TestHook<Phase, Call.SyncVersion>) {
    self.name = other.name
    self.traits = other.traits
    self.declarationLocation = other.declarationLocation
    self.block = Call.wrapSyncCallback(other.block)
  }
}

extension TestHook where Call == SyncMainCall {
  public init(_ name: String = "",
              _ traits: (any Trait)...,
              fileID: String = #fileID,
              filePath: String = #filePath,
              line: Int = #line,
              column: Int = #column,
              execute: @escaping Call.Callback) {
    self.init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
  }

  // Since Swift doesn't yet support "splatting" variadic arguments,
  // each of these constructors must have both versions for the sake
  // of convenience functions that add a trait to a supplied list.
  public init(_ name: String = "",
              _ traits: [any Trait],
              fileID: String = #fileID,
              filePath: String = #filePath,
              line: Int = #line,
              column: Int = #column,
              execute: @escaping Call.Callback) {
    self.name = name
    self.traits = traits
    self.declarationLocation = .init(fileID: fileID, filePath: filePath, line: line, column: column)
    self.block = execute
  }
}


@DeAsyncRD
@_disfavoredOverload
public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      fileID: String = #fileID,
                      filePath: String = #filePath,
                      line: Int = #line,
                      column: Int = #column,
                      execute: @escaping AsyncCall.Callback) -> TestHook<BeforeAllPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

@DeAsyncRD
@_disfavoredOverload
public func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                      fileID: String = #fileID,
                      filePath: String = #filePath,
                      line: Int = #line,
                      column: Int = #column,
                      execute: @escaping AsyncMainCall.Callback) -> TestHook<BeforeAllPhase, AsyncMainCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

/// Runs before every selected example in this group and its nested groups.
/// Enclosing groups' setup runs before nested groups' setup.
@DeAsyncRD
@_disfavoredOverload
public func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                       fileID: String = #fileID,
                       filePath: String = #filePath,
                       line: Int = #line,
                       column: Int = #column,
                       execute: @escaping AsyncCall.Callback) -> TestHook<BeforeEachPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

/// Runs after every selected example in this group and its nested groups.
/// Nested groups' cleanup runs before enclosing groups' cleanup.
@DeAsyncRD
@_disfavoredOverload
public func afterEach(_ name: String = "", _ traits: (any Trait)...,
                      fileID: String = #fileID,
                      filePath: String = #filePath,
                      line: Int = #line,
                      column: Int = #column,
                      execute: @escaping AsyncCall.Callback) -> TestHook<AfterEachPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

/// Runs before each example or nested group in the same enclosing group.
/// A nested group is prepared once, before any of its hooks or examples run.
@DeAsyncRD
@_disfavoredOverload
public func beforeEachPeer(_ name: String = "", _ traits: (any Trait)...,
                           fileID: String = #fileID,
                           filePath: String = #filePath,
                           line: Int = #line,
                           column: Int = #column,
                           execute: @escaping AsyncCall.Callback) -> TestHook<BeforeEachPeerPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

/// Runs after each example or nested group in the same enclosing group.
/// A nested group is cleaned up once, after all of its hooks and examples finish.
@DeAsyncRD
@_disfavoredOverload
public func afterEachPeer(_ name: String = "", _ traits: (any Trait)...,
                          fileID: String = #fileID,
                          filePath: String = #filePath,
                          line: Int = #line,
                          column: Int = #column,
                          execute: @escaping AsyncCall.Callback) -> TestHook<AfterEachPeerPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}

@DeAsyncRD
@_disfavoredOverload
public func afterAll(_ name: String = "", _ traits: (any Trait)...,
                     fileID: String = #fileID,
                     filePath: String = #filePath,
                     line: Int = #line,
                     column: Int = #column,
                     execute: @escaping AsyncCall.Callback) -> TestHook<AfterAllPhase, AsyncCall> {
  .init(name, traits, fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}
