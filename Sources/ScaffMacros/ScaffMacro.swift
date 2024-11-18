import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TestExampleMacro: AttachedMacro {
  static func expansion(of node: AttributeSyntax,
                        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                        in context: some MacroExpansionContext) throws
  -> [CodeBlockItemSyntax] {
    // strip "test" from the function name
    // let [name] = Describe("Name") { [body content] }
    // try [name].execute()
  }
}

@main
struct ScaffPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    TestExampleMacro.self,
  ]
}
