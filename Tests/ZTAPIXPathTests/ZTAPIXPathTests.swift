import XCTest
import ZTAPICore
import ZTAPIXPath

private struct StaticJSONProvider: ZTAPIProvider {
    let data: Data

    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse) {
        let url = urlRequest.url ?? URL(string: "https://api.example.com/fallback")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class ZTAPIXPathTests: XCTestCase {
    private func makeAPI(jsonObject: Any) throws -> ZTAPI<ZTAPIKVParam> {
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        return ZTAPI<ZTAPIKVParam>(
            "https://api.example.com/xpath",
            .get,
            provider: StaticJSONProvider(data: data)
        )
    }

    func testRequiredTypeMismatchThrowsXPathTypeMismatch() async throws {
        let api = try makeAPI(jsonObject: ["data": ["id": 123]])

        do {
            _ = try await api.parseResponse(
                ZTAPIParseConfig("data/id", type: String.self, false)
            )
            XCTFail("Expected type mismatch error")
        } catch let error as ZTAPIError {
            XCTAssertEqual(error.code, 80020002)
        } catch {
            XCTFail("Expected ZTAPIError, got: \(error)")
        }
    }

    func testOptionalTypeMismatchIsIgnored() async throws {
        let api = try makeAPI(jsonObject: ["data": ["id": 123]])
        let result = try await api.parseResponse(
            ZTAPIParseConfig("data/id", type: String.self, true)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRequiredMissingPathThrowsXPathParseFailed() async throws {
        let api = try makeAPI(jsonObject: ["data": ["id": 123]])

        do {
            _ = try await api.parseResponse(
                ZTAPIParseConfig("data/missing", type: String.self, false)
            )
            XCTFail("Expected missing path error")
        } catch let error as ZTAPIError {
            XCTAssertEqual(error.code, 80020001)
        } catch {
            XCTFail("Expected ZTAPIError, got: \(error)")
        }
    }
}
