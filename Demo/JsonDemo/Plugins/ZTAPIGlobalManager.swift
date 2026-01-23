//
//  ZTAPIGlobalManager.swift
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


/// Global API Provider (business Actor)
/// Responsible for maintaining current Provider state
enum ZTAPIGlobalManager {
    static let provider = {
        ZTConcurrencyProvider(
            baseProvider: ZTAlamofireProvider(),
            maxConcurrency: 6
        )
    }()
}

// MARK: - Global Provider Convenience

extension ZTAPI {
    /// Create API instance using global Provider
    public static func global(_ url: String, _ method: ZTHTTPMethod = .get) -> ZTAPI<P> {
        ZTAPI(url, method, provider: ZTAPIGlobalManager.provider)
    }
}
