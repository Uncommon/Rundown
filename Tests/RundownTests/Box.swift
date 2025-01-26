/// "Sendable" container to enable capturing values in sendable closures.
/// For use in tests that are known not to actually introduce concurrency
/// since this does not enforce safety at all.
class Box<T>: @unchecked Sendable
{
  var wrappedValue: T

  init(_ value: T) {
    self.wrappedValue = value
  }
}

extension Box where T == Bool
{
  /// Sets the value to `true`
  func set() { wrappedValue = true }
}

extension Box where T == Int
{
  /// Increments the integer value
  func bump() { wrappedValue += 1 }
}
