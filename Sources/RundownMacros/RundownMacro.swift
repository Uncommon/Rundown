import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TestExampleMacro: BodyMacro {
  public static func expansion(of node: AttributeSyntax,
                               providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                               in context: some MacroExpansionContext) throws
  -> [CodeBlockItemSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self)
    else { return [] }
    let name = function.name.text.droppingPrefix("test")
    let describeNode: CodeBlockItemSyntax = """
      let _test = Describe("\(raw: name)") {\(raw: function.body?.statements.description ?? "")
      }
      """
    let runNode: CodeBlockItemSyntax = """
      try ExampleRun.run(_test)
      """

    // If it's Swift Testing (ie not inside a class):
    // - take the root element and gather the list of spec names/identifiers
    // - create a Test using __function() that treats each spec as a test case

    return [describeNode, runNode]
  }
}

@main
struct RundownPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    TestExampleMacro.self,
  ]
}

extension String
{
  /// Returns the string with the given prefix removed, or returns the string
  /// unchanged if the prefix does not match.
  func droppingPrefix(_ prefix: String) -> String
  {
    guard hasPrefix(prefix)
    else { return self }
    
    return String(self[prefix.endIndex...])
  }
}
