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
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var waiterOrder: [UUID] = []
    let maxCount: Int

    init(maxCount: Int) {
        self.maxCount = max(1, maxCount)
    }

    func acquire() async throws {
        if currentCount < maxCount {
            currentCount += 1
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[waiterID] = continuation
                waiterOrder.append(waiterID)
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID)
            }
        }

        // When woken up, already "inherited" a released slot
        currentCount += 1
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = waiters.removeValue(forKey: waiterID) else {
            return
        }
        waiterOrder.removeAll { $0 == waiterID }
        continuation.resume(throwing: CancellationError())
    }

    func release() {
        if let nextWaiterID = waiterOrder.first,
           let continuation = waiters.removeValue(forKey: nextWaiterID) {
            waiterOrder.removeFirst()
            continuation.resume(returning: ())
            return
        }

        if currentCount > 0 {
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
        try await semaphore.acquire()
        do {
            let result = try await baseProvider.request(
                urlRequest,
                uploadProgress: uploadProgress
            )
            await semaphore.release()
            return result
        } catch {
            await semaphore.release()
            throw error
        }
    }
}
