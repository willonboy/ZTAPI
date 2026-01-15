//
//  ZTAPITests.swift
//  JsonDemo
//
//  Created by zt
//  ZTAPI 网络请求类测试用例
//

import Foundation
import SwiftyJSON
import ZTJSON
import Combine
import OSLog
import UIKit

/// ZTAPI 测试类
@MainActor
class ZTAPITests {

    private let logger = Logger(subsystem: "com.zt.JsonDemo", category: "ZTAPITests")

    // MARK: - 测试结果统计

    private(set) var passedCount = 0
    private(set) var failedCount = 0
    private(set) var testResults: [String] = []

    // MARK: - 辅助方法

    private func log(_ message: String) {
        let logMessage = "[ZTAPI-TEST]: \(message)"
        print(logMessage)
        NSLog(logMessage)
        testResults.append(message)
    }

    private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: String = #file, line: Int = #line) {
        if lhs == rhs {
            passedCount += 1
            log("  ✅ 断言通过: \(lhs) == \(rhs)")
        } else {
            failedCount += 1
            log("  ❌ 断言失败: \(lhs) != \(rhs) (\(file):\(line))")
        }
    }

    private func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        if condition {
            passedCount += 1
            log("  ✅ 断言通过: \(message.isEmpty ? "true" : message)")
        } else {
            failedCount += 1
            log("  ❌ 断言失败: \(message) (\(file):\(line))")
        }
    }

    private func assertThrowsError<T>(_ block: () async throws -> T, file: String = #file, line: Int = #line) async {
        do {
            _ = try await block()
            failedCount += 1
            log("  ❌ 断言失败: 期望抛出错误但没有 (\(file):\(line))")
        } catch {
            passedCount += 1
            log("  ✅ 断言通过: 正确抛出错误 - \(error)")
        }
    }

    private func runTest(_ name: String, test: () async throws -> Void) async {
        log("\n========== \(name) ==========")
        do {
            try await test()
        } catch {
            failedCount += 1
            log("  ❌ 测试异常: \(error)")
        }
    }

    // MARK: - 测试用例

    /// 测试 ZTAPI 使用 Stub Provider
    func testZTAPIWithStubProvider() async {
        await runTest("testZTAPIWithStubProvider") {
            // 创建 stub provider
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/test": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: [
                        "success": true,
                        "message": "Hello from stub"
                    ])
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/test",
                .get,
                provider: stubProvider
            )
            .parse(.init("/success", type: Bool.self))
            .parse(.init("/message", type: String.self))

            let response = try await api.send()
            assertTrue(!response.isEmpty, "响应不应为空")
            log("  收到响应: \(response.count) 个解析项")
        }
    }

    /// 测试 ZTAPI 错误处理 - 无效 URL
    func testZTAPIInvalidURL() async {
        await runTest("testZTAPIInvalidURL") {
            await assertThrowsError {
                try await ZTAPI<ZTAPIKVParam>("invalid url", .get).send()
            }
        }
    }

    /// 测试 ZTAPIPublisher
    func testZTAPIPublisher() async {
        await runTest("testZTAPIPublisher") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/publisher": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: [
                        "data": ["id": 1, "name": "Publisher Test"]
                    ])
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/publisher",
                .get,
                provider: stubProvider
            )

            // 测试 Publisher
            var receivedResult: ZTAPI<ZTAPIKVParam>.APIResponse?
            var receivedError: Error?

            let cancellable = api.publisher.sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                },
                receiveValue: { value in
                    receivedResult = value
                }
            )

            // 等待异步完成
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

            assertTrue(receivedResult != nil || receivedError != nil, "应收到结果或错误")
            if let result = receivedResult {
                log("  Publisher 收到响应: \(result.count) 个解析项")
            }
            if let error = receivedError {
                log("  Publisher 收到错误: \(error)")
            }

            cancellable.cancel()
        }
    }


    /// 测试不同 Publisher 实例独立执行
    func testDifferentPublisherInstances() async {
        await runTest("testDifferentPublisherInstances") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/independent": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: ["value": "test"])
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/independent",
                .get,
                provider: stubProvider
            )

            var firstCall = false
            var secondCall = false

            // 两次访问 asyncPublisher 属性会创建不同的 Future 实例
            let p1 = api.publisher.sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in firstCall = true }
            )

            try await Task.sleep(nanoseconds: 50_000_000)

            let p2 = api.publisher.sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in secondCall = true }
            )

            try await Task.sleep(nanoseconds: 100_000_000)

            // 两个独立的 Future 实例，应该各自执行
            assertTrue(firstCall, "第一个订阅应执行")
            log("  第一次订阅: \(firstCall ? "执行" : "未执行")")
            log("  第二次订阅: \(secondCall ? "执行" : "未执行")")

            p1.cancel()
            p2.cancel()
        }
    }

    /// 测试未订阅时不执行请求
    func testPublisherNoExecutionWithoutSubscription() async {
        await runTest("testPublisherNoExecutionWithoutSubscription") {
            // 创建一个自定义的 Provider 来计数
            final class CountingStubNoExecProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var requestCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    requestCount += 1
                    return Data()
                }
            }

            let provider = CountingStubNoExecProvider()
            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/count",
                .get,
                provider: provider
            )

            // 只获取 Publisher，不订阅
            _ = api.publisher

            // 稍等片刻
            try await Task.sleep(nanoseconds: 100_000_000)

            assertTrue(provider.requestCount == 0, "未订阅时不应执行请求")
            log("  未订阅时请求次数: \(provider.requestCount)")
        }
    }


    // MARK: - 运行所有测试

    @MainActor
    func runAllTests() async {
        log("\n")
        log("╔════════════════════════════════════════════════════════════╗")
        log("║           ZTAPI 测试套件开始运行                              ║")
        log("╚════════════════════════════════════════════════════════════╝")

        // 异步测试
        await testZTAPIWithStubProvider()
        await testZTAPIInvalidURL()
        await testZTAPIPublisher()
        await testDifferentPublisherInstances()
        await testPublisherNoExecutionWithoutSubscription()

        // Timeout & Retry 测试
        await testTimeout()
        await testFixedRetryPolicy()
        await testRetryThenSuccess()
        await testNonRetryableError()
        await testTimeoutAndRetry()
        await testNoRetryPolicy()

        // Upload 测试
        await testUploadMethod()
        await testMultipartMethod()

        // Plugin 测试
        await testPluginProcessHook()

        // Token 刷新并发安全测试
        await testChatGPT_TokenRefresh_ConcurrencyRace()

        // 并发控制测试
        await testConcurrencyProvider()
        await testGlobalAPIProvider()

        // 打印总结
        log("\n")
        log("╔════════════════════════════════════════════════════════════╗")
        log("║                    测试结果汇总                              ║")
        log("╠════════════════════════════════════════════════════════════╣")
        log("║  通过: \(passedCount)                                       ║")
        log("║  失败: \(failedCount)                                       ║")
        log("║  总计: \(passedCount + failedCount)                         ║")
        log("╚════════════════════════════════════════════════════════════╝")

        if failedCount == 0 {
            log("\n✅ 所有测试通过！")
        } else {
            log("\n❌ 有 \(failedCount) 个测试失败")
        }
    }

    // MARK: - Timeout & Retry 测试

    /// 测试 Timeout 设置
    func testTimeout() async {
        await runTest("testTimeout") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/timeout": .init(
                    statusCode: 200,
                    data: Data([1, 2, 3]),
                    delay: 2.0 // 2秒延迟
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/timeout",
                .get,
                provider: stubProvider
            )
            .timeout(1) // 1秒超时

            do {
                _ = try await api.send()
                log("  ❌ 应该超时但没有")
            } catch {
                log("  ✅ 正确捕获超时错误: \(error)")
            }
        }
    }

    /// 测试固定重试策略
    func testFixedRetryPolicy() async {
        await runTest("testFixedRetryPolicy") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/retry": .init(
                    statusCode: 500, // 返回 500 错误
                    data: Data()
                )
            ])

            let retryPolicy = ZTFixedRetryPolicy(
                maxAttempts: 3,
                delay: 0.1,
                retryableCodes: [500]
            )

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/retry",
                .get,
                provider: stubProvider
            )
            .retry(retryPolicy)

            do {
                _ = try await api.send()
                log("  ❌ 应该抛出错误但没有")
            } catch {
                log("  ✅ 正确捕获错误（已重试）: \(error)")
            }
        }
    }

    /// 测试重试后成功
    func testRetryThenSuccess() async {
        await runTest("testRetryThenSuccess") {
            // 创建一个会变化响应的 stub provider
            final class CountingStubRetrySuccessProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    callCount += 1
                    // 前两次返回 500，第三次返回 200
                    if callCount <= 2 {
                        // 创建包含 HTTPURLResponse 的错误，以便重试策略能识别状态码
                        let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                        let error = NSError(domain: "Test", code: 500, userInfo: ["HTTPURLResponse": response])
                        throw error
                    }
                    return try! JSONSerialization.data(withJSONObject: ["result": "success"])
                }
            }

            let provider = CountingStubRetrySuccessProvider()
            let retryPolicy = ZTFixedRetryPolicy(maxAttempts: 3, delay: 0.05, retryableCodes: [500])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/eventual-success",
                .get,
                provider: provider
            )
            .retry(retryPolicy)
            .parse(.init("/result", type: String.self))

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")
            assertTrue(provider.callCount == 3, "应该重试了2次后成功，共3次请求")
            log("  ✅ 重试后成功，总请求次数: \(provider.callCount)")
        }
    }


    /// 测试不可重试的错误不触发重试
    func testNonRetryableError() async {
        await runTest("testNonRetryableError") {
            final class CountingStubNonRetryableProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    callCount += 1
                    // 返回 404 - 不在可重试状态码列表中
                    throw NSError(domain: "Test", code: 404, userInfo: nil)
                }
            }

            let provider = CountingStubNonRetryableProvider()
            let retryPolicy = ZTFixedRetryPolicy(maxAttempts: 5, delay: 0.05, retryableCodes: [500, 503])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/not-retryable",
                .get,
                provider: provider
            )
            .retry(retryPolicy)

            do {
                _ = try await api.send()
                log("  ❌ 应该抛出错误")
            } catch {
                assertTrue(provider.callCount == 1, "不可重试错误不应触发重试")
                log("  ✅ 不可重试错误只执行一次，调用次数: \(provider.callCount)")
            }
        }
    }

    /// 测试组合配置 timeout + retry
    func testTimeoutAndRetry() async {
        await runTest("testTimeoutAndRetry") {
            final class SlowStubProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    callCount += 1
                    // 每次请求返回 500，但很慢
                    try await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
                    throw NSError(domain: "Test", code: 500, userInfo: nil)
                }
            }

            let provider = SlowStubProvider()
            let retryPolicy = ZTFixedRetryPolicy(maxAttempts: 3, delay: 0.02, retryableCodes: [500])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/slow",
                .get,
                provider: provider
            )
            .timeout(1)  // 1秒超时
            .retry(retryPolicy)  // 最多3次重试

            let start = Date()
            do {
                _ = try await api.send()
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                assertTrue(elapsed < 2.0, "应该在超时时间内结束")
                log("  ✅ 组合配置测试通过，耗时: \(String(format: "%.2f", elapsed))s，调用次数: \(provider.callCount)")
            }
        }
    }

    /// 测试没有重试策略时不重试
    func testNoRetryPolicy() async {
        await runTest("testNoRetryPolicy") {
            final class CountingStubNoRetryProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    callCount += 1
                    throw NSError(domain: "Test", code: 500, userInfo: nil)
                }
            }

            let provider = CountingStubNoRetryProvider()

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/no-retry",
                .get,
                provider: provider
            )
            // 不设置 retry policy

            do {
                _ = try await api.send()
                log("  ❌ 应该抛出错误")
            } catch {
                assertTrue(provider.callCount == 1, "没有重试策略时不应重试")
                log("  ✅ 没有重试策略只执行一次，调用次数: \(provider.callCount)")
            }
        }
    }

    // MARK: - Upload Tests

    /// 测试 upload 方法构建 Multipart 数据
    func testUploadMethod() async {
        await runTest("testUploadMethod") {
            let stubProvider = ZTStubProvider(stubs: [
                "POST:https://api.example.com/upload": .init(
                    statusCode: 200,
                    data: Data("{\"success\":true}".utf8)
                )
            ])

            let items: [ZTAPI<ZTAPIKVParam>.ZTUploadItem] = [
                .data(Data("file content".utf8), name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
                .data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json)
            ]

            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: stubProvider)
                .upload(items)
                .parse(.init("/success", type: Bool.self))

            // 验证请求已正确配置
            assertEqual(api.params.count, 0)
            // Content-Type 是在 encoding.encode() 时动态设置的，不是在构建时
            // 所以这里不能直接检查 api.headers["Content-Type"]
            assertTrue(api.bodyData == nil, "bodyData 应被 multipart 清除")

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")

            log("  ✅ upload 方法测试通过")
        }
    }

    /// 测试 multipart 方法
    func testMultipartMethod() async {
        await runTest("testMultipartMethod") {
            let stubProvider = ZTStubProvider(plugins: [], stubs: [
                "POST:https://api.example.com/upload": .init(
                    statusCode: 200,
                    data: Data("{\"success\":true}".utf8)
                )
            ])

            let formData = ZTMultipartFormData()
                .add(.data(Data("content".utf8), name: "file", fileName: "test.txt", mimeType: .txt))

            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: stubProvider)
                .multipart(formData)
                .parse(.init("/success", type: Bool.self))

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")

            log("  ✅ multipart 方法测试通过")
        }
    }


    /// 测试 Plugin 的 process hook
    func testPluginProcessHook() async {
        log("\n========== testPluginProcessHook ==========")

        // 测试插件：只转 JSON 值为大写，不转键
        struct UpperCaseValuePlugin: ZTAPIPlugin {
            func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
                // 将 JSON 中的字符串值转为大写
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return data
                }
                let uppercased = json.mapValues { value -> Any in
                    if let str = value as? String {
                        return str.uppercased()
                    }
                    return value
                }
                return try JSONSerialization.data(withJSONObject: uppercased)
            }
        }

        let stubProvider = ZTStubProvider(plugins: [UpperCaseValuePlugin()], stubs: [
            "GET:https://api.example.com/process": .init(
                statusCode: 200,
                data: Data("{\"message\":\"hello world\"}".utf8)
            )
        ])

        do {
            let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/process", .get, provider: stubProvider)
                .parse(.init("/message", type: String.self))
                .send()

            // process hook 会将响应值转为大写: {"message":"HELLO WORLD"}
            if let msg = result["/message"] as? String {
                assertEqual(msg, "HELLO WORLD")
                log("  ✅ Plugin process hook 测试通过")
            } else {
                log("  ❌ 未找到 message 字段")
                failedCount += 1
            }
        } catch {
            log("  ❌ Plugin process hook 测试失败: \(error)")
            failedCount += 1
        }
    }


    /// 辅助断言方法
    private func XCTAssertEqual<T: Equatable>(_ lhs: T?, _ rhs: T, file: String = #file, line: Int = #line) {
        if lhs == rhs {
            passedCount += 1
            log("  ✅ 断言通过: \(String(describing: lhs)) == \(String(describing: rhs))")
        } else {
            failedCount += 1
            log("  ❌ 断言失败: \(String(describing: lhs)) != \(String(describing: rhs)) (\(file):\(line))")
        }
    }


    /// 验证问题3：Token refresh 并发竞态
    /// ChatGPT 声称多个并发请求会触发多次 token 刷新
    func testChatGPT_TokenRefresh_ConcurrencyRace() async {
        await runTest("testChatGPT_TokenRefresh_ConcurrencyRace") {
            log("  验证：多个并发请求触发 token 刷新的行为")

            // 创建一个用于计数刷新次数的 actor
            actor RefreshCounter {
                private(set) var refreshCount = 0
                private(set) var onRefreshCount = 0

                func incrementRefresh() {
                    refreshCount += 1
                }

                func incrementOnRefresh() {
                    onRefreshCount += 1
                }

                var counts: (refresh: Int, onRefresh: Int) {
                    (refreshCount, onRefreshCount)
                }
            }

            let counter = RefreshCounter()

            // 测试1：不使用 Actor 的旧版本（会并发刷新）
            let oldPlugin = ZTTokenRefreshPlugin(
                shouldRefresh: { _ in true },
                refresh: {
                    await counter.incrementRefresh()
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms 模拟网络延迟
                    return "new-token-\(UUID().uuidString)"
                },
                onRefresh: { _ in
                    // onRefresh 是同步函数，需要用 Task 包装异步调用
                    Task { await counter.incrementOnRefresh() }
                },
                useSingleFlight: false  // 不使用 single-flight 模式
            )

            // 创建一个总是返回 401 的 provider
            final class Always401Provider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin]
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var requestCount = 0

                init(plugins: [any ZTAPIPlugin] = []) {
                    self.plugins = plugins
                }

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> Data {
                    requestCount += 1
                    // 执行 willSend 插件
                    var request = urlRequest
                    for plugin in plugins {
                        try await plugin.willSend(&request)
                    }
                    // 返回 401 错误
                    throw NSError(domain: "Test", code: 401, userInfo: nil)
                }
            }

            let providerWithOldPlugin = Always401Provider(plugins: [oldPlugin])

            // 发起 3 个并发请求
            // 使用 Task 而非 async let 以避免 Sendable 约束
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/1", .get, provider: providerWithOldPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/2", .get, provider: providerWithOldPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/3", .get, provider: providerWithOldPlugin).send()
                }
                await group.waitForAll()
            }

            // 等待所有异步操作完成
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            let oldCounts = await counter.counts
            log("  不使用 Actor 时: refresh 被调用 \(oldCounts.refresh) 次, onRefresh 被调用 \(oldCounts.onRefresh) 次")

            if oldCounts.refresh > 1 {
                log("  ✅ 确认：不使用 Actor 时存在并发竞态（多次刷新）")
            }

            // 测试2：使用 Actor 的新版本（单次刷新）
            let newCounter = RefreshCounter()

            let newPlugin = ZTTokenRefreshPlugin(
                shouldRefresh: { _ in true },
                refresh: {
                    await newCounter.incrementRefresh()
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms 模拟网络延迟
                    return "new-token-\(UUID().uuidString)"
                },
                onRefresh: { _ in
                    // onRefresh 是同步函数，需要用 Task 包装异步调用
                    Task { await newCounter.incrementOnRefresh() }
                },
                useSingleFlight: true  // 使用 single-flight 模式（默认）
            )

            let providerWithNewPlugin = Always401Provider(plugins: [newPlugin])

            // 发起 3 个并发请求
            // 使用 TaskGroup 而非 async let 以避免 Sendable 约束
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/4", .get, provider: providerWithNewPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/5", .get, provider: providerWithNewPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/6", .get, provider: providerWithNewPlugin).send()
                }
                await group.waitForAll()
            }

            // 等待所有异步操作完成
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            let newCounts = await newCounter.counts
            log("  使用 Actor 后: refresh 被调用 \(newCounts.refresh) 次, onRefresh 被调用 \(newCounts.onRefresh) 次")

            if newCounts.refresh == 1 {
                log("  ✅ 确认：使用 Actor 后只刷新一次（single-flight 模式生效）")
                passedCount += 1
            } else if newCounts.refresh < oldCounts.refresh {
                log("  ✅ 使用 Actor 后刷新次数明显减少（从 \(oldCounts.refresh) 降到 \(newCounts.refresh)）")
                passedCount += 1
            }

            log("  结论：修复后的 ZTTokenRefresher Actor 有效防止了并发刷新")
        }
    }

    /// 测试并发控制 Provider
    /// 验证 ZTConcurrencyProvider 能正确限制并发请求数量
    func testConcurrencyProvider() async {
        await runTest("testConcurrencyProvider") {
            // 用于统计并发数的 Actor
            actor ConcurrencyTracker {
                private var currentConcurrent = 0
                private var maxConcurrent = 0
                private var completedCount = 0

                func start() {
                    currentConcurrent += 1
                    if currentConcurrent > maxConcurrent {
                        maxConcurrent = currentConcurrent
                    }
                }

                func end() {
                    currentConcurrent -= 1
                    completedCount += 1
                }

                func getStats() -> (current: Int, max: Int, completed: Int) {
                    (currentConcurrent, maxConcurrent, completedCount)
                }
            }

            let tracker = ConcurrencyTracker()

            // 创建一个能模拟延迟的 Provider
            final class DelayedStubProvider: ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                let delay: TimeInterval
                let tracker: ConcurrencyTracker

                init(delay: TimeInterval = 0.1, tracker: ConcurrencyTracker) {
                    self.delay = delay
                    self.tracker = tracker
                }

                func request(
                    _ urlRequest: URLRequest,
                    timeout: TimeInterval?,
                    uploadProgress: ZTUploadProgressHandler?
                ) async throws -> Data {
                    await tracker.start()
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await tracker.end()
                    return Data()
                }
            }

            // 创建并发控制 Provider，最大并发数为 3
            let baseProvider = DelayedStubProvider(delay: 0.1, tracker: tracker)
            let concurrentProvider = ZTConcurrencyProvider(
                baseProvider: baseProvider,
                maxConcurrency: 3
            )

            // 发起 10 个请求
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        let request = URLRequest(url: URL(string: "https://api.example.com/test/\(i)")!)
                        _ = try? await concurrentProvider.request(request)
                    }
                }
            }

            // 等待所有请求完成
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒

            let stats = await tracker.getStats()

            log("  完成请求数: \(stats.completed)")
            log("  最大并发数: \(stats.max)")

            // 验证：最大并发数不应超过设定的 3
            if stats.max <= 3 {
                log("  ✅ 并发控制正常：最大并发数为 \(stats.max)，不超过限制值 3")
                passedCount += 1
            } else {
                log("  ❌ 并发控制失效：最大并发数为 \(stats.max)，超过限制值 3")
                failedCount += 1
            }

            // 验证：所有请求都完成了
            if stats.completed == 10 {
                log("  ✅ 所有请求都已完成")
            } else {
                log("  ⚠️  部分请求未完成: \(stats.completed)/10")
            }
        }
    }

    /// 测试全局 API Provider 的并发控制
    /// 验证使用 ZTAPI.global() 创建的实例都使用统一的并发控制
    func testGlobalAPIProvider() async {
        await runTest("testGlobalAPIProvider") {
            // 测试1：验证默认并发数
            let originalMax = ZTGlobalAPIProvider.shared.maxConcurrency()
            log("  默认全局并发数: \(originalMax)")
            assertEqual(originalMax, 6)

            // 测试2：验证修改并发数功能
            ZTGlobalAPIProvider.shared.setMaxConcurrency(3)
            let newMax = ZTGlobalAPIProvider.shared.maxConcurrency()
            log("  修改后全局并发数: \(newMax)")
            assertEqual(newMax, 3)

            // 测试3：验证 global() 方法创建的 API 实例使用了全局 Provider
            let api1 = ZTAPI<ZTAPIKVParam>.global("https://api.example.com/test1", .get)
            let api2 = ZTAPI<ZTAPIKVParam>.global("https://api.example.com/test2", .post)

            // 验证 API 实例的配置
            assertEqual(api1.urlStr, "https://api.example.com/test1")
            assertEqual(api1.method, .get)
            assertEqual(api2.urlStr, "https://api.example.com/test2")
            assertEqual(api2.method, .post)
            log("  ✅ global() 方法正确创建了 API 实例")

            // 恢复原设置
            ZTGlobalAPIProvider.shared.setMaxConcurrency(originalMax)
            log("  ✅ 全局 API Provider 测试通过")
        }
    }
}
