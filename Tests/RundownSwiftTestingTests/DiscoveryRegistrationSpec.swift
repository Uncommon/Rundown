#if canImport(Darwin) && compiler(>=6.4)
import RundownSwiftTesting
import Testing

@Spec
struct DiscoveryRegistrationSpec {
  @Spec(.leaves)
  struct Leaves {
    var spec: ExampleGroup<AsyncCall> {
      return DiscoveryRegistrationSpec().spec
    }
  }

  var spec: ExampleGroup<AsyncCall> {
    context("Registered group") {
      for _ in 0..<2 {
        it("Repeated item") {
          await Task.yield()
          #expect(Test.current?.name == "examples(unit:)")
          #expect(Test.Case.current?.isParameterized == true)
          #expect(ExampleRunner.current?.path.suffix(2) == ["Registered group", "Repeated item"])
        }
      }
    }
    xIt("Excluded example") { Issue.record("Ran an excluded example") }
    it("Independent example") { #expect(Test.Case.current?.isParameterized == true) }
  }
}

@Spec(.leaves)
struct DiscoveryRegistrationLeafSpec {
  var spec: ExampleGroup<AsyncCall> {
    return DiscoveryRegistrationSpec().spec
  }
}
#endif
