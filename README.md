# ZTAPI

ZTAPI 是一个超越 Moya 的现代化 Swift 网络请求库。通过 **enum 模块化封装**、**XPath 解析**、**宏自动生成**，提供比 Moya 更强大、更简洁的 API 管理方案。

## 核心优势

| 特性 | ZTAPI | Moya |
|------|-------|------|
| 模块化封装 | enum + 静态方法，类型安全 | enum 关联值，类型安全 |
| 参数定义 | `@ZTAPIParam` 宏自动生成，3 行代码 | 嵌套 CodingKeys，10+ 行代码 |
| Key 映射 | 自动 camelCase → snake_case | 手动 CodingKeys 映射 |
| XPath 解析 | 原生支持，直接映射嵌套字段 | 需手动定义嵌套模型 |
| 响应解析 | Codable + ZTJSON 双模式 | 仅 Codable |
| 并发控制 | 内置 Actor 信号量 | 需自行实现 |
| 内置插件 | 6 种开箱即用插件 | 需自行实现 |

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

## 核心用法

### 1. @ZTAPIParam 宏 - 极简参数定义

使用 `@ZTAPIParam` 宏，一行 case 定义即可完成参数：

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
        case userId(String)
    }

    // 使用
    static func login(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        ZTAPI<UserAPIParam>(baseUrl + "/user/login", .post, provider: provider)
            .params(.userName(userName), .password(password))
    }
}

// 自动生成的 key 映射：
// userName → "user_name"
// password → "password"
// userId → "user_id"
```

**对比手动实现：**

```swift
// 无 ZTJSON 时需要手写
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

    static func isValid(_ params: [String: Sendable]) -> Bool { true }
}
```

### 2. 模块化 API 封装

完整示例展示模块化封装的威力：

```swift
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
        _ path: String, _ method: ZTHTTPMethod
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
        try await makeApi("/user/info", .get)
            .params(.userId(userId))
            .response()
    }

    // 用户列表 - 直接返回数据
    static func userList() async throws -> [User] {
        try await makeApi("/users", .get).response()
    }
}

// 使用 - 直接获取数据，无需 .response()
let response = try await UserCenterAPI.login(userName: "jack", password: "123456")
let users: [User] = try await UserCenterAPI.userList()
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

```swift
#if canImport(ZTJSON)
// 同时解析多个 XPath 路径
let results = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .parseResponse(
        ZTAPIParseConfig("/data/user/name", type: String.self),
        ZTAPIParseConfig("/data/user/age", type: Int.self),
        ZTAPIParseConfig("/data/posts", type: [Post].self)
    )

if let name: String = results["/data/user/name"] {
    print("用户名: \(name)")
}
#endif
```

### 5. 内置插件

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
    baseProvider: ZTURLSessionProvider(),
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
enum OrderAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    @ZTAPIParam
    enum OrderParam {
        case orderId(String)
        case status(OrderStatus)
        case startDate(Date)
        case endDate(Date)
        case page(Int)
        case pageSize(Int)
    }

    private static func makeApi<P: ZTAPIParamProtocol>(
        _ path: String, _ method: ZTHTTPMethod
    ) -> ZTAPI<P> {
        ZTAPI<P>(baseUrl + path, method, provider: provider)
    }

    // 创建订单 - 直接返回数据
    static func create(
        productId: String, quantity: Int, addressId: String
    ) async throws -> OrderDetail {
        try await makeApi("/orders", .post)
            .params(.productId(productId), .quantity(quantity), .addressId(addressId))
            .encoding(ZTJSONEncoding())
            .response()
    }

    // 订单列表（带筛选）- 直接返回数据
    static func list(
        status: OrderStatus? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        page: Int = 1
    ) async throws -> OrderListResponse {
        var api = makeApi("/orders", .get)
            .params(.page(page), .pageSize(20))
        if let status = status { api = api.params(.status(status)) }
        if let start = startDate { api = api.params(.startDate(start)) }
        if let end = endDate { api = api.params(.endDate(end)) }
        return try await api.response()
    }

    // 订单详情 - 直接返回数据
    static func detail(orderId: String) async throws -> OrderDetail {
        try await makeApi("/orders/\(orderId)", .get).response()
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
```

## 内置插件列表

| 插件 | 说明 |
|------|------|
| `ZTLogPlugin` | 请求/响应日志输出 |
| `ZTAuthPlugin` | 自动添加认证 Token |
| `ZTTokenRefreshPlugin` | 自动刷新过期 Token（并发安全） |
| `ZTJSONDecodePlugin` | JSON 美化输出 |
| `ZTDecryptPlugin` | 响应数据解密 |
| `ZTResponseHeaderInjectorPlugin` | 注入响应头到数据中 |

## API 参考

### ZTAPI 方法

| 方法 | 说明 |
|------|------|
| `params(_:)` | 添加请求参数 |
| `headers(_:)` | 添加 HTTP 头 |
| `encoding(_:)` | 设置参数编码 |
| `body(_:)` | 设置原始请求体 |
| `upload(_:)` | 上传文件/Data |
| `multipart(_:)` | 设置 Multipart 表单 |
| `timeout(_:)` | 设置超时时间 |
| `retry(_:)` | 设置重试策略 |
| `uploadProgress(_:)` | 设置上传进度回调 |
| `jsonDecoder(_:)` | 配置 JSON 解码器 |
| `plugins(_:)` | 添加插件 |
| `send()` | 发送请求，返回 Data |
| `response()` | 发送请求，返回 Codable 对象 |
| `parseResponse(_:)` | 发送请求，XPath 解析（需 ZTJSON） |
| `publisher()` | 返回 Combine Publisher |
| `global(_:_:)` | 使用全局 Provider 创建实例 |

### 重试策略

| 策略 | 说明 |
|------|------|
| `ZTFixedRetryPolicy` | 固定延迟重试 |
| `ZTExponentialBackoffRetryPolicy` | 指数退避重试 |
| `ZTConditionalRetryPolicy` | 自定义条件重试 |

### 参数编码

| 编码 | 说明 |
|------|------|
| `ZTURLEncoding` | URL 编码 |
| `ZTJSONEncoding` | JSON 编码 |
| `ZTMultipartEncoding` | Multipart 表单编码 |

## 系统要求

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## 可选依赖

| 库 | 用途 |
|------|------|
| **Alamofire** | 使用 `ZTAlamofireProvider` |
| **ZTJSON** | `@ZTAPIParam` 宏、XPath 解析、`parseResponse(_:)` |

## 许可证

MIT License

## 作者

by zt
