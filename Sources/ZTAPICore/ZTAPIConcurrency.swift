//
//  ZTAPIConcurrency.swift
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

// MARK: - Concurrency Control

/// Concurrency control semaphore (Actor protected)
/// Used to limit the number of concurrent network requests
private actor ZTConcurrencySemaphore {
    private var currentCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let maxCount: Int

    init(maxCount: Int) {
        self.maxCount = maxCount
    }

    func acquire() async {
        if currentCount < maxCount {
            currentCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        // When woken up, already "inherited" a released slot
        currentCount += 1
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            currentCount -= 1
        }
    }

    func getCurrentCount() -> Int {
        currentCount
    }

    nonisolated func getMaxConcurrency() -> Int {
        maxCount
    }
}


/// Concurrency control Provider (internal use)
/// Limits the number of concurrent network requests to avoid resource exhaustion
public final class ZTConcurrencyProvider: ZTAPIProvider {
    private let baseProvider: any ZTAPIProvider
    private let semaphore: ZTConcurrencySemaphore

    var maxConcurrentOperationCount: Int {
        semaphore.getMaxConcurrency()
    }

    public init(baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        self.baseProvider = baseProvider
        self.semaphore = ZTConcurrencySemaphore(maxCount: maxConcurrency)
    }

    public func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        await semaphore.acquire()
        defer {
            Task {
                await semaphore.release()
            }
        }

        return try await baseProvider.request(
            urlRequest,
            uploadProgress: uploadProgress
        )
    }
}
