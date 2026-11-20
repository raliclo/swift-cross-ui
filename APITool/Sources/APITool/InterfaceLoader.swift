import Foundation
import SwiftSyntax
import SwiftParser
import MacroToolkit

enum InterfaceLoader {
    enum Error: LocalizedError {
        case failedToReadFile(Swift.Error)

        var errorDescription: String? {
            switch self {
                case .failedToReadFile(let error):
                    return "Failed to read file: \(error.localizedDescription)"
            }
        }
    }

    static func loadInterface(_ file: URL, moduleName: String) throws(Error) -> SwiftInterface {
        let sourceText: String
        do {
            sourceText = try String(contentsOf: file)
        } catch {
            throw Error.failedToReadFile(error)
        }

        let sourceFile = Parser.parse(source: sourceText)
        var structs: [Struct] = []
        var enums: [Enum] = []
        var extensions: [Extension] = []
        // Xcode 27's interfaces put many declarations inside `#if compiler(...)`
        // blocks; the first clause is the one a current compiler reads.
        // Xcode 27 的介面把許多宣告放在 `#if compiler(...)` 區塊裡;第一個子句就是現行編譯器會讀的那一個。
        func collect(_ items: CodeBlockItemListSyntax) {
            for stmt in items {
                guard case .decl(let decl) = stmt.item else { continue }
                if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
                    if case .statements(let inner)? = ifConfig.clauses.first?.elements {
                        collect(inner)
                    }
                    continue
                }
                let wrapped = Decl(decl)
                if let enumDecl = wrapped.asEnum {
                    enums.append(enumDecl)
                } else if let structDecl = wrapped.asStruct {
                    structs.append(structDecl)
                } else if let extensionDecl = wrapped._syntax.as(ExtensionDeclSyntax.self) {
                    extensions.append(Extension(extensionDecl))
                }
            }
        }
        collect(sourceFile.statements)

        return SwiftInterface(
            moduleName: moduleName,
            sourceFile: sourceFile,
            structs: structs,
            enums: enums,
            extensions: extensions
        )
    }
}
