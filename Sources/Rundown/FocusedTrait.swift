/// Marks an element as focused. If any elements are focused, then only
/// those elements, plus the before/after hooks of their group, will
/// be executed.
///
/// This behavior propagates up the group hierarchy: if
/// if any descendants of a group are focused, then non-focused
/// siblings of that group will be skipped.
///
/// Focusing is intended to be used as a temporary debugging tool.
/// Usages of `FocusedTrait` should usually not be checked in to source
/// code control.
public struct FocusedTrait: ExampleTrait {}

public extension Trait where Self == FocusedTrait {
  static var focused: Self { .init() }
}

public extension TestExample {
  /// Returns `true` if this element has a `FocusedTrait`
  var isFocused: Bool { traits.contains { $0 is FocusedTrait } }
  
  /// Returns `true` if this element or any sub-element has a `FocusedTrait`
  var isDeepFocused: Bool { isFocused }
}


/// Shortcut for adding a `.focused` trait to `Describe`.
func fDescribe(_ description: String,
               _ traits: (any Trait)...,
               @ExampleBuilder builder: () -> ExampleGroup) -> Describe {
  .init(description, traits + [.focused], builder: builder)
}

/// Shortcut for adding a `.focused` trait to `Context`.
func fContext(_ description: String,
              _ traits: [any Trait] = [],
              @ExampleBuilder builder: () -> ExampleGroup) -> Context {
  .init(description, traits + [.focused], builder: builder)
}

/// Shortcut for adding a `.focused` trait to `Within`.
func fWithin(_ description: String,
             _ traits: (any Trait)...,
             executor: @escaping Within.Executor,
             @ExampleBuilder example: () -> ExampleGroup) -> Within {
  .init(description, traits + [.focused],
        executor: executor, example: example)
}

/// Shortcut for adding a `.focused` trait to `It`.
func fIt(_ description: String,
         _ traits: (any Trait)...,
         execute: @escaping () throws -> Void) -> It {
  .init(description, traits + [.focused], execute: execute)
}
