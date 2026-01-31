//
//  ZTAPISamplePlugin.swift
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

// MARK: - Built-in Plugins

/// Log plugin
public struct ZTLogPlugin: ZTAPIPlugin {
    public enum LogLevel: Sendable {
        case verbose
        case simple
        case none
    }

    public let level: LogLevel

    /// Maximum body print length (bytes), only print byte count if exceeded
    /// Prevent memory spikes from printing large JSON
    private let maxBodyPrintLength: Int

    public init(level: LogLevel = .verbose, maxBodyPrintLength: Int = 1024) {
        self.level = level
        self.maxBodyPrintLength = maxBodyPrintLength
    }

    public func willSend(_ request: inout URLRequest) async throws {
        guard level != .none else { return }

        if level == .verbose {
            var output = "curl"

            // Method
            if let method = request.httpMethod, method != "GET" {
                output += " -X \(method)"
            }

            // URL
            if let url = request.url?.absoluteString {
                output += " '\(url)'"
            }

            // Headers
            for (key, value) in request.allHTTPHeaderFields ?? [:] {
                // Escape single quotes
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                output += " \\\n  -H '\(key): \(escapedValue)'"
            }

            // Body
            if let body = request.httpBody, !body.isEmpty {
                let previewCount = min(body.count, maxBodyPrintLength)
                let preview = body.prefix(previewCount)

                if body.count <= maxBodyPrintLength,
                   let bodyStr = String(data: preview, encoding: .utf8) {
                    let escapedBody = bodyStr.replacingOccurrences(of: "'", with: "'\\''")
                    output += " \\\n  -d '\(escapedBody)'"
                } else {
                    output += " \\\n  -d '<\(body.count) bytes data>'"
                }
            }

            print(output)
        } else {
            print("[ZTAPI] \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "")")
        }
    }

    public func didReceive(_ response: HTTPURLResponse, data: Data, request: URLRequest) async throws {
        guard level == .verbose else { return }

        var output = """
        ================== Response =================
        Status: \(response.statusCode)
        Headers:
        """

        for (key, value) in response.allHeaderFields {
            output += "  \(key): \(value)\n"
        }

        let previewCount = min(data.count, maxBodyPrintLength)
        let preview = data.prefix(previewCount)
        if data.count <= maxBodyPrintLength {
            if let str = String(data: preview, encoding: .utf8) {
                output += "Body: \(str)\n"
            } else {
                output += "Body: \(data.count) bytes (binary)\n"
            }
        } else {
            output += "Body: \(data.count) bytes (truncated, first \(previewCount) bytes: "
            if let str = String(data: preview, encoding: .utf8) {
                output += "\(str.prefix(200))...)\n"
            } else {
                output += "binary)\n"
            }
        }
        output += "============================================"

        print(output)
    }

    public func didCatch(_ error: Error, request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws {
        guard level != .none else { return }
        print("[ZTAPI] Error: \(error)")
        print("[ZTAPI] URL: \(request.url?.absoluteString ?? "nil")")
        if let response = response {
            print("[ZTAPI] Status: \(response.statusCode)")
        }
    }
}

/// Authentication plugin - automatically add Token
public struct ZTAuthPlugin: ZTAPIPlugin {
    let token: @Sendable () -> String?
    
    public init(_ handler: @escaping @Sendable () -> String?) {
        token = handler
    }
    
    public func willSend(_ request: inout URLRequest) async throws {
        guard let token = token() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

/// Token refresher - uses Actor to ensure thread safety
/// Implements single-flight pattern: multiple concurrent requests only trigger one token refresh
public actor ZTTokenRefresher {
    private var refreshingTask: Task<String, Error>?

    public init() {}

    /// Refresh token (reuse existing refresh task result if one is in progress)
    public func refreshIfNeeded(
        _ action: @escaping () async throws -> String
    ) async throws -> String {
        // If a refresh task is already in progress, wait for it to complete
        if let task = refreshingTask {
            return try await task.value
        }

        // Create new refresh task
        let task = Task {
            defer { refreshingTask = nil }
            return try await action()
        }
        refreshingTask = task
        return try await task.value
    }
}

/// Token refresh plugin
public struct ZTTokenRefreshPlugin: ZTAPIPlugin {
    let shouldRefresh: @Sendable (_ error: Error) -> Bool
    let refresh: @Sendable () async throws -> String
    let onRefresh: @Sendable (String) -> Void

    /// Token refresher - nil means don't use single-flight mode
    private let refresher: ZTTokenRefresher?

    public init(
        shouldRefresh: @escaping @Sendable (_ error: Error) -> Bool,
        refresh: @escaping @Sendable () async throws -> String,
        onRefresh: @escaping @Sendable (String) -> Void,
        useSingleFlight: Bool = true
    ) {
        self.shouldRefresh = shouldRefresh
        self.refresh = refresh
        self.onRefresh = onRefresh
        self.refresher = useSingleFlight ? ZTTokenRefresher() : nil
    }

    public func willSend(_ request: inout URLRequest) async throws {
        // Can implement token expiration check here
    }

    public func didCatch(_ error: Error, request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws {
        if shouldRefresh(error) {
            do {
                let newToken: String
                if let refresher = refresher {
                    // Use single-flight mode to refresh
                    newToken = try await refresher.refreshIfNeeded(refresh)
                } else {
                    // Direct refresh (not recommended, may cause concurrent refreshes)
                    newToken = try await refresh()
                }
                onRefresh(newToken)
            } catch {
                print("[ZTAPI] Token refresh failed: \(error)")
            }
        }
    }
}

/// JSON decode plugin - automatically parse response data as JSON and re-encode
public struct ZTJSONDecodePlugin: ZTAPIPlugin {
    public func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data {
        // Try to parse JSON, beautify then re-encode and return
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return data  // If not JSON, return as-is
        }
        return prettyData
    }
}

/// Data decrypt plugin - example: automatically decrypt response data
public struct ZTDecryptPlugin: ZTAPIPlugin {
    let decrypt: @Sendable (Data) -> Data
    
    public init(_ handler: @escaping @Sendable (Data) -> Data) {
        decrypt = handler
    }
    
    public func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data {
        return decrypt(data)
    }
}

/// Response header injector plugin - example: add response header info to data
public struct ZTResponseHeaderInjectorPlugin: ZTAPIPlugin {
    public func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data {
        // Add response header info to JSON
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
              let jsonObject = json as? [String: Any] else {
            return data
        }

        // Add response header metadata
        var metadata: [String: Any] = [
            "_response": [
                "statusCode": response.statusCode,
                "headers": response.allHeaderFields
            ]
        ]
        // Merge original data
        metadata.merge(jsonObject) { $1 }

        do {
            return try JSONSerialization.data(withJSONObject: metadata)
        } catch {
            // NSError subclass (JSONSerialization error)
            if type(of: error) is NSError.Type {
                let nsError = error as NSError
                throw ZTAPIError(nsError.code, "JSON encoding failed: \(nsError.localizedDescription)", httpResponse: response)
            }
            throw error
        }
    }
}

// Sometimes there are different providers that may need to convert to upper-level Error types
public struct ZTTransferErrorPlugin: ZTAPIPlugin {
    let transfer: @Sendable (Error) -> Error
    
    public init(_ handler: @escaping @Sendable (Error) -> Error) {
        transfer = handler
    }
    
    public func didCatch(_ error: Error, request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws {
        throw transfer(error)
    }
}

// Check if the returned { "code": 0, "message": "...", "data": ... } code is not 0
public struct ZTCheckRespOKPlugin: ZTAPIPlugin {
    public init() {}

    public func didReceive(_ response: HTTPURLResponse, data: Data, request: URLRequest) async throws {
        // Only handle HTTP success case
        guard response.statusCode == 200 else {
            throw ZTAPIError(response.statusCode, "HTTP error: \(response.statusCode)", httpResponse: response)
        }

        let json: [String: Any]
        do {
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ZTAPIError.invalidResponseFormat(httpResponse: response)
            }
            json = j
        } catch {
            if error is ZTAPIError { throw error }
            // NSError subclass (JSONSerialization error)
            if type(of: error) is NSError.Type {
                let nsError = error as NSError
                throw ZTAPIError(nsError.code, "JSON parse failed: \(nsError.localizedDescription)", httpResponse: response)
            }
            throw error
        }

        let code = json["code"] as? String
        // Check business code
        if code != "0" {
            let msg = json["message"] as? String
            throw ZTAPIError(Int(code ?? "") ?? -1, msg ?? "API returned unknown error", httpResponse: response)
        }
    }
}

// Extract data field from returned { "code": 0, "message": "...", "data": ... } structure
public struct ZTReadPayloadPlugin: ZTAPIPlugin {
    public init() {}

    public func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data {
        let json: [String: Any]
        do {
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ZTAPIError.invalidResponseFormat(httpResponse: response)
            }
            json = j
        } catch {
            if error is ZTAPIError { throw error }
            // NSError subclass (JSONSerialization error)
            if type(of: error) is NSError.Type {
                let nsError = error as NSError
                throw ZTAPIError(nsError.code, "JSON parse failed: \(nsError.localizedDescription)", httpResponse: response)
            }
            throw error
        }

        guard let payload = json["data"] else {
            return Data("null".utf8)
        }

        // Always use JSONSerialization to avoid illegal JSON
        if payload is NSNull {
            return Data("null".utf8)
        }

        guard JSONSerialization.isValidJSONObject(payload) else {
            throw ZTAPIError.unsupportedPayloadType
        }

        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            // NSError subclass (JSONSerialization error)
            if type(of: error) is NSError.Type {
                let nsError = error as NSError
                throw ZTAPIError(nsError.code, "JSON encoding failed: \(nsError.localizedDescription)", httpResponse: response)
            }
            throw error
        }
    }
}
