#if RUNDOWN_DISCOVERY_PROTOTYPE && os(macOS) && compiler(>=6.4)
import RundownSwiftTesting
import Testing

@Spec
struct DiscoveryRegistrationSpec: Spec {
  var spec: ExampleGroup<AsyncCall> {
    context("Registered group") {
      it("Runs under Swift Testing") {
        await Task.yield()
        #expect(Test.current?.name == "examples()")
        #expect(ExampleRunner.current?.path == [
          "DiscoveryRegistrationSpec", "Registered group", "Runs under Swift Testing",
        ])
      }
    }
  }
}
#endif
