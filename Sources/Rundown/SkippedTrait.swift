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
               @ExampleBuilder builder: () -> ExampleGroup) -> Describe {
  .init(description, traits + [.skipped], builder: builder)
}

/// Shortcut for adding a `.skipped` trait to `Context`.
func xContext(_ description: String,
              _ traits: [any Trait] = [],
              @ExampleBuilder builder: () -> ExampleGroup) -> Context {
  .init(description, traits + [.skipped], builder: builder)
}

/// Shortcut for adding a `.skipped` trait to `Within`.
func xWithin(_ description: String,
             _ traits: [any Trait] = [],
             executor: @escaping Within.Executor,
             @ExampleBuilder example: () -> ExampleGroup) -> Within {
  .init(description, traits + [.skipped],
        executor: executor, example: example)
}

/// Shortcut for adding a `.skipped` trait to `It`.
func xIt(_ description: String,
         _ traits: [any Trait] = [],
         execute: @escaping TestCallback) -> It {
  .init(description, traits + [.skipped], execute: execute)
}
