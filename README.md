# ZTAPI

ZTAPI 是一个超越 Moya 的现代化 Swift 网络请求库。通过 **enum 模块化封装**、**XPath 解析**、**宏自动生成**，提供比 Moya 更强大、更简洁的 API 管理方案。

## 核心优势

| 特性         | ZTAPI                                | Moya                        |
| ------------ | ------------------------------------ | --------------------------- |
| 配置方式     | 灵活，无模板代码                      | TargetType 协议，模板多     |
| 异步支持     | 原生 async/await                      | 闭包为主                   |
| 模块化封装   | enum + 静态方法，类型安全            | enum 关联值，类型安全       |
| 参数定义     | `@ZTAPIParam` 宏自动生成            | 手动构造参数                |
| Key 映射     | @ZTAPIParam 宏自动转换              | 需配置 keyDecodingStrategy  |
| XPath 解析   | 原生支持，直接映射嵌套字段           | 需手动定义嵌套模型          |
| 响应解析     | Codable + ZTJSON（SwiftyJSON）双模式 | 主要使用 Codable            |
| 并发控制     | 内置 Actor 信号量                    | 需自行实现                  |
| 插件机制     | 4 个钩子，灵活拦截                   | PluginType（前置/后置）     |

## 安装

### Swift Package Manager

```
https://github.com/willonboy/ZTAPI.git
```

### CocoaPods

```ruby
# 或从 Git 安装（开发版）
pod 'ZTAPI', :git => 'https://github.com/willonboy/ZTAPI.git', :branch => 'main'
```

## 架构设计

### Provider 设计

ZTAPI 通过 `ZTAPIProvider` 协议抽象底层网络实现，支持多种 Provider：

```swift
/// Provider 协议
protocol ZTAPIProvider: Sendable {
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse)
}
```

#### 内置 Provider 实现

> 注：以下 Provider 的实现代码在 Demo 工程中，可根据需要复制到项目使用。

| Provider               | 说明                         | 依赖      |
| ---------------------- | ---------------------------- | --------- |
| `ZTURLSessionProvider` | 基于原生 URLSession          | 无        |
| `ZTAlamofireProvider`  | 基于 Alamofire               | Alamofire |
| `ZTStubProvider`       | 用于单元测试的 Mock Provider | 无        |

**ZTURLSessionProvider - 原生实现**

```swift
// 使用默认 URLSession.shared
let provider = ZTURLSessionProvider()

// 使用自定义 URLSession
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30
let provider = ZTURLSessionProvider(session: URLSession(configuration: config))

// 创建 API
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: provider)
```

**ZTAlamofireProvider - Alamofire 实现**

```swift
import Alamofire

// 使用默认 Session
let provider = ZTAlamofireProvider()

// 使用自定义 Session（可配置 interceptor 等）
let configuration = Configuration()
let session = Session(configuration: configuration)
let provider = ZTAlamofireProvider(session: session)
```

**ZTStubProvider - 测试 Mock**

```swift
// JSON 字典 stub
let stubs: [String: [String: Any]] = [
    "GET:https://api.example.com/user": ["id": 1, "name": "Jack"],
    "POST:https://api.example.com/login": ["token": "abc123"]
]

let provider = ZTStubProvider.jsonStubs(stubs)

// 带延迟和状态码的 stub
let provider = ZTStubProvider(stubs: [
    "GET:https://api.example.com/user": .init(
        statusCode: 200,
        data: jsonData,
        delay: 0.5  // 模拟网络延迟
    )
])
```

### Plugin 插件机制

插件系统通过 `ZTAPIPlugin` 协议实现请求/响应的拦截和增强：

```swift
/// 插件协议
protocol ZTAPIPlugin: Sendable {
    /// 请求即将发送（可修改请求）
    func willSend(_ request: inout URLRequest) async throws

    /// 收到响应
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws

    /// 发生错误
    func didCatch(_ error: Error) async throws

    /// 处理响应数据（可修改返回数据）
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data
}
```

#### 示例插件

> 注：以下插件的实现代码在 Demo 工程中，可根据需要复制到项目使用。

| 插件                             | 说明                           |
| -------------------------------- | ------------------------------ |
| `ZTLogPlugin`                    | 请求/响应日志输出              |
| `ZTAuthPlugin`                   | 自动添加认证 Token             |
| `ZTTokenRefreshPlugin`           | 自动刷新过期 Token（并发安全） |
| `ZTJSONDecodePlugin`             | JSON 美化输出                  |
| `ZTDecryptPlugin`                | 响应数据解密                   |
| `ZTResponseHeaderInjectorPlugin` | 注入响应头到数据中             |

#### 自定义插件示例

```swift
/// 请求签名插件
struct ZTSignPlugin: ZTAPIPlugin {
    let appKey: String
    let appSecret: String

    func willSend(_ request: inout URLRequest) async throws {
        guard let url = request.url else { return }

        // 添加时间戳
        let timestamp = String(Int(Date().timeIntervalSince1970))
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")

        // 生成签名
        let sign = "\(appKey)\(timestamp)\(appSecret)".md5
        request.setValue(sign, forHTTPHeaderField: "X-Sign")
    }
}

/// 使用
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTSignPlugin(appKey: "xxx", appSecret: "yyy"))
    .response()
```

## 核心用法

### 1. @ZTAPIParam 宏 - 极简参数定义

使用 `@ZTAPIParam` 宏，只需声明 case 即可自动生成参数代码（需 ZTJSON 支持）：

```swift
#if canImport(ZTJSON)
import ZTAPI
import ZTJSON

enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    // 宏自动生成：key、value、isValid
    // 自动转换：userName → user_name
    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)
        case password(String)
        // Optional 参数：该参数可选，不参与 isValid 校验
        case email(String?)
        // 自定义参数名：userId → "uid"
        @ZTAPIParamKey("uid")
        case userId(String)
    }

    // 使用
    static func login(userName: String, password: String, email: String? = nil) async throws -> LoginResponse {
        var api = ZTAPI<UserAPIParam>(baseUrl + "/user/login", .post, provider: provider)
            .params(.userName(userName), .password(password))
        // email 参数可选，nil 时不会被添加到请求中
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
#endif
```

**对比手动实现：**

```swift
// 无 ZTJSON 时需要手写
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
        params["user_name"] != nil && params["password"] != nil && params["uid"] != nil
    }
}
```

### 2. 模块化 API 封装

完整示例展示模块化封装的威力（如果使用@ZTAPIParam则需 ZTJSON 支持）：

```swift
#if canImport(ZTJSON)
import ZTJSON

enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)
        case password(String)
        case userId(String)
    }

    private static func makeApi<P: ZTAPIParamProtocol>(
        _ path: String, _ method: ZTHTTPMethod = .get
    ) -> ZTAPI<P> {
        ZTAPI<P>(baseUrl + path, method, provider: provider)
    }

    // 登录 - 直接返回数据
    static func login(userName: String, password: String) async throws -> LoginResponse {
        try await makeApi("/user/login", .post)
            .params(.userName(userName), .password(password))
            .response()
    }

    // 获取用户信息 - 直接返回数据
    static func userInfo(userId: String) async throws -> UserInfoResponse {
        try await makeApi("/user/info")
            .params(.userId(userId))
            .response()
    }

    // 用户列表 - 直接返回数据
    static func userList() async throws -> [User] {
        try await makeApi("/users").response()
    }
}

// 使用 - 直接获取数据
let response = try await UserCenterAPI.login(userName: "jack", password: "123456")
let users: [User] = try await UserCenterAPI.userList()
#endif
```

### 3. XPath 解析

直接将 JSON 嵌套路径映射到模型属性，无需定义嵌套结构：

```swift
#if canImport(ZTJSON)
import ZTJSON

@ZTJSON
struct User {
    let id: Int
    let name: String

    // XPath：address/city → city
    @ZTJSONKey("address/city")
    var city: String = ""

    // XPath：address/geo/lat → lat
    @ZTJSONKey("address/geo/lat")
    var lat: Double = 0

    @ZTJSONKey("address/geo/lng")
    var lng: Double = 0
}

// JSON 响应：
// { "id": 1, "name": "Jack", "address": { "city": "Beijing", "geo": { "lat": 39.9, "lng": 116.4 } } }
// 无需定义 Address、Geo 嵌套模型！
#endif
```

### 4. 运行时 XPath 解析

> 适用场景：当只需要 JSON 中少量嵌套字段时，使用运行时解析可避免为每个字段定义完整模型，降低 model 膨胀速度。

```swift
#if canImport(ZTJSON)
// 同时解析多个 XPath 路径
let results = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .parseResponse(
        // isAllowMissing: true（默认）字段不存在时不报错，返回 nil
        ZTAPIParseConfig("/data/user/name", type: String.self),
        // isAllowMissing: false 字段不存在时抛出异常
        ZTAPIParseConfig("/data/user/age", type: Int.self, false),
        ZTAPIParseConfig("/data/posts", type: [Post].self)
    )

// 获取解析结果
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

### 5. 插件使用

> 注：以下插件的实现代码在 Demo 工程中，可根据需要复制到项目使用。

#### 日志插件

```swift
// 详细日志
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTLogPlugin(level: .verbose))
    .response()

// 简洁日志
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTLogPlugin(level: .simple))
    .response()
```

#### 认证插件

```swift
// 静态 Token
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/protected")
    .plugins(ZTAuthPlugin(token: { "my-token" }))
    .response()

// 动态 Token（从本地存储读取）
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/protected")
    .plugins(ZTAuthPlugin(token: { Keychain.loadToken() }))
    .response()
```

#### Token 刷新插件（并发安全）

```swift
// 自动刷新过期 Token，使用 Actor 确保并发安全
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTTokenRefreshPlugin(
        shouldRefresh: { error in
            // 判断是否需要刷新 Token
            (error as NSError).code == 401
        },
        refresh: {
            // 执行刷新逻辑
            let newToken = try await APIService.refreshToken()
            return newToken
        },
        onRefresh: { newToken in
            // 刷新成功后的回调
            Keychain.saveToken(newToken)
        },
        useSingleFlight: true  // 启用 single-flight 模式，防止并发刷新
    ))
    .response()
```

#### 响应处理插件

```swift
// JSON 美化
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTJSONDecodePlugin())
    .response()

// 数据解密
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/encrypted")
    .plugins(ZTDecryptPlugin(decrypt: { data in
        try CryptoHelper.decrypt(data)
    }))
    .response()

// 注入响应头
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTResponseHeaderInjectorPlugin())
    .response()
```

### 6. 文件上传

```swift
// 上传单个文件
let imageData = try Data(contentsOf: imageURL)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
    .uploadProgress { progress in
        print("上传进度: \(progress.fractionCompleted * 100)%")
    }
    .response()

// 多文件混合上传
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(
        .data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
        .file(fileURL, name: "document", mimeType: .pdf)
    )
    .params(.kv("userId", "123"))
    .response()
```

### 7. 重试策略

```swift
// 固定次数重试
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 1.0))
    .response()

// 指数退避重试
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTExponentialBackoffRetryPolicy(
        maxAttempts: 5,
        baseDelay: 1.0,
        multiplier: 2.0
    ))
    .response()

// 自定义条件重试
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/custom")
    .retry(ZTConditionalRetryPolicy(maxAttempts: 3, delay: 2.0) {
        request, error, attempt, response in
        // 只在 5xx 错误时重试
        if let statusCode = response?.statusCode {
            return statusCode >= 500
        }
        return true
    })
    .response()
```

### 8. 并发控制

```swift
// 全局并发数限制
ZTGlobalAPIProvider.configure(
    ZTURLSessionProvider(),
    maxConcurrency: 6
)

// 动态调整
ZTGlobalAPIProvider.shared.setMaxConcurrency(10)

// 使用全局 Provider
let result = try await ZTAPI<ZTAPIKVParam>.global("https://api.example.com/data")
    .response()
```

### 9. Combine 支持

```swift
import Combine

// 需要返回 ZTAPI 实例而非直接返回数据
enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    @ZTAPIParam
    enum UserAPIParam {
        case userId(String)
    }

    // 返回 ZTAPI 实例，支持链式调用
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        ZTAPI<UserAPIParam>(baseUrl + "/user/info", .get, provider: provider)
            .params(.userId(userId))
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

## 完整示例：订单模块

```swift
#if canImport(ZTJSON)
import ZTJSON

enum OrderAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    @ZTAPIParam
    enum OrderParam {
        case orderId(String)
        case productId(String)
        case quantity(Int)
        case addressId(String)
        case status(OrderStatus)
        case startDate(Date)
        case endDate(Date)
        case page(Int)
        case pageSize(Int)
    }

    private static func makeApi<P: ZTAPIParamProtocol>(
        _ path: String, _ method: ZTHTTPMethod = .get
    ) -> ZTAPI<P> {
        ZTAPI<P>(baseUrl + path, method, provider: provider)
    }

    // 创建订单 - POST 使用 JSONEncoding
    static func create(
        productId: String, quantity: Int, addressId: String
    ) async throws -> OrderDetail {
        try await makeApi("/orders", .post)
            .params(.productId(productId), .quantity(quantity), .addressId(addressId))
            .encoding(ZTJSONEncoding())  // POST 请求使用 JSON 编码
            .response()
    }

    // 订单列表（带筛选）- 直接返回数据
    static func list(
        status: OrderStatus? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        page: Int = 1
    ) async throws -> OrderListResponse {
        var api = makeApi("/orders")
            .params(.page(page), .pageSize(20))
        if let status = status { api = api.params(.status(status)) }
        if let start = startDate { api = api.params(.startDate(start)) }
        if let end = endDate { api = api.params(.endDate(end)) }
        return try await api.response()
    }

    // 订单详情 - 直接返回数据
    static func detail(orderId: String) async throws -> OrderDetail {
        try await makeApi("/orders/\(orderId)").response()
    }

    // 取消订单 - 直接返回数据
    static func cancel(orderId: String) async throws -> EmptyResponse {
        try await makeApi("/orders/\(orderId)/cancel", .post).response()
    }
}

// 使用 - 直接获取数据
let orders: OrderListResponse = try await OrderAPI.list(
    status: .paid,
    page: 1
)

let order: OrderDetail = try await OrderAPI.detail(orderId: "123")
#endif
```

## API 参考

### Provider

| Provider               | 说明                       |
| ---------------------- | -------------------------- |
| `ZTURLSessionProvider` | 基于 URLSession 的原生实现 |
| `ZTAlamofireProvider`  | 基于 Alamofire 的实现      |
| `ZTStubProvider`       | 用于测试的 Mock Provider   |

### Plugin

> 注：以下插件的实现代码在 Demo 工程中，可根据需要复制到项目使用。

| 插件                             | 说明                           |
| -------------------------------- | ------------------------------ |
| `ZTLogPlugin`                    | 请求/响应日志输出              |
| `ZTAuthPlugin`                   | 自动添加认证 Token             |
| `ZTTokenRefreshPlugin`           | 自动刷新过期 Token（并发安全） |
| `ZTJSONDecodePlugin`             | JSON 美化输出                  |
| `ZTDecryptPlugin`                | 响应数据解密                   |
| `ZTResponseHeaderInjectorPlugin` | 注入响应头到数据中             |

### ZTAPI 方法

| 方法                 | 说明                              |
| -------------------- | --------------------------------- |
| `params(_:)`         | 添加请求参数                      |
| `headers(_:)`        | 添加 HTTP 头                      |
| `encoding(_:)`       | 设置参数编码                      |
| `body(_:)`           | 设置原始请求体                    |
| `upload(_:)`         | 上传文件/Data                     |
| `multipart(_:)`      | 设置 Multipart 表单               |
| `timeout(_:)`        | 设置超时时间                      |
| `retry(_:)`          | 设置重试策略                      |
| `uploadProgress(_:)` | 设置上传进度回调                  |
| `jsonDecoder(_:)`    | 配置 JSON 解码器                  |
| `plugins(_:)`        | 添加插件                          |
| `send()`             | 发送请求，返回 Data               |
| `response()`         | 发送请求，返回 Codable 对象       |
| `parseResponse(_:)`  | 发送请求，XPath 解析（需 ZTJSON） |
| `publisher()`        | 返回 Combine Publisher            |
| `global(_:_:)`       | 使用全局 Provider 创建实例        |

### 重试策略

| 策略                              | 说明           |
| --------------------------------- | -------------- |
| `ZTFixedRetryPolicy`              | 固定延迟重试   |
| `ZTExponentialBackoffRetryPolicy` | 指数退避重试   |
| `ZTConditionalRetryPolicy`        | 自定义条件重试 |

### 参数编码

| 编码                  | 说明                                   |
| --------------------- | -------------------------------------- |
| `ZTURLEncoding`       | URL 编码，默认编码，GET/POST 均适用    |
| `ZTJSONEncoding`      | JSON 编码，POST 请求常用                |
| `ZTMultipartEncoding` | Multipart 表单编码，文件上传使用        |

> 提示：POST 请求默认使用 `ZTURLEncoding`，如需发送 JSON 格式需显式指定 `.encoding(ZTJSONEncoding())`

## 系统要求

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## 可选依赖

| 库            | 用途                                              |
| ------------- | ------------------------------------------------- |
| **Alamofire** | 使用 `ZTAlamofireProvider`                        |
| **ZTJSON**    | `@ZTAPIParam` 宏、XPath 解析、`parseResponse(_:)` |

> 注：
> - 内置 Plugin（`ZTLogPlugin`、`ZTAuthPlugin` 等）的实现代码在 Demo 工程中，可根据需要复制到项目使用。
> - `ZTURLSessionProvider`、`ZTAlamofireProvider`、`ZTStubProvider` 的实现代码同样在 Demo 工程中，可根据需要复制到项目使用。

## 许可证

MIT License

## 作者

by zt
