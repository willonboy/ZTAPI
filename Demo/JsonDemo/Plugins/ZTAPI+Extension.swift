//
//  ZTAPI+Extension.swift
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
import Combine

@MainActor
public extension ZTAPI {
    /// Wrapper for safely passing Future.Promise across concurrency domains
    private struct PromiseTransfer<T>: @unchecked Sendable {
        let value: T
    }
    
    /// Send request and return Publisher of Codable type
    func publisher<T: Codable & Sendable>() -> AnyPublisher<T, Error> {
        Deferred {
            Future { promise in
                let promiseTransfer = PromiseTransfer(value: promise)
                Task {
                    do {
                        let result: T
                        // Data should use raw response path instead of JSONDecoder(Data.self,...)
                        if T.self == Data.self {
                            let raw = try await self.send()
                            guard let typed = raw as? T else {
                                throw ZTAPIError.invalidResponseFormat
                            }
                            result = typed
                        } else {
                            result = try await self.response()
                        }
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
}

@MainActor
public extension ZTAPI {
    /// Send request and return response as [String: Any] dictionary
    func responseDict() async throws -> [String: Any] {
        let data = try await send()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZTAPIError.invalidResponseFormat
        }
        return json
    }

    /// Send request and return response as [[String: Any]] array
    func responseArr() async throws -> [[String: Any]] {
        let data = try await send()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ZTAPIError.invalidResponseFormat
        }
        return json
    }
}
