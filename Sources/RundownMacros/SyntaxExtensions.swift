import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension MacroExpansionContext {
  var inAsyncFunction: Bool {
    for lexicalContext in self.lexicalContext {
      if let function = lexicalContext.as(FunctionDeclSyntax.self) {
        return function.isAsync
      }
    }
    return false
  }
  var inMainActorFunction: Bool {
    for lexicalContext in self.lexicalContext {
      if let function = lexicalContext.as(FunctionDeclSyntax.self) {
        return function.isMainActorIsolated
      }
    }
    return false
  }
  var inMainActorType: Bool {
    for lexicalContext in self.lexicalContext {
      if let structDecl = lexicalContext.as(StructDeclSyntax.self) {
        return structDecl.isMainActorIsolated
      }
      if let classDecl = lexicalContext.as(StructDeclSyntax.self) {
        return classDecl.isMainActorIsolated
      }
    }
    return false
  }
}

extension FunctionDeclSyntax {
  var isAsync: Bool {
    signature.effectSpecifiers?.asyncSpecifier != nil
  }
  var isMainActorIsolated: Bool {
    attributes.contains { $0.trimmedDescription == "@MainActor" }
  }
}

extension StructDeclSyntax {
  var isMainActorIsolated: Bool {
    attributes.contains { $0.trimmedDescription == "@MainActor" }
  }
}

extension ClassDeclSyntax {
  var isMainActor: Bool {
    attributes.contains { $0.trimmedDescription == "@MainActor" }
  }
  var isXCTestCase: Bool {
    inheritanceClause?.inheritedTypes.contains { $0.trimmedDescription == "XCTestCase" } ?? false
  }
}
