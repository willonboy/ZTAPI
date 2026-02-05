//
//  ZTAPICacheProvider.swift
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
import ZTJSON
import ZTAPICore

// MARK: - Cache Policy

/// Cache read policy - controls how cache is read
public enum ZTCacheReadPolicy: Sendable {
    case networkOnly               // Only fetch from network, ignore cache
    case cacheOnly                 // Only read from cache, error if miss
    case cacheElseNetwork          // Try cache first, fallback to network if miss
    case networkElseCache          // Try network first, fallback to cache on error
}

/// Cache write policy - controls when data is cached
public enum ZTCacheWritePolicy: Sendable {
    case never                     // Never write to cache
    case always                    // Always write to cache
    case onSuccess                 // Only write on successful responses (2xx)
}

// MARK: - Cache Configuration

public struct ZTAPICacheConfig: Sendable {
    public let readPolicy: ZTCacheReadPolicy
    public let writePolicy: ZTCacheWritePolicy
    public let cacheDuration: TimeInterval    // Cache expiry time in seconds
    public let cacheKeyGenerator: @Sendable (URLRequest) -> String

    public init(
        readPolicy: ZTCacheReadPolicy = .cacheElseNetwork,
        writePolicy: ZTCacheWritePolicy = .onSuccess,
        cacheDuration: TimeInterval = 300,    // Default 5 minutes
        cacheKeyGenerator: @escaping @Sendable (URLRequest) -> String = { request in
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            return "\(method):\(url):\(auth)"
        }
    ) {
        self.readPolicy = readPolicy
        self.writePolicy = writePolicy
        self.cacheDuration = cacheDuration
        self.cacheKeyGenerator = cacheKeyGenerator
    }

    public static let `default` = ZTAPICacheConfig()

    /// Long-lived cache - 1 hour
    public static let longLived = ZTAPICacheConfig(cacheDuration: 3600)

    /// Short-lived cache - 1 minute
    public static let shortLived = ZTAPICacheConfig(cacheDuration: 60)
}

// MARK: - Cache Entry (LRU)

private struct CacheEntry: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let expiry: Date
    var lastAccess: Date

    var isExpired: Bool {
        Date() > expiry
    }
}

// MARK: - Cache Provider (In-memory Cache)

/// A caching provider wrapper that sits on top of any ZTAPIProvider
/// Implements thread-safe in-memory caching with configurable policies
public actor ZTAPICacheProvider: ZTAPIProvider {

    private let baseProvider: any ZTAPIProvider
    private let config: ZTAPICacheConfig

    private var storage: [String: CacheEntry] = [:]

    public private(set) var currentCacheSize: Int = 0
    public let maxCacheSize: Int

    public private(set) var cacheHits = 0
    public private(set) var cacheMisses = 0

    // MARK: - Initialization

    /// Create a new cache provider
    /// - Parameters:
    ///   - baseProvider: The underlying provider to use for network requests
    ///   - config: Cache configuration
    ///   - maxCacheSize: Maximum cache size in bytes (default: 50MB, 0 = unlimited)
    public init(
        baseProvider: any ZTAPIProvider,
        config: ZTAPICacheConfig = .default,
        maxCacheSize: Int = 50 * 1024 * 1024
    ) {
        self.baseProvider = baseProvider
        self.config = config
        self.maxCacheSize = maxCacheSize
    }

    /// Convenience init with individual parameters
    public init(
        baseProvider: any ZTAPIProvider,
        readPolicy: ZTCacheReadPolicy = .cacheElseNetwork,
        writePolicy: ZTCacheWritePolicy = .onSuccess,
        cacheDuration: TimeInterval = 300,
        maxCacheSize: Int = 50 * 1024 * 1024
    ) {
        self.baseProvider = baseProvider
        self.config = ZTAPICacheConfig(
            readPolicy: readPolicy,
            writePolicy: writePolicy,
            cacheDuration: cacheDuration
        )
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - ZTAPIProvider

    public func request(
        _ request: URLRequest,
        uploadProgress: ZTUploadProgressHandler?
    ) async throws -> (Data, HTTPURLResponse) {

        let key = config.cacheKeyGenerator(request)

        switch config.readPolicy {

        case .networkOnly:
            return try await fetchFromNetwork(request, uploadProgress, key)

        case .cacheOnly:
            return try fetchFromCache(key)

        case .cacheElseNetwork:
            if let cached = try? fetchFromCache(key) {
                return cached
            }
            return try await fetchFromNetwork(request, uploadProgress, key)

        case .networkElseCache:
            do {
                return try await fetchFromNetwork(request, uploadProgress, key)
            } catch {
                if let cached = try? fetchFromCache(key) {
                    return cached
                }
                throw error
            }
        }
    }

    // MARK: - Network

    private func fetchFromNetwork(
        _ request: URLRequest,
        _ progress: ZTUploadProgressHandler?,
        _ key: String
    ) async throws -> (Data, HTTPURLResponse) {

        let (data, response) = try await baseProvider.request(request, uploadProgress: progress)

        if shouldCache(response: response, request: request) {
            writeCache(key: key, data: data, response: response)
        }

        return (data, response)
    }

    // MARK: - Cache

    private func fetchFromCache(_ key: String) throws -> (Data, HTTPURLResponse) {
        guard let entry = storage[key] else {
            cacheMisses += 1
            throw ZTAPIError.cacheNotFound
        }

        guard !entry.isExpired else {
            storage.removeValue(forKey: key)
            currentCacheSize -= entry.data.count
            cacheMisses += 1
            throw ZTAPIError.cacheExpired
        }

        cacheHits += 1
        storage[key]?.lastAccess = Date()

        return (entry.data, entry.response)
    }

    private func shouldCache(
        response: HTTPURLResponse,
        request: URLRequest
    ) -> Bool {

        guard request.httpMethod == "GET" else { return false }

        switch config.writePolicy {
        case .never:
            return false
        case .always:
            return true
        case .onSuccess:
            return (200..<300).contains(response.statusCode)
        }
    }

    private func writeCache(
        key: String,
        data: Data,
        response: HTTPURLResponse
    ) {
        evictIfNeeded(adding: data.count)

        let entry = CacheEntry(
            data: data,
            response: response,
            expiry: Date().addingTimeInterval(config.cacheDuration),
            lastAccess: Date()
        )

        if let old = storage[key] {
            currentCacheSize -= old.data.count
        }

        storage[key] = entry
        currentCacheSize += data.count
    }

    // MARK: - Eviction (LRU)

    private func evictIfNeeded(adding size: Int) {
        guard maxCacheSize > 0 else { return }

        while currentCacheSize + size > maxCacheSize {
            guard let lru = storage.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else {
                break
            }
            storage.removeValue(forKey: lru.key)
            currentCacheSize -= lru.value.data.count
        }
    }

    // MARK: - Management

    /// Clear all cached data
    public func clearCache() {
        storage.removeAll()
        currentCacheSize = 0
    }

    /// Clear cached data for a specific key
    public func clearCache(key: String) {
        if let entry = storage.removeValue(forKey: key) {
            currentCacheSize -= entry.data.count
        }
    }

    /// Clear cached data for a specific URL
    public func clearCache(url: String) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        let key = config.cacheKeyGenerator(request)
        clearCache(key: key)
    }

    /// Remove expired entries from cache
    public func removeExpired() {
        for (key, entry) in storage where entry.isExpired {
            storage.removeValue(forKey: key)
            currentCacheSize -= entry.data.count
        }
    }

    /// Get cache statistics
    public var cacheStats: CacheStats {
        let total = cacheHits + cacheMisses
        return CacheStats(
            entryCount: storage.count,
            totalSize: currentCacheSize,
            hitRate: total == 0 ? 0 : Double(cacheHits) / Double(total),
            hits: cacheHits,
            misses: cacheMisses
        )
    }
}

// MARK: - Cache Stats

public struct CacheStats: Sendable {
    public let entryCount: Int
    public let totalSize: Int
    public let hitRate: Double
    public let hits: Int
    public let misses: Int

    /// Formatted cache size (e.g., "1.5 MB")
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    /// Formatted hit rate (e.g., "85.5%")
    public var formattedHitRate: String {
        String(format: "%.1f%%", hitRate * 100)
    }
}

// MARK: - ZTAPIError

extension ZTAPIError {
    static var cacheNotFound: ZTAPIError {
        ZTAPIError(80030001, "Cache not found")
    }

    static var cacheExpired: ZTAPIError {
        ZTAPIError(80030002, "Cache expired")
    }
}
