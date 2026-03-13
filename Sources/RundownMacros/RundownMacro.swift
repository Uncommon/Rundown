import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct RundownPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    DeAsyncMacro.self,
  ]
}
