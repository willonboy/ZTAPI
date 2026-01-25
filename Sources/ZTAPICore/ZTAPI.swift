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
    public private(set) var urlStr: String
    public private(set) var method: ZTHTTPMethod
    public private(set) var params: [String: Sendable] = [:]
    public private(set) var headers: [String: String] = [:]
    public private(set) var bodyData: Data? = nil
    public private(set) var encoding: any ZTParameterEncoding = ZTURLEncoding()

    private let provider: any ZTAPIProvider
    private var plugins: [any ZTAPIPlugin] = []
    private var requestTimeout: TimeInterval?
    private var requestRetryPolicy: (any ZTAPIRetryPolicy)?
    private var uploadProgressHandler: ZTUploadProgressHandler?
    private var jsonDecoder: JSONDecoder = JSONDecoder()

    public init(_ url: String, _ method: ZTHTTPMethod = .get, provider: any ZTAPIProvider) {
        self.urlStr = url
        self.method = method
        self.provider = provider
    }

    /// Add request parameters
    @discardableResult
    public func params(_ ps: P...) -> Self {
        ps.forEach { p in
            params[p.key] = p.value
        }
        return self
    }

    /// Add request parameters (dictionary form)
    @discardableResult
    public func params(_ ps: [String: Sendable]) -> Self {
        params.merge(ps) { k, k2 in k2 }
        return self
    }

    /// Add HTTP headers
    @discardableResult
    public func headers(_ hds: ZTAPIHeader...) -> Self {
        for header in hds {
            headers[header.key] = header.value
        }
        return self
    }

    /// Set parameter encoding
    @discardableResult
    public func encoding(_ e: any ZTParameterEncoding) -> Self {
        encoding = e
        return self
    }

    /// Set raw request body
    @discardableResult
    public func body(_ data: Data) -> Self {
        bodyData = data
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
        bodyData = nil
        encoding = ZTMultipartEncoding(formData)
        return self
    }

    // MARK: - Config

    /// Set request timeout (seconds)
    @discardableResult
    public func timeout(_ interval: TimeInterval) -> Self {
        requestTimeout = interval
        return self
    }

    /// Set retry policy
    @discardableResult
    public func retry(_ policy: (any ZTAPIRetryPolicy)?) -> Self {
        requestRetryPolicy = policy
        return self
    }

    /// Set upload progress callback
    @discardableResult
    public func uploadProgress(_ handler: @escaping ZTUploadProgressHandler) -> Self {
        uploadProgressHandler = handler
        return self
    }

    /* Example usage:
        let user: User = try await ZTAPI<ZTAPIKVParam>(url)
            .jsonDecoder { decoder in
                decoder.dateDecodingStrategy = .formatted(dateFormatter)
                decoder.keyDecodingStrategy = .convertFromSnakeCase
            }.response()
     */
    /// Configure JSON decoder
    @discardableResult
    public func jsonDecoder(_ configure: (inout JSONDecoder) -> Void) -> Self {
        configure(&jsonDecoder)
        return self
    }

    /// Add plugins
    @discardableResult
    public func plugins(_ ps: (any ZTAPIPlugin)...) -> Self {
        plugins.append(contentsOf: ps)
        return self
    }

    // MARK: - Send

    /// Send request and return raw Data
    public func send() async throws -> Data {
        if P.isValid(params) == false {
            throw ZTAPIError.invalidParams
        }

        guard let url = URL(string: urlStr) else {
            throw ZTAPIError.invalidURL(urlStr)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // bodyData takes priority over encoding
        if let body = bodyData {
            urlRequest.httpBody = body
        } else {
            try encoding.encode(&urlRequest, with: params)
        }

        // Set timeout (default 60 seconds)
        urlRequest.timeoutInterval = requestTimeout ?? 60

        // Execute willSend plugins
        for plugin in plugins {
            try await plugin.willSend(&urlRequest)
        }

        let effectiveProvider = if let policy = requestRetryPolicy {
            ZTRetryProvider(baseProvider: provider, retryPolicy: policy)
        } else {
            provider
        }

        var httpResponse: HTTPURLResponse?
        do {
            let (data, response) = try await effectiveProvider.request(
                urlRequest,
                uploadProgress: uploadProgressHandler
            )
            httpResponse = response

            // Execute didReceive plugins
            for plugin in plugins {
                try await plugin.didReceive(response, data: data, request: urlRequest)
            }

            // Execute process plugins
            var processedData = data
            for plugin in plugins {
                processedData = try await plugin.process(processedData, response: response, request: urlRequest)
            }

            return processedData
        } catch {
            // Execute didCatch plugins with request context
            // Priority: response from successful request > response in ZTAPIError > nil
            if httpResponse == nil {
                httpResponse = (error as? ZTAPIError)?.httpResponse
            }
            for plugin in plugins {
                try await plugin.didCatch(error, request: urlRequest, response: httpResponse)
            }
            throw error
        }
    }
    
    /// Send request and return decoded Codable object
    public func response<T: Decodable>() async throws -> T {
        let data = try await send()
        return try jsonDecoder.decode(T.self, from: data)
    }

    // MARK: - Publisher

    /// Wrapper for safely passing Future.Promise across concurrency domains
    private struct PromiseTransfer<T>: @unchecked Sendable {
        let value: T
    }

    /// Send request and return Publisher of Codable type
    public func publisher<T: Codable & Sendable>() -> AnyPublisher<T, Error> {
        Deferred {
            Future { promise in
                let promiseTransfer = PromiseTransfer(value: promise)
                Task {
                    do {
                        let result: T = try await self.response()
                        await MainActor.run {
                            promiseTransfer.value(.success(result))
                        }
                    } catch {
                        await MainActor.run {
                            promiseTransfer.value(.failure(error))
                        }
                    }
                }
            }
        }
        .share()
        .eraseToAnyPublisher()
    }

#if DEBUG
    deinit {
        print("dealloc", urlStr)
    }
#endif
}
