//
//  ZTAPI.swift
//  SnapkitDemo
//
//  Created by zt
//


import Foundation
import SwiftyJSON
import ZTJSON
@preconcurrency import Combine

public extension Result {
    @discardableResult
    func onSuccess(_ code: (Success) -> Void) -> Self {
        if case .success(let s) = self {
            code(s)
        }
        return self
    }

    @discardableResult
    func onFailure(_ code: (Failure) -> Void) -> Self {
        if case .failure(let f) = self {
            code(f)
        }
        return self
    }
}

/// 字典泛型取值函数，支持类型安全的值提取
extension Dictionary {
    func get<T: ZTJSONInitializable>(_ key: String) -> T? where Key == String {
        guard let value = self[key] else { return nil }
        return value as? T
    }
}


struct ZTAPIError: CustomStringConvertible, Error {
    var code: Int
    var msg: String

    init(_ code: Int, _ msg: String) {
        self.code = code
        self.msg = msg
    }
    
    var description: String {
        "ZTAPIError \(code): \(msg)"
    }
}


/// HTTP Header
enum ZTAPIHeader: Sendable {
    case h(key: String, value: String)

    var key: String {
        switch self {
            case .h(let k, _): k
        }
    }

    var value: String {
        switch self {
            case .h(_, let v): v
        }
    }
}


enum ZTAPIKVParam: ZTAPIParamProtocol {
    case kv(String, Sendable)

    var key: String {
        switch self {
            case .kv(let k, _): return k
        }
    }

    var value: Sendable {
        switch self {
            case .kv(_, let v): return v
        }
    }
}

// MARK: - ParameterEncoding

/// 参数编码协议
protocol ZTParameterEncoding: Sendable {
    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws
}

/// URL 编码
struct ZTURLEncoding: ZTParameterEncoding {
    enum Destination {
        case methodDependent
        case queryString
        case httpBody
    }

    let destination: Destination

    init(_ destination: Destination = .methodDependent) {
        self.destination = destination
    }

    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
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
        items.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}

/// JSON 编码
struct ZTJSONEncoding: ZTParameterEncoding {
    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
    }
}

// MARK: - MIME Type

/// MIME 类型
struct ZTMimeType: Sendable, Hashable {
    let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// 自定义 MIME 类型
    static func mimeType(_ value: String) -> ZTMimeType {
        ZTMimeType(value)
    }

    // MARK: - Image Types

    static let jpeg = ZTMimeType("image/jpeg")
    static let png = ZTMimeType("image/png")
    static let gif = ZTMimeType("image/gif")
    static let webp = ZTMimeType("image/webp")
    static let bmp = ZTMimeType("image/bmp")
    static let svg = ZTMimeType("image/svg+xml")
    static let ico = ZTMimeType("image/x-icon")
    static let tiff = ZTMimeType("image/tiff")

    // MARK: - Video Types

    static let mp4 = ZTMimeType("video/mp4")
    static let mpeg = ZTMimeType("video/mpeg")
    static let quicktime = ZTMimeType("video/quicktime")
    static let webm = ZTMimeType("video/webm")

    // MARK: - Audio Types

    static let mp3 = ZTMimeType("audio/mpeg")
    static let m4a = ZTMimeType("audio/mp4")
    static let wav = ZTMimeType("audio/wav")
    static let ogg = ZTMimeType("audio/ogg")
    static let aac = ZTMimeType("audio/aac")

    // MARK: - Document Types

    static let pdf = ZTMimeType("application/pdf")
    static let doc = ZTMimeType("application/msword")
    static let docx = ZTMimeType("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    static let xls = ZTMimeType("application/vnd.ms-excel")
    static let xlsx = ZTMimeType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    static let ppt = ZTMimeType("application/vnd.ms-powerpoint")
    static let pptx = ZTMimeType("application/vnd.openxmlformats-officedocument.presentationml.presentation")
    static let txt = ZTMimeType("text/plain")
    static let html = ZTMimeType("text/html")
    static let css = ZTMimeType("text/css")
    static let javascript = ZTMimeType("text/javascript")
    static let xml = ZTMimeType("application/xml")
    static let json = ZTMimeType("application/json")

    // MARK: - Archive Types

    static let zip = ZTMimeType("application/zip")
    static let gzip = ZTMimeType("application/gzip")
    static let tar = ZTMimeType("application/x-tar")
    static let rar = ZTMimeType("application/vnd.rar")
    static let _7z = ZTMimeType("application/x-7z-compressed")

    // MARK: - Form Data

    static let formUrlEncoded = ZTMimeType("application/x-www-form-urlencoded")
    static let multipartFormData = ZTMimeType("multipart/form-data")
    static let octetStream = ZTMimeType("application/octet-stream")

    // MARK: - Common

    static let plainText = txt
    static let htmlText = html
    static let jsonText = json
    static let xmlText = xml

    /// 根据文件扩展名获取 MIME 类型
    static func fromFileExtension(_ ext: String) -> ZTMimeType {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "gif": return .gif
        case "webp": return .webp
        case "svg": return .svg
        case "mp4": return .mp4
        case "mp3": return .mp3
        case "pdf": return .pdf
        case "txt": return .txt
        case "html", "htm": return .html
        case "css": return .css
        case "js": return .javascript
        case "json": return .json
        case "xml": return .xml
        case "zip": return .zip
        default: return .octetStream
        }
    }

    /// 根据文件 URL 获取 MIME 类型
    static func fromFileURL(_ url: URL) -> ZTMimeType {
        fromFileExtension(url.pathExtension)
    }
}

// MARK: - Multipart Form Data

/// Multipart 表单数据
struct ZTMultipartFormData: Sendable {
    let parts: [ZTMultipartFormBodyPart]
    let boundary: String

    init(parts: [ZTMultipartFormBodyPart] = [], boundary: String? = nil) {
        self.parts = parts
        self.boundary = boundary ?? "Boundary-\(UUID().uuidString)"
    }

    /// 添加表单部分
    func add(_ part: ZTMultipartFormBodyPart) -> ZTMultipartFormData {
        ZTMultipartFormData(parts: parts + [part], boundary: boundary)
    }

    /// 构建完整的请求数据
    func build() -> Data {
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
            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType.rawValue)".data(using: .utf8)!)
                body.append(line.data(using: .utf8)!)
            }

            body.append(line.data(using: .utf8)!)
            body.append(part.provider.data)
            body.append(line.data(using: .utf8)!)
        }

        // 结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

/// Multipart 数据提供者
enum ZTMultipartDataProvider: Sendable {
    /// 内存中的数据
    case data(Data)
    /// 文件 URL（支持内存映射读取）
    case file(URL, mapIfSupported: Bool = true)

    var data: Data {
        switch self {
        case .data(let data):
            return data
        case .file(let url, let mapIfSupported):
            // 读取文件数据
            // 如果支持内存映射，优先使用（iOS/tvOS/watchOS）
            #if !os(OSX)
            if mapIfSupported, let mappedData = try? Data(contentsOf: url, options: .alwaysMapped) {
                return mappedData
            }
            #endif
            // 回退到普通读取
            return (try? Data(contentsOf: url)) ?? Data()
        }
    }
}

/// Multipart 表单 body 部分
struct ZTMultipartFormBodyPart: Sendable {
    let name: String
    let provider: ZTMultipartDataProvider
    let fileName: String?
    let mimeType: ZTMimeType?

    init(
        name: String,
        provider: ZTMultipartDataProvider,
        fileName: String? = nil,
        mimeType: ZTMimeType? = nil
    ) {
        self.name = name
        self.provider = provider
        self.fileName = fileName
        self.mimeType = mimeType
    }

    /// 便捷初始化：从 Data 创建
    static func data(_ data: Data, name: String, fileName: String? = nil, mimeType: ZTMimeType? = nil) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .data(data),
            fileName: fileName,
            mimeType: mimeType
        )
    }

    /// 便捷初始化：从文件 URL 创建
    static func file(_ url: URL, name: String, fileName: String? = nil, mimeType: ZTMimeType? = nil) -> ZTMultipartFormBodyPart {
        ZTMultipartFormBodyPart(
            name: name,
            provider: .file(url),
            fileName: fileName ?? url.lastPathComponent,
            mimeType: mimeType ?? ZTMimeType.fromFileURL(url)
        )
    }
}

/// Multipart 编码
struct ZTMultipartEncoding: ZTParameterEncoding {
    let formData: ZTMultipartFormData

    init(_ formData: ZTMultipartFormData) {
        self.formData = formData
    }

    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        // 注意：params 参数在 multipart 模式下被忽略
        // 所有数据应该通过 MultipartFormData 的 parts 传入
        let boundary = formData.boundary
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.build()
    }
}

/// 数据解析配置：用于指定 JSON 路径和目标类型
struct ZTAPIParseConfig: Hashable {
    let xpath: String
    let type: any ZTJSONInitializable.Type
    let isAllowMissing: Bool

    init(_ xpath: String = "/", type: any ZTJSONInitializable.Type, _ isAllowMissing: Bool = true) {
        self.xpath = xpath.isEmpty ? "/" : xpath
        self.type = type
        self.isAllowMissing = isAllowMissing
    }

    static func == (lhs: ZTAPIParseConfig, rhs: ZTAPIParseConfig) -> Bool {
        lhs.xpath == rhs.xpath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(xpath)
    }
}

/// HTTP 方法
enum ZTHTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// ZTAPI 网络请求类
class ZTAPI<P: ZTAPIParamProtocol>: @unchecked Sendable {
    var urlStr: String
    var method: ZTHTTPMethod
    var params: [String: Sendable] = [:]
    var headers: [String: String] = [:]
    var bodyData: Data? = nil
    var encoding: any ZTParameterEncoding = ZTURLEncoding()

    private var parseConfigs: [ZTAPIParseConfig] = []
    private let provider: any ZTAPIProvider
    private var requestTimeout: TimeInterval?
    private var requestRetryPolicy: (any ZTAPIRetryPolicy)?

    init(_ url: String, _ method: ZTHTTPMethod, provider: (any ZTAPIProvider)? = nil) {
        self.urlStr = url
        self.method = method
        self.provider = provider ?? ZTAlamofireProvider.shared
    }

    // MARK: - Types

    /// API 响应类型别名
    typealias APIResponse = [String: any ZTJSONInitializable]

    /// 添加数据解析配置
    func parse(_ configs: ZTAPIParseConfig...) -> Self {
        parseConfigs.append(contentsOf: configs)
        return self
    }

    // MARK: - Param / Header
    func param(_ p: P) -> Self {
        params[p.key] = p.value
        return self
    }

    func params(_ ps: P...) -> Self {
        ps.forEach { p in
            params[p.key] = p.value
        }
        return self
    }

    func params(_ ps:[String: Sendable]) -> Self {
        params.merge(ps) { k, k2 in k2 }
        return self
    }

    func header(_ h: ZTAPIHeader) -> Self {
        headers([h])
    }

    func headers(_ hds: [ZTAPIHeader]) -> Self {
        for header in hds {
            headers[header.key] = header.value
        }
        return self
    }

    func encoding(_ e: any ZTParameterEncoding) -> Self {
        encoding = e
        return self
    }

    func body(_ data: Data) -> Self {
        bodyData = data
        return self
    }

    // MARK: - Upload

    /// 上传项
    enum ZTUploadItem: Sendable {
        /// 内存中的数据
        case data(Data, name: String, fileName: String? = nil, mimeType: ZTMimeType? = nil)
        /// 文件（支持内存映射读取）
        case file(URL, name: String, fileName: String? = nil, mimeType: ZTMimeType? = nil)

        /// 转换为 MultipartFormBodyPart
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
    func upload(_ items: [ZTUploadItem]) -> Self {
        let parts = items.map { $0.bodyPart }
        return multipart(ZTMultipartFormData(parts: parts))
    }

    /// 使用 Multipart 数据上传（支持多个文件 + 其他表单字段）
    func multipart(_ formData: ZTMultipartFormData) -> Self {
        // Multipart 模式下，清除之前的 bodyData，避免冲突
        bodyData = nil
        _ = encoding(ZTMultipartEncoding(formData))
        return self
    }

    // MARK: - Config

    /// 设置请求超时时间（秒）
    func timeout(_ interval: TimeInterval) -> Self {
        requestTimeout = interval
        return self
    }

    /// 设置重试策略
    func retry(_ policy: any ZTAPIRetryPolicy) -> Self {
        requestRetryPolicy = policy
        return self
    }

    // MARK: - Send

    /// 发送请求并返回解析后的响应
    func send() async throws -> APIResponse {
        if P.isValid(params) == false {
            throw ZTAPIError(-1, "Request params invalid")
        }

        // 构建 URLRequest
        guard let url = URL(string: urlStr) else {
            throw ZTAPIError(-1, "Invalid URL: \(urlStr)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        try encoding.encode(&urlRequest, with: params)

        // 如果设置了 bodyData，覆盖请求体
        if let body = bodyData {
            urlRequest.httpBody = body
        }

        // 应用超时时间到 URLRequest
        if let timeout = requestTimeout {
            urlRequest.timeoutInterval = timeout
        }

        // 如果设置了请求级别的重试策略，创建包装后的 Provider
        let effectiveProvider = overridableRetryProvider(
            base: provider,
            policy: requestRetryPolicy
        )

        // 通过 provider 发送请求
        let data = try await effectiveProvider.request(urlRequest, timeout: requestTimeout)

        // 解析 JSON
        let json = JSON(data)
        var res: APIResponse = [:]

        for config in parseConfigs {
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

    /// 用于在跨并发域传递非 Sendable 值的包装器
    private struct UnsafeTransfer<T>: @unchecked Sendable {
        let value: T
    }

    /// 发送请求并返回 Publisher
    var publisher: AnyPublisher<APIResponse, Error> {
        Future { promise in
            let unsafePromise = UnsafeTransfer(value: promise)
            Task {
                do {
                    let result = try await self.send()
                    unsafePromise.value(.success(result))
                } catch {
                    unsafePromise.value(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

#if DEBUG
    deinit {
        print("dealloc", urlStr)
    }
#endif
}

