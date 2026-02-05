//
//  ZTAPIEncodings.swift
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

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

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

        guard let lineData = line.data(using: .utf8),
              let boundaryLineData = boundaryLine.data(using: .utf8),
              let endBoundaryData = "--\(boundary)--\r\n".data(using: .utf8) else {
            throw ZTAPIError.jsonEncodingFailed("Failed to encode multipart boundary")
        }

        for part in parts {
            body.append(boundaryLineData)

            // Content-Disposition header
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            guard let dispositionData = disposition.data(using: .utf8),
                  let contentTypeData = "Content-Type: \(part.mimeType.rawValue)".data(using: .utf8) else {
                throw ZTAPIError.jsonEncodingFailed("Failed to encode multipart headers")
            }
            body.append(dispositionData)
            body.append(lineData)

            // Content-Type (optional)
            body.append(contentTypeData)
            body.append(lineData)

            body.append(lineData)
            body.append(try part.provider.getData())
            body.append(lineData)
        }

        // End boundary
        body.append(endBoundaryData)

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
