//
//  ZTAPIProvider+Impls.swift
//  ZTAPI
//
//  Copyright (c) 2026 trojanzhang. All rights reserved.
//
//  This file is part of ZTAPI.
//
//  ZTAPI is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ZTAPI is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with ZTAPI. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import ZTAPICore

// MARK: - URLSession Provider

private actor UploadTaskState {
    private let continuation: CheckedContinuation<(Data, URLResponse), Error>

    private var responseData = Data()
    private var response: URLResponse?
    private var finished = false

    init(continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        self.continuation = continuation
    }

    func append(_ data: Data) {
        guard !finished else { return }
        responseData.append(data)
    }

    func setResponse(_ response: URLResponse) {
        self.response = response
    }

    func finish(error: Error?) {
        guard !finished else { return }
        finished = true

        if let error {
            // If response exists, attach it to the error for retry policy
            let httpResponse = response.flatMap { $0 as? HTTPURLResponse }
            if let httpResponse {
                let wrappedError = ZTAPIError(
                    (error as NSError).code,
                    error.localizedDescription,
                    httpResponse: httpResponse
                )
                continuation.resume(throwing: wrappedError)
            } else {
                continuation.resume(throwing: error)
            }
            return
        }

        guard let response else {
            continuation.resume(
                throwing: ZTAPIError.emptyResponse
            )
            return
        }

        continuation.resume(
            returning: (responseData, response)
        )
    }
}

// MARK: - Upload Delegate

private final class UploadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let state: UploadTaskState
    private let progressHandler: ZTUploadProgressHandler?

    init(state: UploadTaskState, progressHandler: ZTUploadProgressHandler? = nil) {
        self.state = state
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let progressHandler else { return }

        let progress = ZTUploadProgress(
            bytesWritten: totalBytesSent,
            totalBytes: totalBytesExpectedToSend
        )

        // App layer Provider: directly guarantee main thread semantics
        Task { @MainActor in
            progressHandler(progress)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
        didReceive data: Data) {
        Task {
            await state.append(data)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        Task {
            await state.setResponse(response)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: Error?) {
        Task {
            await state.finish(error: error)
        }
    }
}

// MARK: - Upload Executor

private actor URLSessionUploadExecutor {
    private var session: URLSession?
    private var task: URLSessionUploadTask?

    func upload(
        baseSession: URLSession,
        request: URLRequest,
        body: Data,
        progress: ZTUploadProgressHandler?
    ) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = UploadTaskState(continuation: continuation)
                let delegate = UploadDelegate(state: state, progressHandler: progress)

                let newSession = URLSession(
                    configuration: baseSession.configuration,
                    delegate: delegate,
                    delegateQueue: nil
                )
                self.session = newSession

                let uploadTask = newSession.uploadTask(with: request, from: body)
                self.task = uploadTask
                uploadTask.resume()
            }
        } onCancel: {
            Task {
                await self.cancel()
            }
        }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func finish() {
        session?.finishTasksAndInvalidate()
    }
}

private extension URLSessionUploadExecutor {
    static func upload(
        baseSession: URLSession,
        request: URLRequest,
        body: Data,
        progress: ZTUploadProgressHandler?
    ) async throws -> (Data, URLResponse) {
        let executor = URLSessionUploadExecutor()
        do {
            let result = try await executor.upload(
                baseSession: baseSession,
                request: request,
                body: body,
                progress: progress
            )
            await executor.finish()
            return result
        } catch {
            await executor.finish()
            throw error
        }
    }
}

// MARK: - URLSession Provider

/// Convert system errors to ZTAPIError
/// - If NSError (including URLError etc.), extract code and localizedDescription to build ZTAPIError
/// - If already ZTAPIError, return directly
/// - Other error types are thrown as-is, let users handle via ZTTransferErrorPlugin
private func convertSystemError(_ error: Error, httpResponse: HTTPURLResponse? = nil) -> Error {
    // Already ZTAPIError, return directly
    if let apiError = error as? ZTAPIError {
        return apiError
    }

    // URLError may contain HTTPURLResponse
    if let urlError = error as? URLError {
        return ZTAPIError(
            urlError.code.rawValue,
            urlError.localizedDescription,
            httpResponse: httpResponse
        )
    }

    // NSError and its subclasses
    if type(of: error) is NSError.Type {
        let nsError = error as NSError
        return ZTAPIError(
            nsError.code,
            nsError.localizedDescription,
            httpResponse: httpResponse
        )
    }

    // Other error types returned as-is
    return error
}

public final class ZTURLSessionProvider: @unchecked Sendable, ZTAPIProvider {
    public static let shared = ZTURLSessionProvider()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse

        do {
            if let uploadProgress {
                guard let body = urlRequest.httpBody else {
                    throw ZTAPIError.uploadRequiresBody
                }

                (data, response) = try await
                    URLSessionUploadExecutor.upload(
                        baseSession: session,
                        request: urlRequest,
                        body: body,
                        progress: uploadProgress
                    )
            } else {
                (data, response) = try await session.data(for: urlRequest)
            }
        } catch {
            // Error may already contain httpResponse from UploadTaskState.finish (for upload requests)
            let httpResponse = (error as? ZTAPIError)?.httpResponse
            throw convertSystemError(error, httpResponse: httpResponse)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZTAPIError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            throw ZTAPIError(
                httpResponse.statusCode,
                "HTTP Error \(httpResponse.statusCode)",
                httpResponse: httpResponse
            )
        }

        return (data, httpResponse)
    }
}

// MARK: - Alamofire Provider

import Alamofire

/// Provider implementation based on Alamofire
public final class ZTAlamofireProvider: @unchecked Sendable, ZTAPIProvider {
    public static let shared = ZTAlamofireProvider()
    private let session: Session

    /// Initialize with custom Configuration
    public init(configuration: URLSessionConfiguration = .af.default) {
        self.session = Session(configuration: configuration)
    }

    /// Initialize with custom Session (for SSL Pinning, etc.)
    public init(session: Session) {
        self.session = session
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
        let request: DataRequest = {
            var req = session.request(urlRequest)
            if let uploadProgress {
                req = req.uploadProgress { progress in
                    uploadProgress(
                        ZTUploadProgress(
                            bytesWritten: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount
                        )
                    )
                }
            }
            return req
        }()

        try Task.checkCancellation()
        // Send request and get complete response
        let dataResponse = await withTaskCancellationHandler {
            let serializer = request.serializingData()
            return await serializer.response
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()

        // Check if there are errors
        guard let data = dataResponse.value else {
            if let error = dataResponse.error {
                throw convertSystemError(error, httpResponse: dataResponse.response)
            }
            throw ZTAPIError.emptyResponse(httpResponse: dataResponse.response)
        }

        // Check if status code is in error range
        guard let httpResponse = dataResponse.response else {
            throw ZTAPIError.invalidResponse
        }

        if httpResponse.statusCode >= 400 {
            throw ZTAPIError(
                httpResponse.statusCode,
                "HTTP Error \(httpResponse.statusCode)",
                httpResponse: httpResponse
            )
        }

        return (data, httpResponse)
    }
}

// MARK: - Stub Provider

/// Stub Provider internal errors
private extension ZTAPIError {
    /// Stub not found
    static func stubNotFound(_ key: String) -> ZTAPIError {
        ZTAPIError(80040001, "No stub found for: \(key)")
    }

    /// Stub URL is nil
    static var stubURLNil: ZTAPIError {
        ZTAPIError(80040002, "Request URL is nil in stub provider")
    }

    /// Stub failed to create HTTPURLResponse
    static var stubResponseCreationFailed: ZTAPIError {
        ZTAPIError(80040003, "Failed to create HTTPURLResponse for stub")
    }
}

/// Stub Provider for testing / preview
public final class ZTStubProvider: @unchecked Sendable, ZTAPIProvider {
    private let stubs: [String: StubResponse]

    public struct StubResponse: Sendable {
        let statusCode: Int
        let data: Data
        let delay: TimeInterval

        public init(
            statusCode: Int = 200,
            data: Data,
            delay: TimeInterval = 0
        ) {
            self.statusCode = statusCode
            self.data = data
            self.delay = delay
        }
    }

    public init(stubs: [String: StubResponse] = [:]) {
        self.stubs = stubs
    }

    public func request(
        _ urlRequest: URLRequest,
        uploadProgress: ZTUploadProgressHandler? = nil
    ) async throws -> (Data, HTTPURLResponse) {

        // Stub Provider does not support progress callback
        _ = uploadProgress

        try Task.checkCancellation()

        // Find stub
        let key = stubKey(for: urlRequest)
        guard let stub = stubs[key] else {
            throw ZTAPIError.stubNotFound(key)
        }

        // Simulate network latency (cancellable)
        if stub.delay > 0 {
            try await Task.sleep(
                nanoseconds: UInt64(stub.delay * 1_000_000_000)
            )
        }

        try Task.checkCancellation()

        // Construct HTTPURLResponse
        guard let url = urlRequest.url else {
            throw ZTAPIError.stubURLNil
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            throw ZTAPIError.stubResponseCreationFailed
        }

        // Throw directly if status code is error
        if stub.statusCode >= 400 {
            throw ZTAPIError(
                stub.statusCode,
                "Stub error with status \(stub.statusCode)",
                httpResponse: response
            )
        }

        return (stub.data, response)
    }

    // MARK: - Key

    private func stubKey(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        var url = request.url?.absoluteString ?? ""

        // Handle possible trailing ? after URL encoding
        if url.hasSuffix("?") {
            url.removeLast()
        }

        return "\(method):\(url)"
    }

    // MARK: - Convenience

    /// Quickly build Stub using JSON dictionary (recommended for testing only)
    public static func jsonStubs(
        _ stubs: [String: [String: Any]],
        statusCode: Int = 200,
        delay: TimeInterval = 0
    ) -> ZTStubProvider {
        let dataStubs: [String: StubResponse] = stubs.mapValues { dict in
            StubResponse(
                statusCode: statusCode,
                data: (try? JSONSerialization.data(withJSONObject: dict)) ?? Data(),
                delay: delay
            )
        }
        return ZTStubProvider(stubs: dataStubs)
    }
}
