import Rundown

extension Box where T == Int {
  func bump() { wrappedValue += 1 }
}

extension Box where T == [String] {
  func note(_ entry: String) { wrappedValue.append(entry) }
}
