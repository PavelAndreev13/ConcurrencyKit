import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ConcurrencyKitMacros)
import ConcurrencyKitMacros

let testMacros: [String: Macro.Type] = [
    "AsyncBridge": AsyncBridgeMacro.self,
]
#endif

final class AsyncBridgeMacroTests: XCTestCase {
    
    // MARK: - Тест 1: Функция возвращает данные и ошибку
    func testAsyncBridgeWithDataAndError() throws {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            // 1. Исходный код, который пишет пользователь
            """
            @AsyncBridge
            func fetchUser(id: Int, completion: @escaping (User?, Error?) -> Void) {
                // Старый код сети
            }
            """,
            // 2. Ожидаемый код (оригинал + сгенерированная async функция)
            expandedSource: """
            func fetchUser(id: Int, completion: @escaping (User?, Error?) -> Void) {
                // Старый код сети
            }
            
            func fetchUser() async throws -> User {
                try await withCheckedThrowingContinuation { continuation in
                    self.fetchUser { result, error in
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
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("Макросы поддерживаются только на определенных платформах")
        #endif
    }
    
    // MARK: - Тест 2: Функция возвращает только ошибку (Void результат)
    func testAsyncBridgeWithErrorOnly() throws {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func saveContext(completion: @escaping (Error?) -> Void) {
                // Код сохранения
            }
            """,
            expandedSource: """
            func saveContext(completion: @escaping (Error?) -> Void) {
                // Код сохранения
            }
            
            func saveContext() async throws -> Void {
                try await withCheckedThrowingContinuation { continuation in
                    self.saveContext { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
            """,
            macros: testMacros
        )
        #endif
    }
    
    // MARK: - Тест 3: Проверка выброса ошибки компиляции
    func testAsyncBridgeFailsWithoutCompletion() throws {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func doSomethingSync() {
                print("Hello")
            }
            """,
            expandedSource: """
            func doSomethingSync() {
                print("Hello")
            }
            """,
            // Здесь мы проверяем, что наш макрос правильно выдает ошибку в Xcode,
            // если параметр completion не найден!
            diagnostics: [
                DiagnosticSpec(message: "Последний параметр должен называться 'completion' или содержать это слово.", line: 1, column: 1)
            ],
            macros: testMacros
        )
        #endif
    }
}
