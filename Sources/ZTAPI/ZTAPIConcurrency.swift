//
//  ZTAPIConcurrency.swift
//  SnapkitDemo
//
//  Created by zt
//

import Foundation

// MARK: - Concurrency Control

/// 并发控制信号量（Actor 保护）
/// 用于限制同时进行的网络请求数量
private actor ConcurrencySemaphore {
    private var currentCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let maxCount: Int

    init(maxCount: Int) {
        self.maxCount = maxCount
    }

    /// 获取执行许可，当达到上限时会等待
    func acquire() async {
        currentCount += 1
        if currentCount > maxCount {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// 释放许可，唤醒等待的任务
    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            currentCount -= 1
        }
    }

    /// 获取当前并发数
    func getCurrentCount() -> Int {
        currentCount
    }

    /// 获取最大并发数
    nonisolated func getMaxConcurrency() -> Int {
        maxCount
    }
}

/// 并发控制 Provider
/// 限制同时进行的网络请求数量，避免过多并发导致资源耗尽
final class ZTConcurrencyProvider: ZTAPIProvider {
    private let baseProvider: any ZTAPIProvider
    private let semaphore: ConcurrencySemaphore

    /// 基础 Provider
    var plugins: [any ZTAPIPlugin] { baseProvider.plugins }

    /// 重试策略（透传给 baseProvider）
    var retryPolicy: (any ZTAPIRetryPolicy)? { baseProvider.retryPolicy }

    /// 当前最大并发数
    var maxConcurrentOperationCount: Int {
        get {
            // 使用 nonisolated 方法直接访问 maxCount（同步访问，无需 await）
            semaphore.getMaxConcurrency()
        }
        set {
            // 修改需要重新创建 semaphore
            // 这里简化处理，运行时不支持动态修改
        }
    }

    /// 初始化并发控制 Provider
    /// - Parameters:
    ///   - baseProvider: 底层 Provider，实际执行网络请求
    ///   - maxConcurrency: 最大并发数，默认 6
    init(
        baseProvider: any ZTAPIProvider,
        maxConcurrency: Int = 6
    ) {
        self.baseProvider = baseProvider
        self.semaphore = ConcurrencySemaphore(maxCount: maxConcurrency)
    }

    /// 发送请求，受并发数限制控制
    /// - Parameters:
    ///   - urlRequest: 请求对象
    ///   - timeout: 超时时间（秒），nil 使用默认值
    ///   - uploadProgress: 上传进度回调（可选）
    /// - Returns: 响应数据
    func request(
        _ urlRequest: URLRequest,
        timeout: TimeInterval?,
        uploadProgress: ZTUploadProgressHandler?
    ) async throws -> Data {
        // 获取执行许可（如果达到上限会等待）
        await semaphore.acquire()

        defer {
            // 释放许可
            Task {
                await semaphore.release()
            }
        }

        // 执行实际的网络请求
        return try await baseProvider.request(
            urlRequest,
            timeout: timeout,
            uploadProgress: uploadProgress
        )
    }
}

/// 便捷初始化：创建带并发控制的默认 Provider
/// - Parameters:
///   - maxConcurrency: 最大并发数
/// - Returns: 包装后的 Provider
func concurrencyProvider(
    maxConcurrency: Int = 6
) -> any ZTAPIProvider {
    // 获取默认的 URLSession Provider
    let baseProvider = ZTURLSessionProvider()
    return ZTConcurrencyProvider(
        baseProvider: baseProvider,
        maxConcurrency: maxConcurrency
    )
}

/// 便捷初始化：为指定 Provider 添加并发控制
/// - Parameters:
///   - provider: 底层 Provider
///   - maxConcurrency: 最大并发数
/// - Returns: 包装后的 Provider
func withConcurrency(
    _ provider: any ZTAPIProvider,
    maxConcurrency: Int = 6
) -> any ZTAPIProvider {
    ZTConcurrencyProvider(
        baseProvider: provider,
        maxConcurrency: maxConcurrency
    )
}

// MARK: - Global API Provider

/// App 全局 API Provider 单例
/// 所有网络请求通过此 Provider 发起，自动控制并发数
final class ZTGlobalAPIProvider: @unchecked Sendable {
    /// 共享实例，配置好并发控制（默认最多 6 个并发）
    static let shared = ZTGlobalAPIProvider()

    /// 底层并发控制 Provider
    private(set) var provider: any ZTAPIProvider

    /// 当前最大并发数
    private(set) var currentMaxConcurrency: Int

    /// 修改并发数时的锁
    private let lock = DispatchQueue(label: "com.zt.global-api.lock")

    private init() {
        self.currentMaxConcurrency = 6
        // 创建基础 Provider
        let baseProvider = ZTURLSessionProvider()
        // 包装并发控制，最多 6 个并发
        self.provider = ZTConcurrencyProvider(
            baseProvider: baseProvider,
            maxConcurrency: 6
        )
    }

    /// 修改全局并发数
    func setMaxConcurrency(_ count: Int) {
        lock.sync {
            let baseProvider = ZTURLSessionProvider()
            provider = ZTConcurrencyProvider(
                baseProvider: baseProvider,
                maxConcurrency: count
            )
            currentMaxConcurrency = count
        }
    }

    /// 获取当前最大并发数
    func maxConcurrency() -> Int {
        lock.sync { currentMaxConcurrency }
    }
}
