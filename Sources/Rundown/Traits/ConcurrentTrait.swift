public struct ConcurrentTrait: ExampleTrait {}

public extension Trait where Self == ConcurrentTrait {
  /// Test groups with this trait will run their elements concurrently.
  ///
  /// Async tests use a task group. Non-async tests use
  /// `DispatchQueue.concurrentPerform()`. In both cases, a failing element
  /// does not stop the others: if multiple elements throw exceptions, only the
  /// first will be captured, and it is rethrown by the test group after all the
  /// elements have finished and the `afterAll` hooks have run.
  ///
  /// Groups that run on the main actor can't be concurrent. Running one throws
  /// `ConcurrentDisallowedError` before any of its hooks run.
  static var concurrent: Self { .init() }
}
