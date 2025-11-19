import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// This SyntaxRewriter is responsible for finding 'await'
/// expressions and removing the 'await' keyword,
/// leaving only the expression that followed it.
private class AwaitStripper: SyntaxRewriter {
  override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
    // Get the expression *after* 'await' (e.g., "try service.fetch()")
    let innerExpression = node.expression
    
    // Recurse on that expression in case it has nested awaits
    // (e.g., "myFunc(await otherFunc())")
    let rewrittenInnerExpression = self.rewrite(innerExpression).as(
      ExprSyntax.self
    )!
    
    // Return *just* the rewritten inner expression.
    // This effectively removes the 'await' keyword.
    return rewrittenInnerExpression
  }
}

private class TypeChangeRewriter: SyntaxRewriter {
  let oldName: String
  let newName: String
  
  init(oldName: String, newName: String) {
    self.oldName = oldName
    self.newName = newName
  }
  
  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    if node.name.text == oldName {
      var newNode = node
      newNode.name = .identifier(newName)
      return TypeSyntax(newNode)
    }
    return super.visit(node)
  }
  
  override func visit(_ node: GenericArgumentSyntax) -> GenericArgumentSyntax {
    if node.argument.description == oldName {
      return node.with(\.argument, .init(stringLiteral: newName))
    }
    return super.visit(node)
  }
  
  override func visit(_ node: SameTypeRequirementSyntax) -> SameTypeRequirementSyntax {
    if node.rightType.description == oldName {
      return node.with(\.rightType, .init(stringLiteral: newName))
    }
    return super.visit(node)
  }
}

public struct DeAsyncMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroError.message("@DeAsync can only be applied to functions.")
    }
    
    let signature = funcDecl.signature
    let effects = signature.effectSpecifiers
    
    guard effects?.asyncSpecifier != nil else {
      throw MacroError.message(
        "@DeAsync can only be applied to 'async' functions."
      )
    }
    
    var newEffects = effects
    newEffects?.asyncSpecifier = nil  // Strip 'async'
    
    if newEffects?.asyncSpecifier == nil
        && newEffects?.throwsClause?.throwsSpecifier == nil
    {
      newEffects = nil
    }
    
    // TODO: parse type names from the macro invocation
    let typeChangeRewriter = TypeChangeRewriter(oldName: "AsyncCall", newName: "SyncCall")
    let convertedSignature = typeChangeRewriter.rewrite(signature).as(FunctionSignatureSyntax.self)!
    let newSignature = convertedSignature.with(\.effectSpecifiers, newEffects)
    let whereClause = funcDecl.genericWhereClause.map {
      typeChangeRewriter.rewrite($0).as(GenericWhereClauseSyntax.self)!
    }
    
    guard let body = funcDecl.body else {
      throw MacroError.message(
        "@DeAsync cannot be applied to a function with no body (e.g., a protocol requirement)."
      )
    }
    
    let rewriter = AwaitStripper()
    let newBody = rewriter.rewrite(body).as(CodeBlockSyntax.self)!
    
    let macroBaseName =
    node.attributeName.trimmedDescription
      .split(separator: ".").last
      .map(String.init) ?? "AddSyncPeer"
    
    let newAttributes = funcDecl.attributes.filter {
      guard case .attribute(let attr) = $0 else { return true }
      let attrBaseName = attr.attributeName.trimmedDescription
        .split(separator: ".").last
        .map(String.init)
      return attrBaseName != macroBaseName
    }
    
    let newFunc = funcDecl
      .with(\.attributes, newAttributes)
      .with(\.signature, newSignature)
      .with(\.genericWhereClause, whereClause)
      .with(\.body, newBody)
    
    return [DeclSyntax(newFunc)]
  }
}

enum MacroError: Error, CustomStringConvertible {
  case message(String)
  var description: String {
    switch self {
    case .message(let text):
      return text
    }
  }
}

