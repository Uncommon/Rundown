public struct ConcurrentTrait: ExampleTrait {}

public extension Trait where Self == ConcurrentTrait {
  /// Test groups with this trait will run their elements concurrently.
  ///
  /// Async tests use a task group. Non-async tests use
  /// `DispatchQueue.concurrentPerform()`. In both cases, if multiple
  /// elements throw exceptions, only the first will be captured
  /// and rethrown by the test group.
  static var concurrent: Self { .init() }
}
