import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin


@main
struct ZTAPIParamPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ZTAPIParam.self,
        ZTAPIParamKey.self,
    ]
}

struct ZTASTError: CustomStringConvertible, Error {
    var description: String

    init(_ desc: String) {
        self.description = desc
    }
}

/// Case 信息
private struct CaseInfo {
    let name: String
    let customKey: String?  // @ZTAPIParamKey 指定的键名
    let isOptional: Bool    // 关联值是否是 Optional 类型
}

public struct ZTAPIParam: MemberMacro, ExtensionMacro {
    // MARK: - MemberMacro

    public static func expansion(of node: AttributeSyntax,
                                 providingMembersOf declaration: some DeclGroupSyntax,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw ZTASTError("@ZTAPIParam 只能用于 enum")
        }

        // 收集所有 case 的信息（包括自定义键名）
        var caseInfos: [CaseInfo] = []

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

            // 检查 case 是否有 @ZTAPIParamKey 注解
            var customKey: String?
            for attribute in caseDecl.attributes {
                if let attrSyntax = attribute.as(AttributeSyntax.self),
                   attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.description == "ZTAPIParamKey" {
                    // 提取参数中的键名
                    if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                       let firstArg = args.first,
                       let keyExpr = firstArg.expression.as(StringLiteralExprSyntax.self) {
                        customKey = keyExpr.representedLiteralValue
                    }
                    break
                }
            }

            for element in caseDecl.elements {
                let name = element.name.text

                // 检查是否有关联值
                guard let parameterClause = element.parameterClause else {
                    throw ZTASTError("@ZTAPIParam 要求所有 case 必须有关联值，case \(name) 没有关联值")
                }

                // 检查关联值约束
                guard let firstParam = parameterClause.parameters.first else {
                    throw ZTASTError("case \(name) 必须有一个关联值")
                }

                let paramType = firstParam.type

                // 检查是否是 Optional 类型（使用 SwiftSyntax 类型检查）
                let isOptional = paramType.is(OptionalTypeSyntax.self)

                // Sendable 约束在编译时检查，这里不做语法分析

                caseInfos.append(CaseInfo(name: name, customKey: customKey, isOptional: isOptional))
            }
        }

        guard !caseInfos.isEmpty else {
            throw ZTASTError("enum 至少需要一个 case")
        }

        // 生成 key 属性
        let keyProperty = generateKeyProperty(caseInfos: caseInfos)

        // 生成 value 属性
        let valueProperty = generateValueProperty(caseInfos: caseInfos)

        // 生成 isValid 方法（只检查非 Optional 的 case）
        let isValidMethod = generateIsValidMethod(caseInfos: caseInfos)

        var members: [DeclSyntax] = []

        members.append(DeclSyntax(stringLiteral: keyProperty))
        members.append(DeclSyntax(stringLiteral: valueProperty))
        members.append(DeclSyntax(stringLiteral: isValidMethod))

        return members
    }

    /// 生成 key 属性
    private static func generateKeyProperty(caseInfos: [CaseInfo]) -> String {
        let switchCases = caseInfos.map { info in
            let key = info.customKey ?? camelToSnakeCase(info.name)
            return "        case .\(info.name):\n            \"\(key)\""
        }.joined(separator: "\n")

        return """
        var key: String {
            switch self {
        \(switchCases)
            }
        }
        """
    }

    /// 生成 value 属性（返回 Sendable）
    private static func generateValueProperty(caseInfos: [CaseInfo]) -> String {
        let cases = caseInfos.map { info in
            "        case .\(info.name)(let v):\n            return v"
        }.joined(separator: "\n")

        return "var value: Sendable {\n    switch self {\n" + cases + "\n    }\n}"
    }

    /// 生成 isValid 静态方法（只检查非 Optional 的 case）
    private static func generateIsValidMethod(caseInfos: [CaseInfo]) -> String {
        // 过滤掉 Optional 的 case
        let requiredCases = caseInfos.filter { !$0.isOptional }

        if requiredCases.isEmpty {
            // 如果所有 case 都是 Optional，isValid 总是返回 true
            return "static func isValid(_ params: [String: Sendable]) -> Bool {\n    return true\n}"
        }

        let keys = requiredCases.map { info in
            info.customKey ?? camelToSnakeCase(info.name)
        }
        let conditions = keys.map { "\"\($0)\"" }.joined(separator: ", ")

        return "static func isValid(_ params: [String: Sendable]) -> Bool {\n    let requiredKeys: Set<String> = [" + conditions + "]\n    return requiredKeys.isSubset(of: params.keys)\n}"
    }

    /// 驼峰命名转蛇形命名
    /// userName -> user_name
    /// zipCode -> zip_code
    /// URL -> url (全大写缩略词处理)
    private static func camelToSnakeCase(_ camelCase: String) -> String {
        var result = ""
        let chars = Array(camelCase)

        for (index, char) in chars.enumerated() {
            if char.isUppercase {
                // 判断是否需要添加下划线：
                // 1. 前一个字符是小写 (userName -> user_Name)
                // 2. 下一个字符是小写且不是第一个字符 (URLPath -> URL_Path)
                let needsUnderscore = (index > 0 && chars[index - 1].isLowercase) ||
                                       (index < chars.count - 1 && chars[index + 1].isLowercase && index > 0)
                if needsUnderscore {
                    result += "_"
                }
                result += char.lowercased()
            } else {
                result.append(char)
            }
        }

        return result
    }

    // MARK: - ExtensionMacro

    public static func expansion(of node: AttributeSyntax,
                                 attachedTo declaration: some DeclGroupSyntax,
                                 providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        // 检查是否已经遵循 ZTAPIParamProtocol
        let currentInherited = declaration.inheritanceClause?.inheritedTypes.compactMap { $0.type.trimmedDescription } ?? []
        if currentInherited.contains("ZTAPIParamProtocol") {
            return []
        }

        // 生成 extension 让 enum 遵循 ZTAPIParamProtocol
        let ext: DeclSyntax = """
        extension \(type.trimmed): ZTAPIParamProtocol {}
        """

        return [ext.cast(ExtensionDeclSyntax.self)]
    }
}
