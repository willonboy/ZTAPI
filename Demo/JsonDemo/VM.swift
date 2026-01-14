//
//  VM.swift
//  JsonDemo
//
//  Created by zt on 2025/3/29.
//

import Foundation
import SwiftyJSON
import ZTJSON


@MainActor
extension ZTAPIHeader {
    static var contentType:ZTAPIHeader = .h(key: "Content-Type", value: "application/json")
    static var auth:ZTAPIHeader = .h(key: "Authorization", value: "Bearer token")
}


@MainActor
enum UserCenterAPI {
    static var baseUrl: String {
        "https://jsonplaceholder.typicode.com"
    }

    static func fullPath(_ path: String) -> String {
        baseUrl + path
    }

    /// 配置 Provider（可注入 plugins）
    static var provider: any ZTAPIProvider {
        // 可在此切换 Provider 实现
        // ZTAlamofireProvider - 基于 Alamofire（功能更丰富）
        // ZTURLSessionProvider - 基于 URLSession（系统原生，无额外依赖）
        return urlSessionProvider
    }

    /// 基于 URLSession 的 Provider（系统原生实现）
    static var urlSessionProvider: any ZTAPIProvider {
        ZTURLSessionProvider(plugins: [
            ZTLogPlugin(level: .simple)
        ])
    }

    /// 基于 Alamofire 的 Provider（需要 Alamofire 依赖）
    static var alamofireProvider: any ZTAPIProvider {
        ZTAlamofireProvider(plugins: [
            ZTLogPlugin(level: .simple)
        ])
    }

    /// 测试用 Provider
    static var stubProvider: any ZTAPIProvider {
        ZTStubProvider.jsonStubs([
            "GET:https://jsonplaceholder.typicode.com/users": [
                "data": [
                    ["id": 1, "name": "Test User"],
                    ["id": 2, "name": "Demo User"]
                ]
            ]
        ])
    }

    static var commonHeaders: [ZTAPIHeader] {
        [.contentType, .auth]
    }

    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)
        case password(String)
        case userId(String)
    }

    private static func makeApi<P: ZTAPIParamProtocol>(_ url: String, _ method: ZTHTTPMethod) -> ZTAPI<P> {
        ZTAPI<P>(url, method, provider: provider).headers(commonHeaders)
    }

    private static func makeApiGet<P: ZTAPIParamProtocol>(_ url: String) -> ZTAPI<P> {
        makeApi(url, .get).encoding(ZTURLEncoding())
    }

    private static func makeApiPost<P: ZTAPIParamProtocol>(_ url: String) -> ZTAPI<P> {
        makeApi(url, .post).encoding(ZTJSONEncoding())
    }

    static func login(userName: String, password: String) -> ZTAPI<ZTAPIKVParam> {
        return makeApiPost(fullPath("/user/login"))
            .param(.kv("user_name", userName))
            .param(.kv("password", password))
            .parse(
                .init("data/token", type: String.self, false)
            )
    }

    static func login2(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        return makeApiPost(fullPath("/user/login"))
            .param(.userName(userName))
            .param(.password(password))
            .parse(
                .init("data/token", type: String.self, false)
            )
    }

    static func userInfo(userId: String) -> ZTAPI<ZTAPIKVParam> {
        return makeApiGet(fullPath("/user/info"))
            .param(.kv("user_id", userId))
            .parse(
                .init("data/token", type: String.self, false),
                .init("data/username", type: String.self),
                .init("data/email", type: String.self)
            )
    }

    static var userList: ZTAPI<ZTAPIKVParam> {
        makeApiGet(fullPath("/users"))
    }
}

/// ViewModel - 封装用户中心相关的 API 调用和业务逻辑
@MainActor
class VM {
    var token: String = ""
    var userList: [User]? = []
    var addressList: [Address]? = []
    var firstAddr: Address? = nil

    func testAPIDemo() {
        Task {
            do {
                let r = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/profile", .get)
                    .param(.kv("user_name", "jack"))
                    .param(.kv("page", 1))
                    .header(ZTAPIHeader.h(key: "Content-Type", value: "application/json"))
                    .send()
                print("✅ Success: \(r)")
            } catch {
                print("❌ Error: \(error.localizedDescription)")
            }
        }
    }

    /// 使用 URLSession Provider 测试
    func testWithURLSessionProvider() async {
        do {
            let r = try await ZTAPI<ZTAPIKVParam>(
                "https://jsonplaceholder.typicode.com/users/1",
                .get,
                provider: ZTURLSessionProvider.shared
            )
            .send()
            print("✅ URLSessionProvider 测试成功: \(r)")
        } catch {
            print("❌ URLSessionProvider 测试失败: \(error)")
        }
    }

    /// 文件上传测试示例
    func testUpload() async {
        // 示例1: 上传单个图片 Data
        do {
            let imageData = Data("fake image data".utf8)
            let items: [ZTAPI<ZTAPIKVParam>.ZTUploadItem] = [
                .data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg)
            ]
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post)
                .upload(items)
                .send()
            print("✅ 上传单个 Data 成功")
        } catch {
            print("❌ 上传 Data 失败: \(error)")
        }

        // 示例2: 上传单个文件
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload.txt")
            try "test file content".write(to: fileURL, atomically: true, encoding: .utf8)

            let items: [ZTAPI<ZTAPIKVParam>.ZTUploadItem] = [
                .file(fileURL, name: "file")
            ]
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post)
                .upload(items)
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

            let items: [ZTAPI<ZTAPIKVParam>.ZTUploadItem] = [
                .data(Data("metadata".utf8), name: "metadata", mimeType: .json),
                .file(fileURL1, name: "photos", mimeType: .jpeg),
                .file(fileURL2, name: "photos", mimeType: .jpeg)
            ]

            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/multiple", .post)
                .upload(items)
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

            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/multipart", .post)
                .multipart(formData)
                .send()
            print("✅ Multipart 上传成功（文件 + 表单字段）")
        } catch {
            print("❌ Multipart 上传失败: \(error)")
        }

        // 示例5: 使用 body() 设置原始请求体
        do {
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/raw", .post)
                .body(Data("raw body data".utf8))
                .header(.h(key: "Content-Type", value: ZTMimeType.octetStream.rawValue))
                .send()
            print("✅ 使用 body() 上传原始数据成功")
        } catch {
            print("❌ 使用 body() 上传失败: \(error)")
        }

        // 示例6: 使用自定义 MIME 类型
        do {
            let items: [ZTAPI<ZTAPIKVParam>.ZTUploadItem] = [
                .data(Data("custom data".utf8), name: "file", mimeType: .mimeType("application/vnd.example"))
            ]
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post)
                .upload(items)
                .send()
            print("✅ 使用自定义 MIME 类型成功")
        } catch {
            print("❌ 使用自定义 MIME 类型失败: \(error)")
        }
    }

    /// 使用 Stub Provider 测试
    func testWithStub() async {
        // 切换到 stub provider
        // let originalProvider = UserCenterAPI.provider

        do {
            // 使用 stub provider 测试
            let r = try await ZTAPI<ZTAPIKVParam>(UserCenterAPI.fullPath("/users"), .get, provider: UserCenterAPI.stubProvider)
                .send()
            print("✅ Stub test success: \(r)")
        } catch {
            print("✅ Stub test err: \(error)")
        }
    }
    
    func performLogin() async {
        // 1. 登录接口
        do {
            let r = try await UserCenterAPI.login(userName: "jack", password: "123456").send()
            if let t: String = r.get("data/token") {
                self.token = t
                print("✅ 登录成功，Token: \(t)")
            }
        } catch {
            print("❌ 登录失败: \(error.localizedDescription)")
        }
        
        // 2. 获取用户信息
        do {
            let r = try await UserCenterAPI.userInfo(userId: "1384264339").send()
            if let t: String = r.get("data/token") {
                self.token = t
            }
            if let username: String = r.get("data/username") {
                print("✅ 用户名: \(username)")
            }
            if let email: String = r.get("data/email") {
                print("✅ 邮箱: \(email)")
            }
            print("✅ 获取用户信息成功")
        } catch {
            print("❌ 获取用户信息失败: \(error.localizedDescription)")
        }
        
        // 3. 获取用户列表
        do {
            let r = try await UserCenterAPI.userList
                .parse(
                    .init(type: [User].self),           // 解析整个响应为 [User]
                    .init("/0/address", type: Address.self),  // 解析第一个用户的地址
                    .init("/*/address", type: [Address].self)  // 解析所有用户的地址
                )
                .send()
            
            print("✅ 获取用户列表成功")
            
            // 从解析结果中获取数据
            if let users: [User] = r.get("/") {
                self.userList = users
                print("✅ userList: \(users.count) 个用户")
                if let firstUser = users.first {
                    print("   第一个用户: \(firstUser.name)")
                }
            }
            
            if let firstAddress: Address = r.get("/0/address") {
                self.firstAddr = firstAddress
                print("✅ firstAddr: \(firstAddress.city)")
            }
            
            if let addresses: [Address] = r.get("/*/address") {
                self.addressList = addresses
                print("✅ addressList: \(addresses.count) 个地址")
            }
        } catch {
            print("❌ 获取用户列表失败: \(error.localizedDescription)")
        }
    }
}
