extension Dictionary {
  /// Appends `element` to the existing array for `key`, or initializes it with
  /// `[element]` if the value has not yet been set.
  mutating func appendOrSet<Element>(_ key: Key,
                                     _ element: Element) where Value == Array<Element> {
    if keys.contains(key) {
      self[key]!.append(element)
    }
    else {
      self[key] = [element]
    }
  }
}

extension String
{
  // TODO: Consolidate this because it's also in the macro target
  /// Returns the string with the given prefix removed, or returns the string
  /// unchanged if the prefix does not match.
  func droppingPrefix(_ prefix: String) -> String
  {
    guard hasPrefix(prefix)
    else { return self }
    
    return String(self[prefix.endIndex...])
  }
}

/// The description for a spec that is named after the test function that
/// calls it: the function's name without its parameters or a "test" prefix,
/// so `testSomething()` becomes "Something".
func specDescription(forFunction function: String) -> String {
  String(function.prefix { $0.isIdentifier })
    .droppingPrefix("test")
}

extension Character {
  var isIdentifier: Bool {
    // Technically incomplete, but enough for most cases
    isLetter || isNumber || self == "_"
  }
}
