import os
import RundownSwiftTesting
import Testing

@Spec
struct CheckoutSpec {
  private let setupCount = OSAllocatedUnfairLock(initialState: 0)

  var spec: ExampleGroup<AsyncCall> {
    beforeAll { setupCount.withLock { $0 += 1 } }
    context("Saved card") {
      it("Authorizes payment") {
        #expect(Test.Case.current?.isParameterized == true)
        #expect(ExampleRunner.current?.path == ["CheckoutSpec", "Saved card", "Authorizes payment"])
      }
      it("Uses the shared setup") {
        #expect(setupCount.withLock { $0 } == 1)
      }
    }
    it("Checks out as a guest") {
      #expect(setupCount.withLock { $0 } == 1)
    }
    afterAll {
      #expect(setupCount.withLock { $0 } == 1)
    }
  }
}
