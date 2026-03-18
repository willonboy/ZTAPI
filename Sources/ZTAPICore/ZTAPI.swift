//
//  ZTAPI.swift
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

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// API parameter protocol
public protocol ZTAPIParamProtocol: Sendable {
    var key: String { get }
    var value: Sendable { get }
    static func isValid(_ params: [String: Sendable]) -> Bool
}

public extension ZTAPIParamProtocol {
    /// 默认实现：总是返回 true
    static func isValid(_ params: [String: Sendable]) -> Bool { true }
}

/// Key-value parameter for direct parameter passing
public enum ZTAPIKVParam: ZTAPIParamProtocol {
    case kv(String, Sendable)

    public var key: String {
        switch self {
        case .kv(let k, _): return k
        }
    }

    public var value: Sendable {
        switch self {
        case .kv(_, let v): return v
        }
    }

    public static func isValid(_ params: [String: Sendable]) -> Bool {
        return true
    }
}

// MARK: - SSE Types

/// SSE (Server-Sent Events) message
public struct ZTSSEMessage: Sendable {
    /// Event type (from "event:" field)
    public let type: String
    /// Message data (from "data:" field, may be multiple lines)
    public let data: String
    /// Message ID (from "id:" field)
    public let id: String?
    /// Retry interval in milliseconds (from "retry:" field)
    public let retry: Int?

    public init(type: String = "message", data: String, id: String? = nil, retry: Int? = nil) {
        self.type = type
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// SSE connection state
public enum ZTSSConnectionState: Sendable {
    case connecting
    case connected
    case disconnected
    case failed(Error)
}

// MARK: - WebSocket Types

/// WebSocket message type
public enum ZTWebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

/// WebSocket close code (RFC 6455)
public struct ZTWebSocketCloseCode: RawRepresentable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let normalClosure = ZTWebSocketCloseCode(rawValue: 1000)
    public static let goingAway = ZTWebSocketCloseCode(rawValue: 1001)
    public static let protocolError = ZTWebSocketCloseCode(rawValue: 1002)
    public static let unsupportedData = ZTWebSocketCloseCode(rawValue: 1003)
    public static let noStatus = ZTWebSocketCloseCode(rawValue: 1005)
    public static let abnormalClosure = ZTWebSocketCloseCode(rawValue: 1006)
    public static let invalidPayload = ZTWebSocketCloseCode(rawValue: 1007)
    public static let policyViolation = ZTWebSocketCloseCode(rawValue: 1008)
    public static let messageTooBig = ZTWebSocketCloseCode(rawValue: 1009)
    public static let mandatoryExt = ZTWebSocketCloseCode(rawValue: 1010)
    public static let internalError = ZTWebSocketCloseCode(rawValue: 1011)
    public static let serviceRestart = ZTWebSocketCloseCode(rawValue: 1012)
    public static let tryAgainLater = ZTWebSocketCloseCode(rawValue: 1013)
    public static let tlsHandshake = ZTWebSocketCloseCode(rawValue: 1015)
}

/// WebSocket connection state
public enum ZTWebSocketConnectionState: Sendable {
    case connecting
    case connected
    case disconnected
    case failed(Error)
}

/// WebSocket handle returned from connect, provides message stream and send methods
public final class ZTWebSocketHandle: @unchecked Sendable {
    private let webSocketTask: URLSessionWebSocketTask?
    private let taskLock = NSLock()
    private var _connectionState: ZTWebSocketConnectionState = .disconnected

    public var connectionState: ZTWebSocketConnectionState {
        taskLock.withLock { _connectionState }
    }

    init(webSocketTask: URLSessionWebSocketTask?) {
        self.webSocketTask = webSocketTask
    }

    /// Send text message
    public func send(_ text: String) async throws {
        guard let task = webSocketTask else {
            throw ZTAPIError.webSocketNotConnected
        }
        try await task.send(.string(text))
    }

    /// Send binary data
    public func send(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw ZTAPIError.webSocketNotConnected
        }
        try await task.send(.data(data))
    }

    /// Send ping
    public func sendPing() async throws {
        guard let task = webSocketTask else {
            throw ZTAPIError.webSocketNotConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Disconnect WebSocket
    public func disconnect(code: ZTWebSocketCloseCode = .normalClosure, reason: String? = nil) {
        guard let task = webSocketTask else { return }

        taskLock.withLock {
            _connectionState = .disconnected
        }

        task.cancel(with: .normalClosure, reason: reason?.data(using: .utf8))
    }

    /// Receive messages stream
    public func receiveStream() -> AsyncStream<ZTWebSocketMessage> {
        AsyncStream { [weak self] continuation in
            guard let self = self, let task = self.webSocketTask else {
                continuation.finish()
                return
            }

            self.taskLock.withLock {
                self._connectionState = .connected
            }

            Task {
                while true {
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text):
                            continuation.yield(.text(text))
                        case .data(let data):
                            continuation.yield(.data(data))
                        @unknown default:
                            break
                        }
                    } catch {
                        self.taskLock.withLock {
                            self._connectionState = .failed(error)
                        }
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.disconnect()
            }
        }
    }
}

// MARK: - ZTAPI

/// ZTAPI network request class
public class ZTAPI<P: ZTAPIParamProtocol>: @unchecked Sendable {
    private let stateLock = NSLock()
    private var _urlStr: String
    private var _method: ZTHTTPMethod
    private var _params: [String: Sendable] = [:]
    private var _headers: [String: String] = [:]
    private var _bodyData: Data? = nil
    private var _encoding: any ZTParameterEncoding = ZTURLEncoding()

    private let provider: any ZTAPIProvider
    private var _plugins: [any ZTAPIPlugin] = []
    private var _requestTimeout: TimeInterval?
    private var _requestRetryPolicy: (any ZTAPIRetryPolicy)?
    private var _uploadProgressHandler: ZTUploadProgressHandler?

    public var urlStr: String {
        stateLock.withLock { _urlStr }
    }

    public var method: ZTHTTPMethod {
        stateLock.withLock { _method }
    }

    public var params: [String: Sendable] {
        stateLock.withLock { _params }
    }

    public var headers: [String: String] {
        stateLock.withLock { _headers }
    }

    public var bodyData: Data? {
        stateLock.withLock { _bodyData }
    }

    public var encoding: any ZTParameterEncoding {
        stateLock.withLock { _encoding }
    }

    private struct StateSnapshot {
        let urlStr: String
        let method: ZTHTTPMethod
        let params: [String: Sendable]
        let headers: [String: String]
        let bodyData: Data?
        let encoding: any ZTParameterEncoding
        let plugins: [any ZTAPIPlugin]
        let requestTimeout: TimeInterval?
        let requestRetryPolicy: (any ZTAPIRetryPolicy)?
        let uploadProgressHandler: ZTUploadProgressHandler?
    }

    public init(_ url: String, _ method: ZTHTTPMethod = .get, provider: any ZTAPIProvider) {
        self._urlStr = url
        self._method = method
        self.provider = provider
    }

    /// Add request parameters
    @discardableResult
    public func params(_ ps: P...) -> Self {
        stateLock.withLock {
            ps.forEach { p in
                _params[p.key] = p.value
            }
        }
        return self
    }

    /// Add request parameters (dictionary form)
    @discardableResult
    public func params(_ ps: [String: Sendable]) -> Self {
        stateLock.withLock {
            _params.merge(ps) { _, new in new }
        }
        return self
    }

    /// Add HTTP headers
    @discardableResult
    public func headers(_ hds: ZTAPIHeader...) -> Self {
        stateLock.withLock {
            for header in hds {
                _headers[header.key] = header.value
            }
        }
        return self
    }

    /// Set parameter encoding
    @discardableResult
    public func encoding(_ e: any ZTParameterEncoding) -> Self {
        stateLock.withLock {
            _encoding = e
        }
        return self
    }

    /// Set raw request body
    @discardableResult
    public func body(_ data: Data) -> Self {
        stateLock.withLock {
            _bodyData = data
        }
        return self
    }

    // MARK: - Upload

    /// Upload item
    public enum ZTUploadItem: Sendable {
        case data(Data, name: String, fileName: String? = nil, mimeType: ZTMimeType)
        case file(URL, name: String, fileName: String? = nil, mimeType: ZTMimeType)

        public var bodyPart: ZTMultipartFormBodyPart {
            switch self {
            case .data(let data, let name, let fileName, let mimeType):
                return .data(data, name: name, fileName: fileName, mimeType: mimeType)
            case .file(let url, let name, let fileName, let mimeType):
                return .file(url, name: name, fileName: fileName, mimeType: mimeType)
            }
        }
    }

    /// Upload multiple items (supports mixed Data and File)
    @discardableResult
    public func upload(_ items: ZTUploadItem...) -> Self {
        let parts = items.map { $0.bodyPart }
        return multipart(ZTMultipartFormData(parts: parts))
    }

    /// Upload using Multipart data (supports multiple files + other form fields)
    @discardableResult
    public func multipart(_ formData: ZTMultipartFormData) -> Self {
        stateLock.withLock {
            _bodyData = nil
            _encoding = ZTMultipartEncoding(formData)
        }
        return self
    }

    // MARK: - Config

    /// Set request timeout (seconds)
    @discardableResult
    public func timeout(_ interval: TimeInterval) -> Self {
        stateLock.withLock {
            _requestTimeout = interval
        }
        return self
    }

    /// Set retry policy
    @discardableResult
    public func retry(_ policy: (any ZTAPIRetryPolicy)?) -> Self {
        stateLock.withLock {
            _requestRetryPolicy = policy
        }
        return self
    }

    /// Set upload progress callback
    @discardableResult
    public func uploadProgress(_ handler: @escaping ZTUploadProgressHandler) -> Self {
        stateLock.withLock {
            _uploadProgressHandler = handler
        }
        return self
    }

    /// Add plugins
    @discardableResult
    public func plugins(_ ps: (any ZTAPIPlugin)...) -> Self {
        stateLock.withLock {
            _plugins.append(contentsOf: ps)
        }
        return self
    }

    // MARK: - Plugin Execution

    /// Execute willSend plugins
    private func _executeWillSendPlugins(_ plugins: [any ZTAPIPlugin], request: inout URLRequest) async throws {
        for plugin in plugins {
            try await plugin.willSend(&request)
        }
    }

    /// Execute didReceive plugins
    private func _executeDidReceivePlugins(_ plugins: [any ZTAPIPlugin], response: HTTPURLResponse, data: Data, request: URLRequest) async throws {
        for plugin in plugins {
            try await plugin.didReceive(response, data: data, request: request)
        }
    }

    /// Execute process plugins
    private func _executeProcessPlugins(_ plugins: [any ZTAPIPlugin], data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data {
        var processedData = data
        for plugin in plugins {
            processedData = try await plugin.process(processedData, response: response, request: request)
        }
        return processedData
    }

    /// Execute didCatch plugins
    private func _executeDidCatchPlugins(_ plugins: [any ZTAPIPlugin], error: Error, request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws {
        for plugin in plugins {
            try await plugin.didCatch(error, request: request, response: response, data: data)
        }
    }

    // MARK: - Send

    /// Send request and return raw Data
    @discardableResult
    public func send() async throws -> Data {
        let snapshot = stateLock.withLock {
            StateSnapshot(
                urlStr: _urlStr,
                method: _method,
                params: _params,
                headers: _headers,
                bodyData: _bodyData,
                encoding: _encoding,
                plugins: _plugins,
                requestTimeout: _requestTimeout,
                requestRetryPolicy: _requestRetryPolicy,
                uploadProgressHandler: _uploadProgressHandler
            )
        }

        if P.isValid(snapshot.params) == false {
            throw ZTAPIError.invalidParams
        }

        guard let url = URL(string: snapshot.urlStr) else {
            throw ZTAPIError.invalidURL(snapshot.urlStr)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = snapshot.method.rawValue

        for (key, value) in snapshot.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // bodyData takes priority over encoding
        if let body = snapshot.bodyData {
            urlRequest.httpBody = body
        } else {
            try snapshot.encoding.encode(&urlRequest, with: snapshot.params)
        }

        // Set timeout (default 60 seconds)
        urlRequest.timeoutInterval = snapshot.requestTimeout ?? 60

        // Execute willSend plugins
        try await _executeWillSendPlugins(snapshot.plugins, request: &urlRequest)

        let effectiveProvider = if let policy = snapshot.requestRetryPolicy {
            ZTRetryProvider(baseProvider: provider, retryPolicy: policy)
        } else {
            provider
        }

        var httpResponse: HTTPURLResponse?
        var responseData: Data?
        do {
            let (data, response) = try await effectiveProvider.request(
                urlRequest,
                uploadProgress: snapshot.uploadProgressHandler
            )
            httpResponse = response
            responseData = data

            // Execute didReceive plugins
            try await _executeDidReceivePlugins(snapshot.plugins, response: response, data: data, request: urlRequest)

            // Execute process plugins
            let processedData = try await _executeProcessPlugins(snapshot.plugins, data: data, response: response, request: urlRequest)

            return processedData
        } catch {
            // Execute didCatch plugins with request context and optional response data
            // Priority: response from successful request > response in ZTAPIError > nil
            if httpResponse == nil {
                httpResponse = (error as? ZTAPIError)?.httpResponse
            }
            try await _executeDidCatchPlugins(snapshot.plugins, error: error, request: urlRequest, response: httpResponse, data: responseData)
            throw error
        }
    }

    // MARK: - Send SSE

    /// Send SSE request and return message stream
    public func sendSSE() async throws -> AsyncStream<ZTSSEMessage> {
        let snapshot = stateLock.withLock {
            StateSnapshot(
                urlStr: _urlStr,
                method: _method,
                params: _params,
                headers: _headers,
                bodyData: _bodyData,
                encoding: _encoding,
                plugins: _plugins,
                requestTimeout: _requestTimeout,
                requestRetryPolicy: nil,
                uploadProgressHandler: nil
            )
        }

        guard let url = URL(string: snapshot.urlStr) else {
            throw ZTAPIError.invalidURL(snapshot.urlStr)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = snapshot.method.rawValue
        // SSE requires Accept: text/event-stream
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        for (key, value) in snapshot.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Encode params
        try snapshot.encoding.encode(&urlRequest, with: snapshot.params)

        // Set timeout (default 24h for SSE)
        urlRequest.timeoutInterval = snapshot.requestTimeout ?? 86400

        // Execute willSend plugins
        try await _executeWillSendPlugins(snapshot.plugins, request: &urlRequest)

        let delegate = SSEDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)

        return AsyncStream { [weak self] continuation in
            delegate.continuation = continuation
            task.resume()

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stateLock.withLock {
                    self?._requestTimeout = nil
                }
                session.invalidateAndCancel()
            }
        }
    }

    // MARK: - WebSocket Connect

    /// Connect to WebSocket endpoint and return handle
    public func connect() async throws -> ZTWebSocketHandle {
        let snapshot = stateLock.withLock {
            StateSnapshot(
                urlStr: _urlStr,
                method: _method,
                params: _params,
                headers: _headers,
                bodyData: _bodyData,
                encoding: _encoding,
                plugins: _plugins,
                requestTimeout: _requestTimeout,
                requestRetryPolicy: nil,
                uploadProgressHandler: nil
            )
        }

        guard let url = URL(string: snapshot.urlStr) else {
            throw ZTAPIError.invalidURL(snapshot.urlStr)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = snapshot.requestTimeout ?? 60

        for (key, value) in snapshot.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Execute willSend plugins
        try await _executeWillSendPlugins(snapshot.plugins, request: &urlRequest)

        let task = URLSession.shared.webSocketTask(with: urlRequest)
        task.resume()
        let handle = ZTWebSocketHandle(webSocketTask: task)

        // Execute didReceive plugins on successful connection
        let response = HTTPURLResponse(url: url, statusCode: 101, httpVersion: nil, headerFields: nil)!
        try await _executeDidReceivePlugins(snapshot.plugins, response: response, data: Data(), request: urlRequest)

        return handle
    }

#if DEBUG
    deinit {
        print("dealloc", _urlStr)
    }
#endif
}

// MARK: - SSE Delegate

private final class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var continuation: AsyncStream<ZTSSEMessage>.Continuation?
    private var buffer: String = ""

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        buffer += chunk
        processBuffer()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        if httpResponse.mimeType != "text/event-stream" && httpResponse.mimeType != nil {
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation?.finish()
    }

    private func processBuffer() {
        guard let continuation = continuation else { return }

        var lines = buffer.components(separatedBy: "\n")

        // Keep the last incomplete line in buffer
        if let last = lines.last, !last.isEmpty && !buffer.hasSuffix("\n") {
            buffer = last
            lines.removeLast()
        } else {
            buffer = ""
        }

        var messageData = ""
        var messageType = "message"
        var messageId: String?
        var messageRetry: Int?

        for line in lines {
            if line.hasPrefix("event:") {
                messageType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let dataContent = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !messageData.isEmpty {
                    messageData += "\n"
                }
                messageData += dataContent
            } else if line.hasPrefix("id:") {
                messageId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("retry:") {
                if let retryInt = Int(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
                    messageRetry = retryInt
                }
            } else if line.isEmpty {
                // Empty line means message complete
                if !messageData.isEmpty {
                    let message = ZTSSEMessage(type: messageType, data: messageData, id: messageId, retry: messageRetry)
                    continuation.yield(message)
                    // Reset for next message
                    messageData = ""
                    messageType = "message"
                    messageId = nil
                    messageRetry = nil
                }
            }
        }
    }
}
