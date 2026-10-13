import Rundown

// 1) Empty group triggers "Group must have examples"
@ExampleBuilder<SyncCall>
func emptyGroup() -> ExampleGroup<SyncCall> {
  describe("empty") { // expected-error {{Group must have examples}}
    beforeEach { }
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
  describe("afterEach after afterAll") { // expected-error {{AfterEach must precede AfterAll}}
    it("ex") { }
    afterAll { }
    afterEach { }
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

// 10) An if/else whose branches end before examples
@ExampleBuilder<SyncCall>
func conditionalEndingBeforeExamples() -> ExampleGroup<SyncCall> {
  describe("conditional ending before examples") {
    if Bool.random() { // expected-error {{Conditional must end in example or 'after' element}}
      beforeEach { }
    }
    else { // expected-error {{Conditional must end in example or 'after' element}}
      beforeEach { }
    }
    it("ex") { }
  }
}

// 11) An if without else whose branch ends before examples
@ExampleBuilder<SyncCall>
func optionalEndingBeforeExamples() -> ExampleGroup<SyncCall> {
  describe("optional ending before examples") {
    if Bool.random() { // expected-error {{Conditional must end in example or 'after' element}}
      beforeEach { }
    }
    it("ex") { }
  }
}

// 12) A switch whose cases end before examples
@ExampleBuilder<SyncCall>
func switchEndingBeforeExamples() -> ExampleGroup<SyncCall> {
  describe("switch ending before examples") {
    switch Int.random(in: 0..<2) {
      case 0: beforeEach { } // expected-error {{Conditional must end in example or 'after' element}}
      default: beforeEach { } // expected-error {{Conditional must end in example or 'after' element}}
    }
    it("ex") { }
  }
}

// 13) An if without else whose branch ends in an after hook
@ExampleBuilder<SyncCall>
func optionalEndingInAfterHook() -> ExampleGroup<SyncCall> {
  describe("optional ending in after hook") {
    if Bool.random() { // expected-error {{Conditional without 'else' must end in an example}}
      it("ex") { }
      afterEach { }
    }
  }
}

// 14) An after hook with nothing before it
@ExampleBuilder<SyncCall>
func afterHookFirst() -> ExampleGroup<SyncCall> {
  describe("after hook first") { // expected-error {{AfterEach and AfterAll must come after examples}}
    afterAll { }
  }
}

// 15) A before hook followed directly by an after hook
@ExampleBuilder<SyncCall>
func afterHookAfterBeforeHook() -> ExampleGroup<SyncCall> {
  describe("after hook after before hook") { // expected-error {{AfterEach and AfterAll must come after examples}}
    beforeEach { }
    afterEach { }
    it("ex") { }
  }
}

// 16) An example after an after hook
@ExampleBuilder<SyncCall>
func exampleAfterAfterHook() -> ExampleGroup<SyncCall> {
  describe("example after after hook") { // expected-error {{Examples cannot appear after AfterEach or AfterAll}}
    it("ex") { }
    afterEach { }
    it("more") { }
  }
}

@MainActor
private func mainThing() { }

// 17) A main actor group built in a free function, with a hook before a context
@MainActor
@ExampleBuilder<SyncMainCall>
func mainActorHookThenContext() -> ExampleGroup<SyncMainCall> { // expected-error {{Main actor groups must be built in a type that conforms to MainActorSuite; use a method of such a type instead of a free function}}
  beforeAll { @MainActor in mainThing() }
  context("Search by summary") { @MainActor in
    it("finds items") { }
  }
}

// 18) A main actor group built in a free function, with just an example
@MainActor
@ExampleBuilder<SyncMainCall>
func mainActorExample() -> ExampleGroup<SyncMainCall> { // expected-error {{Main actor groups must be built in a type that conforms to MainActorSuite; use a method of such a type instead of a free function}}
  it("ex") { }
}
