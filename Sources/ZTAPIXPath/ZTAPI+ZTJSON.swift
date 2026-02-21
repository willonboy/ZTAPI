//
//  ZTAPITests.swift
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

#if canImport(ZTJSON)
import Foundation
import SwiftyJSON
import ZTJSON
import ZTAPICore

// MARK: - Parse Config

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

// MARK: - ZTAPI Error Extension

public extension ZTAPIError {
    /// XPath related errors 80020000-80020999

    /// XPath parsing failed
    static func xpathParseFailed(_ xpath: String) -> ZTAPIError {
        ZTAPIError(80020001, "XPath parsing failed: path '\(xpath)' not found")
    }

    /// XPath type conversion failed
    static func xpathTypeMismatch(_ xpath: String, expectedType: Any.Type, underlying: Error? = nil) -> ZTAPIError {
        if let underlying {
            return ZTAPIError(
                80020002,
                "XPath parsing failed at '\(xpath)': expected \(expectedType), underlying: \(underlying)"
            )
        }
        return ZTAPIError(
            80020002,
            "XPath parsing failed at '\(xpath)': expected \(expectedType)"
        )
    }
}

// MARK: - ZTAPI ZTJSON Extension

extension ZTAPI {
    /// Runtime XPath parsing for multiple fields
    /// - Parameter configs: Parse configurations with xpath and target type
    /// - Returns: Dictionary mapping xpath to parsed objects
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
                    if !config.isAllowMissing {
                        throw ZTAPIError.xpathTypeMismatch(
                            config.xpath,
                            expectedType: config.type,
                            underlying: error
                        )
                    }
                }
            } else if !config.isAllowMissing {
                throw ZTAPIError.xpathParseFailed(config.xpath)
            }
        }

        return res
    }
}
#endif
