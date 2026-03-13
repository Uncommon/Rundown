import Foundation

/// A test suite that runs all its tests on the Main Actor.
///
/// Inherit this protocol in your `XCTestCase` subclass or Swift Testing suite
/// to define tests that are MainActor isolated
public protocol MainActorSuite {}

extension MainActorSuite {
  // MARK: Examples
  
  @DeAsyncRD
  @_disfavoredOverload
  func it(_ description: String,
          _ traits: (any Trait)...,
          execute: @escaping AsyncMainCall.Callback) -> It<AsyncMainCall> {
    .init(description, traits, execute: execute)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func describe(_ description: String,
                _ traits: (any Trait)...,
                @ExampleBuilder<AsyncMainCall> builder: () -> ExampleGroup<AsyncMainCall>) -> ExampleGroup<AsyncMainCall> {
    .init(description, traits, builder: builder)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func context(_ description: String,
               _ traits: (any Trait)...,
               @ExampleBuilder<AsyncMainCall> builder: () -> ExampleGroup<AsyncMainCall>) -> ExampleGroup<AsyncMainCall> {
    .init(description, traits, builder: builder)
  }
  
  // MARK: Hooks
  
  @DeAsyncRD
  @_disfavoredOverload
  func aroundEach(_ name: String = "",
                  _ traits: (any Trait)...,
                  executor: @escaping AsyncMainCall.AroundCallback)
  -> AroundEach<AsyncMainCall> {
    .init(name: name, traits: traits, block: executor)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func aroundEach(_ traits: (any Trait)...,
                  executor: @escaping AsyncMainCall.AroundCallback)
  -> AroundEach<AsyncMainCall> {
    .init(name: "", traits: traits, block: executor)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func beforeAll(_ name: String = "", _ traits: (any Trait)...,
                 execute: @escaping AsyncMainCall.Callback) -> TestHook<BeforeAllPhase, AsyncMainCall> {
    .init(name, traits, execute: execute)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func beforeEach(_ name: String = "", _ traits: (any Trait)...,
                  execute: @escaping AsyncMainCall.Callback) -> TestHook<BeforeEachPhase, AsyncMainCall> {
    .init(name, traits, execute: execute)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func afterEach(_ name: String = "", _ traits: (any Trait)...,
                 execute: @escaping AsyncMainCall.Callback) -> TestHook<AfterEachPhase, AsyncMainCall> {
    .init(name, traits, execute: execute)
  }
  
  @DeAsyncRD
  @_disfavoredOverload
  func afterAll(_ name: String = "", _ traits: (any Trait)...,
                execute: @escaping AsyncMainCall.Callback) -> TestHook<AfterAllPhase, AsyncMainCall> {
    .init(name, traits, execute: execute)
  }
  
  // MARK: Spec Runners
  
  @DeAsyncRD @MainActor
  @_disfavoredOverload
  func spec(@ExampleBuilder<AsyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<AsyncMainCall>,
            function: String = #function) async throws {
    let description = dropTestPrefix(function)
    try await describe(description, builder: builder).run()
  }

  @DeAsyncRD @MainActor
  @_disfavoredOverload
  func spec(_ description: String,
            @ExampleBuilder<AsyncMainCall> builder: @Sendable @MainActor () -> ExampleGroup<AsyncMainCall>) async throws {
    try await describe(description, builder: builder).run()
  }
}

private func dropTestPrefix(_ string: String) -> String { // duplicated?
  .init(string.prefix { $0.isIdentifier })
    .droppingPrefix("test")
}
