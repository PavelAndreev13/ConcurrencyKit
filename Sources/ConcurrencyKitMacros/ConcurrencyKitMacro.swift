import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct AsyncBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw MacroError.onlyApplicableToFunctions
        }
        
        let funcName = funcDecl.name.text
        
        guard let completionParam = funcDecl.signature.parameterClause.parameters.last,
              let paramName = completionParam.firstName.text as String?,
              paramName.contains("completion") else {
            throw MacroError.noCompletionHandlerFound
        }
        
        let typeSyntax = completionParam.type
        guard let functionType = typeSyntax.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self) ??
                                 typeSyntax.as(FunctionTypeSyntax.self) else {
            throw MacroError.unsupportedCompletionFormat
        }
        
        let closureParams = Array(functionType.parameters)
        
        var generatedAsyncReturnType = "Void"
        var generatedBody = ""
        
        if closureParams.count == 2 {
            // ПАТТЕРН 1: (SuccessType?, Error?) -> Void
            
            // Получаем текстовое представление первого типа (например, "User?")
            // и убираем знак вопроса, чтобы получить чистый тип "User"
            let rawTypeStr = closureParams[0].type.description
            let cleanTypeStr = rawTypeStr.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
            
            generatedAsyncReturnType = cleanTypeStr
            
            // Генерируем тело для функции с возвращаемым значением
            generatedBody = """
            try await withCheckedThrowingContinuation { continuation in
                self.\(funcName) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        let unknownError = NSError(domain: "AsyncBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error or missing data"])
                        continuation.resume(throwing: unknownError)
                    }
                }
            }
            """
            
        } else if closureParams.count == 1 {
            // ПАТТЕРН 2: (Error?) -> Void
            // Функция ничего не возвращает, просто ждем завершения
            
            generatedBody = """
            try await withCheckedThrowingContinuation { continuation in
                self.\(funcName) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            """
            
        } else {
            throw MacroError.unsupportedCompletionFormat
        }
        
        // 5. Собираем новую async функцию целиком
        let asyncFuncString = """
        func \(funcName)() async throws -> \(generatedAsyncReturnType) {
            \(generatedBody)
        }
        """
        
        // Возвращаем готовый узел
        return [DeclSyntax(stringLiteral: asyncFuncString)]
    }
}

// Расширяем список ошибок
enum MacroError: Error, CustomStringConvertible {
    case onlyApplicableToFunctions
    case noCompletionHandlerFound
    case unsupportedCompletionFormat
    
    var description: String {
        switch self {
        case .onlyApplicableToFunctions: return "@AsyncBridge применим только к функциям."
        case .noCompletionHandlerFound: return "Последний параметр должен называться 'completion' или содержать это слово."
        case .unsupportedCompletionFormat: return "Поддерживаются только замыкания вида (T?, Error?) -> Void или (Error?) -> Void."
        }
    }
}

public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct ConcurrencyKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
    ]
}
