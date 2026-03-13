import Foundation
import OSLog

public protocol CallType: Sendable {
  associatedtype Callback: Sendable
  associatedtype AroundCallback: Sendable
}

public protocol AsyncConvertibleCallType: CallType {
  associatedtype SyncVersion: CallType

  static func wrapSyncCallback(_ callback: SyncVersion.Callback) -> Callback
}

public enum SyncCall: CallType {
  public typealias Callback = @Sendable () throws -> Void
  public typealias AroundCallback = @Sendable (Callback) throws -> Void
}
public enum AsyncCall: AsyncConvertibleCallType {
  public typealias SyncVersion = SyncCall
  public typealias Callback = @Sendable () async throws -> Void
  public typealias AroundCallback = @Sendable (Callback) async throws -> Void

  public static func wrapSyncCallback(_ callback: @escaping SyncCall.Callback) -> Callback {
    callback
  }
}
public enum SyncMainCall: CallType {
  public typealias Callback = @Sendable @MainActor () throws -> Void
  public typealias AroundCallback = @Sendable @MainActor (Callback) throws -> Void
}
public enum AsyncMainCall: AsyncConvertibleCallType {
  public typealias SyncVersion = SyncMainCall
  public typealias Callback = @Sendable @MainActor () async throws -> Void
  public typealias AroundCallback = @Sendable @MainActor (Callback) async throws -> Void

  public static func wrapSyncCallback(_ callback: @escaping SyncMainCall.Callback) -> Callback {
    {
      try callback()
    }
  }
}

/// An async test element was found while running a non-async test
public struct UnexpectedAsyncError: Error {}

public struct ConcurrentDisallowedError: Error {
  public var description: String { "concurrent tests are not allowed in this context" }
}

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

  @DeAsyncRD @MainActor
  public func execute(in runner: ExampleRunner) async throws
                      where Call == AsyncMainCall {
    try await block()
  }
}

// The SyncCall and AsyncCall versions could be a single generic function, but
// that creates an ambiguous call site when used in the result builder.
@DeAsyncRD
public func it(_ description: String,
               _ traits: (any Trait)...,
               execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits, execute: execute)
}

@DeAsyncRD(stripSendable: .parameters)
public func spec(@ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>,
                 function: String = #function) async throws {
  let description = dropTestPrefix(function)
  try await describe(description, builder: builder).run()
}

private func dropTestPrefix(_ string: String) -> String {
  .init(string.prefix { $0.isIdentifier })
    .droppingPrefix("test")
}

@DeAsyncRD(stripSendable: .parameters)
public func spec(_ description: String,
                 @ExampleBuilder<AsyncCall> builder: @Sendable () -> ExampleGroup<AsyncCall>) async throws {
  try await describe(description, builder: builder).run()
}
