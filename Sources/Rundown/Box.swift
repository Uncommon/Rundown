/// "Sendable" container to enable capturing values in sendable closures.
/// For use in cases that are known not to actually introduce concurrency
/// since this does not enforce safety at all.
///
/// This public because it is used both internally and in tests where we do not
/// want to use `@testable import` in order to test that the right types are public.
public final class Box<T>: @unchecked Sendable
{
  public var wrappedValue: T

  public init(_ value: T) {
    self.wrappedValue = value
  }
}

public extension Box where T == Bool
{
  /// Sets the value to `true`
  func set() { wrappedValue = true }
}

public extension Box where T == Int
{
  /// Increments the integer value
  func bump() { wrappedValue += 1 }
}
