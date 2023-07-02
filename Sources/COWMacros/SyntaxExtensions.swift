//
//  SyntaxExtensions.swift
//
//
//  Created by WeZZard on 7/1/23.
//

import SwiftSyntax

internal struct COWStoragePropertyDescriptor {
  
  internal let keyword: TokenSyntax
  
  internal let name: TokenSyntax
  
  internal let type: TypeSyntax?
  
  internal let initializer: ExprSyntax
  
  internal func makeVarDecl() -> DeclSyntax {
    if let typeAnnotation = type {
      return
        """
        \(keyword) \(name) : \(typeAnnotation) = \(initializer)
        """
    } else {
      return
        """
        \(keyword) \(name) = \(initializer)
        """
    }
  }
  
}

extension StructDeclSyntax {
  
  internal var copyOnWriteStorageName: TokenSyntax? {
    guard case .attribute(let attribute) = attributes?.first else {
      return nil
    }
    return attribute.argument?.storageName
  }
  
  internal func isEquivalent(to other: StructDeclSyntax) -> Bool {
    return identifier == other.identifier
  }
  
}

extension VariableDeclSyntax {
  
  internal struct Info {
    
    internal let hasStorage: Bool
    
    internal let isMarkedIncluded: Bool
    
    internal let isMarkedExcluded: Bool
    
    internal let hasDefaultValue: Bool
    
  }
  
  internal var info: Info? {
    guard let binding = bindings.first else {
      return nil
    }
    
    let hasStorage = binding.accessor == nil
    let hasDefaultValue = binding.initializer != nil
    let isMarkedIncluded = hasMacroApplication(COWIncludedMacro.name)
    let isMarkedExcluded = hasMacroApplication(COWExcludedMacro.name)
    
    return Info(
      hasStorage: hasStorage,
      isMarkedIncluded: isMarkedIncluded,
      isMarkedExcluded: isMarkedExcluded,
      hasDefaultValue: hasDefaultValue
    )
  }
  
  internal var storagePropertyDescritors: [COWStoragePropertyDescriptor] {
    bindings.compactMap { binding in
      binding.storagePropertyDescritor(bindingKeyword)
    }
  }
  
  internal var isIncludeable: Bool {
    guard let info = info else {
      return false
    }
    return !info.isMarkedExcluded
  }
  
}

extension AttributeListSyntax.Element {
  
  /// Attribute list may contains a `#if ... #else ... #end` wrapped
  /// attributes. Unconditional attribute name means attributes outside
  /// `#if ... #else ... #end`.
  ///
  internal func hasName(_ name: String) -> Bool {
    switch self {
    case .attribute(let syntax):
      return syntax.hasName(name)
    case .ifConfigDecl:
      return false
    }
  }
  
}


extension AttributeSyntax {
  
  internal func hasName(_ name: String) -> Bool {
    return attributeName.tokens(viewMode: .all).map({ $0.tokenKind }) == [.identifier(name)]
  }
  
}

extension PatternBindingSyntax {
  
  internal func storagePropertyDescritor(_ keyword: TokenSyntax) -> COWStoragePropertyDescriptor? {
    guard let identPattern = pattern.as(IdentifierPatternSyntax.self),
          let initializer = initializer else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: identPattern.identifier,
      type: typeAnnotation?.type,
      initializer: initializer.value
    )
  }
  
}

extension AttributeSyntax.Argument {
  
  /// The copy-on-write storage name
  internal var storageName: TokenSyntax? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard args.count >= 1 else {
      return nil
    }
    
    let arg0 = args[args.startIndex]
    
    guard case .identifier("storageName") = arg0.label?.tokenKind else {
      return nil
    }
    
    guard let storageNameArg
            = arg0.expression.as(StringLiteralExprSyntax.self) else {
      return nil
    }
    
    return TokenSyntax(
      .identifier(storageNameArg.trimmed.segments.description),
      presence: .present
    )
  }
  
  internal var storagePropertyDescriptor: COWStoragePropertyDescriptor? {
    guard case .argumentList(let args) = self else {
      return nil
    }
    
    guard args.count >= 4 else {
      return nil
    }
    
    let arg0 = args[args.startIndex]
    let arg1 = args[args.index(args.startIndex, offsetBy: 1)]
    let arg2 = args[args.index(args.startIndex, offsetBy: 2)]
    let arg3 = args[args.index(args.startIndex, offsetBy: 3)]
    
    guard case .identifier("keyword") = arg0.label?.tokenKind,
          case .identifier("name") = arg1.label?.tokenKind,
          case .identifier("type") = arg2.label?.tokenKind,
          case .identifier("initialValue") = arg3.label?.tokenKind else {
      return nil
    }
    
    let keywordArg = arg0.expression.as(MemberAccessExprSyntax.self)
    let nameArg = arg1.expression.as(StringLiteralExprSyntax.self)
    let typeArg = arg2.expression.as(StringLiteralExprSyntax.self)
    let initialValueArg = arg3.expression.as(StringLiteralExprSyntax.self)
    
    guard let keyword = keywordArg?.name else {
      return nil
    }
    guard let name = nameArg?.trimmed.segments.description else {
      return nil
    }
    let type = typeArg?.trimmed.segments.description
    guard let initialValue = initialValueArg?.trimmed.segments.description else {
      return nil
    }
    
    return COWStoragePropertyDescriptor(
      keyword: keyword,
      name: TokenSyntax(.stringSegment(name), presence: .present),
      type: type.map(TypeSyntax.init),
      initializer: ExprSyntax(stringLiteral: initialValue)
    )
  }
  
}

extension DeclGroupSyntax {
  
  internal func hasMemberStruct(equivalentTo other: StructDeclSyntax) -> Bool {
    for member in memberBlock.members {
      if let `struct` = member.as(MemberDeclListItemSyntax.self)?.decl.as(StructDeclSyntax.self) {
        if `struct`.isEquivalent(to: other) {
          return true
        }
      }
    }
    return false
  }
  
  internal var isStruct: Bool {
    return self.is(StructDeclSyntax.self)
  }
  
}
