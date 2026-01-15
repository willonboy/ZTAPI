//
//  ZTAPIRetryPolicy.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation

// MARK: - Retry Policy

/// 重试策略协议
protocol ZTAPIRetryPolicy: Sendable {
    /// 是否应该重试
    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool
    /// 下次重试前的延迟时间（秒）
    func delay(for attempt: Int) async -> TimeInterval
}

/// 固定次数重试策略
struct ZTFixedRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let retryableCodes: Set<Int>
    let retryableErrorCodes: Set<Int>

    init(
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

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        // 检查 HTTP 状态码
        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        // 检查 NSError 错误码
        let nsError = error as NSError
        if retryableErrorCodes.contains(nsError.code) {
            return true
        }

        return false
    }

    func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}

/// 指数退避重试策略
struct ZTExponentialBackoffRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    let retryableCodes: Set<Int>
    let retryableErrorCodes: Set<Int>

    init(
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

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }

        if let statusCode = response?.statusCode, retryableCodes.contains(statusCode) {
            return true
        }

        let nsError = error as NSError
        if retryableErrorCodes.contains(nsError.code) {
            return true
        }

        return false
    }

    func delay(for attempt: Int) async -> TimeInterval {
        let delay = baseDelay * pow(multiplier, Double(attempt))
        return min(delay, maxDelay)
    }
}

/// 自定义条件重试策略
struct ZTConditionalRetryPolicy: ZTAPIRetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval
    let shouldRetryCondition: @Sendable (
        _ request: URLRequest,
        _ error: Error,
        _ attempt: Int,
        _ response: HTTPURLResponse?
    ) async -> Bool

    init(
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

    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        guard attempt < maxAttempts else { return false }
        return await shouldRetryCondition(request, error, attempt, response)
    }

    func delay(for attempt: Int) async -> TimeInterval {
        delay
    }
}
