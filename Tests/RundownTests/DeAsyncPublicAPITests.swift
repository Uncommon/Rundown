import Rundown
import XCTest

private enum Payloads {
  struct Async {
    let value: Int
  }

  struct Sync {
    let value: Int
  }
}

@DeAsync(replacing: [Payloads.Async.self], with: [Payloads.Sync.self], stripSendable: .parameters)
private func payloadValue(_ payload: Payloads.Async, adding increment: @Sendable () async -> Int) async -> Int {
  payload.value + (await increment())
}

@DeAsync
private func valuesMatch<Value>(_ first: Value, _ second: Value) async -> Bool where Value: Equatable {
  first == second
}

final class DeAsyncPublicAPITests: XCTestCase {
  func testGeneratedSyncOverloadReplacesTypesAndAllowsMutableCaptures() {
    var calls = 0
    let result = payloadValue(Payloads.Sync(value: 40)) {
      calls += 1
      return 2
    }
    XCTAssertEqual(result, 42)
    XCTAssertEqual(calls, 1)
  }

  func testOriginalAsyncOverloadRemainsUsable() async {
    let result = await payloadValue(Payloads.Async(value: 40)) { 2 }
    XCTAssertEqual(result, 42)
    let equal = await valuesMatch(42, 42)
    XCTAssertTrue(equal)
  }

  func testGeneratedSyncOverloadPreservesGenericConstraints() {
    XCTAssertTrue(valuesMatch("same", "same"))
    XCTAssertFalse(valuesMatch("first", "second"))
  }
}
