# ZTAPI

## 流畅链式 DSL

ZTAPI 采用 **Fluent Interface / Builder 模式**，所有配置方法返回 `Self` 并标记 `@discardableResult`：

```swift
import ZTAPI

// 完整的链式 DSL 示例
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users", .get)
    .params(.kv("id", 123), .kv("include", "profile"))
    .headers(.kv("Authorization", "Bearer xxx"))
    .timeout(30)
    .retry(ZTExponentialBackoffRetryPolicy(maxRetries: 3))
    .upload(.data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .imageJPEG))
    .uploadProgress { progress in
        print("上传进度: \(progress.fractionCompleted)")
    }
    .jsonDecoder { decoder in
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    .plugins(logPlugin, authPlugin)
    .response()
```

**DSL 方法列表：**

| 方法 | 功能 |
|------|------|
| `.params(...)` | 添加请求参数 |
| `.headers(...)` | 添加 HTTP 头 |
| `.encoding(...)` | 设置参数编码方式 |
| `.body(...)` | 设置原始请求体 |
| `.upload(...)` | 上传文件 |
| `.multipart(...)` | 设置 multipart 表单 |
| `.timeout(...)` | 设置超时时间 |
| `.retry(...)` | 设置重试策略 |
| `.uploadProgress(...)` | 上传进度回调 |
| `.jsonDecoder {...}` | 配置 JSONDecoder |
| `.plugins(...)` | 添加插件 |

---

ZTAPI 是一个超越 Moya 的现代化 Swift 网络请求库。通过 **enum 模块化封装**、**XPath 解析**、**宏自动生成**，提供比 Moya 更强大、更简洁的 API 管理方案。

## 核心优势

| 特性         | ZTAPI                                | Moya                        |
| ------------ | ------------------------------------ | --------------------------- |
| 配置方式     | 灵活，无模板代码                      | TargetType 协议，模板多     |
| 异步支持     | 原生 async/await                      | 闭包为主                   |
| 模块化封装   | enum + 静态方法，类型安全            | enum 关联值，类型安全       |
| 参数定义     | `@ZTAPIParam` 宏自动生成            | 手动构造参数                |
| XPath 解析   | 原生支持，直接映射嵌套字段           | 需手动定义嵌套模型          |
| 响应解析     | Codable + ZTJSON（SwiftyJSON）双模式 | 主要使用 Codable            |
| 插件机制     | 4 个钩子，灵活拦截                   | PluginType（前置/后置）     |

## 安装

### Swift Package Manager

**完整功能（ZTAPICore + ZTAPIXPath + ZTAPIParamMacro）：**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPI", package: "ZTAPI")  // 包含 ZTAPICore + ZTAPIXPath + ZTAPIParamMacro
        ]
    )
]
```

**仅 ZTAPICore（无第三方依赖）：**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI")  // 仅 ZTAPICore 功能
        ]
    )
]
```

**ZTAPICore + ZTAPIParamMacro（含宏支持）：**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI"),
            .product(name: "ZTAPIParamMacro", package: "ZTAPI")  // 启用 @ZTAPIParam 宏
        ]
    )
]
```

**ZTAPICore + ZTAPIXPath（含 XPath 解析）：**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI"),
            .product(name: "ZTAPIXPath", package: "ZTAPI")  // 启用 XPath 解析
        ]
    )
]
```

### CocoaPods

```ruby
pod 'ZTAPI', :git => 'https://github.com/willonboy/ZTAPI.git', :branch => 'main'
```

---

## 快速入门

最简单的 GET 请求：

```swift
import ZTAPI

// 直接获取数据
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123")
    .response()

// 带参数
let users: [User] = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users")
    .params(.kv("page", 1), .kv("size", 20))
    .response()
```

POST 请求：

```swift
// URL 表单编码（默认）
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/login", .post)
    .params(.kv("username", "jack"), .kv("password", "123456"))
    .response()

// JSON 请求体
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/login", .post)
    .params(.kv("username", "jack"), .kv("password", "123456"))
    .encoding(ZTJSONEncoding())
    .response()
```

---

## 基础用法

### 响应模型

```swift
struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct LoginResponse: Codable {
    let token: String
    let userId: Int
}
```

### 常见 HTTP 方法

```swift
// GET
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123").response()

// POST
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users", .post)
    .params(.kv("name", "Jack"), .kv("email", "jack@example.com"))
    .response()

// PUT
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .put)
    .params(.kv("name", "Jack Updated"))
    .response()

// DELETE
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .delete).response()
```

### 请求头与超时

```swift
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .headers(.h("Authorization", "Bearer token123"), .h("Accept", "application/json"))
    .timeout(30)
    .response()
```

### 原始数据响应

```swift
// 获取原始 Data
let data = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data").send()

// 获取原始 String
let text = String(decoding: data, as: UTF8.self)
```

### 错误处理

```swift
do {
    let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123").response()
} catch let error as ZTAPIError {
    print("错误 \(error.code): \(error.msg)")
    // 根据错误码处理
    switch error.code {
    case 401: print("未授权")
    case 404: print("未找到")
    default: print("其他错误")
    }
}
```

---

## 进阶用法

### 1. @ZTAPIParam 宏 - 类型安全参数

使用 `@ZTAPIParam` 宏（需要 ZTAPIParamMacro）生成类型安全参数，自动映射 key：

```swift
import ZTAPIParamMacro

enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }

    // 宏自动生成：key、value、isValid
    // 自动转换：userName → user_name（驼峰转下划线）
    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)      // → "user_name"（必填）
        case password(String)      // → "password"（必填）
        // 可选参数：该参数为可选，不参与 isValid 校验
        case email(String?)        // → "email"（可选）
        // 自定义参数名：userId → "uid"
        @ZTAPIParamKey("uid")
        case userId(String)        // → "uid"（必填）
    }

    // 使用示例
    static func login(userName: String, password: String, email: String? = nil) async throws -> LoginResponse {
        var api = ZTAPI<UserAPIParam>(baseUrl + "/user/login", .post)
            .params(.userName(userName), .password(password))
        // email 参数为可选，nil 时不会添加到请求中
        if let email = email {
            api = api.params(.email(email))
        }
        return try await api.response()
    }
}
// 自动生成的 key 映射：
// userName → "user_name"（必填，不传会报错）
// password → "password"（必填，不传会报错）
// email → "email"（可选）
// userId → "uid"（必填，通过 @ZTAPIParamKey 自定义）
//
// isValid 自动校验：非 Optional 参数必须存在，否则抛出异常
```

**对比手动实现：**

```swift
// 无宏时需要手写
enum UserAPIParam: ZTAPIParamProtocol {
    case userName(String)
    case password(String)
    case email(String?)
    case userId(String)

    var key: String {
        switch self {
        case .userName: return "user_name"
        case .password: return "password"
        case .email: return "email"
        case .userId: return "uid"  // 自定义参数名
        }
    }

    var value: Sendable {
        switch self {
        case .userName(let v): return v
        case .password(let v): return v
        case .email(let v): return v
        case .userId(let v): return v
        }
    }

    // 非 Optional 参数必须存在
    static func isValid(_ params: [String: Sendable]) -> Bool {
        return params["user_name"] != nil && params["password"] != nil && params["uid"] != nil
    }
}
```

### 2. 模块化 API 封装

用 enum 组织 API 模块。推荐模式 - 内部定义端点，返回 `ZTAPI` 实例支持链式调用和 Combine：

```swift
enum UserCenterAPI {
    // 内部定义端点
    enum API {
        case custom(url: String, method: ZTHTTPMethod)

        static var baseUrl: String { "https://api.example.com" }
        static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

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

        // 使用 build() 统一配置
        fileprivate func build<P: ZTAPIParamProtocol>() -> ZTAPI<P> {
            ZTAPI<P>(API.baseUrl + url, method, provider: API.provider)
                .encoding(ZTJSONEncoding())
                .timeout(30)
                .plugins(
                    ZTAuthPlugin { "TOKEN" },
                    ZTLogPlugin(level: .simple)
                )
        }

        static var login = API.custom(url: "/user/login", method: .post)
        static var userInfo = API.custom(url: "/user/info", method: .get)
        static var userList = API.custom(url: "/users", method: .get)
    }

    // 登录 - 返回 ZTAPI 实例支持链式调用
    static func login(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        API.login.build()
            .params(.userName(userName), .password(password))
    }

    // 获取用户信息
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        API.userInfo.build()
            .params(.userId(userId))
    }

    // 用户列表 - 返回 ZTAPI 实例
    static var userList: ZTAPI<ZTAPIKVParam> {
        API.userList.build()
    }
}

// 使用 - 调用 .response() 获取数据
let response: LoginResponse = try await UserCenterAPI.login(userName: "jack", password: "123456").response()
let users: [User] = try await UserCenterAPI.userList.response()
```

### 3. XPath 解析

解析 JSON 嵌套字段，无需定义嵌套结构（需要 ZTJSON）：

```swift
#if canImport(ZTJSON)
import ZTJSON

@ZTJSON
struct User {
    let id: Int
    let name: String

    // 直接映射嵌套路径
    @ZTJSONKey("address/city")
    var city: String = ""

    @ZTJSONKey("address/geo/lat")
    var lat: Double = 0

    @ZTJSONKey("address/geo/lng")
    var lng: Double = 0
}

// JSON: { "id": 1, "name": "Jack", "address": { "city": "Beijing", "geo": { "lat": 39.9, "lng": 116.4 } } }
// 无需定义 Address、Geo 嵌套模型！

let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/1").response()
#endif
```

### 4. 运行时 XPath 解析

> XPath 解析扩展在 `ZTAPIXPath` 模块中（需要 ZTJSON）。

运行时解析多个 XPath 路径，无需定义模型：

```swift
#if canImport(ZTJSON)
let results = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .parseResponse(
        // isAllowMissing: true（默认）- 字段不存在时不报错，返回 nil
        ZTAPIParseConfig("/data/user/name", type: String.self),
        // isAllowMissing: false - 字段不存在时抛出异常
        ZTAPIParseConfig("/data/user/age", type: Int.self, false),
        ZTAPIParseConfig("/data/posts", type: [Post].self)
    )

if let name = results["/data/user/name"] as? String {
    print("用户名: \(name)")
}
if let age = results["/data/user/age"] as? Int {
    print("年龄: \(age)")
}
if let posts = results["/data/posts"] as? [Post] {
    print("文章数: \(posts.count)")
}
#endif
```

### 5. 文件上传

```swift
// 上传单个 Data
let imageData = try Data(contentsOf: imageURL)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
    .uploadProgress { progress in
        print("进度: \(progress.fractionCompleted * 100)%")
    }
    .response()

// 上传单个文件
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(.file(fileURL, name: "file", mimeType: .txt))
    .response()

// 多文件混合上传（Data + File）
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/multiple", .post)
    .upload(
        .data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
        .file(fileURL, name: "document", mimeType: .pdf)
    )
    .params(.kv("userId", "123"))
    .response()

// 使用 Multipart 上传文件 + 表单字段
let formData = ZTMultipartFormData()
    .add(.data(Data("file1".utf8), name: "files", fileName: "file1.txt", mimeType: .txt))
    .add(.data(Data("file2".utf8), name: "files", fileName: "file2.txt", mimeType: .txt))
    .add(.data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json))

let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/multipart", .post)
    .multipart(formData)
    .response()

// 原始 body 上传
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/raw", .post)
    .body(Data("raw body data".utf8))
    .headers(.h("Content-Type", ZTMimeType.octetStream.rawValue))
    .response()

// 自定义 MIME 类型
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(.data(Data("custom data".utf8), name: "file", mimeType: .custom(ext: "", mime: "application/vnd.example")))
    .response()
```

---

## 高级特性

### Provider 架构

ZTAPI 通过 `ZTAPIProvider` 协议抽象底层网络实现，支持多种 Provider：

> 注：Provider 实现代码在 Demo 工程中，按需复制使用。

| Provider               | 说明                   | 依赖      |
| ---------------------- | ---------------------- | --------- |
| `ZTURLSessionProvider` | 原生 URLSession        | 无        |
| `ZTAlamofireProvider`  | 基于 Alamofire         | Alamofire |
| `ZTStubProvider`       | 单元测试 Mock          | 无        |
| `ZTSSLPinningProvider` | SSL 证书固定（URLSession） | 无     |
| `ZTAPICacheProvider`   | 内存缓存，支持策略配置 | 无        |

```swift
// 使用 shared 单例
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: ZTURLSessionProvider.shared)

// 或使用 Alamofire
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: ZTAlamofireProvider.shared)

// 或使用缓存
let cacheProvider = ZTAPICacheProvider(
    baseProvider: ZTURLSessionProvider.shared,
    readPolicy: .cacheElseNetwork,
    cacheDuration: 300
)
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: cacheProvider)
```

### 缓存 Provider

> 缓存 Provider 的实现代码在 Demo 工程的 `ZTAPICacheProvider.swift` 中。

`ZTAPICacheProvider` 包装任意 Provider，添加可配置的内存缓存和 LRU 淘汰策略：

```swift
// 创建缓存 Provider
let cacheProvider = ZTAPICacheProvider(
    baseProvider: ZTURLSessionProvider.shared,
    readPolicy: .cacheElseNetwork,
    cacheDuration: 300               // 5 分钟
)

// 使用
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .get, provider: cacheProvider)
    .response()
```

**缓存读取策略：**

| 策略                  | 说明                              |
| --------------------- | --------------------------------- |
| `.networkOnly`        | 仅从网络获取，忽略缓存            |
| `.cacheOnly`          | 仅读缓存，未命中时报错            |
| `.cacheElseNetwork`   | 先读缓存，未命中则网络请求        |
| `.networkElseCache`   | 先网络请求，失败时回退到缓存      |

**缓存写入策略：**

| 策略          | 说明                     |
| ------------- | ------------------------ |
| `.never`      | 从不写入缓存             |
| `.always`     | 总是写入缓存             |
| `.onSuccess`  | 仅成功响应时写入 (2xx)    |

**缓存管理：**

```swift
// 清除所有缓存
await cacheProvider.clearCache()

// 清除指定 URL
await cacheProvider.clearCache(url: "https://api.example.com/user/123")

// 获取缓存统计
let stats = await cacheProvider.cacheStats
print("缓存命中率: \(stats.formattedHitRate)")
print("缓存大小: \(stats.formattedSize)")

// 清除过期条目
await cacheProvider.removeExpired()
```

### Plugin 插件系统

插件系统提供 4 个钩子拦截请求/响应：

```swift
protocol ZTAPIPlugin: Sendable {
    func willSend(_ request: inout URLRequest) async throws
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws
    func didCatch(_ error: Error) async throws
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data
}
```

> 注：插件实现在 Demo 工程中。

**内置插件：**

| 插件              | 说明               |
| ----------------- | ------------------ |
| `ZTLogPlugin`     | 请求/响应日志      |
| `ZTAuthPlugin`    | 自动添加认证 Token |
| `ZTTokenRefreshPlugin` | 自动刷新过期 Token |
| `ZTJSONDecodePlugin`   | JSON 美化输出  |
| `ZTDecryptPlugin` | 响应数据解密       |
| `ZTCheckRespOKPlugin` | 检查业务状态码 |
| `ZTReadPayloadPlugin` | 提取响应 data 字段 |

```swift
// 使用插件
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTLogPlugin(), ZTAuthPlugin { "my-token" })
    .response()
```

**自定义插件示例：**

```swift
struct RequestSignPlugin: ZTAPIPlugin {
    let appKey: String
    let appSecret: String

    func willSend(_ request: inout URLRequest) async throws {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        let sign = "\(appKey)\(timestamp)\(appSecret)".md5
        request.setValue(sign, forHTTPHeaderField: "X-Sign")
    }
}
```

### 重试策略

| 策略                              | 说明           |
| --------------------------------- | -------------- |
| `ZTFixedRetryPolicy`              | 固定延迟重试   |
| `ZTExponentialBackoffRetryPolicy` | 指数退避重试   |
| `ZTConditionalRetryPolicy`        | 自定义条件重试 |

```swift
// 固定延迟重试
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 1.0))
    .response()

// 指数退避
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTExponentialBackoffRetryPolicy(maxAttempts: 5, baseDelay: 1.0, multiplier: 2.0))
    .response()

// 自定义条件重试（async 闭包）
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/custom")
    .retry(ZTConditionalRetryPolicy(maxAttempts: 3, delay: 2.0) {
        request, error, attempt, response in
        // 只在 5xx 错误时重试
        (response?.statusCode ?? 0) >= 500
    })
    .response()
```

### SSL Pinning

> SSL Pinning 的实现代码在 Demo 工程的 `ZTAPISecurityPlugin.swift` 和 `ZTAlamofireSecurityExtension.swift` 中。

**URLSession SSL Pinning：**

```swift
// 证书固定
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver") // 从 Bundle 加载 myserver.cer
let provider = ZTSSLPinningProvider(mode: .certificate(certificates))

// 公钥固定
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver")
let publicKeyHashes = ZTCertificateLoader.publicKeyHashes(from: certificates)
let provider = ZTSSLPinningProvider(mode: .publicKey(publicKeyHashes))

// 禁用验证（仅开发环境）
let provider = ZTSSLPinningProvider(mode: .disabled)
```

**Alamofire SSL Pinning：**

> 注：Alamofire Provider 仅支持证书固定，如需公钥固定请使用 `ZTSSLPinningProvider`。

```swift
import Alamofire

// 从 Bundle 加载证书固定
let provider = ZTAlamofireProvider.certificatePinning(from: "myserver")

// 或直接使用 pinning(mode:) 方法
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver")
let provider = ZTAlamofireProvider.pinning(mode: .certificate(certificates))

// 禁用验证（仅开发环境，仅 DEBUG 模式可用）
let provider = ZTAlamofireProvider.insecureProvider()
```

导出服务器证书：
```bash
openssl s_client -connect api.example.com:443 -showcerts
```

### 并发控制

> 全局 API Provider 的实现代码在 Demo 工程的 `ZTAPIGlobalManager.swift` 中。

全局 Provider 已预配置（Alamofire + 并发限制 6）：

```swift
// 直接使用全局 Provider（无需配置）
let result = try await ZTAPI<ZTAPIKVParam>.global("https://api.example.com/data")
    .response()
```

如需自定义全局 Provider（如使用 URLSession 或修改并发限制），请修改 Demo 工程中的 `ZTAPIGlobalManager.provider`。

### Combine 支持

```swift
import Combine

enum UserCenterAPI {
    // 返回 ZTAPI 实例用于链式调用
    static func userInfo(userId: String) -> ZTAPI<ZTAPIKVParam> {
        ZTAPI<ZTAPIKVParam>("https://api.example.com/user/info")
            .params(.kv("userId", userId))
    }
}

// 使用 Combine
let publisher: AnyPublisher<User, Error> = UserCenterAPI.userInfo(userId: "123")
    .publisher()

cancellable = publisher
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion {
                print("Error: \(error)")
            }
        },
        receiveValue: { user in
            print("User: \(user.name)")
        }
    )
```

---

## 错误参考

### ZTAPIError 结构

```swift
public struct ZTAPIError: Error {
    public let code: Int           // 错误码
    public let msg: String         // 错误信息
    public let httpResponse: HTTPURLResponse?  // 关联的 HTTP 响应
}
```

### 内置错误

| 错误                 | 错误码 | 说明                |
| -------------------- | ------ | ------------------- |
| `invalidURL`         | 80001  | URL 为空            |
| `invalidParams`      | 80002  | 请求参数无效        |
| `invalidResponse`    | 80003  | 响应类型无效        |
| `emptyResponse`      | 80004  | 响应为空            |
| `jsonEncodingFailed` | 81002  | JSON 编码失败       |
| `jsonParseFailed`    | 81003  | JSON 解析失败       |
| `xpathParseFailed`   | 82001  | XPath 解析失败      |

---

## API 参考

### ZTAPI 方法

| 方法                | 说明                         |
| ------------------- | ---------------------------- |
| `params(_:)`        | 添加请求参数                 |
| `headers(_:)`       | 添加 HTTP 头                 |
| `encoding(_:)`      | 设置参数编码（URL/JSON/Multipart） |
| `body(_:)`          | 设置原始请求体               |
| `upload(_:)`        | 上传文件/Data                |
| `timeout(_:)`       | 设置超时                     |
| `retry(_:)`         | 设置重试策略                 |
| `uploadProgress(_:)` | 设置上传进度回调             |
| `jsonDecoder(_:)`   | 配置 JSON 解码器             |
| `plugins(_:)`       | 添加插件                     |
| `send()`            | 发送请求，返回 Data          |
| `response()`        | 发送请求，返回 Codable 对象  |
| `parseResponse(_:)` | 发送请求，XPath 解析（需 ZTJSON） |
| `publisher()`       | 返回 Combine Publisher       |

### HTTP 方法

```swift
public enum ZTHTTPMethod: Sendable {
    case get
    case post
    case put
    case patch
    case delete
    case head
}
```

### 参数编码

| 编码                  | 说明                            |
| --------------------- | ------------------------------- |
| `ZTURLEncoding`       | URL 编码，默认                  |
| `ZTJSONEncoding`      | JSON 编码，POST 请求常用        |
| `ZTMultipartEncoding` | Multipart 表单编码，文件上传使用 |

> 提示：POST 请求默认使用 `ZTURLEncoding`，发送 JSON 请求体需显式指定 `.encoding(ZTJSONEncoding())`

---

## 系统要求

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## 可选依赖

| 库             | 用途                          |
| -------------- | ----------------------------- |
| **Alamofire**  | 使用 `ZTAlamofireProvider`    |
| **ZTJSON**     | XPath 解析                     |
| **SwiftyJSON** | `ZTAPIXPath` 产品必需       |

> 注：内置 Plugin 和 Provider 的实现代码在 Demo 工程中，按需复制使用。

## 许可证

AGPL v3 License

## 作者

by zt
