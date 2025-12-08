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
  describe("beforeAllAfterBeforeEach") {
    beforeEach { }
    beforeAll { } // expected-error {{BeforeAll must precede BeforeEach}}
  }
}

// 3) BeforeAll after examples triggers "BeforeAll cannot appear after examples"
@ExampleBuilder<SyncCall>
func beforeAllAfterExamples() -> ExampleGroup<SyncCall> {
  describe("beforeAllAfterExamples") {
    it("ex") { }
    beforeAll { } // expected-error {{BeforeAll cannot appear after examples}}
  }
}

// 4) BeforeEach after examples triggers "BeforeEach cannot appear after examples"
@ExampleBuilder<SyncCall>
func beforeEachAfterExamples() -> ExampleGroup<SyncCall> {
  describe("beforeEachAfterExamples") {
    it("ex") { }
    beforeEach { } // expected-error {{BeforeEach cannot appear after examples}}
  }
}

// 5) AfterEach after AfterAll triggers "AfterEach must precede AfterAll"
@ExampleBuilder<SyncCall>
func afterEachAfterAfterAll() -> ExampleGroup<SyncCall> {
  describe("afterEachAfterAfterAll") {
    afterEach { }
    afterAll { } // expected-error {{AfterEach must precede AfterAll}}
  }
}

// 6) AroundEach after examples triggers "AroundEach cannot appear after examples"
@ExampleBuilder<SyncCall>
func aroundEachAfterExamples() -> ExampleGroup<SyncCall> {
  describe("aroundEachAfterExamples") {
    it("ex") { }
    aroundEach { _ in } // expected-error {{AroundEach cannot appear after examples}}
  }
}

// 7) Loop ending before examples triggers "Loop must end in example or 'after' element"
@ExampleBuilder<SyncCall>
func loopEndingBeforeExamples() -> ExampleGroup<SyncCall> {
  describe("loopEndingBeforeExamples") {
    for _ in 1..<2 {
      beforeAll { } // expected-error {{Loop must end in example or 'after' element}}
    }
  }
}

// 8) Group must have examples when ending in BeforePhase
@ExampleBuilder<SyncCall>
func groupEndsInBeforePhase() -> ExampleGroup<SyncCall> {
  describe("groupEndsInBeforePhase") {
    beforeEach { } // expected-error {{Group must have examples when ending in BeforePhase}}
  }
}

// 9) Group must have examples when ending in AroundEachPhase
@ExampleBuilder<SyncCall>
func groupEndsInAroundEachPhase() -> ExampleGroup<SyncCall> {
  describe("groupEndsInAroundEachPhase") {
    aroundEach { _ in } // expected-error {{Group must have examples when ending in AroundEachPhase}}
  }
}
