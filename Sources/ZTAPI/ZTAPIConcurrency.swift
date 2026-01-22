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
final class ZTConcurrencyProvider: ZTAPIProvider {
    let baseProvider: any ZTAPIProvider
    private let semaphore: ZTConcurrencySemaphore

    var maxConcurrentOperationCount: Int {
        semaphore.getMaxConcurrency()
    }

    init(baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        self.baseProvider = baseProvider
        self.semaphore = ZTConcurrencySemaphore(maxCount: maxConcurrency)
    }

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
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

// MARK: - Global API Provider


/// Global API Provider (business Actor)
/// Responsible for maintaining current Provider state
public actor ZTGlobalAPIProvider {

    private var baseProvider: any ZTAPIProvider
    private var concurrencyProvider: ZTConcurrencyProvider
    private(set) var currentMaxConcurrency: Int

    init(baseProvider: any ZTAPIProvider, maxConcurrency: Int) {
        self.baseProvider = baseProvider
        self.currentMaxConcurrency = maxConcurrency
        self.concurrencyProvider = ZTConcurrencyProvider(
            baseProvider: baseProvider,
            maxConcurrency: maxConcurrency
        )
    }

    /// Exposed Provider
    public var provider: any ZTAPIProvider {
        concurrencyProvider
    }

    /// Replace underlying Provider (keep concurrency count)
    public func setProvider(_ newProvider: any ZTAPIProvider) {
        baseProvider = newProvider
        concurrencyProvider = ZTConcurrencyProvider(
            baseProvider: newProvider,
            maxConcurrency: currentMaxConcurrency
        )
    }

    /// Change max concurrency count
    public func setMaxConcurrency(_ count: Int) {
        currentMaxConcurrency = count
        concurrencyProvider = ZTConcurrencyProvider(
            baseProvider: baseProvider,
            maxConcurrency: count
        )
    }
}

/// Global Provider storage Actor
/// Responsible for lifecycle and singleton semantics
public actor ZTGlobalAPIProviderStore {
    public static let shared = ZTGlobalAPIProviderStore()
    private var instance: ZTGlobalAPIProvider?

    private init() {}

    /// Configure global Provider
    public func configure(baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        instance = ZTGlobalAPIProvider(baseProvider: baseProvider, maxConcurrency: maxConcurrency)
    }

    /// Get global Provider
    public func get() -> ZTGlobalAPIProvider {
        guard let instance else {
            fatalError(
                "ZTGlobalAPIProvider not configured. Call configure() first."
            )
        }
        return instance
    }

    /// Reset (usually only for testing)
    public func reset() {
        instance = nil
    }
}


/// Synchronous proxy for global Provider
/// Purpose:
/// - Provide synchronously available ZTAPIProvider
/// - Internally forward to actor-managed global Provider
final class ZTGlobalProviderProxy: ZTAPIProvider {
    static let shared = ZTGlobalProviderProxy()

    private init() {}

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let globalProvider = await ZTGlobalAPIProviderStore.shared.get()
        let provider = await globalProvider.provider

        return try await provider.request(
            urlRequest,
            uploadProgress: uploadProgress
        )
    }
}

// MARK: - Global Provider Convenience

extension ZTAPI {
    /// Create API instance using global Provider
    public static func global(_ url: String, _ method: ZTHTTPMethod = .get) -> ZTAPI<P> {
        ZTAPI(url, method, provider: ZTGlobalProviderProxy.shared)
    }
}
