public protocol Trait {}

public protocol ExampleTrait: Trait {}

public struct SkipTrait: Trait {}

public extension Trait where Self == SkipTrait {
  static var skip: Self { .init() }
}

public struct FocusedTrait: ExampleTrait {}

public extension Trait where Self == FocusedTrait {
  static var focused: Self { .init() }
}

// RSpec has pending(), which executes the test and fails if the test
// succeeds, to bring attention to tests that no longer need to be
// considered "pending".
