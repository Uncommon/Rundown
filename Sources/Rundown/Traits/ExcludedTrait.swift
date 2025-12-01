/// Marks an element as excluded. It will not be executed, and a group
/// where all elements are excluded will also not execute before/after
/// hooks.
///
/// "Excluded" is a slightly different concept from "skipped" as in
/// `XCTSkip`. Excluding is meant to be a temporary change during
/// development, and results in the element being omitted from the
/// generated test structure. Skipping is often conditional, and
/// therefore a more permanent part of the test.
public struct ExcludedTrait: Trait {}

public extension Trait where Self == ExcludedTrait {
  static var excluded: Self { .init() }
}

public extension TestElement {
  var isExcluded: Bool { traits.contains { $0 is ExcludedTrait } }
}


/// Shortcut for adding a `.excluded` trait to `Describe`.
func xDescribe(_ description: String,
               _ traits: [any Trait] = [],
               @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits + [.excluded], builder: builder)
}

/// Shortcut for adding a `.excluded` trait to `Context`.
func xContext(_ description: String,
              _ traits: [any Trait] = [],
              @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits + [.excluded], builder: builder)
}

/// Shortcut for adding a `.excluded` trait to `It`.
func xIt(_ description: String,
         _ traits: [any Trait] = [],
         execute: @escaping SyncCall.Callback) -> It<SyncCall> {
  .init(description, traits + [.excluded], execute: execute)
}

/// Shortcut for adding a `.excluded` trait to `It`.
func xIt(_ description: String,
         _ traits: [any Trait] = [],
         execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits + [.excluded], execute: execute)
}
