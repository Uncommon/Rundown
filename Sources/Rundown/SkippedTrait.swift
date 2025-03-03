/// Marks an element as skipped. It will not be executed, and a group
/// where all elements are skipped will also not execute before/after
/// hooks.
public struct SkippedTrait: Trait {}

public extension Trait where Self == SkippedTrait {
  static var skipped: Self { .init() }
}

public extension TestElement {
  var isSkipped: Bool { traits.contains { $0 is SkippedTrait } }
}


/// Shortcut for adding a `.skipped` trait to `Describe`.
func xDescribe(_ description: String,
               _ traits: [any Trait] = [],
               @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits + [.skipped], builder: builder)
}

/// Shortcut for adding a `.skipped` trait to `Context`.
func xContext(_ description: String,
              _ traits: [any Trait] = [],
              @ExampleBuilder<SyncCall> builder: () -> ExampleGroup<SyncCall>) -> ExampleGroup<SyncCall> {
  .init(description, traits + [.skipped], builder: builder)
}

/// Shortcut for adding a `.skipped` trait to `Within`.
func xWithin(_ description: String,
             _ traits: [any Trait] = [],
             executor: @escaping SyncCall.WithinCallback,
             @ExampleBuilder<SyncCall> example: () -> ExampleGroup<SyncCall>) -> Within<SyncCall> {
  .init(description, traits + [.skipped],
        executor: executor, example: example)
}
/// Shortcut for adding a `.skipped` trait to `Within`.
func xWithin(_ description: String,
             _ traits: [any Trait] = [],
             executor: @escaping AsyncCall.WithinCallback,
             @ExampleBuilder<AsyncCall> example: () -> ExampleGroup<AsyncCall>) -> Within<AsyncCall> {
  .init(description, traits + [.skipped],
        executor: executor, example: example)
}

/// Shortcut for adding a `.skipped` trait to `It`.
func xIt(_ description: String,
         _ traits: [any Trait] = [],
         execute: @escaping SyncCall.Callback) -> It<SyncCall> {
  .init(description, traits + [.skipped], execute: execute)
}

/// Shortcut for adding a `.skipped` trait to `It`.
func xIt(_ description: String,
         _ traits: [any Trait] = [],
         execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits + [.skipped], execute: execute)
}
