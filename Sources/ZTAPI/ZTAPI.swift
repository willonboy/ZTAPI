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

#if canImport(ZTJSON)
import SwiftyJSON
import ZTJSON
#endif

@preconcurrency import Combine
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Error

/// ZTAPI error type
public struct ZTAPIError: CustomStringConvertible, Error, Equatable {
    public let code: Int
    public let msg: String
    /// Associated HTTP response (read-only, used for retry policy judgment)
    public let httpResponse: HTTPURLResponse?

    public init(_ code: Int, _ msg: String, httpResponse: HTTPURLResponse? = nil) {
        self.code = code
        self.msg = msg
        self.httpResponse = httpResponse
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code
    }
    
    public var description: String {
        "ZTAPIError \(code): \(msg)"
    }

    public var localizedDescription: String { "\(msg)(\(code))" }
}

// MARK: - Built-in Errors

public extension ZTAPIError {
    /// Common errors 80000-80999

    /// URL is nil
    static var invalidURL: ZTAPIError { ZTAPIError(80001, "URL is nil") }

    /// Invalid URL format
    static func invalidURL(_ url: String) -> ZTAPIError {
        ZTAPIError(80001, "Invalid URL: \(url)")
    }

    /// Invalid request parameters
    static var invalidParams: ZTAPIError { ZTAPIError(80002, "Request params invalid") }

    /// Invalid response type
    static var invalidResponse: ZTAPIError { ZTAPIError(80003, "Invalid response type") }

    /// Empty response
    static var emptyResponse: ZTAPIError { ZTAPIError(80004, "Empty response") }

    /// Upload requires httpBody
    static var uploadRequiresBody: ZTAPIError { ZTAPIError(80005, "Upload requires httpBody") }

    /// JSON related errors 81000-81999

    /// Parameters contain non-JSON-serializable objects
    static var invalidJSONObject: ZTAPIError { ZTAPIError(81001, "Params contain non-JSON-serializable objects") }

    /// JSON encoding failed
    static func jsonEncodingFailed(_ message: String = "JSON encoding failed") -> ZTAPIError {
        ZTAPIError(81002, message)
    }

    /// JSON parsing failed
    static func jsonParseFailed(_ message: String = "JSON parse failed") -> ZTAPIError {
        ZTAPIError(81003, message)
    }

    /// Invalid response format
    static var invalidResponseFormat: ZTAPIError { ZTAPIError(81004, "Invalid response format") }

    /// Unsupported payload type
    static var unsupportedPayloadType: ZTAPIError { ZTAPIError(81005, "Unsupported payload type") }

    /// XPath related errors 82000-82999

    /// XPath parsing failed
    static func xpathParseFailed(_ xpath: String) -> ZTAPIError {
        ZTAPIError(82001, "XPath parsing failed: path '\(xpath)' not found")
    }

    /// File related errors 83000-83999

    /// File read failed
    static func fileReadFailed(_ path: String, _ message: String) -> ZTAPIError {
        ZTAPIError(83001, "Failed to read file at \(path): \(message)")
    }
}

// MARK: - HTTP Header

/// HTTP Header wrapper
public enum ZTAPIHeader: Sendable {
    case h(key: String, value: String)

    public var key: String {
        switch self {
        case .h(let k, _): k
        }
    }

    public var value: String {
        switch self {
        case .h(_, let v): v
        }
    }
}

// MARK: - Param Protocol

#if !canImport(ZTJSON)
/// API parameter protocol
public protocol ZTAPIParamProtocol: Sendable {
    var key: String { get }
    var value: Sendable { get }
    static func isValid(_ params: [String: Sendable]) -> Bool
}
#endif

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

// MARK: - ParameterEncoding

/// Parameter encoding protocol
public protocol ZTParameterEncoding: Sendable {
    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws
}

/// URL encoding
public struct ZTURLEncoding: ZTParameterEncoding {
    public enum Destination: Sendable {
        case methodDependent
        case queryString
        case httpBody
    }

    public let destination: Destination

    public init(_ destination: Destination = .methodDependent) {
        self.destination = destination
    }

    public func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        guard let url = request.url else {
            throw ZTAPIError.invalidURL
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = components?.queryItems ?? []

        for (key, value) in params {
            let v = "\(value)"
            items.append(URLQueryItem(name: key, value: v))
        }

        switch destination {
        case .methodDependent:
            switch request.httpMethod {
            case "GET", "HEAD", "DELETE":
                components?.queryItems = items
            default:
                request.httpBody = query(items).data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        case .queryString:
            components?.queryItems = items
        case .httpBody:
            request.httpBody = query(items).data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }

        request.url = components?.url
    }

    private func query(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }
}

/// JSON encoding
public struct ZTJSONEncoding: ZTParameterEncoding {
    public init() {}

    public func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if JSONSerialization.isValidJSONObject(params) {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: params)
            } catch {
                // NSError subclass (JSONSerialization error)
                if type(of: error) is NSError.Type {
                    let nsError = error as NSError
                    throw ZTAPIError(nsError.code, "JSON encoding failed: \(nsError.localizedDescription)")
                }
                throw error
            }
        } else {
            throw ZTAPIError.invalidJSONObject
        }
    }
}

// MARK: - MIME Type

/// MIME type
public enum ZTMimeType: Sendable, Hashable {
    case custom(ext: String, mime: String)

    /// MIME type string value
    public var rawValue: String {
        if case .custom(_, let mime) = self { return mime }
        return ""
    }

    /// File extension
    public var ext: String {
        if case .custom(let ext, _) = self { return ext }
        return ""
    }

    public static let jpeg = custom(ext: "jpg", mime: "image/jpeg")
    public static let jpg = jpeg
    public static let png = custom(ext: "png", mime: "image/png")
    public static let gif = custom(ext: "gif", mime: "image/gif")
    public static let webp = custom(ext: "webp", mime: "image/webp")
    public static let svg = custom(ext: "svg", mime: "image/svg+xml")

    public static let json = custom(ext: "json", mime: "application/json")
    public static let pdf = custom(ext: "pdf", mime: "application/pdf")
    public static let txt = custom(ext: "txt", mime: "text/plain")
    public static let html = custom(ext: "html", mime: "text/html")
    public static let xml = custom(ext: "xml", mime: "application/xml")

    public static let formUrlEncoded = custom(ext: "", mime: "application/x-www-form-urlencoded")
    public static let multipartFormData = custom(ext: "", mime: "multipart/form-data")
    public static let octetStream = custom(ext: "", mime: "application/octet-stream")

    public static let zip = custom(ext: "zip", mime: "application/zip")
    public static let gzip = custom(ext: "gz", mime: "application/gzip")
}

// MARK: - Multipart Form Data

/// Multipart form data
public struct ZTMultipartFormData: Sendable {
    public let parts: [ZTMultipartFormBodyPart]
    public let boundary: String

    public init(parts: [ZTMultipartFormBodyPart] = [], boundary: String? = nil) {
        self.parts = parts
        self.boundary = boundary ?? "Boundary-\(UUID().uuidString)"
    }

    /// Add form part
    public func add(_ part: ZTMultipartFormBodyPart) -> ZTMultipartFormData {
        ZTMultipartFormData(parts: parts + [part], boundary: boundary)
    }

    /// Build complete request data
    public func build() throws -> Data {
        var body = Data()
        let line = "\r\n"
        let boundaryLine = "--\(boundary)\r\n"

        for part in parts {
            body.append(boundaryLine.data(using: .utf8)!)

            // Content-Disposition header
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append(disposition.data(using: .utf8)!)
            body.append(line.data(using: .utf8)!)

            // Content-Type (optional)
            body.append("Content-Type: \(part.mimeType.rawValue)".data(using: .utf8)!)
            body.append(line.data(using: .utf8)!)

            body.append(line.data(using: .utf8)!)
            body.append(try part.provider.getData())
            body.append(line.data(using: .utf8)!)
        }

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

/// Multipart data provider
public enum ZTMultipartDataProvider: Sendable {
    case data(Data)
    case file(URL, mapIfSupported: Bool = true)

    /// Get data, throws error if file read fails
    public func getData() throws -> Data {
        switch self {
        case .data(let data):
            return data
        case .file(let url, let mapIfSupported):
            #if !os(OSX)
            if mapIfSupported {
                do {
                    return try Data(contentsOf: url, options: .alwaysMapped)
                } catch {
                    // Memory mapping failed, try normal read
                }
            }
            #endif
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ZTAPIError.fileReadFailed(url.path, error.localizedDescription)
            }
        }
    }
}

/// Multipart form body part
public struct ZTMultipartFormBodyPart: Sendable {
    public let name: String
    public let provider: ZTMultipartDataProvider
    public let fileName: String?
    public let mimeType: ZTMimeType

    public init(
        name: String,
        provider: ZTMultipartDataProvider,
        fileName: String? = nil,
        mimeType: ZTMimeType
    ) {
        self.name = name
        self.provider = provider
        self.fileName = fileName
        self.mimeType = mimeType
    }

    /// Convenience initializer: create from Data
    public static func data(_ data: Data, name: String, fileName: String? = nil, mimeType: ZTMimeType = .octetStream) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .data(data),
            fileName: fileName,
            mimeType: mimeType
        )
    }

    /// Convenience initializer: create from file URL
    public static func file(_ url: URL, name: String, fileName: String? = nil, mimeType: ZTMimeType) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .file(url),
            fileName: fileName ?? url.lastPathComponent,
            mimeType: mimeType
        )
    }
}

/// Multipart encoding
public struct ZTMultipartEncoding: ZTParameterEncoding {
    public let formData: ZTMultipartFormData

    public init(_ formData: ZTMultipartFormData) {
        self.formData = formData
    }

    public func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        let boundary = formData.boundary
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try formData.build()
    }
}

// MARK: - Upload Progress

/// Upload progress information
public struct ZTUploadProgress: Sendable {
    /// Bytes written/uploaded
    public let bytesWritten: Int64
    /// Total bytes (-1 means unknown, e.g., chunked encoding)
    public let totalBytes: Int64

    public init(bytesWritten: Int64, totalBytes: Int64) {
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }

    /// Calculate progress percentage (0.0 - 1.0)
    public var fractionCompleted: Double {
        if totalBytes > 0 {
            return Double(bytesWritten) / Double(totalBytes)
        }
        return 0
    }

    /// Readable format of uploaded bytes
    public var bytesWrittenFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
    }

    /// Readable format of total bytes
    public var totalBytesFormatted: String {
        if totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
        return "Unknown"
    }
}

/// Upload progress callback type
public typealias ZTUploadProgressHandler = @Sendable (ZTUploadProgress) -> Void

// MARK: - HTTP Method

/// HTTP request method
public enum ZTHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case query = "QUERY"
    case trace = "TRACE"
    case connect = "CONNECT"
    case options = "OPTIONS"
}


#if canImport(ZTJSON)
/// Data parsing configuration: used to specify JSON path and target type
public struct ZTAPIParseConfig: Hashable {
    public let xpath: String
    public let type: any ZTJSONInitializable.Type
    public let isAllowMissing: Bool

    public init(_ xpath: String = "/", type: any ZTJSONInitializable.Type, _ isAllowMissing: Bool = true) {
        self.xpath = xpath.isEmpty ? "/" : xpath
        self.type = type
        self.isAllowMissing = isAllowMissing
    }

    public static func == (lhs: ZTAPIParseConfig, rhs: ZTAPIParseConfig) -> Bool {
        lhs.xpath == rhs.xpath
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(xpath)
    }
}
#endif


// MARK: - Plugin

/// ZTAPI plugin protocol for intercepting and enhancing requests
public protocol ZTAPIPlugin: Sendable {
    /// Request about to be sent
    func willSend(_ request: inout URLRequest) async throws
    /// Response received
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws
    /// Error occurred
    func didCatch(_ error: Error) async throws
    /// Process response data, can modify returned data (after didReceive, before returning to caller)
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data
}

/// Default empty implementation
extension ZTAPIPlugin {
    public func willSend(_ request: inout URLRequest) async throws {}
    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {}
    public func didCatch(_ error: Error) async throws {}
    public func process(_ data: Data, response: HTTPURLResponse) async throws -> Data { data }
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

        var bodyPart: ZTMultipartFormBodyPart {
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

        do {
            let (data, response) = try await effectiveProvider.request(
                urlRequest,
                uploadProgress: uploadProgressHandler
            )

            // Execute didReceive plugins
            for plugin in plugins {
                try await plugin.didReceive(response, data: data)
            }

            // Execute process plugins
            var processedData = data
            for plugin in plugins {
                processedData = try await plugin.process(processedData, response: response)
            }

            return processedData
        } catch {
            // Execute didCatch plugins
            for plugin in plugins {
                try await plugin.didCatch(error)
            }
            throw error
        }
    }
    
    /// Send request and return decoded Codable object
    public func response<T: Decodable>() async throws -> T {
        let data = try await send()
        return try jsonDecoder.decode(T.self, from: data)
    }

#if canImport(ZTJSON)
    /// Runtime XPath parsing for multiple fields
    public func parseResponse(_ configs: ZTAPIParseConfig...) async throws -> [String: any ZTJSONInitializable] {
        let data = try await send()

        // Parse JSON
        let json = JSON(data)
        var res: [String: any ZTJSONInitializable] = [:]

        for config in configs {
            if let js = json.find(xpath: config.xpath) {
                do {
                    let parsed = try config.type.init(from: js)
                    res[config.xpath] = parsed
                } catch {
                    // Parse failed, silently ignore (optional config)
                }
            } else if !config.isAllowMissing {
                throw ZTAPIError.xpathParseFailed(config.xpath)
            }
        }

        return res
    }
#endif

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
