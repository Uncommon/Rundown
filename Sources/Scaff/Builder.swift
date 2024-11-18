public struct ExampleAccumulator {
  var examples: [any ExampleElement]
  
  init(example: any ExampleElement) {
    self.examples = [example]
  }
}

@resultbuilder
public struct ExampleBuilder {
  // TODO: hooks
  
  static func buildPartialBlock(first: any ExampleElement) -> ExampleAccumulator {
    .init(example: first)
  }
  static func buildPartialBlock(accumulated: ExampleAccumulator, next: any ExampleElement) {
    accumulated.examples.append(next)
    return accumulated
  }
  
  // TODO: if/switch and for support
  
  static func buildFinalBlock(_ accumulator: ExampleAccumulator) -> ExampleGroup {
    .init(elements: accumulator.examples)
  }
}
