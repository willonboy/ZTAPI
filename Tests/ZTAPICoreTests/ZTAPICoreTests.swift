import XCTest
@testable import ZTAPICore

private final class AlwaysFailProvider: @unchecked Sendable, ZTAPIProvider {
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let url = urlRequest.url ?? URL(string: "https://api.example.com/fallback")!
        let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
        throw ZTAPIError(500, "always fail", httpResponse: response)
    }
}

private struct InfiniteDelayRetryPolicy: ZTAPIRetryPolicy {
    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        attempt == 1
    }

    func delay(for attempt: Int) async -> TimeInterval {
        .infinity
    }
}

private actor FailOnceProvider: ZTAPIProvider {
    private var attempts = 0

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        attempts += 1
        let url = urlRequest.url ?? URL(string: "https://api.example.com/fallback")!
        if attempts == 1 {
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
            throw ZTAPIError(503, "temporary failure", httpResponse: response)
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("ok".utf8), response)
    }

    func getAttempts() -> Int { attempts }
}

private struct NegativeDelayRetryPolicy: ZTAPIRetryPolicy {
    func shouldRetry(
        request: URLRequest,
        error: Error,
        attempt: Int,
        response: HTTPURLResponse?
    ) async -> Bool {
        attempt == 1
    }

    func delay(for attempt: Int) async -> TimeInterval {
        -1
    }
}

private actor BlockingProvider: ZTAPIProvider {
    private var attempts = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        attempts += 1
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        let url = urlRequest.url ?? URL(string: "https://api.example.com/fallback")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("ok".utf8), response)
    }

    func getAttempts() -> Int { attempts }

    func waitUntilAttempts(_ expected: Int, timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while attempts < expected {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                return attempts >= expected
            }
            await Task.yield()
        }
        return true
    }

    func unblockAll() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct ImmediateSuccessProvider: ZTAPIProvider {
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let url = urlRequest.url ?? URL(string: "https://api.example.com/fallback")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), response)
    }
}

final class ZTAPICoreTests: XCTestCase {
    func testRetryPolicyInvalidDelayThrows() async {
        let api = ZTAPI<ZTAPIKVParam>(
            "https://api.example.com/retry-invalid-delay",
            .get,
            provider: AlwaysFailProvider()
        )
        .retry(InfiniteDelayRetryPolicy())

        do {
            _ = try await api.send()
            XCTFail("Expected invalid retry delay error")
        } catch let error as ZTAPIError {
            XCTAssertEqual(error.code, 80000007)
        } catch {
            XCTFail("Expected ZTAPIError, got: \(error)")
        }
    }

    func testRetryPolicyNegativeDelayRetriesSuccessfully() async throws {
        let provider = FailOnceProvider()
        let api = ZTAPI<ZTAPIKVParam>(
            "https://api.example.com/retry-negative-delay",
            .get,
            provider: provider
        )
        .retry(NegativeDelayRetryPolicy())

        let data = try await api.send()
        XCTAssertEqual(data, Data("ok".utf8))
        let attempts = await provider.getAttempts()
        XCTAssertEqual(attempts, 2)
    }

    func testConcurrencyProviderCancellationDoesNotStartCancelledRequest() async throws {
        let baseProvider = BlockingProvider()
        let provider = ZTConcurrencyProvider(baseProvider: baseProvider, maxConcurrency: 1)
        let request = URLRequest(url: URL(string: "https://api.example.com/concurrency-cancel")!)

        let firstTask = Task {
            try await provider.request(request, uploadProgress: nil)
        }

        let firstStarted = await baseProvider.waitUntilAttempts(1)
        XCTAssertTrue(firstStarted)

        let secondTask = Task {
            try await provider.request(request, uploadProgress: nil)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        secondTask.cancel()

        do {
            _ = try await secondTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got: \(error)")
        }

        let startedAttempts = await baseProvider.getAttempts()
        XCTAssertEqual(startedAttempts, 1)
        await baseProvider.unblockAll()
        _ = try await firstTask.value
    }

    func testConcurrencyProviderClampsZeroToOne() {
        let provider = ZTConcurrencyProvider(baseProvider: ImmediateSuccessProvider(), maxConcurrency: 0)
        XCTAssertEqual(provider.maxConcurrentOperationCount, 1)
    }
}
