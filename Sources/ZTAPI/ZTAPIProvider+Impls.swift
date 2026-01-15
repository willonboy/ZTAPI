//
//  ZTAPIProvider+Impls.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation
import Alamofire

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

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
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
                let (data, response) = try await performRequest(request, uploadProgress: uploadProgress)

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

                guard await policy.shouldRetry(
                    request: request,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
                ) else {
                    // 不再重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

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

    /// 执行请求（支持上传进度）
    private func performRequest(_ request: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, URLResponse) {
        // URLSession 原生 API 不支持在 async/await 中直接获取上传进度
        // 如果需要上传进度，建议使用 ZTAlamofireProvider
        // 这里提供一个简化的实现，使用标准 async/await API
        return try await session.data(for: request)
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

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
        var attempt = 0
        var currentRequest = urlRequest

        // 应用超时时间
        let effectiveTimeout = timeout ?? defaultTimeout
        currentRequest.timeoutInterval = effectiveTimeout

        // 在循环外部定义 mutableRequest，使 catch 块也能访问
        var mutableRequest = currentRequest

        while true {
            do {
                mutableRequest = currentRequest

                // 执行 willSend 插件
                for plugin in plugins {
                    try await plugin.willSend(&mutableRequest)
                }

                // 构建请求，添加上传进度支持
                var dataRequest = session.request(mutableRequest)
                    .cURLDescription { description in
#if DEBUG
                        if effectiveTimeout != 60 {
                            print("[ZTAPI] Request timeout: \(effectiveTimeout)s")
                        }
                        print("cURL: \(description)")
#endif
                    }

                // 添加上传进度回调
                if let uploadProgress = uploadProgress {
                    dataRequest = dataRequest.uploadProgress { progress in
                        uploadProgress(ZTUploadProgress(
                            bytesWritten: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount
                        ))
                    }
                }

                // 发送请求并获取完整响应
                let dataResponse = await dataRequest.serializingData().response

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
                } else if let afError = error as? AFError {
                    // Alamofire 5: AFError 是枚举，通过 underlyingError 获取 URLResponse
                    switch afError {
                    case .responseValidationFailed(reason: let reason):
                        if case .unacceptableStatusCode(let code) = reason,
                           let url = mutableRequest.url {
                            // 创建一个临时响应用于重试判断
                            httpResponse = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)
                        }
                    case .sessionTaskFailed(let sessionError):
                        if let urlResponse = (sessionError as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
                            httpResponse = urlResponse
                        }
                    default:
                        break
                    }
                }

                guard await policy.shouldRetry(
                    request: mutableRequest,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
                ) else {
                    // 不再重试，执行 didCatch 插件后抛出错误
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }

                // 计算延迟并重试
                let delay = await policy.delay(for: attempt)
                attempt += 1

#if DEBUG
                print("[ZTAlamofireProvider] Retrying request (attempt \(attempt)) after \(delay)s delay")
#endif

                // 使用 Task.detached 确保延迟在后台线程执行
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

    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
        // Stub Provider 忽略进度回调，直接返回数据
        _ = uploadProgress
        var attempt = 0

        // 定义实际的请求逻辑（带重试）
        func executeRequest() async throws -> Data {
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
                    guard let url = request.url else {
                        throw ZTAPIError(-1, "Request URL is nil in stub provider")
                    }
                    guard let response = HTTPURLResponse(
                        url: url,
                        statusCode: stub.statusCode,
                        httpVersion: nil,
                        headerFields: nil
                    ) else {
                        throw ZTAPIError(-1, "Failed to create HTTPURLResponse for stub")
                    }

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

        // 如果设置了超时，使用竞速模式
        if let timeout = timeout {
            // 复制需要的属性以避免捕获 self
            let capturedPlugins = plugins
            let capturedRetryPolicy = retryPolicy
            let capturedStubs = stubs

            return try await withThrowingTaskGroup(of: Data.self) { group in
                // 添加请求任务
                group.addTask {
                    // 在子任务中执行请求
                    var attempt = 0
                    while true {
                        do {
                            var request = urlRequest

                            // 执行 willSend 插件
                            for plugin in capturedPlugins {
                                try await plugin.willSend(&request)
                            }

                            // 查找 stub（内联 stubKey 逻辑避免捕获 self）
                            let method = request.httpMethod ?? "GET"
                            var urlStr = request.url?.absoluteString ?? ""
                            if urlStr.hasSuffix("?") {
                                urlStr.removeLast()
                            }
                            let key = "\(method):\(urlStr)"
                            guard let stub = capturedStubs[key] else {
                                throw ZTAPIError(-404, "No stub found for: \(key)")
                            }

                            // 模拟延迟
                            if stub.delay > 0 {
                                try await Task.detached {
                                    try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
                                }.value
                            }

                            // 构造响应
                            guard let url = request.url else {
                                throw ZTAPIError(-1, "Request URL is nil in stub provider")
                            }
                            guard let response = HTTPURLResponse(
                                url: url,
                                statusCode: stub.statusCode,
                                httpVersion: nil,
                                headerFields: nil
                            ) else {
                                throw ZTAPIError(-1, "Failed to create HTTPURLResponse for stub")
                            }

                            // 执行 didReceive 插件
                            for plugin in capturedPlugins {
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

                            // 执行 process 插件
                            var processedData = stub.data
                            for plugin in capturedPlugins {
                                processedData = try await plugin.process(processedData, response: response)
                            }

                            return processedData

                        } catch {
                            // 检查是否需要重试
                            guard let policy = capturedRetryPolicy else {
                                for plugin in capturedPlugins {
                                    try await plugin.didCatch(error)
                                }
                                throw error
                            }

                            if await policy.shouldRetry(
                                request: urlRequest,
                                error: error,
                                attempt: attempt,
                                response: nil
                            ) {
                                let delay = await policy.delay(for: attempt)
                                attempt += 1
                                try await Task.detached {
                                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                }.value
                            } else {
                                for plugin in capturedPlugins {
                                    try await plugin.didCatch(error)
                                }
                                throw error
                            }
                        }
                    }
                }

                // 添加超时任务
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ZTAPIError(-1, "Request timeout after \(timeout)s")
                }

                do {
                    // 返回先完成的结果
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                } catch {
                    // 超时或其他错误，执行 didCatch 插件后抛出
                    group.cancelAll()
                    for plugin in plugins {
                        try await plugin.didCatch(error)
                    }
                    throw error
                }
            }
        } else {
            // 没有超时设置，直接执行请求
            return try await executeRequest()
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
