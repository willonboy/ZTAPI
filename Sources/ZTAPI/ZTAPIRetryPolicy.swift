//
//  ZTAPIRetryPolicy.swift
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

// MARK: - Retry Policy

/// Retry policy protocol
public protocol ZTAPIRetryPolicy: Sendable {
    /// Whether should retry
    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool
    /// Delay before next retry (seconds)
    func delay(for attempt: Int) async -> TimeInterval
}

/// Fixed count retry policy
public struct ZTFixedRetryPolicy: ZTAPIRetryPolicy {
    public let maxAttempts: Int
    public let delay: TimeInterval
    public let retryableCodes: Set<Int>
    public let retryableErrorCodes: Set<Int>

    public init(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        retryableCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableErrorCodes: Set<Int> = [-1001, -1003, -1004, -1005, -1009]
    ) {
        self.maxAttempts = maxAttempts
        self.delay = delay
        self.retryableCodes = retryableCodes
        self.retryableErrorCodes = retryableErrorCodes
    }

    public func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        // Check HTTP status code
        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        // Check ZTAPIError code
        if let apiError = error as? ZTAPIError, retryableErrorCodes.contains(apiError.code) {
            return true
        }

        return false
    }

    public func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}

/// Exponential backoff retry policy
public struct ZTExponentialBackoffRetryPolicy: ZTAPIRetryPolicy {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let multiplier: Double
    public let retryableCodes: Set<Int>
    public let retryableErrorCodes: Set<Int>

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        multiplier: Double = 2.0,
        retryableCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        retryableErrorCodes: Set<Int> = [-1001, -1003, -1004, -1005, -1009]
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.retryableCodes = retryableCodes
        self.retryableErrorCodes = retryableErrorCodes
    }

    public func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        if let apiError = error as? ZTAPIError, retryableErrorCodes.contains(apiError.code) {
            return true
        }

        return false
    }

    public func delay(for attempt: Int) async -> TimeInterval {
        let delay = baseDelay * pow(multiplier, Double(attempt))
        return min(delay, maxDelay)
    }
}

/// Custom condition retry policy
public struct ZTConditionalRetryPolicy: ZTAPIRetryPolicy {
    public let maxAttempts: Int
    public let delay: TimeInterval
    public let shouldRetryCondition: @Sendable (
        _ request: URLRequest,
        _ error: Error,
        _ attempt: Int,
        _ response: HTTPURLResponse?
    ) async -> Bool

    public init(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        shouldRetryCondition: @escaping @Sendable (
            _ request: URLRequest,
            _ error: Error,
            _ attempt: Int,
            _ response: HTTPURLResponse?
        ) async -> Bool
    ) {
        self.maxAttempts = maxAttempts
        self.delay = delay
        self.shouldRetryCondition = shouldRetryCondition
    }

    public func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }
        return await shouldRetryCondition(request, error, attempt, response)
    }

    public func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}
