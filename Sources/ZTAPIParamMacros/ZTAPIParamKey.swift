import SwiftSyntax
import SwiftSyntaxMacros

public struct ZTAPIParamKey: PeerMacro {
    public static func expansion(of node: AttributeSyntax,
                                 providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        // 不生成任何代码，只作为标记使用
        // 实际的键名由 @ZTAPIParam 宏读取此宏的参数来处理
        return []
    }
}
