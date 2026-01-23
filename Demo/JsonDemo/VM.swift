//
//  VM.swift
//  JsonDemo
//
//  Copyright (c) 2026 trojanzhang. All rights reserved.
//
//  This file is part of ZTAPI.
//
//  ZTAPI is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ZTAPI is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with ZTAPI. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
#if canImport(ZTJSON)
import SwiftyJSON
import ZTJSON
#endif
import ZTAPICore
import ZTAPIParamMacro

#if !canImport(ZTJSON)
// MARK: - Models
//
/// User model
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

/// Address model
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

/// Geo location model
struct Geo: Codable, Sendable {
    let lat: String
    let lng: String
}

/// Company model
struct Company: Codable, Sendable {
    let name: String
    let catchPhrase: String?
    let bs: String?
}
#endif

/// Login response
struct LoginResponse: Codable, Sendable {
    struct Data: Codable, Sendable {
        let token: String
    }
    let code: Int
    let data: Data?
    let msg: String?
}

/// User info response
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

/// User list response (standard API response format)
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
    @MainActor
    enum API {
        case custom(url: String, method: ZTHTTPMethod)
        
        static var baseUrl: String {
            "https://jsonplaceholder.typicode.com"
        }

        /// Configure Provider
        static var provider: any ZTAPIProvider {
            ZTURLSessionProvider()
        }
        
        /// Convenience method to create API instance
        fileprivate func build<P:ZTAPIParamProtocol>() -> ZTAPI<P> {
            ZTAPI<P>(API.baseUrl + url, method, provider: API.provider)
                .encoding(ZTJSONEncoding())
                .timeout(30)
                .plugins(
                    ZTAuthPlugin { "TOKEN" },
                    ZTLogPlugin(level: .simple)
                )
        }
        
        private static func makeApi<P: ZTAPIParamProtocol>(_ url: String, _ method: ZTHTTPMethod) -> ZTAPI<P> {
            ZTAPI<P>(url, method, provider: provider)
        }
        
        var url: String {
            switch self {
            case .custom(let url, _): return url
            }
        }
        
        var method: ZTHTTPMethod {
            switch self {
            case .custom(_, let method): return method
            }
        }
        
        static var login = API.custom(url: "/user/login", method: .post)
        static var userInfo = API.custom(url: "/user/info", method: .get)
        static var userList = API.custom(url: "/users", method: .get)
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
    
    /// Login
    static func login(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        API.login.build()
            .params(.userName(userName))
            .params(.password(password))
    }

    /// Get user info
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        API.userInfo.build()
            .params(.userId(userId))
    }

    /// Get user list
    static var userList: ZTAPI<ZTAPIKVParam> {
        API.userList.build()
    }

    /// Get single user
    static func user(id: Int) -> ZTAPI<ZTAPIKVParam> {
        API.custom(url: "/users/\(id)", method: .get).build()
    }
}

// MARK: - ViewModel

@MainActor
class VM {
    var token: String = ""
    var userList: [User] = []
    var addressList: [Address] = []
    var firstAddr: Address? = nil

    // MARK: - Basic Tests

    func testAPIDemo() {
        Task {
            do {
                // Return Codable type directly
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
            print("✅ URLSessionProvider test success: \(user.name)")
        } catch {
            print("❌ URLSessionProvider test failed: \(error)")
        }
    }

    // MARK: - File Upload Tests

    func testUpload() async {
        // Example 1: Upload single image Data
        do {
            let imageData = Data("fake image data".utf8)
            let data: Data = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
                .send()
            print("✅ Upload single Data success, response: \(data.count) bytes")
        } catch {
            print("❌ Upload Data failed: \(error)")
        }

        // Example 2: Upload single file
        do {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload.txt")
            try "test file content".write(to: fileURL, atomically: true, encoding: .utf8)
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.file(fileURL, name: "file", mimeType: .txt))
                .send()
            print("✅ Upload single file success")
        } catch {
            print("❌ Upload file failed: \(error)")
        }

        // Example 3: Upload multiple items (Data + File mixed)
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
            print("✅ Upload multiple items success (Data + File mixed)")
        } catch {
            print("❌ Upload multiple items failed: \(error)")
        }

        // Example 4: Use Multipart to upload files + form fields
        do {
            let formData = ZTMultipartFormData()
                .add(.data(Data("file1".utf8), name: "files", fileName: "file1.txt", mimeType: .txt))
                .add(.data(Data("file2".utf8), name: "files", fileName: "file2.txt", mimeType: .txt))
                .add(.data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json))

            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/multipart", .post, provider: ZTAlamofireProvider.shared)
                .multipart(formData)
                .send()
            print("✅ Multipart upload success (files + form fields)")
        } catch {
            print("❌ Multipart upload failed: \(error)")
        }

        // Example 5: Use body() to set raw request body
        do {
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload/raw", .post, provider: ZTAlamofireProvider.shared)
                .body(Data("raw body data".utf8))
                .headers(.h(key: "Content-Type", value: ZTMimeType.octetStream.rawValue))
                .send()
            print("✅ Upload raw data using body() success")
        } catch {
            print("❌ Upload using body() failed: \(error)")
        }

        // Example 6: Use custom MIME type
        do {
            _ = try await ZTAPI<ZTAPIKVParam>("https://example.com/upload", .post, provider: ZTAlamofireProvider.shared)
                .upload(.data(Data("custom data".utf8), name: "file", mimeType: .custom(ext:"", mime: "application/vnd.example")))
                .send()
            print("✅ Use custom MIME type success")
        } catch {
            print("❌ Use custom MIME type failed: \(error)")
        }
    }

    // MARK: - Stub Tests

    func testWithStub() async {
        do {
            let response: UserListResponse = try await ZTAPI<ZTAPIKVParam>(
                "https://jsonplaceholder.typicode.com/users",
                .get,
                provider: UserCenterAPI.stubProvider
            )
            .response()
            print("✅ Stub test success: \(response.data?.count ?? 0) users")
        } catch {
            print("✅ Stub test err: \(error)")
        }
    }

    // MARK: - Business Flows

    func performLogin() async {
        // 1. Login API - Use Codable for parsing
        do {
            let response: LoginResponse = try await UserCenterAPI.login(userName: "jack", password: "123456").response()
            if let token = response.data?.token {
                self.token = token
                print("✅ Login success, Token: \(token)")
            }
        } catch {
            print("❌ Login failed: \(error.localizedDescription)")
        }
    }

    func fetchUserInfo() async {
        do {
            let response: UserInfoResponse = try await UserCenterAPI.userInfo(userId: "1384264339").response()
            if let data = response.data {
                self.token = data.token
                print("✅ Username: \(data.username)")
                print("✅ Email: \(data.email)")
            }
            print("✅ Get user info success")
        } catch {
            print("❌ Get user info failed: \(error.localizedDescription)")
        }
    }

    func fetchUserList() async {
        do {
            // Method 1: If API returns array directly
            let users: [User] = try await UserCenterAPI.userList.response()
            self.userList = users
            print("✅ Get user list success: \(users.count) users")
            if let first = users.first {
                print("   First user: \(first.name)")
            }
        } catch {
            print("❌ Get user list failed: \(error.localizedDescription)")
        }
    }

    func fetchSingleUser() async {
        do {
            let user: User = try await UserCenterAPI.user(id: 1).response()
            print("✅ Get single user success: \(user.name)")
            if let address = user.address {
                print("   Address: \(address.city)")
            }
        } catch {
            print("❌ Get single user failed: \(error.localizedDescription)")
        }
    }
}
