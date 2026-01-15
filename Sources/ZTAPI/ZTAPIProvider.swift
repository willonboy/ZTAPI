//
//  ZTAPIProvider.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation

// MARK: - Provider

/// 网络请求提供者协议
protocol ZTAPIProvider: Sendable {
    /// 插件列表
    var plugins: [any ZTAPIPlugin] { get }
    /// 重试策略
    var retryPolicy: (any ZTAPIRetryPolicy)? { get }
    /// 发送请求
    /// - Parameters:
    ///   - urlRequest: 请求对象
    ///   - timeout: 超时时间（秒），nil 使用默认值
    ///   - uploadProgress: 上传进度回调（可选）
    func request(_ urlRequest: URLRequest, timeout: TimeInterval?, uploadProgress: ZTUploadProgressHandler?) async throws -> Data
}

/// 默认实现：不带进度回调的请求方法
extension ZTAPIProvider {
    func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        return try await request(urlRequest, timeout: timeout, uploadProgress: nil)
    }
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

    func request(_ urlRequest: URLRequest, timeout: TimeInterval?, uploadProgress: ZTUploadProgressHandler?) async throws -> Data {
        // retryPolicy 在这里一定不为 nil
        guard let policy = retryPolicy else {
            return try await baseProvider.request(urlRequest, timeout: timeout, uploadProgress: uploadProgress)
        }

        var attempt = 0

        while true {
            do {
                return try await baseProvider.request(urlRequest, timeout: timeout, uploadProgress: uploadProgress)
            } catch {
                // 从错误中提取 HTTPURLResponse，以便重试策略能根据状态码判断
                var httpResponse: HTTPURLResponse?
                if let urlResponse = (error as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
                    httpResponse = urlResponse
                }

                guard await policy.shouldRetry(
                    request: urlRequest,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
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
