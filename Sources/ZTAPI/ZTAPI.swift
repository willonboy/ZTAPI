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
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

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
        // 利用 URLComponents 的自动编码功能
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }
}

/// JSON 编码
struct ZTJSONEncoding: ZTParameterEncoding {
    func encode(_ request: inout URLRequest, with params: [String: Sendable]) throws {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 预先验证对象是否可 JSON 序列化
        // 注意：isValidJSONObject 只能检测字典顶层的键值对，无法检测嵌套的不可序列化对象
        // 对于嵌套对象，JSONSerialization 可能会抛出 NSException（Swift 无法捕获）
        // 这是 Swift 与 Foundation 互操作的固有限制
        if JSONSerialization.isValidJSONObject(params) {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            throw ZTAPIError(-1, "Params contain non-JSON-serializable objects")
        }
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
    /// 使用系统的 UTType API 自动识别（iOS 14+ / macOS 11+ / tvOS 14+）
    static func fromFileExtension(_ ext: String) -> ZTMimeType {
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            if let uttype = UTType(filenameExtension: ext),
               let mimeType = uttype.preferredMIMEType {
                return ZTMimeType(mimeType)
            }
        }
        // 降级处理：未知扩展名返回 octet-stream
        return .octetStream
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
    func build() throws -> Data {
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
            body.append(try part.provider.getData())  // 调用 getData() 可能抛出错误
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

    /// 获取数据，文件读取失败时会抛出错误
    func getData() throws -> Data {
        switch self {
        case .data(let data):
            return data
        case .file(let url, let mapIfSupported):
            // 读取文件数据
            // 如果支持内存映射，优先使用（iOS/tvOS/watchOS）
            #if !os(OSX)
            if mapIfSupported {
                do {
                    return try Data(contentsOf: url, options: .alwaysMapped)
                } catch {
                    // 内存映射失败，尝试普通读取
                }
            }
            #endif
            // 回退到普通读取
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ZTAPIError(-2, "Failed to read file at \(url.path): \(error.localizedDescription)")
            }
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
        request.httpBody = try formData.build()  // 可能抛出文件读取错误
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

// MARK: - Upload Progress

/// 上传进度信息
struct ZTUploadProgress: Sendable {
    /// 已写入/上传的字节数
    let bytesWritten: Int64
    /// 总字节数（-1 表示未知，例如 chunked 编码）
    let totalBytes: Int64

    /// 计算进度百分比（0.0 - 1.0）
    var fractionCompleted: Double {
        if totalBytes > 0 {
            return Double(bytesWritten) / Double(totalBytes)
        }
        return 0
    }

    /// 已上传字节的可读格式
    var bytesWrittenFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
    }

    /// 总字节的可读格式
    var totalBytesFormatted: String {
        if totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
        return "Unknown"
    }
}

/// 上传进度回调类型
typealias ZTUploadProgressHandler = @Sendable (ZTUploadProgress) -> Void

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
    private var uploadProgressHandler: ZTUploadProgressHandler?

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

    /// 设置上传进度回调
    func uploadProgress(_ handler: @escaping ZTUploadProgressHandler) -> Self {
        uploadProgressHandler = handler
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

        // bodyData 优先级高于 encoding：如果设置了 bodyData，跳过参数编码
        if let body = bodyData {
            urlRequest.httpBody = body
        } else {
            try encoding.encode(&urlRequest, with: params)
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

        // 通过 provider 发送请求（传递进度回调）
        let data = try await effectiveProvider.request(
            urlRequest,
            timeout: requestTimeout,
            uploadProgress: uploadProgressHandler
        )

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

    /// 用于安全地在跨并发域传递 Future.Promise 的包装器
    /// Future.Promise 实际上是线程安全的（Combine 内部处理同步），
    /// 但 Swift 6 类型系统无法识别这一点，需要使用 @unchecked Sendable
    private struct PromiseTransfer<T>: @unchecked Sendable {
        let value: T
    }

    /// 发送请求并返回 Publisher
    /// 使用 Deferred 延迟 Future 创建，确保只在订阅时才执行请求
    /// 使用 MainActor.run 确保 promise 在主线程上被调用
    /// 避免从后台线程直接调用 Combine Future.Promise 导致的 executor 断言失败
    /// 使用 share() 确保多订阅时只执行一次请求，结果共享给所有订阅者
    var publisher: AnyPublisher<APIResponse, Error> {
        Deferred {
            Future { promise in
                let promiseTransfer = PromiseTransfer(value: promise)
                Task {
                    do {
                        let result = try await self.send()
                        // 仅在回调 promise 时切回主线程
                        // 这里的操作是安全的：result 在 MainActor.run 内同步使用，无并发风险
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
    /// 全局 Provider 自动控制并发数（默认最多 6 个）
    /// - Parameters:
    ///   - url: 请求地址
    ///   - method: 请求方法
    /// - Returns: 使用全局 Provider 的 ZTAPI 实例
    static func global(_ url: String, _ method: ZTHTTPMethod = .get) -> ZTAPI<P> {
        ZTAPI(url, method, provider: ZTGlobalAPIProvider.shared.provider)
    }

#if DEBUG
    deinit {
        print("dealloc", urlStr)
    }
#endif
}

