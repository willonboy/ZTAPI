//
//  ZTAPIError.swift
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
    /// Common errors 80000000-80000999

    /// URL is nil
    static var invalidURL: ZTAPIError { ZTAPIError(80000001, "URL is nil") }

    /// Invalid URL format
    static func invalidURL(_ url: String) -> ZTAPIError {
        ZTAPIError(80000001, "Invalid URL: \(url)")
    }

    /// Invalid request parameters
    static var invalidParams: ZTAPIError { ZTAPIError(80000002, "Request params invalid") }

    /// Invalid response type
    static var invalidResponse: ZTAPIError { ZTAPIError(80000003, "Invalid response type") }

    /// Invalid response type with associated HTTP response
    static func invalidResponse(httpResponse: HTTPURLResponse?) -> ZTAPIError {
        ZTAPIError(80000003, "Invalid response type", httpResponse: httpResponse)
    }

    /// Empty response
    static var emptyResponse: ZTAPIError { ZTAPIError(80000004, "Empty response") }

    /// Empty response with associated HTTP response
    static func emptyResponse(httpResponse: HTTPURLResponse?) -> ZTAPIError {
        ZTAPIError(80000004, "Empty response", httpResponse: httpResponse)
    }

    /// Upload requires httpBody
    static var uploadRequiresBody: ZTAPIError { ZTAPIError(80000005, "Upload requires httpBody") }

    /// Retry policy returned invalid delay
    static func invalidRetryDelay(_ delay: TimeInterval) -> ZTAPIError {
        ZTAPIError(80000007, "Retry policy returned invalid delay: \(delay)")
    }

    /// JSON related errors 80010000-80010999

    /// Parameters contain non-JSON-serializable objects
    static var invalidJSONObject: ZTAPIError { ZTAPIError(80010001, "Params contain non-JSON-serializable objects") }

    /// JSON encoding failed
    static func jsonEncodingFailed(_ message: String = "JSON encoding failed", httpResponse: HTTPURLResponse? = nil) -> ZTAPIError {
        ZTAPIError(80010002, message, httpResponse: httpResponse)
    }

    /// JSON parsing failed
    static func jsonParseFailed(_ message: String = "JSON parse failed", httpResponse: HTTPURLResponse? = nil) -> ZTAPIError {
        ZTAPIError(80010003, message, httpResponse: httpResponse)
    }

    /// Invalid response format
    static var invalidResponseFormat: ZTAPIError { ZTAPIError(80010004, "Invalid response format") }

    /// Invalid response format with associated HTTP response
    static func invalidResponseFormat(httpResponse: HTTPURLResponse?) -> ZTAPIError {
        ZTAPIError(80010004, "Invalid response format", httpResponse: httpResponse)
    }

    /// Unsupported payload type
    static var unsupportedPayloadType: ZTAPIError { ZTAPIError(80010005, "Unsupported payload type") }

    /// File related errors 80030000-80030999

    /// File read failed
    static func fileReadFailed(_ path: String, _ message: String) -> ZTAPIError {
        ZTAPIError(80030001, "Failed to read file at \(path): \(message)")
    }
}
