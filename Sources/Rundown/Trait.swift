public protocol Trait: Sendable {}

public protocol ExampleTrait: Trait {}




// RSpec has pending(), which executes the test and fails if the test
// succeeds, to bring attention to tests that no longer need to be
// considered "pending".
