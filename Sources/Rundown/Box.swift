/// "Sendable" container to enable capturing values in sendable closures.
/// For use in cases that are known not to actually introduce concurrency
/// since this does not enforce safety at all.
package final class Box<T>: @unchecked Sendable
{
  package var wrappedValue: T

  package init(_ value: T) {
    self.wrappedValue = value
  }
}

package extension Box where T == Bool
{
  /// Sets the value to `true`
  func set() { wrappedValue = true }
}

