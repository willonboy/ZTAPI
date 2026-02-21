# ZTAPI

## Fluent Chain DSL

ZTAPI adopts **Fluent Interface / Builder pattern**, where all configuration methods return `Self` and are marked with `@discardableResult`:

```swift
import ZTAPI

// Complete chain DSL example
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users", .get, provider: ZTURLSessionProvider.shared)
    .params(.kv("id", 123), .kv("include", "profile"))
    .headers(.h(key: "Authorization", value: "Bearer xxx"))
    .timeout(30)
    .retry(ZTExponentialBackoffRetryPolicy(maxAttempts: 3))
    .upload(.data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg))
    .uploadProgress { progress in
        print("Upload progress: \(progress.fractionCompleted)")
    }
    .plugins(logPlugin, authPlugin)
    .response()
```

**DSL Methods:**

| Method | Description |
|--------|-------------|
| `.params(...)` | Add request parameters |
| `.headers(...)` | Add HTTP headers |
| `.encoding(...)` | Set parameter encoding |
| `.body(...)` | Set raw request body |
| `.upload(...)` | Upload file(s) |
| `.multipart(...)` | Set multipart form |
| `.timeout(...)` | Set timeout interval |
| `.retry(...)` | Set retry policy |
| `.uploadProgress(...)` | Upload progress callback |
| `.plugins(...)` | Add plugins |

---

ZTAPI is a modern Swift networking library that goes beyond Moya. Through **enum modular encapsulation**, **XPath parsing**, and **macro auto-generation**, it provides a more powerful and concise API management solution than Moya.

## ZTAPICore Advantages

| Feature          | ZTAPI                                | Moya                        |
| ---------------- | ------------------------------------ | --------------------------- |
| Configuration    | Flexible, no boilerplate             | TargetType protocol, verbose |
| Async Support    | Native async/await                   | Closure-based               |
| Modular API      | enum + static methods, type-safe     | enum associated values, type-safe |
| Parameter Def    | `@ZTAPIParam` macro auto-generation  | Manual parameter construction |
| XPath Parsing    | Native support, direct nested mapping| Manual nested model definition |
| Response Parsing | Codable + ZTJSON (SwiftyJSON) dual mode | Mainly Codable            |
| Plugin System    | 4 hooks, flexible interception       | PluginType (before/after)    |

## Installation

### Swift Package Manager

**Full features (ZTAPICore + ZTAPIXPath + ZTAPIParamMacro):**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPI", package: "ZTAPI")  // Includes ZTAPICore + ZTAPIXPath + ZTAPIParamMacro
        ]
    )
]
```

**ZTAPICore only (no third-party dependency):**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI")  // ZTAPICore features only
        ]
    )
]
```

**ZTAPICore + ZTAPIParamMacro (with macro support):**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI"),
            .product(name: "ZTAPIParamMacro", package: "ZTAPI")  // Enables @ZTAPIParam macro
        ]
    )
]
```

**ZTAPICore + ZTAPIXPath (with XPath parsing):**
```swift
dependencies: [
    .package(url: "https://github.com/willonboy/ZTAPI.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ZTAPICore", package: "ZTAPI"),
            .product(name: "ZTAPIXPath", package: "ZTAPI")  // Enables XPath parsing
        ]
    )
]
```

### CocoaPods

```ruby
pod 'ZTAPI', :git => 'https://github.com/willonboy/ZTAPI.git', :branch => 'main'
```

---

## Quick Start

> Note: `ZTAPI` requires a concrete `provider:` for each request. The examples below use `ZTURLSessionProvider.shared` from the Demo project provider implementations.

The simplest GET request:

```swift
import ZTAPI

// Get data directly
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", provider: ZTURLSessionProvider.shared)
    .response()

// With parameters
let users: [User] = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users", provider: ZTURLSessionProvider.shared)
    .params(.kv("page", 1), .kv("size", 20))
    .response()
```

POST request:

```swift
// URL-encoded form (default)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/login", .post, provider: ZTURLSessionProvider.shared)
    .params(.kv("username", "jack"), .kv("password", "123456"))
    .response()

// JSON body
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/login", .post, provider: ZTURLSessionProvider.shared)
    .params(.kv("username", "jack"), .kv("password", "123456"))
    .encoding(ZTJSONEncoding())
    .response()
```

---

## Basic Usage

### Response Models

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

### Common HTTP Methods

```swift
// GET
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", provider: ZTURLSessionProvider.shared).response()

// POST
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/users", .post, provider: ZTURLSessionProvider.shared)
    .params(.kv("name", "Jack"), .kv("email", "jack@example.com"))
    .response()

// PUT
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .put, provider: ZTURLSessionProvider.shared)
    .params(.kv("name", "Jack Updated"))
    .response()

// DELETE
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .delete, provider: ZTURLSessionProvider.shared).response()
```

### Headers & Timeout

```swift
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data", provider: ZTURLSessionProvider.shared)
    .headers(.h(key: "Authorization", value: "Bearer token123"), .h(key: "Accept", value: "application/json"))
    .timeout(30)
    .response()
```

### Raw Data Response

```swift
// Get raw Data
let data = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data", provider: ZTURLSessionProvider.shared).send()

// Get raw String
let text = String(decoding: data, as: UTF8.self)
```

### Dictionary Response

Get response as dictionary without defining models:

```swift
// Get as [String: Any] dictionary
let dict = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data", provider: ZTURLSessionProvider.shared)
    .responseDict()

// Access fields
dict["name"] as? String
dict["age"] as? Int
```

### Error Handling

```swift
do {
    let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", provider: ZTURLSessionProvider.shared).response()
} catch let error as ZTAPIError {
    print("Error \(error.code): \(error.msg)")
    // Handle error by code
    switch error.code {
    case 401: print("Unauthorized")
    case 404: print("Not found")
    default: print("Other error")
    }
}
```

---

## Advanced Usage

### 1. @ZTAPIParam Macro - Type-Safe Parameters

Using `@ZTAPIParam` macro (requires ZTAPIParamMacro) to generate type-safe parameters with automatic key mapping:

```swift
import ZTAPIParamMacro

enum UserCenterAPI {
    static var baseUrl: String { "https://api.example.com" }

    // Macro auto-generates: key, value, isValid
    // Auto-converts: userName → user_name (camelCase to snake_case)
    @ZTAPIParam
    enum UserAPIParam {
        case userName(String)      // → "user_name" (required)
        case password(String)      // → "password" (required)
        // Optional parameter: this parameter is optional, not included in isValid validation
        case email(String?)        // → "email" (optional)
        // Custom parameter name: userId → "uid"
        @ZTAPIParamKey("uid")
        case userId(String)        // → "uid" (required)
    }

    // Usage
    static func login(userName: String, password: String, email: String? = nil) async throws -> LoginResponse {
        var api = ZTAPI<UserAPIParam>(baseUrl + "/user/login", .post)
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
```

**Compared to manual implementation:**

```swift
// Manual implementation without macro
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

Organize your APIs into modules with enum. Recommended pattern - define endpoints internally and return `ZTAPI` instances for chain calls and Combine support:

```swift
enum UserCenterAPI {
    // Define endpoints internally
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

        // Unified configuration with build()
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

    // Login - returns ZTAPI instance for chain calls
    static func login(userName: String, password: String) -> ZTAPI<UserAPIParam> {
        API.login.build()
            .params(.userName(userName), .password(password))
    }

    // Get user info
    static func userInfo(userId: String) -> ZTAPI<UserAPIParam> {
        API.userInfo.build()
            .params(.userId(userId))
    }

    // User list - returns ZTAPI instance
    static var userList: ZTAPI<ZTAPIKVParam> {
        API.userList.build()
    }
}

// Usage - call .response() to get data
let response: LoginResponse = try await UserCenterAPI.login(userName: "jack", password: "123456").response()
let users: [User] = try await UserCenterAPI.userList.response()
```

### 3. XPath Parsing

Parse nested JSON fields without defining nested structures (requires ZTJSON):

```swift
#if canImport(ZTJSON)
import ZTJSON

@ZTJSON
struct User {
    let id: Int
    let name: String

    // Directly map nested paths
    @ZTJSONKey("address/city")
    var city: String = ""

    @ZTJSONKey("address/geo/lat")
    var lat: Double = 0

    @ZTJSONKey("address/geo/lng")
    var lng: Double = 0
}

// JSON: { "id": 1, "name": "Jack", "address": { "city": "Beijing", "geo": { "lat": 39.9, "lng": 116.4 } } }
// No need to define Address, Geo nested models!

let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/1", provider: ZTURLSessionProvider.shared).response()
#endif
```

### 4. Runtime XPath Parsing

> XPath parsing extension is in `ZTAPIXPath` module (requires ZTJSON).

Parse multiple XPath paths at runtime without defining models:

```swift
#if canImport(ZTJSON)
let results = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data", provider: ZTURLSessionProvider.shared)
    .parseResponse(
        // isAllowMissing: true (default) - doesn't error when field missing, returns nil
        ZTAPIParseConfig("/data/user/name", type: String.self),
        // isAllowMissing: false - throws exception when field missing
        ZTAPIParseConfig("/data/user/age", type: Int.self, false),
        ZTAPIParseConfig("/data/posts", type: [Post].self)
    )

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

### 5. File Upload

```swift
// Upload single Data
let imageData = try Data(contentsOf: imageURL)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: ZTURLSessionProvider.shared)
    .upload(.data(imageData, name: "avatar", fileName: "photo.jpg", mimeType: .jpeg))
    .uploadProgress { progress in
        print("Progress: \(progress.fractionCompleted * 100)%")
    }
    .response()

// Upload single file
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: ZTURLSessionProvider.shared)
    .upload(.file(fileURL, name: "file", mimeType: .txt))
    .response()

// Multi-file mixed upload (Data + File)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/multiple", .post, provider: ZTURLSessionProvider.shared)
    .upload(
        .data(imageData, name: "avatar", fileName: "avatar.jpg", mimeType: .jpeg),
        .file(fileURL, name: "document", mimeType: .pdf)
    )
    .params(.kv("userId", "123"))
    .response()

// Use Multipart for files + form fields
let formData = ZTMultipartFormData()
    .add(.data(Data("file1".utf8), name: "files", fileName: "file1.txt", mimeType: .txt))
    .add(.data(Data("file2".utf8), name: "files", fileName: "file2.txt", mimeType: .txt))
    .add(.data(Data("{\"userId\":\"123\"}".utf8), name: "metadata", mimeType: .json))

let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/multipart", .post, provider: ZTURLSessionProvider.shared)
    .multipart(formData)
    .response()

// Raw body upload
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload/raw", .post, provider: ZTURLSessionProvider.shared)
    .body(Data("raw body data".utf8))
    .headers(.h("Content-Type", ZTMimeType.octetStream.rawValue))
    .response()

// Custom MIME type
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/upload", .post, provider: ZTURLSessionProvider.shared)
    .upload(.data(Data("custom data".utf8), name: "file", mimeType: .custom(ext: "", mime: "application/vnd.example")))
    .response()
```

---

## Advanced Features

### Provider Architecture

ZTAPI abstracts the underlying network implementation through `ZTAPIProvider` protocol, supporting multiple providers:

> Note: Provider implementations are in the Demo project. Copy them to your project as needed.

| Provider               | Description                         | Dependencies |
| ---------------------- | ----------------------------------- | ------------ |
| `ZTURLSessionProvider` | Native URLSession                  | None         |
| `ZTAlamofireProvider`  | Alamofire-based                     | Alamofire    |
| `ZTStubProvider`       | Mock for unit testing               | None         |
| `ZTSSLPinningProvider` | SSL Certificate Pinning (URLSession)| None         |
| `ZTAPICacheProvider`   | In-memory caching with policies     | None         |

```swift
// Use shared provider
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: ZTURLSessionProvider.shared)

// Or with Alamofire
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: ZTAlamofireProvider.shared)

// Or with Cache
let cacheProvider = ZTAPICacheProvider(
    baseProvider: ZTURLSessionProvider.shared,
    readPolicy: .cacheElseNetwork,
    cacheDuration: 300
)
let api = ZTAPI<ZTAPIKVParam>("https://api.example.com/data", .get, provider: cacheProvider)
```

### Cache Provider

> Cache Provider implementation is in `ZTAPICacheProvider.swift` in the Demo project.

The `ZTAPICacheProvider` wraps any provider and adds in-memory caching with configurable policies and LRU eviction:

```swift
// Create cache provider
let cacheProvider = ZTAPICacheProvider(
    baseProvider: ZTURLSessionProvider.shared,
    readPolicy: .cacheElseNetwork,
    cacheDuration: 300               // 5 minutes
)

// Use with ZTAPI
let user: User = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/user/123", .get, provider: cacheProvider)
    .response()
```

**Cache Read Policies:**

| Policy                | Description                              |
| --------------------- | ---------------------------------------- |
| `.networkOnly`        | Only fetch from network, ignore cache    |
| `.cacheOnly`          | Only read from cache, error if miss      |
| `.cacheElseNetwork`   | Try cache first, fallback to network     |
| `.networkElseCache`   | Try network first, fallback to cache on error |

**Cache Write Policies:**

| Policy                | Description                              |
| --------------------- | ---------------------------------------- |
| `.never`              | Never write to cache                     |
| `.always`             | Always write to cache                    |
| `.onSuccess`          | Only write on successful responses (2xx) |

**Cache Management:**

```swift
// Clear all cache
await cacheProvider.clearCache()

// Clear specific URL
await cacheProvider.clearCache(url: "https://api.example.com/user/123")

// Get cache statistics
let stats = await cacheProvider.cacheStats
print("Cache hit rate: \(stats.formattedHitRate)")
print("Cache size: \(stats.formattedSize)")

// Remove expired entries
await cacheProvider.removeExpired()
```

### Plugin System

The plugin system provides 4 hooks for request/response interception:

```swift
protocol ZTAPIPlugin: Sendable {
    func willSend(_ request: inout URLRequest) async throws
    func didReceive(_ response: HTTPURLResponse, data: Data, request: URLRequest) async throws
    func didCatch(_ error: Error, request: URLRequest, response: HTTPURLResponse?, data: Data?) async throws
    func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data
}
```

> Note: Plugin implementations are in the Demo project.

**Built-in Plugins:**

| Plugin                          | Description                              |
| ------------------------------- | ---------------------------------------- |
| `ZTLogPlugin`                   | Request/response logging                 |
| `ZTAuthPlugin`                  | Auto-add authentication Token            |
| `ZTTokenRefreshPlugin`          | Auto-refresh expired Token               |
| `ZTJSONDecodePlugin`            | JSON pretty print                        |
| `ZTDecryptPlugin`               | Response data decryption                 |
| `ZTCheckRespOKPlugin`           | Check business code in response          |
| `ZTReadPayloadPlugin`           | Extract data field from response         |

```swift
// Use plugins
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/data", provider: ZTURLSessionProvider.shared)
    .plugins(ZTLogPlugin(), ZTAuthPlugin { "my-token" })
    .response()
```

**Custom Plugin Example:**

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

### Retry Policy

| Policy                           | Description              |
| -------------------------------- | ------------------------ |
| `ZTFixedRetryPolicy`             | Fixed delay retry        |
| `ZTExponentialBackoffRetryPolicy`| Exponential backoff retry|
| `ZTConditionalRetryPolicy`       | Custom condition retry   |

```swift
// Fixed delay retry
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable", provider: ZTURLSessionProvider.shared)
    .retry(ZTFixedRetryPolicy(maxAttempts: 3, delay: 1.0))
    .response()

// Exponential backoff
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/unstable", provider: ZTURLSessionProvider.shared)
    .retry(ZTExponentialBackoffRetryPolicy(maxAttempts: 5, baseDelay: 1.0, multiplier: 2.0))
    .response()

// Custom condition retry (async closure)
let result = try await ZTAPI<ZTAPIKVParam>("https://api.example.com/custom", provider: ZTURLSessionProvider.shared)
    .retry(ZTConditionalRetryPolicy(maxAttempts: 3, delay: 2.0) {
        request, error, attempt, response in
        // Only retry on 5xx errors
        (response?.statusCode ?? 0) >= 500
    })
    .response()
```

### SSL Pinning

> SSL Pinning implementations are in `ZTAPISecurityPlugin.swift` and `ZTAlamofireSecurityExtension.swift` in the Demo project.

**URLSession SSL Pinning:**

```swift
// Certificate Pinning
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver") // Load myserver.cer from Bundle
let provider = ZTSSLPinningProvider(mode: .certificate(certificates))

// Public Key Pinning
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver")
let publicKeyHashes = ZTCertificateLoader.publicKeyHashes(from: certificates)
let provider = ZTSSLPinningProvider(mode: .publicKey(publicKeyHashes))

// Disable validation (development only)
let provider = ZTSSLPinningProvider(mode: .disabled)
```

**Alamofire SSL Pinning:**

> Note: `ZTAlamofireProvider.pinning(mode:)` supports both certificate pinning and public-key-hash pinning. Host wildcard (`*`) mapping is supported by default.

```swift
import Alamofire

// Certificate Pinning from Bundle
let provider = ZTAlamofireProvider.certificatePinning(from: "myserver")

// Or using pinning(mode:) directly
let certificates = ZTCertificateLoader.loadCertificates(named: "myserver")
let provider = ZTAlamofireProvider.pinning(mode: .certificate(certificates))

// Public Key Hash pinning
let keyHashes = ZTCertificateLoader.publicKeyHashes(from: certificates)
let provider = ZTAlamofireProvider.pinning(mode: .publicKey(keyHashes))

// Disable validation (development only, DEBUG only)
let provider = ZTAlamofireProvider.insecureProvider()
```

Export server certificate:
```bash
openssl s_client -connect api.example.com:443 -showcerts
```

### Concurrency Control

> Global API Provider implementation is in `ZTAPIGlobalManager.swift` in the Demo project.

The global provider comes pre-configured with Alamofire and a concurrency limit of 6:

```swift
// Use global Provider directly (no configuration needed)
let result = try await ZTAPI<ZTAPIKVParam>.global("https://api.example.com/data")
    .response()
```

To customize the global provider (e.g., use URLSession or different concurrency limit), modify the `ZTAPIGlobalManager.provider` in the Demo project.

### Combine Support

> Note: `publisher()` is provided via `ZTAPI+Extension.swift` in the Demo project. Copy it to your project to use Combine support.

```swift
import Combine

enum UserCenterAPI {
    // Return ZTAPI instance for chain calls
    static func userInfo(userId: String) -> ZTAPI<ZTAPIKVParam> {
        ZTAPI<ZTAPIKVParam>("https://api.example.com/user/info", provider: ZTURLSessionProvider.shared)
            .params(.kv("userId", userId))
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

---

## Error Reference

### ZTAPIError Structure

```swift
public struct ZTAPIError: Error {
    public let code: Int           // Error code
    public let msg: String         // Error message
    public let httpResponse: HTTPURLResponse?  // Associated HTTP response
}
```

### Built-in Errors

| Error                  | Code  | Description                      |
| ---------------------- | ----- | -------------------------------- |
| `invalidURL`           | 80000001 | URL is nil                       |
| `invalidParams`        | 80000002 | Invalid request parameters       |
| `invalidResponse`      | 80000003 | Invalid response type            |
| `emptyResponse`        | 80000004 | Empty response                   |
| `uploadRequiresBody`   | 80000005 | Upload requires httpBody         |
| `invalidJSONObject`    | 80010001 | Params contain non-JSON-serializable objects |
| `jsonEncodingFailed`   | 80010002 | JSON encoding failed             |
| `jsonParseFailed`      | 80010003 | JSON parsing failed              |
| `invalidResponseFormat`| 80010004 | Invalid response format          |
| `unsupportedPayloadType`| 80010005 | Unsupported payload type         |
| `fileReadFailed`       | 80030001 | Failed to read file              |
| `xpathParseFailed`     | 80020001 | XPath parsing failed             |

---

## API Reference

### ZTAPI Methods

| Method                | Description                              |
| --------------------- | ---------------------------------------- |
| `params(_:)`          | Add request parameters                   |
| `headers(_:)`         | Add HTTP headers                         |
| `encoding(_:)`        | Set parameter encoding (URL/JSON/Multipart) |
| `body(_:)`            | Set raw request body                     |
| `upload(_:)`          | Upload files/Data                        |
| `timeout(_:)`         | Set timeout                              |
| `retry(_:)`           | Set retry policy                         |
| `uploadProgress(_:)`  | Set upload progress callback             |
| `plugins(_:)`         | Add plugins                              |
| `send()`              | Send request, return Data                |
| `response()`          | Send request, return Codable object      |
| `responseDict()`      | Send request, return [String: Any]       |
| `responseArr()`       | Send request, return [[String: Any]]     |
| `parseResponse(_:)`   | Send request, XPath parsing (requires ZTJSON) |
| `publisher()`         | Return Combine Publisher (requires extension) |

### HTTP Methods

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

### Parameter Encoding

| Encoding              | Description                                    |
| --------------------- | ---------------------------------------------- |
| `ZTURLEncoding`       | URL encoding, default                          |
| `ZTJSONEncoding`      | JSON encoding, for POST requests               |
| `ZTMultipartEncoding` | Multipart form encoding, for file uploads      |

> Tip: POST requests default to `ZTURLEncoding`. Use `.encoding(ZTJSONEncoding())` for JSON body.

---

## System Requirements

- iOS 13.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 6.0+
- Swift 6.0+
- Xcode 16.0+

## Optional Dependencies

| Library       | Usage                                      |
| ------------- | ------------------------------------------ |
| **Alamofire** | Use `ZTAlamofireProvider`                 |
| **ZTJSON**    | XPath parsing                               |
| **SwiftyJSON**| Required by `ZTAPIXPath` product        |

> Note: Built-in Plugin and Provider implementations are in the Demo project. Copy them to your project as needed.

## License

AGPL v3 License

## Author

by zt
