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
@preconcurrency import Combine

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

// MARK: - ZTAPI

/// ZTAPI network request class
/// Uses Codable protocol for response parsing, no third-party JSON library dependency
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
        for plugin in snapshot.plugins {
            try await plugin.willSend(&urlRequest)
        }

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
            for plugin in snapshot.plugins {
                try await plugin.didReceive(response, data: data, request: urlRequest)
            }

            // Execute process plugins
            var processedData = data
            for plugin in snapshot.plugins {
                processedData = try await plugin.process(processedData, response: response, request: urlRequest)
            }

            return processedData
        } catch {
            // Execute didCatch plugins with request context and optional response data
            // Priority: response from successful request > response in ZTAPIError > nil
            if httpResponse == nil {
                httpResponse = (error as? ZTAPIError)?.httpResponse
            }
            for plugin in snapshot.plugins {
                try await plugin.didCatch(error, request: urlRequest, response: httpResponse, data: responseData)
            }
            throw error
        }
    }
    
    /// Send request and return decoded Codable object
    @discardableResult
    public func response<T: Decodable>() async throws -> T {
        let data = try await send()
        return try JSONDecoder().decode(T.self, from: data)
    }

#if DEBUG
    deinit {
        print("dealloc", _urlStr)
    }
#endif
}
