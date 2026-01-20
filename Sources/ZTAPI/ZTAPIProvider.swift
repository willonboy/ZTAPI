//
//  ZTAPIProvider.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation

/// 网络请求提供者协议
protocol ZTAPIProvider: Sendable {
    /// 发送请求
    /// - Parameters:
    ///   - urlRequest: 请求对象（超时已通过 URLRequest.timeoutInterval 设置）
    ///   - uploadProgress: 上传进度回调（可选）
    /// - Returns: (响应数据, HTTP响应)
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse)
}





/// Provider 重试包装器（请求级别重试）
final class ZTRetryProvider: @unchecked Sendable, ZTAPIProvider {
    private let baseProvider: any ZTAPIProvider
    private let retryPolicy: any ZTAPIRetryPolicy

    init(baseProvider: any ZTAPIProvider, retryPolicy: any ZTAPIRetryPolicy) {
        self.baseProvider = baseProvider
        self.retryPolicy = retryPolicy
    }

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            do {
                return try await baseProvider.request(urlRequest, uploadProgress: uploadProgress)
            } catch {
                // 从错误中提取 HTTPURLResponse，以便重试策略能根据状态码判断
                var httpResponse: HTTPURLResponse?
                if let urlResponse = (error as NSError).userInfo["HTTPURLResponse"] as? HTTPURLResponse {
                    httpResponse = urlResponse
                }

                guard await retryPolicy.shouldRetry(request: urlRequest, error: error,
                                                    attempt: attempt, response: httpResponse) else {
                    throw error
                }

                let delay = await retryPolicy.delay(for: attempt)
                attempt += 1

#if DEBUG
                print("[ZTAPI] Request-level retry (attempt \(attempt)) after \(delay)s delay")
#endif

                try await Task.detached {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }.value
            }
        }
    }
}
