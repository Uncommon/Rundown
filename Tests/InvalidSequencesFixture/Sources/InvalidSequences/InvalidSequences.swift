import Rundown

// 1) Empty group triggers "Examples must not be empty"
@ExampleBuilder<SyncCall>
func emptyGroup() -> ExampleGroup<SyncCall> {
  describe("empty") { // expected-error {{Examples must not be empty}}
  }
}

// 2) BeforeAll after BeforeEach triggers "BeforeAll must precede BeforeEach"
@ExampleBuilder<SyncCall>
func beforeAllAfterBeforeEach() -> ExampleGroup<SyncCall> {
  describe("beforeAll after beforeEach") { // expected-error {{BeforeAll must precede BeforeEach}}
    beforeEach { }
    beforeAll { }
    it("ex") { }
  }
}

// 3) BeforeAll after examples triggers "BeforeAll cannot appear after examples"
@ExampleBuilder<SyncCall>
func beforeAllAfterExamples() -> ExampleGroup<SyncCall> {
  describe("beforeAll after examples") { // expected-error {{BeforeAll cannot appear after examples}}
    it("ex") { }
    beforeAll { }
  }
}

// 4) BeforeEach after examples triggers "BeforeEach cannot appear after examples"
@ExampleBuilder<SyncCall>
func beforeEachAfterExamples() -> ExampleGroup<SyncCall> {
  describe("beforeEach after examples") { // expected-error {{BeforeEach cannot appear after examples}}
    it("ex") { }
    beforeEach { }
  }
}

// 5) AfterEach after AfterAll triggers "AfterEach must precede AfterAll"
@ExampleBuilder<SyncCall>
func afterEachAfterAfterAll() -> ExampleGroup<SyncCall> {
  describe("afterEach after afterAll") {
    // Doesn't trigger the expected message.. oh well
    afterEach { } // expected-error {{cannot convert value of type 'TestHook<AfterEachPhase, SyncCall>' to expected argument type 'AroundEach<SyncCall>'}}
    afterAll { }
  }
}

// 6) AroundEach after examples triggers "AroundEach cannot appear after examples"
@ExampleBuilder<SyncCall>
func aroundEachAfterExamples() -> ExampleGroup<SyncCall> {
  describe("aroundEacha after examples") { // expected-error {{AroundEach cannot appear after examples}}
    it("ex") { }
    aroundEach { _ in }
  }
}

// 7) Loop ending before examples triggers "Loop must end in example or 'after' element"
@ExampleBuilder<SyncCall>
func loopEndingBeforeExamples() -> ExampleGroup<SyncCall> {
  describe("loop ending before examples") {
    for _ in 1..<2 {
      beforeAll { }
    } // expected-error {{Loop must end in example or 'after' element}}
    it("ex") { }
  }
}

// 8) Group must have examples when ending in BeforePhase
@ExampleBuilder<SyncCall>
func groupEndsInBeforePhase() -> ExampleGroup<SyncCall> {
  describe("group ends in before phase") { // expected-error {{Group must have examples}}
    beforeEach { }
  }
}

// 9) Group must have examples when ending in AroundEachPhase
@ExampleBuilder<SyncCall>
func groupEndsInAroundEachPhase() -> ExampleGroup<SyncCall> {
  describe("group ends in aroundEach phase") { // expected-error {{Group must have examples}}
    aroundEach { _ in }
  }
}
