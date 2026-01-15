//
//  ZTAPIPlugin.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation

// MARK: - Plugin

/// ZTAPI 插件协议，用于拦截和增强请求
protocol ZTAPIPlugin: Sendable {
    /// 请求即将发送
    func willSend(_ request: inout URLRequest) async throws
    /// 收到响应
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws
    /// 发生错误
    func didCatch(_ error: Error) async throws
    /// 处理响应数据，可修改返回的数据（在 didReceive 之后，返回给调用者之前）
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data
}

/// 默认空实现
extension ZTAPIPlugin {
    func willSend(_ request: inout URLRequest) async throws {}
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {}
    func didCatch(_ error: Error) async throws {}
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data { data }
}

// MARK: - Built-in Plugins

/// 日志插件
struct ZTLogPlugin: ZTAPIPlugin {
    enum LogLevel {
        case verbose
        case simple
        case none
    }

    let level: LogLevel

    /// 最大 body 打印长度（字节），超过则只打印字节数
    /// 防止打印大 JSON 导致内存峰值
    private let maxBodyPrintLength: Int

    init(level: LogLevel = .verbose, maxBodyPrintLength: Int = 1024) {
        self.level = level
        self.maxBodyPrintLength = maxBodyPrintLength
    }

    func willSend(_ request: inout URLRequest) async throws {
        guard level != .none else { return }

        if level == .verbose {
            var output = """
            ================== Request ==================
            URL: \(request.url?.absoluteString ?? "nil")
            Method: \(request.httpMethod ?? "nil")
            Headers:
            """

            for (key, value) in request.allHTTPHeaderFields ?? [:] {
                output += "  \(key): \(value)\n"
            }

            if let body = request.httpBody {
                let previewCount = min(body.count, maxBodyPrintLength)
                let preview = body.prefix(previewCount)
                if body.count <= maxBodyPrintLength {
                    if let str = String(data: preview, encoding: .utf8) {
                        output += "Body: \(str)\n"
                    } else {
                        output += "Body: \(body.count) bytes (binary)\n"
                    }
                } else {
                    output += "Body: \(body.count) bytes (truncated)\n"
                }
            }

            output += "============================================"

            print(output)
        } else {
            print("[ZTAPI] \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
        }
    }

    func didReceive(_ response: HTTPURLResponse, data: Data) async throws {
        guard level == .verbose else { return }

        var output = """
        ================== Response =================
        Status: \(response.statusCode)
        Headers:
        """

        for (key, value) in response.allHeaderFields {
            output += "  \(key): \(value)\n"
        }

        let previewCount = min(data.count, maxBodyPrintLength)
        let preview = data.prefix(previewCount)
        if data.count <= maxBodyPrintLength {
            if let str = String(data: preview, encoding: .utf8) {
                output += "Body: \(str)\n"
            } else {
                output += "Body: \(data.count) bytes (binary)\n"
            }
        } else {
            output += "Body: \(data.count) bytes (truncated, first \(previewCount) bytes: "
            if let str = String(data: preview, encoding: .utf8) {
                output += "\(str.prefix(200))...)\n"
            } else {
                output += "binary)\n"
            }
        }
        output += "============================================"

        print(output)
    }

    func didCatch(_ error: Error) async throws {
        guard level != .none else { return }
        print("[ZTAPI] Error: \(error)")
    }
}

/// 认证插件 - 自动添加 Token
struct ZTAuthPlugin: ZTAPIPlugin {
    let token: @Sendable () -> String?

    func willSend(_ request: inout URLRequest) async throws {
        guard let token = token() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

/// Token 刷新器 - 使用 Actor 确保并发安全
/// 实现 single-flight 模式：多个并发请求只会触发一次 token 刷新
public actor ZTTokenRefresher {
    private var refreshingTask: Task<String, Error>?

    public init() {}

    /// 刷新 token（如果已有刷新任务在进行，则复用该任务的结果）
    public func refreshIfNeeded(
        _ action: @escaping () async throws -> String
    ) async throws -> String {
        // 如果已有刷新任务在进行，等待其完成
        if let task = refreshingTask {
            return try await task.value
        }

        // 创建新的刷新任务
        let task = Task {
            defer { refreshingTask = nil }
            return try await action()
        }
        refreshingTask = task
        return try await task.value
    }
}

/// Token 刷新插件
struct ZTTokenRefreshPlugin: ZTAPIPlugin {
    let shouldRefresh: @Sendable (_ error: Error) -> Bool
    let refresh: @Sendable () async throws -> String
    let onRefresh: @Sendable (String) -> Void

    /// Token 刷新器 - 如果为 nil 则不使用 single-flight 模式
    private let refresher: ZTTokenRefresher?

    public init(
        shouldRefresh: @escaping @Sendable (_ error: Error) -> Bool,
        refresh: @escaping @Sendable () async throws -> String,
        onRefresh: @escaping @Sendable (String) -> Void,
        useSingleFlight: Bool = true
    ) {
        self.shouldRefresh = shouldRefresh
        self.refresh = refresh
        self.onRefresh = onRefresh
        self.refresher = useSingleFlight ? ZTTokenRefresher() : nil
    }

    func willSend(_ request: inout URLRequest) async throws {
        // 这里可以实现 token 过期检查
    }

    func didCatch(_ error: Error) async throws {
        if shouldRefresh(error) {
            do {
                let newToken: String
                if let refresher = refresher {
                    // 使用 single-flight 模式刷新
                    newToken = try await refresher.refreshIfNeeded(refresh)
                } else {
                    // 直接刷新（不推荐，可能导致并发刷新）
                    newToken = try await refresh()
                }
                onRefresh(newToken)
            } catch {
                print("[ZTAPI] Token refresh failed: \(error)")
            }
        }
    }
}

/// JSON 解码插件 - 自动将响应数据解析为 JSON 并重新编码
struct ZTJSONDecodePlugin: ZTAPIPlugin {
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
        // 尝试解析 JSON，美化后再编码返回
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return data  // 如果不是 JSON，原样返回
        }
        return prettyData
    }
}

/// 数据解密插件 - 示例：自动解密响应数据
struct ZTDecryptPlugin: ZTAPIPlugin {
    let decrypt: @Sendable (Data) -> Data

    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
        return decrypt(data)
    }
}

/// 响应头添加插件 - 示例：将响应头信息添加到数据中
struct ZTResponseHeaderInjectorPlugin: ZTAPIPlugin {
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
        // 将响应头信息添加到 JSON 中
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
              let jsonObject = json as? [String: Any] else {
            return data
        }

        // 添加响应头元数据
        var metadata: [String: Any] = [
            "_response": [
                "statusCode": response.statusCode,
                "headers": response.allHeaderFields
            ]
        ]
        // 合并原有数据
        metadata.merge(jsonObject) { $1 }

        return try JSONSerialization.data(withJSONObject: metadata)
    }
}
