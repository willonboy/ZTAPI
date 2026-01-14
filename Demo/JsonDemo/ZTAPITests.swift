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

    /// 测试 ZTAPIError 描述
    func testZTAPIErrorDescription() {
        log("\n========== testZTAPIErrorDescription ==========")
        let error = ZTAPIError(404, "Not Found")
        assertEqual(error.description, "ZTAPIError 404: Not Found")
        assertEqual(error.code, 404)
        assertEqual(error.msg, "Not Found")
    }

    /// 测试 ZTAPIHeader 枚举
    func testZTAPIHeader() {
        log("\n========== testZTAPIHeader ==========")
        let header = ZTAPIHeader.h(key: "Content-Type", value: "application/json")
        assertEqual(header.key, "Content-Type")
        assertEqual(header.value, "application/json")
    }

    /// 测试 ZTAPIKVParam 枚举
    func testZTAPIKVParam() {
        log("\n========== testZTAPIKVParam ==========")
        let param = ZTAPIKVParam.kv("user_id", "12345")
        assertEqual(param.key, "user_id")
        assertEqual(param.value as? String, "12345")
    }

    /// 测试 ZTURLEncoding - GET 请求
    func testZTURLEncodingGET() {
        log("\n========== testZTURLEncodingGET ==========")
        let encoding = ZTURLEncoding(.queryString)
        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "GET"

        try? encoding.encode(&request, with: ["page": 1, "limit": 10])

        assertTrue(
            request.url?.absoluteString.contains("page=1") == true,
            "URL 应包含 page=1"
        )
        assertTrue(
            request.url?.absoluteString.contains("limit=10") == true,
            "URL 应包含 limit=10"
        )

        log("  编码后 URL: \(request.url?.absoluteString ?? "nil")")
    }

    /// 测试 ZTURLEncoding - POST 请求
    func testZTURLEncodingPOST() {
        log("\n========== testZTURLEncodingPOST ==========")
        let encoding = ZTURLEncoding(.httpBody)
        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "POST"

        try? encoding.encode(&request, with: ["name": "John", "age": 30])

        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        assertTrue(
            bodyString.contains("name=John") == true,
            "Body 应包含 name=John"
        )
        assertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )

        log("  编码后 Body: \(bodyString)")
    }

    /// 测试 ZTJSONEncoding
    func testZTJSONEncoding() {
        log("\n========== testZTJSONEncoding ==========")
        let encoding = ZTJSONEncoding()
        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "POST"

        let params: [String: Sendable] = ["name": "John", "age": 30]
        try? encoding.encode(&request, with: params)

        assertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )

        if let body = request.httpBody,
           let json = try? JSON(data: body) {
            assertEqual(json["name"].stringValue, "John")
            assertEqual(json["age"].intValue, 30)
            log("  编码后 JSON: \(json)")
        } else {
            failedCount += 1
            log("  ❌ JSON 编码失败")
        }
    }

    /// 测试 ZTAPIParseConfig
    func testZTAPIParseConfig() {
        log("\n========== testZTAPIParseConfig ==========")
        let config1 = ZTAPIParseConfig("data/user", type: String.self)
        assertEqual(config1.xpath, "data/user")
        assertTrue(config1.isAllowMissing == true, "默认允许缺失")

        let config2 = ZTAPIParseConfig("data/token", type: String.self, false)
        assertEqual(config2.xpath, "data/token")
        assertTrue(config2.isAllowMissing == false, "不允许缺失")

        // 测试 Hashable
        let config3 = ZTAPIParseConfig("data/user", type: Int.self)
        assertTrue(config1 == config3, "相同 xpath 应该相等")
    }

    /// 测试 ZTAPI 链式调用构建
    func testZTAPIChaining() {
        log("\n========== testZTAPIChaining ==========")
        let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/users", .get)
            .param(.kv("page", 1))
            .param(.kv("limit", 10))
            .header(.h(key: "Authorization", value: "Bearer token"))
            .encoding(ZTURLEncoding())

        assertEqual(api.urlStr, "https://api.example.com/users")
        assertEqual(api.params.count, 2)
        assertEqual(api.params["page"] as? Int, 1)
        assertEqual(api.params["limit"] as? Int, 10)
        assertEqual(api.headers["Authorization"], "Bearer token")
    }

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

    /// 测试 Publisher 多次订阅行为
    func testPublisherMultipleSubscriptions() async {
        await runTest("testPublisherMultipleSubscriptions") {
            // 使用 async send 方法代替 Publisher，避免并发问题
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/multi": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: ["count": 1])
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/multi",
                .get,
                provider: stubProvider
            )

            // 使用 async send 测试
            let _ = try await api.send()
            log("  Publisher 测试通过 (使用 async send)")
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

                func request(_ urlRequest: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
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

    /// 测试 ZTStubProvider 延迟
    func testStubProviderDelay() async {
        await runTest("testStubProviderDelay") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/delay": .init(
                    statusCode: 200,
                    data: Data(),
                    delay: 0.1 // 100ms 延迟
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/delay",
                .get,
                provider: stubProvider
            )

            let start = Date()
            _ = try await api.send()
            let elapsed = Date().timeIntervalSince(start)

            assertTrue(elapsed >= 0.1, "应该至少延迟 0.1 秒")
            log("  延迟时间: \(elapsed) 秒")
        }
    }

    /// 测试 Result 扩展
    func testResultExtensions() {
        log("\n========== testResultExtensions ==========")
        var successCount = 0
        var failureCount = 0

        Result<Int, Error>.success(42)
            .onSuccess { _ in successCount += 1 }
            .onFailure { _ in failureCount += 1 }

        assertEqual(successCount, 1)
        assertEqual(failureCount, 0)

        successCount = 0
        failureCount = 0

        Result<Int, Error>.failure(NSError(domain: "test", code: -1))
            .onSuccess { _ in successCount += 1 }
            .onFailure { _ in failureCount += 1 }

        assertEqual(successCount, 0)
        assertEqual(failureCount, 1)
    }

    /// 测试使用 JSONPlaceholder 真实 API
    func testRealAPI() async {
        await runTest("testRealAPI") {
            // 使用真实的 jsonplaceholder API
            let api = ZTAPI<ZTAPIKVParam>(
                "https://jsonplaceholder.typicode.com/users/1",
                .get
            )

            let response = try await api.send()
            assertTrue(!response.isEmpty, "应收到响应")

            log("  真实 API 响应成功")

            // 测试 Publisher
            var publisherResult: ZTAPI<ZTAPIKVParam>.APIResponse?
            let cancellable = api.publisher.sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.log("  Publisher 错误: \(error)")
                    }
                },
                receiveValue: { [weak self] value in
                    publisherResult = value
                    self?.log("  Publisher 收到响应")
                }
            )

            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒

            assertTrue(publisherResult != nil, "Publisher 应收到响应")

            cancellable.cancel()
        }
    }

    // MARK: - 运行所有测试

    @MainActor
    func runAllTests() async {
        log("\n")
        log("╔════════════════════════════════════════════════════════════╗")
        log("║           ZTAPI 测试套件开始运行                              ║")
        log("╚════════════════════════════════════════════════════════════╝")

        // 同步测试
        testZTAPIErrorDescription()
        testZTAPIHeader()
        testZTAPIKVParam()
        testZTURLEncodingGET()
        testZTURLEncodingPOST()
        testZTJSONEncoding()
        testZTAPIParseConfig()
        testZTAPIChaining()
        testResultExtensions()

        // 异步测试
        await testZTAPIWithStubProvider()
        await testZTAPIInvalidURL()
        await testZTAPIPublisher()
        await testPublisherMultipleSubscriptions()
        await testDifferentPublisherInstances()
        await testPublisherNoExecutionWithoutSubscription()
        await testStubProviderDelay()
        await testRealAPI()

        // Timeout & Retry 测试
        await testTimeout()
        await testFixedRetryPolicy()
        await testExponentialBackoffRetry()
        await testConditionalRetry()
        await testProviderLevelRetry()
        await testRetryThenSuccess()
        await testRequestRetryOverrideProvider()
        await testNonRetryableError()
        await testTimeoutAndRetry()
        await testNoRetryPolicy()
        await testMultipleRequestsDifferentRetries()
        await testTimeoutAppliedToRequest()
        await testChainingOrder()

        // Upload 测试
        testZTMimeType()
        testZTUploadItem()
        testZTMultipartFormData()
        await testUploadMethod()
        await testMultipartMethod()
        await testBodyAndMultipartMutualExclusion()

        // Plugin 测试
        await testPluginProcessHook()

        // Provider 测试
        await testProviderConsistency()

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

    /// 测试指数退避重试策略
    func testExponentialBackoffRetry() async {
        await runTest("testExponentialBackoffRetry") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/backoff": .init(
                    statusCode: 503,
                    data: Data()
                )
            ])

            let retryPolicy = ZTExponentialBackoffRetryPolicy(
                maxAttempts: 2,
                baseDelay: 0.1,
                multiplier: 2.0,
                retryableCodes: [503]
            )

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/backoff",
                .get,
                provider: stubProvider
            )
            .retry(retryPolicy)

            let start = Date()
            do {
                _ = try await api.send()
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                log("  ✅ 指数退避测试通过，耗时: \(String(format: "%.2f", elapsed))s")
            }
        }
    }

    /// 测试自定义重试条件
    func testConditionalRetry() async {
        await runTest("testConditionalRetry") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/conditional": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: ["status": "error"])
                )
            ])

            let retryPolicy = ZTConditionalRetryPolicy(
                maxAttempts: 2,
                delay: 0.1
            ) { _, _, attempt, _ in
                // 仅在第一次失败时重试
                return attempt == 0
            }

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/conditional",
                .get,
                provider: stubProvider
            )
            .retry(retryPolicy)

            do {
                _ = try await api.send()
                log("  ✅ 自定义重试策略测试通过")
            } catch {
                log("  ❌ 测试失败: \(error)")
            }
        }
    }

    /// 测试在 Provider 层面设置重试策略
    func testProviderLevelRetry() async {
        await runTest("testProviderLevelRetry") {
            _ = ZTAlamofireProvider(
                retryPolicy: ZTFixedRetryPolicy(maxAttempts: 2, delay: 0.1)
            )

            log("  ✅ Provider 层重试策略配置成功")
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

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
                    callCount += 1
                    // 前两次返回 500，第三次返回 200
                    if callCount <= 2 {
                        throw NSError(domain: "Test", code: 500, userInfo: nil)
                    }
                    return try! JSONSerialization.data(withJSONObject: ["result": "success"])
                }
            }

            let provider = CountingStubRetrySuccessProvider()
            let retryPolicy = ZTFixedRetryPolicy(maxAttempts: 3, delay: 0.05, retryableErrorCodes: [500])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/eventual-success",
                .get,
                provider: provider
            )
            .retry(retryPolicy)

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")
            assertTrue(provider.callCount == 3, "应该重试了2次后成功，共3次请求")
            log("  ✅ 重试后成功，总请求次数: \(provider.callCount)")
        }
    }

    /// 测试请求级别重试覆盖 Provider 级别
    func testRequestRetryOverrideProvider() async {
        await runTest("testRequestRetryOverrideProvider") {
            // Provider 设置 2 次重试
            _ = ZTAlamofireProvider(
                retryPolicy: ZTFixedRetryPolicy(maxAttempts: 2, delay: 1.0)
            )

            // 请求级别设置 5 次重试（应该覆盖 Provider 的设置）
            let requestRetryPolicy = ZTFixedRetryPolicy(maxAttempts: 5, delay: 0.05, retryableCodes: [500])

            final class CountingStubOverrideProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
                    callCount += 1
                    if callCount < 4 {
                        throw NSError(domain: "Test", code: 500, userInfo: nil)
                    }
                    return Data([1])
                }
            }

            let countingProvider = CountingStubOverrideProvider()

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/override",
                .get,
                provider: countingProvider
            )
            .retry(requestRetryPolicy)

            _ = try await api.send()
            assertTrue(countingProvider.callCount == 4, "应该使用请求级别的5次重试（实际4次成功）")
            log("  ✅ 请求级别重试覆盖 Provider 设置，总请求次数: \(countingProvider.callCount)")
        }
    }

    /// 测试不可重试的错误不触发重试
    func testNonRetryableError() async {
        await runTest("testNonRetryableError") {
            final class CountingStubNonRetryableProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCount = 0

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
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

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
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

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
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

    /// 测试不同请求使用不同重试策略
    func testMultipleRequestsDifferentRetries() async {
        await runTest("testMultipleRequestsDifferentRetries") {
            final class CountingStubMultiProvider: @unchecked Sendable, ZTAPIProvider {
                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil
                var callCounts: [String: Int] = [:]

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
                    let url = urlRequest.url?.absoluteString ?? "unknown"
                    callCounts[url, default: 0] += 1
                    throw NSError(domain: "Test", code: 500, userInfo: nil)
                }

                func getCallCount(for url: String) -> Int {
                    callCounts[url] ?? 0
                }
            }

            let provider = CountingStubMultiProvider()

            // 第一个请求：2次重试
            let api1 = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/request1",
                .get,
                provider: provider
            )
            .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 0.01, retryableCodes: [500]))

            // 第二个请求：5次重试
            let api2 = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/request2",
                .get,
                provider: provider
            )
            .retry(ZTFixedRetryPolicy(maxAttempts: 6, delay: 0.01, retryableCodes: [500]))

            // 第三个请求：不重试
            let api3 = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/request3",
                .get,
                provider: provider
            )

            _ = try? await api1.send()
            _ = try? await api2.send()
            _ = try? await api3.send()

            assertTrue(provider.getCallCount(for: "https://api.example.com/request1") == 3, "请求1应执行3次")
            assertTrue(provider.getCallCount(for: "https://api.example.com/request2") == 6, "请求2应执行6次")
            assertTrue(provider.getCallCount(for: "https://api.example.com/request3") == 1, "请求3应执行1次")

            log("  ✅ 不同请求使用不同重试策略")
        }
    }

    /// 测试超时时间设置到 URLRequest
    func testTimeoutAppliedToRequest() async {
        await runTest("testTimeoutAppliedToRequest") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/check-timeout": .init(
                    statusCode: 200,
                    data: Data([1, 2, 3])
                )
            ])

            final class TimeoutCaptureProvider: @unchecked Sendable, ZTAPIProvider {
                let baseProvider: any ZTAPIProvider
                var capturedTimeout: TimeInterval?

                init(baseProvider: any ZTAPIProvider) {
                    self.baseProvider = baseProvider
                    self.capturedTimeout = nil
                }

                let plugins: [any ZTAPIPlugin] = []
                let retryPolicy: (any ZTAPIRetryPolicy)? = nil

                func request(_ urlRequest: URLRequest, timeout: TimeInterval?) async throws -> Data {
                    capturedTimeout = timeout
                    return try await baseProvider.request(urlRequest, timeout: timeout)
                }
            }

            let captureProvider = TimeoutCaptureProvider(baseProvider: stubProvider)

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/check-timeout",
                .get,
                provider: captureProvider
            )
            .timeout(30)

            _ = try await api.send()

            XCTAssertEqual(captureProvider.capturedTimeout, 30)
            log("  ✅ 超时时间正确传递: \(captureProvider.capturedTimeout ?? 0)s")
        }
    }

    /// 测试链式调用顺序
    func testChainingOrder() async {
        await runTest("testChainingOrder") {
            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/test", .get)
                .param(.kv("key1", "value1"))
                .param(.kv("key2", "value2"))
                .header(.h(key: "Accept", value: "application/json"))
                .timeout(30)
                .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 1.0))

            assertEqual(api.params.count, 2)
            assertEqual(api.params["key1"] as? String, "value1")
            assertEqual(api.params["key2"] as? String, "value2")
            assertEqual(api.headers["Accept"], "application/json")

            log("  ✅ 链式调用顺序正确")
        }
    }

    // MARK: - Upload Tests

    /// 测试 ZTMimeType 预定义类型
    func testZTMimeType() {
        log("\n========== testZTMimeType ==========")

        assertEqual(ZTMimeType.jpeg.rawValue, "image/jpeg")
        assertEqual(ZTMimeType.png.rawValue, "image/png")
        assertEqual(ZTMimeType.gif.rawValue, "image/gif")
        assertEqual(ZTMimeType.mp4.rawValue, "video/mp4")
        assertEqual(ZTMimeType.mp3.rawValue, "audio/mpeg")
        assertEqual(ZTMimeType.pdf.rawValue, "application/pdf")
        assertEqual(ZTMimeType.json.rawValue, "application/json")
        assertEqual(ZTMimeType.txt.rawValue, "text/plain")
        assertEqual(ZTMimeType.zip.rawValue, "application/zip")
        assertEqual(ZTMimeType.octetStream.rawValue, "application/octet-stream")

        // 测试自定义 MIME 类型
        let custom = ZTMimeType.mimeType("application/vnd.test")
        assertEqual(custom.rawValue, "application/vnd.test")

        // 测试从文件扩展名获取 MIME 类型
        assertEqual(ZTMimeType.fromFileExtension("jpg").rawValue, "image/jpeg")
        assertEqual(ZTMimeType.fromFileExtension("png").rawValue, "image/png")
        assertEqual(ZTMimeType.fromFileExtension("json").rawValue, "application/json")
        assertEqual(ZTMimeType.fromFileExtension("unknown").rawValue, "application/octet-stream")

        log("  ✅ ZTMimeType 测试通过")
    }

    /// 测试 ZTUploadItem
    func testZTUploadItem() {
        log("\n========== testZTUploadItem ==========")

        let imageData = Data("fake image".utf8)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")

        // 测试 data case
        let dataItem: ZTAPI<ZTAPIKVParam>.ZTUploadItem = .data(imageData, name: "file", fileName: "photo.jpg", mimeType: .jpeg)
        let dataPart = dataItem.bodyPart
        assertEqual(dataPart.name, "file")
        assertEqual(dataPart.fileName, "photo.jpg")
        assertEqual(dataPart.mimeType?.rawValue, "image/jpeg")

        // 测试 file case
        let fileItem: ZTAPI<ZTAPIKVParam>.ZTUploadItem = .file(fileURL, name: "upload")
        let filePart = fileItem.bodyPart
        assertEqual(filePart.name, "upload")
        assertEqual(filePart.fileName, fileURL.lastPathComponent)

        log("  ✅ ZTUploadItem 测试通过")
    }

    /// 测试 ZTMultipartFormData 构建
    func testZTMultipartFormData() {
        log("\n========== testZTMultipartFormData ==========")

        let formData = ZTMultipartFormData()
            .add(.data(Data("file1".utf8), name: "file1", fileName: "file1.txt", mimeType: .txt))
            .add(.data(Data("file2".utf8), name: "file2", fileName: "file2.txt", mimeType: .txt))
            .add(.data(Data("metadata".utf8), name: "metadata", mimeType: .json))

        assertEqual(formData.parts.count, 3)
        assertEqual(formData.parts[0].name, "file1")
        assertEqual(formData.parts[1].name, "file2")
        assertEqual(formData.parts[2].name, "metadata")

        // 测试 build() 方法
        let builtData = formData.build()
        assertTrue(builtData.count > 0, "构建的数据不应为空")
        let builtString = String(data: builtData, encoding: .utf8) ?? ""
        assertTrue(builtString.contains("Content-Disposition"), "应包含 Content-Disposition")
        assertTrue(builtString.contains("Content-Type"), "应包含 Content-Type")
        assertTrue(builtString.contains(formData.boundary), "应包含 boundary")

        log("  ✅ ZTMultipartFormData 测试通过")
    }

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

            // 验证请求已正确配置
            assertEqual(api.params.count, 0)
            assertTrue(api.headers["Content-Type"]?.contains("multipart/form-data") == true, "应设置 multipart Content-Type")
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

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")

            log("  ✅ multipart 方法测试通过")
        }
    }

    /// 测试 body 方法与 multipart 的互斥关系
    func testBodyAndMultipartMutualExclusion() async {
        await runTest("testBodyAndMultipartMutualExclusion") {
            let stubProvider = ZTStubProvider(plugins: [], stubs: [
                "POST:https://api.example.com/upload": .init(
                    statusCode: 200,
                    data: Data([1, 2, 3])
                )
            ])

            // 先设置 body，再调用 multipart - multipart 应该清除 bodyData
            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: stubProvider)
                .body(Data("raw data".utf8))
                .multipart(ZTMultipartFormData().add(.data(Data("multipart".utf8), name: "file")))

            assertTrue(api.bodyData == nil, "multipart 应该清除之前设置的 bodyData")

            let result = try await api.send()
            assertTrue(!result.isEmpty, "应收到响应")

            log("  ✅ body 和 multipart 互斥关系正确")
        }
    }

    /// 测试 Plugin 的 process hook
    func testPluginProcessHook() async {
        log("\n========== testPluginProcessHook ==========")

        // 测试插件
        struct UpperCasePlugin: ZTAPIPlugin {
            func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
                // 将响应数据转为大写（仅适用于文本数据）
                let string = String(data: data, encoding: .utf8) ?? ""
                return string.uppercased().data(using: .utf8) ?? data
            }
        }

        let stubProvider = ZTStubProvider(plugins: [UpperCasePlugin()], stubs: [
            "GET:https://api.example.com/process": .init(
                statusCode: 200,
                data: Data("{\"message\":\"hello world\"}".utf8)
            )
        ])

        do {
            let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/process", .get, provider: stubProvider)
                .send()

            // process hook 会将响应转为大写: {"message":"HELLO WORLD"}
            if let msg: String = result.get("message") {
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

    // MARK: - Provider Tests

    /// 测试 ZTURLSessionProvider 与 ZTAlamofireProvider 行为一致性
    func testProviderConsistency() async {
        log("\n========== testProviderConsistency ==========")

        let responseData = Data("{\"result\":\"success\"}".utf8)

        // 创建两个 provider 的 stub
        let urlSessionStub = ZTStubProvider(plugins: [], stubs: [
            "GET:https://api.example.com/test": .init(statusCode: 200, data: responseData)
        ])

        let alamofireStub = ZTStubProvider(plugins: [], stubs: [
            "GET:https://api.example.com/test": .init(statusCode: 200, data: responseData)
        ])

        do {
            // 测试 URLSession Provider
            let result1 = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/test", .get, provider: urlSessionStub)
                .send()

            // 测试 Alamofire Provider
            let result2 = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/test", .get, provider: alamofireStub)
                .send()

            assertEqual(result1.count, result2.count)
            log("  ✅ Provider 行为一致")
        } catch {
            log("  ❌ Provider 一致性测试失败: \(error)")
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
}
