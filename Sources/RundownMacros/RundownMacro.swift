import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

fileprivate func runCall(for context: some MacroExpansionContext) -> String {
  // Assume if it's in a class then it's XCTestCase or a subclass.
  // Swift Testing recommends using structs over classes.
  let isClass = context.lexicalContext.first?.as(ClassDeclSyntax.self) != nil
  return isClass ? "runActivity(under: self)" : "run()"
}

struct NotAFunctionMessage: DiagnosticMessage {
  var message: String { "@Example must be attached to a function" }
  var diagnosticID: SwiftDiagnostics.MessageID {
    .init(domain: "Rundown", id: "notFunction")
  }
  var severity: SwiftDiagnostics.DiagnosticSeverity { .error }
}

struct ReturnTypeMessage: DiagnosticMessage {
  var message: String { "Return type must be ExampleGroup" }
  var diagnosticID: SwiftDiagnostics.MessageID {
    .init(domain: "Rundown", id: "returnType")
  }
  var severity: SwiftDiagnostics.DiagnosticSeverity { .error }
}
struct FixReturnTypeMessage: FixItMessage {
  var message: String { "Change return type to ExampleGroup" }
  var fixItID: MessageID {
    .init(domain: "Rundown", id: "fixReturnType")
  }
}

public struct ExampleMacro: PeerMacro {
  public static func expansion(
    of node: SwiftSyntax.AttributeSyntax,
    providingPeersOf declaration: some SwiftSyntax.DeclSyntaxProtocol,
    in context: some SwiftSyntaxMacros.MacroExpansionContext) throws
  -> [SwiftSyntax.DeclSyntax] {
    // check that declaration is a function
    guard let function = declaration.as(FunctionDeclSyntax.self)
    else {
      context.diagnose(.init(node: declaration,
                             message: NotAFunctionMessage()))
      return []
    }
    // TODO: function should also have @ExampleBuilder
    guard let identifier = function.signature.returnClause?.type.as(IdentifierTypeSyntax.self),
          identifier.name.text == "ExampleGroup"
    else {
      var fixedSignature = function.signature
      // Space before type name to get "-> ExampleGroup"
      // instead of "->ExampleGroup"
      fixedSignature.returnClause = .init(type: TypeSyntax(stringLiteral: " ExampleGroup"))
      let fixit = FixIt(message: FixReturnTypeMessage(),
                        changes: [
                          .replace(oldNode: Syntax(function.signature),
                                   newNode: Syntax(fixedSignature)),
                        ])
      
      context.diagnose(.init(node: function.signature,
                             message: ReturnTypeMessage(),
                             fixIt: fixit))
      return []
    }
    
    // maybe check that function name doesn't start with "test"
    
    let testFuncName = "test" + function.name.text.firstCapitalized
    // TODO: maybe if the original function contained a single Describe,
    // unwrap to that instead of adding the function name as description
    let testFunc = FunctionDeclSyntax(
      name: .identifier(testFuncName),
      signature: .init(parameterClause: .init(parameters: []),
                       effectSpecifiers: .init(throwsClause: .init(throwsSpecifier: "throws"))),
      body: """
        {
          try \(function.name)().named("\(function.name)").\(raw: runCall(for: context))
        }
        """)

    return [.init(testFunc)]
  }
}

@main
struct RundownPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    ExampleMacro.self,
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
  
  var firstCapitalized: String {
    prefix(1).uppercased() + dropFirst()
  }
}
