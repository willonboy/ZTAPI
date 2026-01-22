# ZTAPI

ZTAPI is a modern Swift networking library that goes beyond Moya. Through **enum modular encapsulation**, **XPath parsing**, and **macro auto-generation**, it provides a more powerful and concise API management solution than Moya.

## Core Advantages

| Feature          | ZTAPI                                | Moya                        |
| ---------------- | ------------------------------------ | --------------------------- |
| Configuration    | Flexible, no boilerplate             | TargetType protocol, verbose |
| Async Support    | Native async/await                   | Closure-based               |
| Modular API      | enum + static methods, type-safe     | enum associated values, type-safe |
| Parameter Def    | `@ZTAPIParam` macro auto-generation  | Manual parameter construction |
| Key Mapping      | @ZTAPIParam macro auto conversion    | Need keyDecodingStrategy config |
| XPath Parsing    | Native support, direct nested mapping| Manual nested model definition |
| Response Parsing | Codable + ZTJSON (SwiftyJSON) dual mode | Mainly Codable            |
| Concurrency      | Built-in Actor semaphore             | Manual implementation       |
| Plugin System    | 4 hooks, flexible interception       | PluginType (before/after)    |

## Installation

### Swift Package Manager

```
https://github.com/willonboy/ZTAPI.git
```

### CocoaPods

```ruby
# Or install from Git (development version)
pod 'ZTAPI', :git => 'https://github.com/willonboy/ZTAPI.git', :branch => 'main'
```

## Architecture Design

### Provider Design

ZTAPI abstracts the underlying network implementation through the `ZTAPIProvider` protocol, supporting multiple providers:

```swift
/// Provider protocol
protocol ZTAPIProvider: Sendable {
    func request(_ urlRequest: URLRequest, uploadProgress: ZTUploadProgressHandler?) async throws -> (Data, HTTPURLResponse)
}
```

#### Built-in Provider Implementations

> Note: The following provider implementations are in the Demo project. Copy them to your project as needed.

| Provider               | Description                         | Dependencies |
| ---------------------- | ----------------------------------- | ------------ |
| `ZTURLSessionProvider` | Based on native URLSession          | None         |
| `ZTAlamofireProvider`  | Based on Alamofire                  | Alamofire    |
| `ZTStubProvider`       | Mock Provider for unit testing      | None         |

**ZTURLSessionProvider - Native Implementation**

```swift
// Use default URLSession.shared
let provider = ZTURLSessionProvider()

// Use custom URLSession
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 30
let provider = ZTURLSessionProvider(session: URLSession(configuration: config))

// Create API
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: provider)
```

**ZTAlamofireProvider - Alamofire Implementation**

```swift
import Alamofire

// Use default Session
let provider = ZTAlamofireProvider()

// Use custom Session (can configure interceptor, etc.)
let configuration = Configuration()
let session = Session(configuration: configuration)
let provider = ZTAlamofireProvider(session: session)
```

**ZTStubProvider - Test Mock**

```swift
// JSON dictionary stub
let stubs: [String: [String: Any]] = [
    "GET:https://api.example.com/user": ["id": 1, "name": "Jack"],
    "POST:https://api.example.com/login": ["token": "abc123"]
]

let provider = ZTStubProvider.jsonStubs(stubs)

// Stub with delay and status code
let provider = ZTStubProvider(stubs: [
    "GET:https://api.example.com/user": .init(
        statusCode: 200,
        data: jsonData,
        delay: 0.5  // Simulate network latency
    )
])
```

**ZTSSLPinningProvider - SSL Certificate Pinning**

> Note: SSL Pinning implementations are in `ZTAPISecurityPlugin.swift` and `ZTAlamofireSecurityExtension.swift` in the Demo project.

```swift
// Certificate Pinning
let certificates = ZTCertificateLoader.load(from: "myserver") // Load myserver.cer from Bundle
let provider = ZTSSLPinningProvider(mode: .certificate(certificates))

let api = ZTAPI(
    baseURL: "https://api.example.com",
    provider: provider
)

// Public Key Pinning
let certificates = ZTCertificateLoader.load(from: "myserver")
let publicKeys = ZTCertificateLoader.publicKeys(from: certificates)
let provider = ZTSSLPinningProvider(mode: .publicKey(publicKeys))

// Disable validation (development only)
let provider = ZTSSLPinningProvider(mode: .disabled)
```

**Alamofire SSL Pinning**

```swift
import Alamofire

// Certificate Pinning
let provider = ZTAlamofireProvider.certificatePinning(from: "myserver")
let api = ZTAPI(baseURL: "https://api.example.com", provider: provider)

// Public Key Pinning
let provider = ZTAlamofireProvider.publicKeyPinning(from: "myserver")

// Disable validation (development only)
let provider = ZTAlamofireProvider.insecureProvider()
```

**Getting Server Certificates**

```bash
# Export certificate from server
openssl s_client -connect api.example.com:443 -showcerts

# Save certificate as .cer or .der format
# Add to project Bundle
```

### Plugin Mechanism

The plugin system implements request/response interception and enhancement through the `ZTAPIPlugin` protocol:

```swift
/// Plugin protocol
protocol ZTAPIPlugin: Sendable {
    /// Request about to be sent (can modify request)
    func willSend(_ request: inout URLRequest) async throws

    /// Response received
    func didReceive(_ response: HTTPURLResponse, data: Data) async throws

    /// Error occurred
    func didCatch(_ error: Error) async throws

    /// Process response data (can modify returned data)
    func process(_ data: Data, response: HTTPURLResponse) async throws -> Data
}
```

#### Example Plugins

> Note: The following plugin implementations are in the Demo project. Copy them to your project as needed.

| Plugin                          | Description                              |
| ------------------------------- | ---------------------------------------- |
| `ZTLogPlugin`                   | Request/response logging                 |
| `ZTAuthPlugin`                  | Auto-add authentication Token            |
| `ZTTokenRefreshPlugin`          | Auto-refresh expired Token (thread-safe) |
| `ZTJSONDecodePlugin`            | JSON pretty print                        |
| `ZTDecryptPlugin`               | Response data decryption                 |
| `ZTResponseHeaderInjectorPlugin`| Inject response headers into data        |

#### Custom Plugin Example

```swift
/// Request signing plugin
struct ZTSignPlugin: ZTAPIPlugin {
    let appKey: String
    let appSecret: String

    func willSend(_ request: inout URLRequest) async throws {
        guard let url = request.url else { return }

        // Add timestamp
        let timestamp = String(Int(Date().timeIntervalSince1970))
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")

        // Generate signature
        let sign = "\(appKey)\(timestamp)\(appSecret)".md5
        request.setValue(sign, forHTTPHeaderField: "X-Sign")
    }
}

/// Usage
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTSignPlugin(appKey: "xxx", appSecret: "yyy"))
    .response()
```

### Error Handling

#### ZTAPIError

ZTAPI uses a unified `ZTAPIError` type for all errors:

```swift
public struct ZTAPIError: Error {
    public let code: Int           // Error code
    public let msg: String         // Error message
    public private(set) var httpResponse: HTTPURLResponse?  // Associated HTTP response (read-only)
}
```

**Built-in Error Definitions** (recommended):

```swift
// Common errors 80000-80999
ZTAPIError.invalidURL              // URL is nil
ZTAPIError.invalidURL(urlStr)      // Invalid URL format
ZTAPIError.invalidParams           // Invalid request parameters
ZTAPIError.invalidResponse         // Invalid response type
ZTAPIError.emptyResponse           // Empty response
ZTAPIError.uploadRequiresBody      // Upload requires httpBody

// JSON related errors 81000-81999
ZTAPIError.invalidJSONObject       // Parameters contain non-JSON-serializable objects
ZTAPIError.jsonEncodingFailed(msg) // JSON encoding failed
ZTAPIError.jsonParseFailed(msg)    // JSON parsing failed
ZTAPIError.invalidResponseFormat   // Invalid response format
ZTAPIError.unsupportedPayloadType  // Unsupported payload type

// XPath related errors 82000-82999
ZTAPIError.xpathParseFailed(xpath) // XPath parsing failed

// File related errors 83000-83999
ZTAPIError.fileReadFailed(path, msg) // File read failed
```

#### Error Conversion Rules

| Error Source          | Conversion Behavior                          |
| --------------------- | -------------------------------------------- |
| NSError and subclasses (URLError, etc.) | Auto-convert to ZTAPIError, extract code and localizedDescription |
| Already ZTAPIError    | Pass through directly                        |
| Other custom Error    | Throw as-is, use ZTTransferErrorPlugin to handle |

#### Notes for Custom Provider/Plugin

**Please always throw `ZTAPIError` type** to ensure retry policies and error handling work correctly:

```swift
// ✅ Correct: Use built-in error definitions
public func request(...) async throws -> (Data, HTTPURLResponse) {
    guard let url = request.url else {
        throw ZTAPIError.invalidURL
    }
    // ...
}

// ✅ Correct: Dynamic parameter errors
public func request(...) async throws -> (Data, HTTPURLResponse) {
    guard let url = URL(string: urlStr) else {
        throw ZTAPIError.invalidURL(urlStr)
    }
    // ...
}

// ❌ Wrong: Throw other types
public func request(...) async throws -> (Data, HTTPURLResponse) {
    guard let url = request.url else {
        throw MyCustomError()  // Retry policy cannot recognize
    }
}
```

If you must use custom error types, use `ZTTransferErrorPlugin` for conversion:

```swift
struct MyError: Error { ... }

let provider = MyProvider()
let api = ZTAPI<ZTAPIKVParam>("...", .get, provider: provider)
    .plugins(ZTTransferErrorPlugin { error in
        // Convert custom error to ZTAPIError
        if let myError = error as? MyError {
            return ZTAPIError(myError.code, myError.message)
        }
        return error
    })
```

## Core Usage

### 1. @ZTAPIParam Macro - Minimal Parameter Definition

Using `@ZTAPIParam` macro, just declare cases to auto-generate parameter code (requires ZTJSON):

```swift
#if canImport(ZTJSON)
import ZTAPI
import ZTJSON

enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    // Macro auto-generates: key, value, isValid
    // Auto-converts: userName → user_name
    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)
        case password(String)
        // Optional parameter: this parameter is optional, not included in isValid validation
        case email(String?)
        // Custom parameter name: userId → "uid"
        @ZTAPIParamKey("uid")
        case userId(String)
    }

    // Usage
    static func login(userName: String, password: String, email: String? = nil) async throws -> LoginResponse {
        var api = ZTAPI<UserAPIParam>(baseUrl + "/user/login", .post, provider: provider)
            .params(.userName(userName), .password(password))
        // email parameter is optional, won't be added to request when nil
        if let email = email {
            api = api.params(.email(email))
        }
        return try await api.response()
    }
}
// Auto-generated key mapping:
// userName → "user_name" (required, error if not provided)
// password → "password" (required, error if not provided)
// email → "email" (optional)
// userId → "uid" (required, customized via @ZTAPIParamKey)
//
// isValid auto-validates: non-Optional parameters must exist, otherwise throws exception
#endif
```

**Compared to manual implementation:**

```swift
// Manual implementation without ZTJSON
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
        case .userId: return "uid"  // Custom parameter name
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

    // Non-Optional parameters must exist
    static func isValid(_ params: [String: Sendable]) -> Bool {
        params["user_name"] != nil && params["password"] != nil && params["uid"] != nil
    }
}
```

### 2. Modular API Encapsulation

Complete example showing the power of modular encapsulation (requires ZTJSON if using @ZTAPIParam):

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

    // Login - returns data directly
    static func login(userName: String, password: String) async throws -> LoginResponse {
        try await makeApi("/user/login", .post)
            .params(.userName(userName), .password(password))
            .response()
    }

    // Get user info - returns data directly
    static func userInfo(userId: String) async throws -> UserInfoResponse {
        try await makeApi("/user/info")
            .params(.userId(userId))
            .response()
    }

    // User list - returns data directly
    static func userList() async throws -> [User] {
        try await makeApi("/users").response()
    }
}

// Usage - get data directly
let response = try await UserCenterAPI.login(userName: "jack", password: "123456")
let users: [User] = try await UserCenterAPI.userList()
#endif
```

### 3. XPath Parsing

Directly map JSON nested paths to model properties without defining nested structures:

```swift
#if canImport(ZTJSON)
import ZTJSON

@ZTJSON
struct User {
    let id: Int
    let name: String

    // XPath: address/city → city
    @ZTJSONKey("address/city")
    var city: String = ""

    // XPath: address/geo/lat → lat
    @ZTJSONKey("address/geo/lat")
    var lat: Double = 0

    @ZTJSONKey("address/geo/lng")
    var lng: Double = 0
}

// JSON response:
// { "id": 1, "name": "Jack", "address": { "city": "Beijing", "geo": { "lat": 39.9, "lng": 116.4 } } }
// No need to define Address, Geo nested models!
#endif
```

### 4. Runtime XPath Parsing

> Use case: When you only need a few nested fields from JSON, use runtime parsing to avoid defining complete models for each field, reducing model bloat.

```swift
#if canImport(ZTJSON)
// Parse multiple XPath paths simultaneously
let results = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .parseResponse(
        // isAllowMissing: true (default) - doesn't error when field missing, returns nil
        ZTAPIParseConfig("/data/user/name", type: String.self),
        // isAllowMissing: false - throws exception when field missing
        ZTAPIParseConfig("/data/user/age", type: Int.self, false),
        ZTAPIParseConfig("/data/posts", type: [Post].self)
    )

// Get parsing results
if let name = results["/data/user/name"] as? String {
    print("Username: \(name)")
}
if let age = results["/data/user/age"] as? Int {
    print("Age: \(age)")
}
if let posts = results["/data/posts"] as? [Post] {
    print("Posts count: \(posts.count)")
}
#endif
```

### 5. Plugin Usage

> Note: The following plugin implementations are in the Demo project. Copy them to your project as needed.

#### Log Plugin

```swift
// Verbose logging
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTLogPlugin(level: .verbose))
    .response()

// Simple logging
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTLogPlugin(level: .simple))
    .response()
```

#### Auth Plugin

```swift
// Static Token
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/protected")
    .plugins(ZTAuthPlugin(token: { "my-token" }))
    .response()

// Dynamic Token (read from local storage)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/protected")
    .plugins(ZTAuthPlugin(token: { Keychain.loadToken() }))
    .response()
```

#### Token Refresh Plugin (Thread-Safe)

```swift
// Auto-refresh expired Token, use Actor to ensure thread safety
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTTokenRefreshPlugin(
        shouldRefresh: { error in
            // Check if Token refresh is needed
            (error as? ZTAPIError)?.code == 401
        },
        refresh: {
            // Execute refresh logic
            let newToken = try await APIService.refreshToken()
            return newToken
        },
        onRefresh: { newToken in
            // Callback after successful refresh
            Keychain.saveToken(newToken)
        },
        useSingleFlight: true  // Enable single-flight mode to prevent concurrent refresh
    ))
    .response()
```

#### Response Processing Plugins

```swift
// JSON pretty print
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTJSONDecodePlugin())
    .response()

// Data decryption
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/encrypted")
    .plugins(ZTDecryptPlugin(decrypt: { data in
        try CryptoHelper.decrypt(data)
    }))
    .response()

// Inject response headers
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data")
    .plugins(ZTResponseHeaderInjectorPlugin())
    .response()
```

### 6. File Upload

```swift
// Upload single file
let imageData = try Data(contentsOf: imageURL)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
    .uploadProgress { progress in
        print("Upload progress: \(progress.fractionCompleted * 100)%")
    }
    .response()

// Multi-file mixed upload
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post)
    .upload(
        .data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
        .file(fileURL, name: "document", mimeType: .pdf)
    )
    .params(.kv("userId", "123"))
    .response()
```

### 7. Retry Policy

```swift
// Fixed count retry
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 1.0))
    .response()

// Exponential backoff retry
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable")
    .retry(ZTExponentialBackoffRetryPolicy(
        maxAttempts: 5,
        baseDelay: 1.0,
        multiplier: 2.0
    ))
    .response()

// Custom condition retry
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/custom")
    .retry(ZTConditionalRetryPolicy(maxAttempts: 3, delay: 2.0) {
        request, error, attempt, response in
        // Only retry on 5xx errors
        if let statusCode = response?.statusCode {
            return statusCode >= 500
        }
        return true
    })
    .response()
```

### 8. Concurrency Control

```swift
// Global concurrency limit
ZTGlobalAPIProvider.configure(
    ZTURLSessionProvider(),
    maxConcurrency: 6
)

// Dynamic adjustment
ZTGlobalAPIProvider.shared.setMaxConcurrency(10)

// Use global Provider
let result = try await ZTAPI<ZTAPIKVParam>.global("https://api.example.com/data")
    .response()
```

### 9. Combine Support

```swift
import Combine

// Need to return ZTAPI instance instead of directly returning data
enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }
    static var provider: any ZTAPIProvider { ZTURLSessionProvider() }

    @ZTAPIParam
    enum UserAPIParam {
        case userId(String)
    }

    // Return ZTAPI instance, supports chain calls
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        ZTAPI<UserAPIParam>(baseUrl + "/user/info", .get, provider: provider)
            .params(.userId(userId))
    }
}

// Use Combine
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

## Complete Example: Order Module

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

    // Create order - POST uses JSONEncoding
    static func create(
        productId: String, quantity: Int, addressId: String
    ) async throws -> OrderDetail {
        try await makeApi("/orders", .post)
            .params(.productId(productId), .quantity(quantity), .addressId(addressId))
            .encoding(ZTJSONEncoding())  // POST request uses JSON encoding
            .response()
    }

    // Order list (with filter) - returns data directly
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

    // Order detail - returns data directly
    static func detail(orderId: String) async throws -> OrderDetail {
        try await makeApi("/orders/\(orderId)").response()
    }

    // Cancel order - returns data directly
    static func cancel(orderId: String) async throws -> EmptyResponse {
        try await makeApi("/orders/\(orderId)/cancel", .post).response()
    }
}

// Usage - get data directly
let orders: OrderListResponse = try await OrderAPI.list(
    status: .paid,
    page: 1
)

let order: OrderDetail = try await OrderAPI.detail(orderId: "123")
#endif
```

## API Reference

### Provider

| Provider                   | Description                       | Dependencies |
| -------------------------- | --------------------------------- | ------------ |
| `ZTURLSessionProvider`     | Native URLSession-based implementation | None         |
| `ZTAlamofireProvider`      | Alamofire-based implementation    | Alamofire    |
| `ZTStubProvider`           | Mock Provider for testing         | None         |
| `ZTSSLPinningProvider`     | SSL Certificate Pinning (URLSession) | None         |

**SSL Pinning Components:**
| Class                     | Description                       |
| ------------------------- | --------------------------------- |
| `ZTSSLPinningMode`        | Pinning mode enum (certificate/publicKey/disabled) |
| `ZTCertificateLoader`     | Certificate loading utility       |
| `ZTSSLPinningValidator`   | Certificate validation logic      |

### Plugin

> Note: The following plugin implementations are in the Demo project. Copy them to your project as needed.

| Plugin                          | Description                              |
| ------------------------------- | ---------------------------------------- |
| `ZTLogPlugin`                   | Request/response logging                 |
| `ZTAuthPlugin`                  | Auto-add authentication Token            |
| `ZTTokenRefreshPlugin`          | Auto-refresh expired Token (thread-safe) |
| `ZTJSONDecodePlugin`            | JSON pretty print                        |
| `ZTDecryptPlugin`               | Response data decryption                 |
| `ZTResponseHeaderInjectorPlugin`| Inject response headers into data        |

### ZTAPI Methods

| Method                | Description                              |
| --------------------- | ---------------------------------------- |
| `params(_:)`          | Add request parameters                   |
| `headers(_:)`         | Add HTTP headers                         |
| `encoding(_:)`        | Set parameter encoding                   |
| `body(_:)`            | Set raw request body                     |
| `upload(_:)`          | Upload files/Data                        |
| `multipart(_:)`       | Set Multipart form                       |
| `timeout(_:)`         | Set timeout                              |
| `retry(_:)`           | Set retry policy                         |
| `uploadProgress(_:)`  | Set upload progress callback             |
| `jsonDecoder(_:)`     | Configure JSON decoder                   |
| `plugins(_:)`         | Add plugins                              |
| `send()`              | Send request, return Data                |
| `response()`          | Send request, return Codable object      |
| `parseResponse(_:)`   | Send request, XPath parsing (requires ZTJSON) |
| `publisher()`         | Return Combine Publisher                 |
| `global(_:_:)`        | Create instance using global Provider    |

### Retry Policy

| Policy                           | Description              |
| -------------------------------- | ------------------------ |
| `ZTFixedRetryPolicy`             | Fixed delay retry        |
| `ZTExponentialBackoffRetryPolicy`| Exponential backoff retry|
| `ZTConditionalRetryPolicy`       | Custom condition retry   |

### Parameter Encoding

| Encoding              | Description                                    |
| --------------------- | ---------------------------------------------- |
| `ZTURLEncoding`       | URL encoding, default, for GET/POST           |
| `ZTJSONEncoding`      | JSON encoding, commonly used for POST requests |
| `ZTMultipartEncoding` | Multipart form encoding, for file uploads     |

> Tip: POST requests default to `ZTURLEncoding`. To send JSON format, explicitly specify `.encoding(ZTJSONEncoding())`

## System Requirements

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## Optional Dependencies

| Library    | Usage                                      |
| ---------- | ------------------------------------------ |
| **Alamofire** | Use `ZTAlamofireProvider`                 |
| **ZTJSON**  | `@ZTAPIParam` macro, XPath parsing, `parseResponse(_:)` |

> Note:
> - Built-in Plugin implementations (`ZTLogPlugin`, `ZTAuthPlugin`, etc.) are in the Demo project. Copy them to your project as needed.
> - `ZTURLSessionProvider`, `ZTAlamofireProvider`, `ZTStubProvider` implementations are also in the Demo project. Copy them to your project as needed.

## License

AGPL v3 License

## Author

by zt
