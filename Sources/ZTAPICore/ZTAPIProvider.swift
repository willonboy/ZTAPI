//
//  ZTAPIProvider.swift
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

/// Network request provider protocol
public protocol ZTAPIProvider: Sendable {
    /// Send request
    /// - Parameters:
    ///   - urlRequest: Request object (timeout already set via URLRequest.timeoutInterval)
    ///   - uploadProgress: Upload progress callback (optional)
    /// - Returns: (Response data, HTTP response)
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse)
}




/// Provider retry wrapper (request-level retry, internal use)
final class ZTRetryProvider: @unchecked Sendable, ZTAPIProvider {
    /// Maximum hard limit for retry attempts to prevent infinite loops
    private static let maxRetryHardLimit = 100

    private let baseProvider: any ZTAPIProvider
    private let retryPolicy: any ZTAPIRetryPolicy

    init(baseProvider: any ZTAPIProvider, retryPolicy: any ZTAPIRetryPolicy) {
        self.baseProvider = baseProvider
        self.retryPolicy = retryPolicy
    }

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while attempt < Self.maxRetryHardLimit {
            try Task.checkCancellation()

            do {
                return try await baseProvider.request(
                    urlRequest,
                    uploadProgress: uploadProgress
                )
            } catch {
                if error is CancellationError {
                    throw error
                }

                attempt += 1

                // Hard limit check to prevent infinite loops from buggy retry policies
                guard attempt < Self.maxRetryHardLimit else {
                    throw ZTAPIError(
                        80000006,
                        "Exceeded maximum retry limit (\(Self.maxRetryHardLimit))",
                        httpResponse: (error as? ZTAPIError)?.httpResponse
                    )
                }

                // Try to get associated HTTPURLResponse from ZTAPIError
                let httpResponse = (error as? ZTAPIError)?.httpResponse

                guard await retryPolicy.shouldRetry(
                    request: urlRequest,
                    error: error,
                    attempt: attempt,
                    response: httpResponse
                ) else {
                    throw error
                }

                let delay = await retryPolicy.delay(for: attempt)

    #if DEBUG
                print("[ZTAPI] Retry attempt \(attempt) after \(delay)s")
    #endif

                try await Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000)
                )
            }
        }

        // This should never be reached, but added for compiler safety
        throw ZTAPIError(80000006, "Retry loop exited unexpectedly")
    }
}
