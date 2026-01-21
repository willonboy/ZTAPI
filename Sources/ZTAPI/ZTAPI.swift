//
//  ZTAPI.swift
//  SnapkitDemo
//
//  Created by zt
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

/// ZTAPI 错误类型
public struct ZTAPIError: CustomStringConvertible, Error {
    public var code: Int
    public var msg: String

    public init(_ code: Int, _ msg: String) {
        self.code = code
        self.msg = msg
    }

    public var description: String {
        "ZTAPIError \(code): \(msg)"
    }
}

// MARK: - HTTP Header

/// HTTP Header 封装
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
/// API 参数协议
public protocol ZTAPIParamProtocol: Sendable {
    var key: String { get }
    var value: Sendable { get }
    static func isValid(_ params: [String: Sendable]) -> Bool
}
#endif

/// 键值对参数，用于直接传参
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

/// 参数编码协议
public protocol ZTParameterEncoding: Sendable {
    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws
}

/// URL 编码
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
            throw ZTAPIError(-1, "URL is nil")
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

/// JSON 编码
public struct ZTJSONEncoding: ZTParameterEncoding {
    public init() {}

    public func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if JSONSerialization.isValidJSONObject(params) {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            throw ZTAPIError(-1, "Params contain non-JSON-serializable objects")
        }
    }
}

// MARK: - MIME Type

/// MIME 类型
public enum ZTMimeType: Sendable, Hashable {
    case custom(ext: String, mime: String)

    /// MIME 类型字符串值
    public var rawValue: String {
        if case .custom(_, let mime) = self { return mime }
        return ""
    }

    /// 文件扩展名
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

/// Multipart 表单数据
public struct ZTMultipartFormData: Sendable {
    public let parts: [ZTMultipartFormBodyPart]
    public let boundary: String

    public init(parts: [ZTMultipartFormBodyPart] = [], boundary: String? = nil) {
        self.parts = parts
        self.boundary = boundary ?? "Boundary-\(UUID().uuidString)"
    }

    /// 添加表单部分
    public func add(_ part: ZTMultipartFormBodyPart) -> ZTMultipartFormData {
        ZTMultipartFormData(parts: parts + [part], boundary: boundary)
    }

    /// 构建完整的请求数据
    public func build() throws -> Data {
        var body = Data()
        let line = "\r\n"
        let boundaryLine = "--\(boundary)\r\n"

        for part in parts {
            body.append(boundaryLine.data(using: .utf8)!)

            // Content-Disposition
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append(disposition.data(using: .utf8)!)
            body.append(line.data(using: .utf8)!)

            // Content-Type (可选)
            body.append("Content-Type: \(part.mimeType.rawValue)".data(using: .utf8)!)
            body.append(line.data(using: .utf8)!)

            body.append(line.data(using: .utf8)!)
            body.append(try part.provider.getData())
            body.append(line.data(using: .utf8)!)
        }

        // 结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

/// Multipart 数据提供者
public enum ZTMultipartDataProvider: Sendable {
    case data(Data)
    case file(URL, mapIfSupported: Bool = true)

    /// 获取数据，文件读取失败时会抛出错误
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
                    // 内存映射失败，尝试普通读取
                }
            }
            #endif
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ZTAPIError(-2, "Failed to read file at \(url.path): \(error.localizedDescription)")
            }
        }
    }
}

/// Multipart 表单 body 部分
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

    /// 便捷初始化：从 Data 创建
    public static func data(_ data: Data, name: String, fileName: String? = nil, mimeType: ZTMimeType = .octetStream) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .data(data),
            fileName: fileName,
            mimeType: mimeType
        )
    }

    /// 便捷初始化：从文件 URL 创建
    public static func file(_ url: URL, name: String, fileName: String? = nil, mimeType: ZTMimeType) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .file(url),
            fileName: fileName ?? url.lastPathComponent,
            mimeType: mimeType
        )
    }
}

/// Multipart 编码
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

/// 上传进度信息
public struct ZTUploadProgress: Sendable {
    /// 已写入/上传的字节数
    public let bytesWritten: Int64
    /// 总字节数（-1 表示未知，例如 chunked 编码）
    public let totalBytes: Int64

    public init(bytesWritten: Int64, totalBytes: Int64) {
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }

    /// 计算进度百分比（0.0 - 1.0）
    public var fractionCompleted: Double {
        if totalBytes > 0 {
            return Double(bytesWritten) / Double(totalBytes)
        }
        return 0
    }

    /// 已上传字节的可读格式
    public var bytesWrittenFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
    }

    /// 总字节的可读格式
    public var totalBytesFormatted: String {
        if totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
        return "Unknown"
    }
}

/// 上传进度回调类型
public typealias ZTUploadProgressHandler = @Sendable (ZTUploadProgress) -> Void

// MARK: - HTTP Method

/// HTTP 请求方法
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
/// 数据解析配置：用于指定 JSON 路径和目标类型
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

/// ZTAPI 插件协议，用于拦截和增强请求
public protocol ZTAPIPlugin: Sendable {
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
    public func willSend(_ request: inout URLRequest) async throws {}
    public func didReceive(_ response: HTTPURLResponse, data: Data) async throws {}
    public func didCatch(_ error: Error) async throws {}
    public func process(_ data: Data, response: HTTPURLResponse) async throws -> Data { data }
}


// MARK: - ZTAPI

/// ZTAPI 网络请求类
/// 使用 Codable 协议进行响应解析，不依赖第三方 JSON 库
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

    /// 添加请求参数
    @discardableResult
    public func params(_ ps: P...) -> Self {
        ps.forEach { p in
            params[p.key] = p.value
        }
        return self
    }

    /// 添加请求参数（字典形式）
    @discardableResult
    public func params(_ ps: [String: Sendable]) -> Self {
        params.merge(ps) { k, k2 in k2 }
        return self
    }

    /// 添加 HTTP 头
    @discardableResult
    public func headers(_ hds: ZTAPIHeader...) -> Self {
        for header in hds {
            headers[header.key] = header.value
        }
        return self
    }

    /// 设置参数编码
    @discardableResult
    public func encoding(_ e: any ZTParameterEncoding) -> Self {
        encoding = e
        return self
    }

    /// 设置原始请求体
    @discardableResult
    public func body(_ data: Data) -> Self {
        bodyData = data
        return self
    }

    // MARK: - Upload

    /// 上传项
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

    /// 上传多个项（支持混合 Data 和 File）
    @discardableResult
    public func upload(_ items: ZTUploadItem...) -> Self {
        let parts = items.map { $0.bodyPart }
        return multipart(ZTMultipartFormData(parts: parts))
    }

    /// 使用 Multipart 数据上传（支持多个文件 + 其他表单字段）
    @discardableResult
    public func multipart(_ formData: ZTMultipartFormData) -> Self {
        bodyData = nil
        encoding = ZTMultipartEncoding(formData)
        return self
    }

    // MARK: - Config

    /// 设置请求超时时间（秒）
    @discardableResult
    public func timeout(_ interval: TimeInterval) -> Self {
        requestTimeout = interval
        return self
    }

    /// 设置重试策略
    @discardableResult
    public func retry(_ policy: (any ZTAPIRetryPolicy)?) -> Self {
        requestRetryPolicy = policy
        return self
    }

    /// 设置上传进度回调
    @discardableResult
    public func uploadProgress(_ handler: @escaping ZTUploadProgressHandler) -> Self {
        uploadProgressHandler = handler
        return self
    }

    /* 示例用法：
        let user: User = try await ZTAPI<ZTAPIKVParam>(url)
            .jsonDecoder { decoder in
                decoder.dateDecodingStrategy = .formatted(dateFormatter)
                decoder.keyDecodingStrategy = .convertFromSnakeCase
            }.response()
     */
    /// 配置 JSON 解码器
    @discardableResult
    public func jsonDecoder(_ configure: (inout JSONDecoder) -> Void) -> Self {
        configure(&jsonDecoder)
        return self
    }

    /// 添加插件
    @discardableResult
    public func plugins(_ ps: (any ZTAPIPlugin)...) -> Self {
        plugins.append(contentsOf: ps)
        return self
    }

    // MARK: - Send

    /// 发送请求并返回原始 Data
    public func send() async throws -> Data {
        if P.isValid(params) == false {
            throw ZTAPIError(-1, "Request params invalid")
        }

        guard let url = URL(string: urlStr) else {
            throw ZTAPIError(-1, "Invalid URL: \(urlStr)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // bodyData 优先级高于 encoding
        if let body = bodyData {
            urlRequest.httpBody = body
        } else {
            try encoding.encode(&urlRequest, with: params)
        }

        // 设置超时（默认 60 秒）
        urlRequest.timeoutInterval = requestTimeout ?? 60

        // 执行 willSend 插件
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

            // 执行 didReceive 插件
            for plugin in plugins {
                try await plugin.didReceive(response, data: data)
            }

            // 执行 process 插件
            var processedData = data
            for plugin in plugins {
                processedData = try await plugin.process(processedData, response: response)
            }

            return processedData
        } catch {
            // 执行 didCatch 插件
            for plugin in plugins {
                try await plugin.didCatch(error)
            }
            throw error
        }
    }
    
    /// 发送请求并返回解码后的 Codable 对象
    public func response<T: Decodable>() async throws -> T {
        let data = try await send()
        return try jsonDecoder.decode(T.self, from: data)
    }

#if canImport(ZTJSON)
    /// 运行时 XPath 解析多个字段
    public func parseResponse(_ configs: ZTAPIParseConfig...) async throws -> [String: any ZTJSONInitializable] {
        let data = try await send()

        // 解析 JSON
        let json = JSON(data)
        var res: [String: any ZTJSONInitializable] = [:]

        for config in configs {
            if let js = json.find(xpath: config.xpath) {
                do {
                    let parsed = try config.type.init(from: js)
                    res[config.xpath] = parsed
                } catch {
                    // 解析失败，静默忽略（可选配置）
                }
            } else if !config.isAllowMissing {
                throw ZTAPIError(-2, "Parse xpath failed, no exist \(config.xpath)")
            }
        }

        return res
    }
#endif

    // MARK: - Publisher

    /// 用于安全地在跨并发域传递 Future.Promise 的包装器
    private struct PromiseTransfer<T>: @unchecked Sendable {
        let value: T
    }

    /// 发送请求并返回 Codable 类型的 Publisher
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

    // MARK: - Global Provider Convenience

    /// 使用全局 Provider 创建 API 实例
    public static func global(_ url: String, _ method: ZTHTTPMethod = .get) -> ZTAPI<P> {
        ZTAPI(url, method, provider: ZTGlobalAPIProvider.shared.provider)
    }

#if DEBUG
    deinit {
        print("dealloc", urlStr)
    }
#endif
}
