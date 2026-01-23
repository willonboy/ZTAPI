//
//  ZTAPIPlugin.swift
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
