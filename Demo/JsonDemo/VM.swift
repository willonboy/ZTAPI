//
//  VM.swift
//  JsonDemo
//
//  Created by zt on 2026/1/13.
//

import Foundation
#if canImport(ZTJSON)
import SwiftyJSON
import ZTJSON
#endif


#if !canImport(ZTJSON)
// MARK: - Models
//
/// 用户模型
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let username: String?
    let email: String?
    let phone: String?
    let website: String?
    let address: Address?
    let company: Company?

    private enum CodingKeys: String, CodingKey {
        case id, name, username, email, phone, website, address, company
    }
}

/// 地址模型
struct Address: Codable, Sendable {
    let street: String
    let suite: String
    let city: String
    let zipcode: String
    let geo: Geo?

    private enum CodingKeys: String, CodingKey {
        case street, suite, city, zipcode, geo
    }
}

/// 地理位置模型
struct Geo: Codable, Sendable {
    let lat: String
    let lng: String
}

/// 公司模型
struct Company: Codable, Sendable {
    let name: String
    let catchPhrase: String?
    let bs: String?
}
#endif

/// 登录响应
struct LoginResponse: Codable, Sendable {
    struct Data: Codable, Sendable {
        let token: String
    }
    let code: Int
    let data: Data?
    let msg: String?
}

/// 用户信息响应
struct UserInfoResponse: Codable, Sendable {
    struct Data: Codable, Sendable {
        let token: String
        let username: String
        let email: String
        let userId: String
    }
    let code: Int
    let data: Data?
    let msg: String?
}

/// 用户列表响应（标准 API 响应格式）
struct UserListResponse: Codable {
    let code: Int
    let data: [User]?
    let msg: String?
}

// MARK: - API Headers

@MainActor
extension ZTAPIHeader {
    static var contentType: ZTAPIHeader {
        .h(key: "Content-Type", value: "application/json")
    }
    static var auth: ZTAPIHeader {
        .h(key: "Authorization", value: "Bearer token")
    }
}

// MARK: - API

@MainActor
enum UserCenterAPI {
    static var baseUrl: String {
        "https://jsonplaceholder.typicode.com"
    }

    static func fullPath(_ path: String) -> String {
        baseUrl + path
    }

    /// 配置 Provider
    static var provider: any ZTAPIProvider {
        ZTURLSessionProvider()
    }

    static var stubProvider: any ZTAPIProvider {
        ZTStubProvider.jsonStubs([
            "GET:https://jsonplaceholder.typicode.com/users": [
                "code": 0,
                "data": [
                    ["id": 1, "name": "Leanne Graham", "username": "Bret", "email": "sincere@april.biz"],
                    ["id": 2, "name": "Ervin Howell", "username": "Antonette", "email": "shanna@melissa.tv"]
                ]
            ]
        ])
    }

#if canImport(ZTJSON)
    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)
        case password(String)
        case userId(String)
    }
#else
    enum UserAPIParam: ZTAPIParamProtocol {
        case userName(String)
        case password(String)
        case userId(String)

        var key: String {
            switch self {
            case .userName: return "user_name"
            case .password: return "password"
            case .userId: return "user_id"
            }
        }

        var value: Sendable {
            switch self {
            case .userName(let v): return v
            case .password(let v): return v
            case .userId(let v): return v
            }
        }

        static func isValid(_ params: [String: Sendable]) -> Bool {
            return true
        }
    }
#endif
    

    private static func makeApi<P: ZTAPIParamProtocol>(_ url: String, _ method: ZTHTTPMethod) -> ZTAPI<P> {
        ZTAPI<P>(url, method, provider: provider)
    }

    /// 登录
    static func login(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        makeApi(fullPath("/user/login"), .post)
            .params(.userName(userName))
            .params(.password(password))
    }

    /// 获取用户信息
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        makeApi(fullPath("/user/info"), .get)
            .params(.userId(userId))
    }

    /// 获取用户列表
    static var userList: ZTAPI<ZTAPIKVParam> {
        makeApi(fullPath("/users"), .get)
    }

    /// 获取单个用户
    static func user(id: Int) -> ZTAPI<ZTAPIKVParam> {
        makeApi(fullPath("/users/\(id)"), .get)
    }
}

// MARK: - ViewModel

@MainActor
class VM {
    var token: String = ""
    var userList: [User] = []
    var addressList: [Address] = []
    var firstAddr: Address? = nil

    // MARK: - 基础测试

    func testAPIDemo() {
        Task {
            do {
                // 直接返回 Codable 类型
                let user: User = try await ZTAPI<ZTAPIKVParam>(
                    "https://jsonplaceholder.typicode.com/users/1",
                    provider: ZTAlamofireProvider.shared
                )
                .params(.kv("user_name", "jack"))
                .headers(.contentType)
                .response()
                print("✅ Success: \(user.name)")
            } catch {
                print("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    func testWithURLSessionProvider() async {
        do {
            let user: User = try await ZTAPI<ZTAPIKVParam>(
                "https://jsonplaceholder.typicode.com/users/1",
                .get,
                provider: ZTURLSessionProvider.shared
            )
            .response()
            print("✅ URLSessionProvider 测试成功: \(user.name)")
        } catch {
            print("❌ URLSessionProvider 测试失败: \(error)")
        }
    }

    // MARK: - 文件上传测试

    func testUpload() async {
        // 示例1: 上传单个图片 Data
        do {
            let imageData = Data("fake image data".utf8)
            let data: Data = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
                .send()
            print("✅ 上传单个 Data 成功，响应: \(data.count) bytes")
        } catch {
            print("❌ 上传 Data 失败: \(error)")
        }

        // 示例2: 上传单个文件
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload.txt")
            try "test file content".write(to: fileURL, atomically: true, encoding: .utf8)
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.file(fileURL, name: "file", mimeType: .txt))
                .send()
            print("✅ 上传单个文件成功")
        } catch {
            print("❌ 上传文件失败: \(error)")
        }

        // 示例3: 上传多个项（Data + File 混合）
        do {
            let fileURL1 = FileManager.default.temporaryDirectory.appendingPathComponent("file1.jpg")
            let fileURL2 = FileManager.default.temporaryDirectory.appendingPathComponent("file2.jpg")
            try "fake image 1".write(to: fileURL1, atomically: true, encoding: .utf8)
            try "fake image 2".write(to: fileURL2, atomically: true, encoding: .utf8)

            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/multiple", .post, provider: ZTAlamofireProvider.shared)
                .upload(.data(Data("metadata".utf8), name: "metadata", mimeType: .json),
                        .file(fileURL1, name: "photos", mimeType: .jpeg),
                        .file(fileURL2, name: "photos", mimeType: .jpeg))
                .send()
            print("✅ 上传多个项成功（Data + File 混合）")
        } catch {
            print("❌ 上传多个项失败: \(error)")
        }

        // 示例4: 使用 Multipart 上传文件 + 表单字段
        do {
            let formData = ZTMultipartFormData()
                .add(.data(Data("file1".utf8), name: "files", fileName: "file1.txt", mimeType: .txt))
                .add(.data(Data("file2".utf8), name: "files", fileName: "file2.txt", mimeType: .txt))
                .add(.data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json))

            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/multipart", .post, provider: ZTAlamofireProvider.shared)
                .multipart(formData)
                .send()
            print("✅ Multipart 上传成功（文件 + 表单字段）")
        } catch {
            print("❌ Multipart 上传失败: \(error)")
        }

        // 示例5: 使用 body() 设置原始请求体
        do {
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/raw", .post, provider: ZTAlamofireProvider.shared)
                .body(Data("raw body data".utf8))
                .headers(.h(key: "Content-Type", value: ZTMimeType.octetStream.rawValue))
                .send()
            print("✅ 使用 body() 上传原始数据成功")
        } catch {
            print("❌ 使用 body() 上传失败: \(error)")
        }

        // 示例6: 使用自定义 MIME 类型
        do {
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.data(Data("custom data".utf8), name: "file", mimeType: .custom(ext:"", mime: "application/vnd.example")))
                .send()
            print("✅ 使用自定义 MIME 类型成功")
        } catch {
            print("❌ 使用自定义 MIME 类型失败: \(error)")
        }
    }

    // MARK: - Stub 测试

    func testWithStub() async {
        do {
            let response: UserListResponse = try await ZTAPI<ZTAPIKVParam>(
                UserCenterAPI.fullPath("/users"),
                .get,
                provider: UserCenterAPI.stubProvider
            )
            .response()
            print("✅ Stub test success: \(response.data?.count ?? 0) users")
        } catch {
            print("✅ Stub test err: \(error)")
        }
    }

    // MARK: - 业务流程

    func performLogin() async {
        // 1. 登录接口 - 使用 Codable 解析
        do {
            let response: LoginResponse = try await UserCenterAPI.login(userName: "jack", password: "123456").response()
            if let token = response.data?.token {
                self.token = token
                print("✅ 登录成功，Token: \(token)")
            }
        } catch {
            print("❌ 登录失败: \(error.localizedDescription)")
        }
    }

    func fetchUserInfo() async {
        do {
            let response: UserInfoResponse = try await UserCenterAPI.userInfo(userId: "1384264339").response()
            if let data = response.data {
                self.token = data.token
                print("✅ 用户名: \(data.username)")
                print("✅ 邮箱: \(data.email)")
            }
            print("✅ 获取用户信息成功")
        } catch {
            print("❌ 获取用户信息失败: \(error.localizedDescription)")
        }
    }

    func fetchUserList() async {
        do {
            // 方式1: 如果 API 直接返回数组
            let users: [User] = try await UserCenterAPI.userList.response()
            self.userList = users
            print("✅ 获取用户列表成功: \(users.count) 个用户")
            if let first = users.first {
                print("   第一个用户: \(first.name)")
            }
        } catch {
            print("❌ 获取用户列表失败: \(error.localizedDescription)")
        }
    }

    func fetchSingleUser() async {
        do {
            let user: User = try await UserCenterAPI.user(id: 1).response()
            print("✅ 获取单个用户成功: \(user.name)")
            if let address = user.address {
                print("   地址: \(address.city)")
            }
        } catch {
            print("❌ 获取单个用户失败: \(error.localizedDescription)")
        }
    }
}
