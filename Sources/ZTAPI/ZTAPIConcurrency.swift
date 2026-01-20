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
private actor ZTConcurrencySemaphore {
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
    /// 底层 Provider（暴露以便外部访问和复用）
    let baseProvider: any ZTAPIProvider
    private let semaphore: ZTConcurrencySemaphore

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
    init(baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        self.baseProvider = baseProvider
        self.semaphore = ZTConcurrencySemaphore(maxCount: maxConcurrency)
    }

    /// 发送请求，受并发数限制控制
    /// - Parameters:
    ///   - urlRequest: 请求对象
    ///   - uploadProgress: 上传进度回调（可选）
    /// - Returns: (响应数据, HTTP响应)
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        // 获取执行许可（如果达到上限会等待）
        await semaphore.acquire()

        defer {
            // 释放许可
            Task {
                await semaphore.release()
            }
        }

        // 执行实际的网络请求
        return try await baseProvider.request(urlRequest, uploadProgress: uploadProgress)
    }
}

// MARK: - Global API Provider

/// App 全局 API Provider 单例
/// 所有网络请求通过此 Provider 发起，自动控制并发数
/// 使用前必须先调用 configure(_:) 配置
final class ZTGlobalAPIProvider: @unchecked Sendable {
    nonisolated(unsafe) private static var _instance: ZTGlobalAPIProvider?

    /// 共享实例
    /// 使用前必须先调用 configure(_:) 配置
    static var shared: ZTGlobalAPIProvider {
        guard let instance = _instance else {
            fatalError("ZTGlobalAPIProvider not configured. Call configure(_:) first.")
        }
        return instance
    }

    /// 底层并发控制 Provider
    private(set) var provider: any ZTAPIProvider

    /// 当前最大并发数
    private(set) var currentMaxConcurrency: Int

    /// 修改并发数时的锁
    private let lock = DispatchQueue(label: "com.zt.global-api.lock")

    /// 原始基础 Provider（不含并发控制包装）
    private var baseProvider: any ZTAPIProvider

    private init(baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        self.currentMaxConcurrency = maxConcurrency
        self.baseProvider = baseProvider
        // 包装并发控制
        self.provider = ZTConcurrencyProvider(baseProvider: baseProvider, maxConcurrency: maxConcurrency)
    }

    /// 配置全局 Provider
    /// - Parameters:
    ///   - baseProvider: 底层 Provider
    ///   - maxConcurrency: 最大并发数，默认 6
    static func configure(_ baseProvider: any ZTAPIProvider, maxConcurrency: Int = 6) {
        _instance = ZTGlobalAPIProvider(baseProvider: baseProvider, maxConcurrency: maxConcurrency)
    }

    /// 重置配置（主要用于测试）
    static func reset() {
        _instance = nil
    }

    /// 设置新的基础 Provider（保留当前并发数配置）
    /// - Parameter baseProvider: 新的基础 Provider
    func setProvider(_ baseProvider: any ZTAPIProvider) {
        lock.sync {
            self.baseProvider = baseProvider
            provider = ZTConcurrencyProvider(baseProvider: baseProvider, maxConcurrency: currentMaxConcurrency)
        }
    }

    /// 修改全局并发数（保留现有 baseProvider）
    /// - Parameter count: 新的最大并发数
    func setMaxConcurrency(_ count: Int) {
        lock.sync {
            provider = ZTConcurrencyProvider(baseProvider: baseProvider, maxConcurrency: count)
            currentMaxConcurrency = count
        }
    }

    /// 获取当前最大并发数
    func maxConcurrency() -> Int {
        lock.sync { currentMaxConcurrency }
    }
}
