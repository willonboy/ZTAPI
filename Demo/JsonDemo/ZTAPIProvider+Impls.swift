//
//  ZTAPIProvider+Impls.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation
import Alamofire

// MARK: - URLSession Provider

/// 上传进度上报器（Actor 保证线程安全）
private actor UploadProgressReporter {
    private var handler: ZTUploadProgressHandler?

    func setHandler(_ handler: @escaping ZTUploadProgressHandler) {
        self.handler = handler
    }

    func report(_ progress: ZTUploadProgress) {
        handler?(progress)
    }
}

/// 基于 URLSession 的 Provider 实现
public final class ZTURLSessionProvider: @unchecked Sendable, ZTAPIProvider {
    public static let shared = ZTURLSessionProvider()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
#if DEBUG
        print("[ZTURLSessionProvider] \(urlRequest.httpMethod ?? "") \(urlRequest.url?.absoluteString ?? "")")
#endif

        // 发送请求
        let (data, response) = try await performRequest(urlRequest, uploadProgress: uploadProgress)

        // 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZTAPIError(-1, "Invalid response type")
        }

#if DEBUG
        print("[ZTURLSessionProvider] Response status: \(httpResponse.statusCode)")
#endif

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

        return (data, httpResponse)
    }

    /// 执行请求（支持上传进度）
    private func performRequest(_ request: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, URLResponse) {
        // 如果需要上传进度，使用 upload API + delegate
        if let uploadProgress = uploadProgress {
            let uploadData = request.httpBody ?? Data()
            return try await URLSessionUploadOperation.upload(
                session: session,
                request: request,
                data: uploadData,
                uploadProgress: uploadProgress
            )
        }

        // 默认使用 data API
        return try await session.data(for: request)
    }
}

/// URLSession 上传任务的 async 包装器
/// 桥接 delegate-based upload API 到 async/await
private struct URLSessionUploadOperation {
    static func upload(
        session: URLSession,
        request: URLRequest,
        data: Data,
        uploadProgress: @escaping ZTUploadProgressHandler
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in

            // 创建一个自定义的 delegate 来捕获响应
            final class ResponseCaptureDelegate: NSObject, URLSessionDataDelegate {
                nonisolated(unsafe) var continuation: CheckedContinuation<(Data, URLResponse), Error>?
                nonisolated(unsafe) var responseData = Data()
                nonisolated(unsafe) var urlResponse: URLResponse?

                func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                    responseData.append(data)
                }

                func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                    if let error = error {
                        continuation?.resume(throwing: error)
                    } else if let response = urlResponse {
                        continuation?.resume(returning: (responseData, response))
                    }
                }

                func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                    self.urlResponse = response
                    completionHandler(.allow)
                }
            }

            // 组合 delegate：同时处理进度和响应
            final class CombinedDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
                let progressReporter: UploadProgressReporter
                nonisolated(unsafe) var responseCapture: ResponseCaptureDelegate

                init(progressReporter: UploadProgressReporter, responseCapture: ResponseCaptureDelegate) {
                    self.progressReporter = progressReporter
                    self.responseCapture = responseCapture
                }

                // URLSessionTaskDelegate - 上传进度
                nonisolated func urlSession(
                    _ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64
                ) {
                    Task {
                        await progressReporter.report(ZTUploadProgress(
                            bytesWritten: totalBytesSent,
                            totalBytes: totalBytesExpectedToSend
                        ))
                    }
                }

                // URLSessionDataDelegate - 响应数据
                nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
                    responseCapture.responseData.append(data)
                }

                nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                    responseCapture.urlSession(session, task: task, didCompleteWithError: error)
                }

                nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                    responseCapture.urlResponse = response
                    completionHandler(.allow)
                }
            }

            let progressReporter = UploadProgressReporter()
            let responseCapture = ResponseCaptureDelegate()
            let combinedDelegate = CombinedDelegate(
                progressReporter: progressReporter,
                responseCapture: responseCapture
            )
            responseCapture.continuation = continuation

            Task {
                await progressReporter.setHandler(uploadProgress)
            }

            let config = session.configuration
            let customSession = URLSession(configuration: config, delegate: combinedDelegate, delegateQueue: nil)

            let task = customSession.uploadTask(with: request, from: data)
            task.resume()
        }
    }
}

// MARK: - Alamofire Provider

/// 基于 Alamofire 的 Provider实现
public final class ZTAlamofireProvider: @unchecked Sendable, ZTAPIProvider {
    public static let shared = ZTAlamofireProvider()

    private let session: Session

    public init(session: Session = .default) {
        self.session = session
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
        // 构建请求，添加上传进度支持
        var dataRequest = session.request(urlRequest)
#if DEBUG
            .cURLDescription { description in
                print("cURL: \(description)")
            }
#endif

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

        // 检查状态码是否在错误范围
        guard let httpResponse = dataResponse.response else {
            throw ZTAPIError(-1, "Invalid response type")
        }

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

        return (data, httpResponse)
    }
}

// MARK: - Stub Provider

/// 用于测试的 Stub Provider
public final class ZTStubProvider: @unchecked Sendable, ZTAPIProvider {
    private let stubs: [String: StubResponse]

    public struct StubResponse: Sendable {
        let statusCode: Int
        let data: Data
        let delay: TimeInterval

        init(statusCode: Int = 200, data: Data, delay: TimeInterval = 0) {
            self.statusCode = statusCode
            self.data = data
            self.delay = delay
        }
    }

    public init(stubs: [String: StubResponse] = [:]) {
        self.stubs = stubs
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
        // Stub Provider 忽略进度回调
        _ = uploadProgress

        // 查找 stub
        let key = stubKey(for: urlRequest)
        guard let stub = stubs[key] else {
            throw ZTAPIError(-404, "No stub found for: \(key)")
        }

        // 模拟延迟
        if stub.delay > 0 {
            try await Task.detached {
                try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
            }.value
        }

        // 构造响应
        guard let url = urlRequest.url else {
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

        // 如果状态码 >= 400，视为错误
        if stub.statusCode >= 400 {
            let error = NSError(
                domain: "ZTStubProvider",
                code: stub.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Stub error with status \(stub.statusCode)"]
            )
            throw error
        }

        return (stub.data, response)
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
    public static func jsonStubs(
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
