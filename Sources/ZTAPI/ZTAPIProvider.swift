//
//  ZTAPIProvider.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation
import Alamofire

// MARK: - Retry Policy

/// 重试策略协议
protocol ZTAPIRetryPolicy: Sendable {
    /// 是否应该重试
    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool
    /// 下次重试前的延迟时间（秒）
    func delay(for attempt: Int) async -> TimeInterval
}

/// 固定次数重试策略
struct ZTFixedRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let retryableCodes: Set<Int>
    let retryableErrorCodes: Set<Int>

    init(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        retryableCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableErrorCodes: Set<Int> = [-1001, -1003, -1004, -1005, -1009]
    ) {
        self.maxAttempts = maxAttempts
        self.delay = delay
        self.retryableCodes = retryableCodes
        self.retryableErrorCodes = retryableErrorCodes
    }

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        // 检查 HTTP 状态码
        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        // 检查 NSError 错误码
        let nsError = error as NSError
        if retryableErrorCodes.contains(nsError.code) {
            return true
        }

        return false
    }

    func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}

/// 指数退避重试策略
struct ZTExponentialBackoffRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    let retryableCodes: Set<Int>
    let retryableErrorCodes: Set<Int>

    init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        multiplier: Double = 2.0,
        retryableCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableErrorCodes: Set<Int> = [-1001, -1003, -1004, -1005, -1009]
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.retryableCodes = retryableCodes
        self.retryableErrorCodes = retryableErrorCodes
    }

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        let nsError = error as NSError
        if retryableErrorCodes.contains(nsError.code) {
            return true
        }

        return false
    }

    func delay(for attempt: Int) async -> TimeInterval {
        let delay = baseDelay * pow(multiplier, Double(attempt))
        return min(delay, maxDelay)
    }
}

/// 自定义条件重试策略
struct ZTConditionalRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let shouldRetryCondition: @Sendable (
        _ request: URLRequest,
        _ error: Error,
        _ attempt: Int,
        _ response: HTTPURLResponse?
    ) async -> Bool

    init(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        shouldRetryCondition: @escaping @Sendable (
            _ request: URLRequest,
            _ error: Error,
            _ attempt: Int,
            _ response: HTTPURLResponse?
        ) async -> Bool
    ) {
        self.maxAttempts = maxAttempts
        self.delay = delay
        self.shouldRetryCondition = shouldRetryCondition
    }

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }
        return await shouldRetryCondition(request, error, attempt, response)
    }

    func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}

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

    init(level: LogLevel = .verbose) {
        self.level = level
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
                output += "Body: \(body.count) bytes\n"
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

        output += "Body: \(data.count) bytes\n"
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

/// Token 刷新插件
struct ZTTokenRefreshPlugin: ZTAPIPlugin {
    let shouldRefresh: @Sendable (_ error: Error) -> Bool
    let refresh: @Sendable () async throws -> String
    let onRefresh: @Sendable (String) -> Void

    func willSend(_ request: inout URLRequest) async throws {
        // 这里可以实现 token 过期检查
    }

    func didCatch(_ error: Error) async throws {
        if shouldRefresh(error) {
            do {
                let newToken = try await refresh()
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

// MARK: - Provider

/// 网络请求提供者协议
protocol ZTAPIProvider: Sendable {
    /// 插件列表
    var plugins: [any ZTAPIPlugin] { get }
    /// 重试策略
    var retryPolicy: (any ZTAPIRetryPolicy)? { get }
    /// 发送请求
    func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data
}

/// 创建可覆盖重试策略的 Provider
func overridableRetryProvider(base: any ZTAPIProvider, policy: (any ZTAPIRetryPolicy)?) -> any ZTAPIProvider {
    guard let policy = policy else {
        return base
    }
    return ZTOverridableRetryProviderImpl(baseProvider: base, retryPolicy: policy)
}

/// Provider 包装器实现（内部类）
final class ZTOverridableRetryProviderImpl: @unchecked Sendable, ZTAPIProvider {
    let plugins: [any ZTAPIPlugin]
    let retryPolicy: (any ZTAPIRetryPolicy)?
    private let baseProvider: any ZTAPIProvider

    init(baseProvider: any ZTAPIProvider, retryPolicy: any ZTAPIRetryPolicy) {
        self.baseProvider = baseProvider
        self.plugins = baseProvider.plugins
        self.retryPolicy = retryPolicy
    }

    func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
        // retryPolicy 在这里一定不为 nil
        guard let policy = retryPolicy else {
            return try await baseProvider.request(urlRequest, timeout: timeout)
        }

        var attempt = 0

        while true {
            do {
                return try await baseProvider.request(urlRequest, timeout: timeout)
            } catch {
                guard await policy.shouldRetry(
                    request: urlRequest,
                    error: error,
                    attempt: attempt,
                    response: nil
                ) else {
                    throw error
                }

                let delay = await policy.delay(for: attempt)
                attempt += 1

#if DEBUG
                print("[ZTAPI] Request-level retry (attempt \(attempt)) after \(delay)s delay")
#endif

                // 使用 Task.detached 确保延迟在后台线程执行，避免阻塞主线程
                try await Task.detached {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }.value
            }
        }
    }
}

// MARK: - URLSession Provider

/// 基于 URLSession 的 Provider 实现
final class ZTURLSessionProvider: @unchecked Sendable, ZTAPIProvider {
    static let shared = ZTURLSessionProvider()

    let plugins: [any ZTAPIPlugin]
    let retryPolicy: (any ZTAPIRetryPolicy)?
    private let session: URLSession
    private let defaultTimeout: TimeInterval

    init(
        plugins: [any ZTAPIPlugin] = [],
        retryPolicy: (any ZTAPIRetryPolicy)? = nil,
        session: URLSession = .shared,
        defaultTimeout: TimeInterval = 60
    ) {
        self.plugins = plugins
        self.retryPolicy = retryPolicy
        self.session = session
        self.defaultTimeout = defaultTimeout
    }

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var attempt = 0
        var request = urlRequest
        request.timeoutInterval = timeout ?? defaultTimeout

        while true {
            do {

                // 执行 willSend 插件
                for plugin in plugins {
                    try await plugin.willSend(&request)
                }

#if DEBUG
                let effectiveTimeout = timeout ?? defaultTimeout
                if effectiveTimeout != 60 {
                    print("[ZTURLSessionProvider] Request timeout: \(effectiveTimeout)s")
                }
                print("[ZTURLSessionProvider] \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
#endif

                // 发送请求
                let (data, response) = try await session.data(for: request)

                // 检查 HTTP 状态码
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ZTAPIError(-1, "Invalid response type")
                }

#if DEBUG
                print("[ZTURLSessionProvider] Response status: \(httpResponse.statusCode)")
#endif

                // 执行 didReceive 插件
                for plugin in plugins {
                    try await plugin.didReceive(httpResponse, data: data)
                }

                // 检查状态码是否在错误范围
                if httpResponse.statusCode >= 400 {
                    let error = NSError(
                        domain: "ZTURLSessionProvider",
                        code: httpResponse.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)",
                            "HTTPURLResponse": httpResponse
                        ]
                    )
                    throw error
                }

                // 执行 process 插件，允许修改响应数据
                var processedData = data
                for plugin in plugins {
                    processedData = try await plugin.process(processedData, response: httpResponse)
                }

                return processedData

            } catch {
                // 检查是否需要重试
                guard let policy = retryPolicy else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 尝试从错误中获取 HTTPURLResponse
                var httpResponse: HTTPURLResponse?
                if let urlResponse = (error as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
                    httpResponse = urlResponse
                }

                // 检查是否应该重试
                guard await policy.shouldRetry(
                    request: urlRequest,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
                ) else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 计算延迟并重试
                let delay = await policy.delay(for: attempt)
                attempt += 1

#if DEBUG
                print("[ZTURLSessionProvider] Retrying request (attempt \(attempt)) after \(delay)s delay")
#endif

                // 使用 Task.detached 确保延迟在后台线程执行
                try await Task.detached {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }.value
            }
        }
    }
}

// MARK: - Alamofire Provider

/// 基于 Alamofire 的 Provider实现
final class ZTAlamofireProvider: @unchecked Sendable, ZTAPIProvider {
    static let shared = ZTAlamofireProvider()

    let plugins: [any ZTAPIPlugin]
    let retryPolicy: (any ZTAPIRetryPolicy)?
    private let session: Session
    private let defaultTimeout: TimeInterval

    init(
        plugins: [any ZTAPIPlugin] = [],
        retryPolicy: (any ZTAPIRetryPolicy)? = nil,
        session: Session = .default,
        defaultTimeout: TimeInterval = 60
    ) {
        self.plugins = plugins
        self.retryPolicy = retryPolicy
        self.session = session
        self.defaultTimeout = defaultTimeout
    }

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var attempt = 0
        var currentRequest = urlRequest

        // 应用超时时间
        let effectiveTimeout = timeout ?? defaultTimeout
        currentRequest.timeoutInterval = effectiveTimeout

        while true {
            do {
                var request = currentRequest

                // 执行 willSend 插件
                for plugin in plugins {
                    try await plugin.willSend(&request)
                }

                // 发送请求并获取完整响应
                let dataResponse = await session.request(request)
                    .cURLDescription { description in
#if DEBUG
                        if effectiveTimeout != 60 {
                            print("[ZTAPI] Request timeout: \(effectiveTimeout)s")
                        }
                        print("cURL: \(description)")
#endif
                    }
                    .serializingData()
                    .response

                // 检查是否有错误
                guard let data = dataResponse.value else {
                    if let error = dataResponse.error {
                        throw error
                    }
                    throw ZTAPIError(-1, "Empty response")
                }

                // 执行 didReceive 插件
                var processedData = data
                if let httpResponse = dataResponse.response {
                    for plugin in plugins {
                        try await plugin.didReceive(httpResponse, data: data)
                    }

                    // 检查状态码是否在错误范围
                    if httpResponse.statusCode >= 400 {
                        let error = NSError(
                            domain: "ZTAlamofireProvider",
                            code: httpResponse.statusCode,
                            userInfo: [
                                NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode)",
                                "HTTPURLResponse": httpResponse
                            ]
                        )
                        throw error
                    }

                    // 执行 process 插件，允许修改响应数据
                    for plugin in plugins {
                        processedData = try await plugin.process(processedData, response: httpResponse)
                    }
                }

                return processedData

            } catch {
                // 检查是否需要重试
                guard let policy = retryPolicy else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 尝试从错误中获取 HTTPURLResponse
                var httpResponse: HTTPURLResponse?
                if let urlResponse = (error as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
                    httpResponse = urlResponse
                }

                // 检查是否应该重试
                guard await policy.shouldRetry(
                    request: currentRequest,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
                ) else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 计算延迟并重试
                let delay = await policy.delay(for: attempt)
                attempt += 1

#if DEBUG
                print("[ZTAPI] Retrying request (attempt \(attempt)) after \(delay)s delay")
#endif

                // 使用 Task.detached 确保延迟在后台线程执行，避免阻塞主线程
                try await Task.detached {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }.value
            }
        }
    }
}

// MARK: - Stub Provider

/// 用于测试的 Stub Provider
final class ZTStubProvider: @unchecked Sendable, ZTAPIProvider {
    let plugins: [any ZTAPIPlugin]
    let retryPolicy: (any ZTAPIRetryPolicy)?
    private let stubs: [String: StubResponse]

    struct StubResponse: Sendable {
        let statusCode: Int
        let data: Data
        let delay: TimeInterval

        init(statusCode: Int = 200, data: Data, delay: TimeInterval = 0) {
            self.statusCode = statusCode
            self.data = data
            self.delay = delay
        }
    }

    init(
        plugins: [any ZTAPIPlugin] = [],
        retryPolicy: (any ZTAPIRetryPolicy)? = nil,
        stubs: [String: StubResponse] = [:]
    ) {
        self.plugins = plugins
        self.retryPolicy = retryPolicy
        self.stubs = stubs
    }

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var attempt = 0

        while true {
            do {
                var request = urlRequest

                // 执行 willSend 插件
                for plugin in plugins {
                    try await plugin.willSend(&request)
                }

                // 查找 stub
                let key = stubKey(for: request)
                guard let stub = stubs[key] else {
                    throw ZTAPIError(-404, "No stub found for: \(key)")
                }

                // 模拟延迟（使用 detached 确保在后台线程）
                if stub.delay > 0 {
                    try await Task.detached {
                        try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
                    }.value
                }

                // 构造响应
                let url = request.url!
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: stub.statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!

                // 执行 didReceive 插件
                for plugin in plugins {
                    try await plugin.didReceive(response, data: stub.data)
                }

                // 如果状态码 >= 400，视为错误
                if stub.statusCode >= 400 {
                    let error = NSError(
                        domain: "ZTStubProvider",
                        code: stub.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Stub error with status \(stub.statusCode)"]
                    )
                    throw error
                }

                // 执行 process 插件，允许修改响应数据
                var processedData = stub.data
                for plugin in plugins {
                    processedData = try await plugin.process(processedData, response: response)
                }

                return processedData

            } catch {
                // 检查是否需要重试
                guard let policy = retryPolicy else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 检查是否应该重试
                if await policy.shouldRetry(
                    request: urlRequest,
                    error: error,
                    attempt: attempt,
                    response: nil
                ) {
                    // 计算延迟并重试
                    let delay = await policy.delay(for: attempt)
                    attempt += 1

                    // 使用 Task.detached 确保延迟在后台线程执行
                    try await Task.detached {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }.value
                } else {
                    // 不重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }
            }
        }
    }

    private func stubKey(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        var url = request.url?.absoluteString ?? ""
        // 移除末尾的 ? 以处理没有查询参数但 URL 编码后带 ? 的情况
        if url.hasSuffix("?") {
            url.removeLast()
        }
        return "\(method):\(url)"
    }

    /// 便捷初始化 - 使用 JSON 字典
    static func jsonStubs(
        _ stubs: [String: [String: Any]],
        statusCode: Int = 200
    ) -> ZTStubProvider {
        let dataStubs = stubs.mapValues { dict in
            StubResponse(
                statusCode: statusCode,
                data: (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            )
        }
        return ZTStubProvider(stubs: dataStubs)
    }
}
