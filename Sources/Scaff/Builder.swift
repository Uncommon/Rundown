public struct ExampleAccumulator {
  var examples: [any ExampleElement]
  
  init(example: any ExampleElement) {
    self.examples = [example]
  }
}

@resultBuilder
public struct ExampleBuilder {
  // TODO: hooks
  
  public static func buildPartialBlock(first: any ExampleElement) -> ExampleAccumulator {
    .init(example: first)
  }
  public static func buildPartialBlock(accumulated: ExampleAccumulator, next: any ExampleElement) -> ExampleAccumulator {
    var result = accumulated
    result.examples.append(next)
    return result
  }
  
  // TODO: if/switch and for support
  
  public static func buildFinalResult(_ accumulator: ExampleAccumulator) -> ExampleGroup {
    .init(elements: accumulator.examples)
  }
}
