/// Marks an element as focused. If any elements are focused, then only
/// those elements, plus the before/after hooks of their group, will
/// be executed.
///
/// This behavior propagates up the group hierarchy: if any descendants of a
/// group are focused, then non-focused siblings of that group will be skipped.
/// Excluded elements and their descendants never contribute focus.
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
  
  /// Returns `true` if this element or a descendant contributes focus.
  /// Excluded elements and their descendants do not contribute focus.
  var isDeepFocused: Bool { !isExcluded && isFocused }
}


/// Shortcut for adding a `.focused` trait to `describe`.
@DeAsyncRD
@_disfavoredOverload
public func fDescribe(_ description: String,
                      _ traits: (any Trait)...,
                      @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits + [.focused], builder: builder)
}

/// Shortcut for adding a `.focused` trait to `context`.
@DeAsyncRD
@_disfavoredOverload
public func fContext(_ description: String,
                     _ traits: (any Trait)...,
                     @ExampleBuilder<AsyncCall> builder: () -> ExampleGroup<AsyncCall>) -> ExampleGroup<AsyncCall> {
  .init(description, traits + [.focused], builder: builder)
}

/// Shortcut for adding a `.focused` trait to `it`.
@DeAsyncRD
public func fIt(_ description: String,
                _ traits: (any Trait)...,
                fileID: String = #fileID,
                filePath: String = #filePath,
                line: Int = #line,
                column: Int = #column,
                execute: @escaping AsyncCall.Callback) -> It<AsyncCall> {
  .init(description, traits + [.focused], fileID: fileID, filePath: filePath, line: line, column: column, execute: execute)
}
