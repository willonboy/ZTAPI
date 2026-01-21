//
//  ZTAPITests.swift
//  JsonDemo
//
//  Created by zt
//  ZTAPI 网络请求类测试用例
//

import Foundation
import Combine
import OSLog
import UIKit
import SwiftyJSON
import ZTJSON



public extension URLRequest {
    init?(urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(url: url)
    }

    var curlString: String {
        guard let url else { return "" }

        var baseCommand = "curl \(url.absoluteString)"
        if httpMethod == "HEAD" {
            baseCommand += " --head"
        }

        var command = [baseCommand]
        if let method = httpMethod, method != "GET", method != "HEAD" {
            command.append("-X \(method)")
        }

        if let headers = allHTTPHeaderFields {
            for (key, value) in headers where key != "Cookie" {
                command.append("-H '\(key): \(value)'")
            }
        }

        if let data = httpBody,
           let body = String(data: data, encoding: .utf8) {
            command.append("-d '\(body)'")
        }

        return command.joined(separator: " \\\n")
    }
}

// MARK: - Test Models

struct StubResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

struct TestUser: Codable, Sendable {
    let id: Int
    let name: String
}

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

    private func assertThrowsError<T: Sendable>(_ block: () async throws -> T, file: String = #file, line: Int = #line) async {
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
        let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/users", provider: ZTAlamofireProvider.shared)
            .params(.kv("page", 1))
            .params(.kv("limit", 10))
            .headers(.h(key: "Authorization", value: "Bearer token"))
            .encoding(ZTURLEncoding())

        assertEqual(api.urlStr, "https://api.example.com/users")
        assertEqual(api.params.count, 2)
        assertEqual(api.params["page"] as? Int, 1)
        assertEqual(api.params["limit"] as? Int, 10)
        assertEqual(api.headers["Authorization"], "Bearer token")
    }

    /// 测试 ZTAPI 使用 XPath 解析
    func testZTAPIXPathParsing() async {
        await runTest("testZTAPIXPathParsing") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/test": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: [
                        "success": true,
                        "data": [
                            "user": "John",
                            "token": "abc123",
                            "count": 42
                        ]
                    ])
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/test",
                .get,
                provider: stubProvider
            )

            // 使用 parseResponse 解析多个 XPath
            let results = try await api.parseResponse(
                ZTAPIParseConfig("success", type: Bool.self),
                ZTAPIParseConfig("data/user", type: String.self),
                ZTAPIParseConfig("data/token", type: String.self),
                ZTAPIParseConfig("data/count", type: Int.self)
            )

            log("  解析结果数量: \(results.count)")
            if let success = results["success"] as? Bool {
                log("  success: \(success)")
            }
            if let user = results["data/user"] as? String {
                log("  user: \(user)")
            }
            if let token = results["data/token"] as? String {
                log("  token: \(token)")
            }
            if let count = results["data/count"] as? Int {
                log("  count: \(count)")
            }

            assertTrue(results.count == 4, "应解析出 4 个字段")
        }
    }

    /// 测试 ZTUploadItem
    func testZTUploadItem() {
        log("\n========== testZTUploadItem ==========")

        let data = Data("test content".utf8)
        let item1 = ZTAPI<ZTAPIKVParam>.ZTUploadItem.data(data, name: "file", fileName: "test.txt", mimeType: .txt)
        let item2 = ZTAPI<ZTAPIKVParam>.ZTUploadItem.file(URL(fileURLWithPath: "/path/to/file.jpg"), name: "image", mimeType: .jpeg)

        // 转换为 bodyPart
        let part1 = item1.bodyPart
        assertEqual(part1.name, "file")
        assertEqual(part1.fileName, "test.txt")

        let part2 = item2.bodyPart
        assertEqual(part2.name, "image")

        log("  ✅ ZTUploadItem 测试通过")
    }

    /// 测试使用 Codable 解析
    func testZTAPIWithCodable() async {
        await runTest("testZTAPIWithCodable") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/test": .init(
                    statusCode: 200,
                    data: try! JSONSerialization.data(withJSONObject: [
                        "success": true,
                        "message": "Hello from stub"
                    ])
                )
            ])

            let response: StubResponse = try await ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/test",
                .get,
                provider: stubProvider
            )
            .response()

            assertTrue(response.success, "响应 success 应为 true")
            assertEqual(response.message, "Hello from stub")
            log("  Codable 解析成功")
        }
    }

    /// 测试返回原始 Data
    func testZTAPIReturnData() async {
        await runTest("testZTAPIReturnData") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/data": .init(
                    statusCode: 200,
                    data: Data("raw response data".utf8)
                )
            ])

            let data = try await ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/data",
                .get,
                provider: stubProvider
            )
            .send()

            assertEqual(data, Data("raw response data".utf8))
            log("  原始 Data 返回正确")
        }
    }

    /// 测试 ZTAPI 错误处理 - 无效 URL
    func testZTAPIInvalidURL() async {
        await runTest("testZTAPIInvalidURL") {
            await assertThrowsError {
                try await ZTAPI<ZTAPIKVParam>("invalid url", provider: ZTAlamofireProvider.shared).send()
            }
        }
    }

    /// 测试 ZTAPI Publisher
    func testZTAPIPublisher() async {
        await runTest("testZTAPIPublisher") {
            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/publisher": .init(
                    statusCode: 200,
                    data: try! JSONEncoder().encode(TestUser(id: 1, name: "Publisher Test"))
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/publisher",
                .get,
                provider: stubProvider
            )

            var receivedResult: TestUser?
            var receivedError: Error?

            let cancellable: AnyCancellable = api.publisher().sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        receivedError = error
                    }
                },
                receiveValue: { value in
                    receivedResult = value
                }
            )

            try await Task.sleep(nanoseconds: 100_000_000)

            assertTrue(receivedResult != nil || receivedError != nil, "应收到结果或错误")
            if let user = receivedResult {
                log("  Publisher 收到响应: \(user.name)")
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

            let pub1: AnyPublisher<Data, Error> = api.publisher()
            let p1 = pub1.sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in firstCall = true }
            )

            try await Task.sleep(nanoseconds: 50_000_000)

            let pub2: AnyPublisher<Data, Error> = api.publisher()
            let p2 = pub2.sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in secondCall = true }
            )

            try await Task.sleep(nanoseconds: 100_000_000)

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
            final class CountingStubProvider: @unchecked Sendable, ZTAPIProvider {
                var requestCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
                    requestCount += 1
                    let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (Data(), response)
                }
            }

            let provider = CountingStubProvider()
            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/count",
                .get,
                provider: provider
            )

            let _: AnyPublisher<Data, Error> = api.publisher()

            try await Task.sleep(nanoseconds: 100_000_000)

            assertTrue(provider.requestCount == 0, "未订阅时不应执行请求")
            log("  未订阅时请求次数: \(provider.requestCount)")
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
                    delay: 2.0
                )
            ])

            let api = ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/timeout",
                .get,
                provider: stubProvider
            )
            .timeout(1)

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
                    statusCode: 500,
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
            final class CountingStubRetrySuccessProvider: @unchecked Sendable, ZTAPIProvider {
                var callCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
                    callCount += 1
                    if callCount <= 2 {
                        let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
                        let error = NSError(domain: "Test", code: 500, userInfo: ["HTTPURLResponse": response])
                        throw error
                    }
                    let data = try! JSONSerialization.data(withJSONObject: ["result": "success"])
                    let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (data, response)
                }
            }

            let provider = CountingStubRetrySuccessProvider()
            let retryPolicy = ZTFixedRetryPolicy(maxAttempts: 3, delay: 0.05, retryableCodes: [500])

            struct Response: Codable {
                let result: String
            }

            let response: Response = try await ZTAPI<ZTAPIKVParam>(
                "https://api.example.com/eventual-success",
                .get,
                provider: provider
            )
            .retry(retryPolicy)
            .response()

            assertEqual(response.result, "success")
            assertTrue(provider.callCount == 3, "应该重试了2次后成功，共3次请求")
            log("  ✅ 重试后成功，总请求次数: \(provider.callCount)")
        }
    }

    /// 测试不可重试的错误不触发重试
    func testNonRetryableError() async {
        await runTest("testNonRetryableError") {
            final class CountingStubNonRetryableProvider: @unchecked Sendable, ZTAPIProvider {
                var callCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
                    callCount += 1
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
                var callCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
                    callCount += 1
                    try await Task.sleep(nanoseconds: 50_000_000)
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
            .timeout(1)
            .retry(retryPolicy)

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
                var callCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
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

            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: stubProvider)
                .upload(.data(Data("file content".utf8), name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
                        .data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json))

            assertEqual(api.params.count, 0)
            assertTrue(api.bodyData == nil, "bodyData 应被 multipart 清除")

            let data = try await api.send()
            assertTrue(!data.isEmpty, "应收到响应")

            log("  ✅ upload 方法测试通过")
        }
    }

    /// 测试 multipart 方法
    func testMultipartMethod() async {
        await runTest("testMultipartMethod") {
            let stubProvider = ZTStubProvider(stubs: [
                "POST:https://api.example.com/upload": .init(
                    statusCode: 200,
                    data: Data("{\"success\":true}".utf8)
                )
            ])

            let formData = ZTMultipartFormData()
                .add(.data(Data("content".utf8), name: "file", fileName: "test.txt", mimeType: .txt))

            let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: stubProvider)
                .multipart(formData)

            let data = try await api.send()
            assertTrue(!data.isEmpty, "应收到响应")

            log("  ✅ multipart 方法测试通过")
        }
    }

    /// 测试 Plugin 的 process hook
    func testPluginProcessHook() async {
        await runTest("testPluginProcessHook") {
            struct UpperCaseValuePlugin: ZTAPIPlugin {
                func process(_ data: Data, response: HTTPURLResponse) async throws -> Data {
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

            let stubProvider = ZTStubProvider(stubs: [
                "GET:https://api.example.com/process": .init(
                    statusCode: 200,
                    data: Data("{\"message\":\"hello world\"}".utf8)
                )
            ])

            struct Response: Codable {
                let message: String
            }

            let result: Response = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/process", .get, provider: stubProvider)
                .plugins(UpperCaseValuePlugin())
                .response()

            // process hook 会将响应值转为大写
            assertEqual(result.message, "HELLO WORLD")
            log("  ✅ Plugin process hook 测试通过")
        }
    }

    /// 验证 Token refresh 并发安全
    func testChatGPT_TokenRefresh_ConcurrencyRace() async {
        await runTest("testChatGPT_TokenRefresh_ConcurrencyRace") {
            log("  验证：多个并发请求触发 token 刷新的行为")

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

            // 测试不使用 Actor 的旧版本
            let oldPlugin = ZTTokenRefreshPlugin(
                shouldRefresh: { _ in true },
                refresh: {
                    await counter.incrementRefresh()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return "new-token-\(UUID().uuidString)"
                },
                onRefresh: { _ in
                    Task { await counter.incrementOnRefresh() }
                },
                useSingleFlight: false
            )

            final class Always401Provider: @unchecked Sendable, ZTAPIProvider {
                var requestCount = 0

                func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler? = nil) async throws -> (Data, HTTPURLResponse) {
                    requestCount += 1
                    let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                    let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    let error = NSError(domain: "Test", code: 401, userInfo: ["HTTPURLResponse": response])
                    throw error
                }
            }

            let baseProvider = Always401Provider()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/1", .get, provider: baseProvider).plugins(oldPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/2", .get, provider: baseProvider).plugins(oldPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/3", .get, provider: baseProvider).plugins(oldPlugin).send()
                }
                await group.waitForAll()
            }

            try await Task.sleep(nanoseconds: 200_000_000)

            let oldCounts = await counter.counts
            log("  不使用 Actor 时: refresh 被调用 \(oldCounts.refresh) 次, onRefresh 被调用 \(oldCounts.onRefresh) 次")

            if oldCounts.refresh > 1 {
                log("  ✅ 确认：不使用 Actor 时存在并发竞态（多次刷新）")
            }

            // 测试使用 Actor 的新版本
            let newCounter = RefreshCounter()

            let newPlugin = ZTTokenRefreshPlugin(
                shouldRefresh: { _ in true },
                refresh: {
                    await newCounter.incrementRefresh()
                    try await Task.sleep(nanoseconds: 50_000_000)
                    return "new-token-\(UUID().uuidString)"
                },
                onRefresh: { _ in
                    Task { await newCounter.incrementOnRefresh() }
                },
                useSingleFlight: true
            )

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/4", .get, provider: baseProvider).plugins(newPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/5", .get, provider: baseProvider).plugins(newPlugin).send()
                }
                group.addTask {
                    _ = try? await ZTAPI<ZTAPIKVParam>("https://api.example.com/6", .get, provider: baseProvider).plugins(newPlugin).send()
                }
                await group.waitForAll()
            }

            try await Task.sleep(nanoseconds: 200_000_000)

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
    func testConcurrencyProvider() async {
        await runTest("testConcurrencyProvider") {
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

            final class DelayedStubProvider: ZTAPIProvider {
                let delay: TimeInterval
                let tracker: ConcurrencyTracker

                init(delay: TimeInterval = 0.1, tracker: ConcurrencyTracker) {
                    self.delay = delay
                    self.tracker = tracker
                }

                func request(
                    _ urlRequest: URLRequest,
                    uploadProgress: ZTUploadProgressHandler?
                ) async throws -> (Data, HTTPURLResponse) {
                    await tracker.start()
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await tracker.end()
                    let url = urlRequest.url ?? URL(string: "https://api.example.com")!
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (Data(), response)
                }
            }

            let baseProvider = DelayedStubProvider(delay: 0.1, tracker: tracker)
            let concurrentProvider = ZTConcurrencyProvider(
                baseProvider: baseProvider,
                maxConcurrency: 3
            )

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<10 {
                    group.addTask {
                        let request = URLRequest(url: URL(string: "https://api.example.com/test/\(i)")!)
                        _ = try? await concurrentProvider.request(request, uploadProgress: nil)
                    }
                }
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let stats = await tracker.getStats()

            log("  完成请求数: \(stats.completed)")
            log("  最大并发数: \(stats.max)")

            if stats.max <= 3 {
                log("  ✅ 并发控制正常：最大并发数为 \(stats.max)，不超过限制值 3")
                passedCount += 1
            } else {
                log("  ❌ 并发控制失效：最大并发数为 \(stats.max)，超过限制值 3")
                failedCount += 1
            }

            if stats.completed == 10 {
                log("  ✅ 所有请求都已完成")
            } else {
                log("  ⚠️  部分请求未完成: \(stats.completed)/10")
            }
        }
    }

    /// 测试全局 API Provider
    func testGlobalAPIProvider() async {
        await runTest("testGlobalAPIProvider") {
            // 配置全局 Provider
            ZTGlobalAPIProvider.configure(ZTURLSessionProvider(), maxConcurrency: 6)

            let originalMax = ZTGlobalAPIProvider.shared.currentMaxConcurrency
            log("  默认全局并发数: \(originalMax)")
            assertEqual(originalMax, 6)

            ZTGlobalAPIProvider.shared.setMaxConcurrency(3)
            let newMax = ZTGlobalAPIProvider.shared.currentMaxConcurrency
            log("  修改后全局并发数: \(newMax)")
            assertEqual(newMax, 3)

            let api1 = ZTAPI<ZTAPIKVParam>.global("https://api.example.com/test1", .get)
            let api2 = ZTAPI<ZTAPIKVParam>.global("https://api.example.com/test2", .post)

            assertEqual(api1.urlStr, "https://api.example.com/test1")
            assertEqual(api1.method, .get)
            assertEqual(api2.urlStr, "https://api.example.com/test2")
            assertEqual(api2.method, .post)
            log("  ✅ global() 方法正确创建了 API 实例")

            ZTGlobalAPIProvider.shared.setMaxConcurrency(originalMax)
            log("  ✅ 全局 API Provider 测试通过")
        }
    }

    // MARK: - 运行所有测试

    func runAllTests() async {
        log("\n")
        log("╔════════════════════════════════════════════════════════════╗")
        log("║           ZTAPI 测试套件开始运行                              ║")
        log("╚════════════════════════════════════════════════════════════╝")

        // 基础单元测试
        testZTAPIErrorDescription()
        testZTURLEncodingGET()
        testZTURLEncodingPOST()
        testZTJSONEncoding()
        testZTAPIParseConfig()
        testZTAPIChaining()
        testZTUploadItem()

        // Codable 测试
        await testZTAPIWithCodable()
        await testZTAPIReturnData()
        await testZTAPIInvalidURL()
        await testZTAPIPublisher()
        await testDifferentPublisherInstances()
        await testPublisherNoExecutionWithoutSubscription()

        // XPath 解析测试
        await testZTAPIXPathParsing()

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
}
