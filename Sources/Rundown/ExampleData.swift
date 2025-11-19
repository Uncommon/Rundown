import Foundation
import OSLog
import XCTest

public protocol CallType: Sendable {
  associatedtype Callback: Sendable
  associatedtype WithinCallback: Sendable
}

public enum SyncCall: CallType {
  public typealias Callback = @Sendable () throws -> Void
  public typealias WithinCallback = @Sendable (Callback) throws -> Void
}
public enum AsyncCall: CallType {
  public typealias Callback = @Sendable () async throws -> Void
  public typealias WithinCallback = @Sendable (Callback) async throws -> Void
}

/// An async test element was found while running a non-async test
public struct UnexpectedAsyncError: Error {}

public protocol TestElement: Sendable {
  var description: String { get }
  var traits: [any Trait] { get }
}

public protocol TestExample<Call>: TestElement {
  associatedtype Call: CallType
  var isDeepFocused: Bool { get }
}


public struct It<Call: CallType>: TestExample {
  public let description: String
  public let traits: [any Trait]
  let block: Call.Callback

  public init(_ description: String,
              _ traits: (any Trait)...,
              executing block:  Call.Callback) {
    self.init(description, traits, execute: block)
  }

  public init(_ description: String,
              _ traits: [any Trait],
              execute: Call.Callback) {
    self.description = description
    self.traits = traits
    self.block = execute
  }

  /// "Casts" a sync instance to an async one
  public init(fromSync other: It<SyncCall>)
              where Call == AsyncCall {
    self.description = other.description
    self.traits = other.traits
    self.block = other.block
  }

  @DeAsyncRD
  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncCall {
    try await block()
  }
}

// These two could be a single generic function, but that creates
// an ambiguous call site when used in the result builder.
public func it(_ description: String,
               _ traits: (any Trait)...,
               execute: @escaping SyncCall.Callback) -> It<SyncCall> {
  .init(description, traits, execute: execute)
}

public func it(_ description: String,
               _ traits: (any Trait)...,
               execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits, execute: execute)
}

public func spec(@ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>,
                 function: String = #function) throws {
  let description = dropTestPrefix(function)
  try describe(description, builder: builder).run()
}

public func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>,
                 function: String = #function) async throws {
  let description = dropTestPrefix(function)
  try await describe(description, builder: builder).run()
}

private func dropTestPrefix(_ string: String) -> String {
  .init(string.prefix { $0.isIdentifier })
    .droppingPrefix("test")
}

public func spec(_ description: String,
                 @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) throws {
  try describe(description, builder: builder).run()
}

public func spec(_ description: String,
                 @ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async throws {
  try await describe(description, builder: builder).run()
}
