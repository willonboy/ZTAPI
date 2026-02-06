# Network Layer Migration: Moya to ZTAPI

This document describes the standard workflow and considerations for replacing the Moya network layer with ZTAPI.

## Migration Workflow

### 1. Analyze Original API Structure

First analyze the original Moya API file and record:
- Number and names of interfaces
- baseURL source
- HTTP methods (GET/POST)
- Request parameter structure
- Encoding method (URLEncoding/JSONEncoding)
- Whether authentication Token is needed
- Plugin configuration

### 2. Create New ZTAPI File

#### File Structure Template

```swift
//
//  XXXAPI.swift
//  ProjectName
//
//  Created by zt
//

import Foundation
import ZTAPI

/// Module API
enum XXXAPI {
    enum API {
        case custom(url: String, method: ZTHTTPMethod)

        /// Base URL
        private static var baseUrl: String {
            // Get baseURL based on actual project configuration
            AppEnvironment.shared.baseURL
        }

        /// Network request Provider
        private static var provider: any ZTAPIProvider {
            YourAlamofireProvider.shared
        }

        /// Convenience method for creating API instances
        fileprivate func build<P: ZTAPIParamProtocol>() -> ZTAPI<P> {
            let encoding: ZTParameterEncoding = self.method == .get ? ZTURLEncoding() : ZTJSONEncoding()
            return ZTAPI<P>(API.baseUrl + self.url, self.method, provider: API.provider)
                .encoding(encoding)
                .timeout(30)
                .plugins(
                    // Configure plugins based on project requirements
                    YourRequestPlugin(),
                    YourCheckRespPlugin(),
                    YourPayloadPlugin(),
                    LogPlugin(level: .verbose)
                )
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

        // MARK: Interface Definitions
        static var interfaceName = API.custom(url: "/path", method: .get/.post)
    }

    // MARK: - Interface Methods

    /// Interface description
    static func interfaceName(parameters) async throws -> ReturnType {
        let api: ZTAPI<ZTAPIKVParam> = API.interfaceName.build()
            .params(.kv("parameterName", parameterValue))
        return try await api.response()
    }
}
```

### 3. Key Considerations

#### 3.1 Parameter Complete Alignment Principle

**Core Principle**: Whatever the key was before replacement, it should remain the same after replacement! Whatever parameters were originally required must still be required after replacement!

#### 3.2 Parameter Case Sensitivity

- Check the original API's parameter key casing
- Some interfaces may use PascalCase (e.g., `RoomId`, `LiveId`)
- Some interfaces may use camelCase (e.g., `roomId`, `liveId`)
- Must maintain original casing exactly

#### 3.3 HTTP Method Alignment

- All interfaces default to `.post`
- GET requests explicitly use `.get`

#### 3.4 Encoding Method Selection

- GET requests use `ZTURLEncoding()`
- POST requests use `ZTJSONEncoding()`

#### 3.5 Optional Parameter Handling

For `String?` type parameters at the call site, use `guard let` to unwrap:

```swift
guard let roomId = liveRoomId, let recordId = liveRecordId else {
    HUD.showError("Missing parameters")
    return
}
```

#### 3.6 Avoid Converting Fixed-Type Parameters to `[String: Any]`

**Core Principle**: For interfaces with fixed parameters, use named parameters rather than dictionary parameters.

```swift
// ✅ Recommended: Use named parameters - type safe, clear code, compile-time checking
static func getUserInfo(userId: String) async throws -> UserInfoModel {
    let api: ZTAPI<ZTAPIKVParam> = API.getUserInfo.build()
        .params(["userId": userId])
    return try await api.responseHandyJSON()
}

// Call style: Clear and explicit
let user = try await UserAPI.getUserInfo(userId: userId)

// ❌ Avoid: Use dictionary parameters - loses type safety, unclear code
static func getUserInfo(_ param: [String: Any]) async throws -> UserInfoModel {
    let api: ZTAPI<ZTAPIKVParam> = API.getUserInfo.build()
        .params(param)
    return try await api.responseHandyJSON()
}

// Call style: Need to construct dictionary, error-prone
let user = try await UserAPI.getUserInfo(["userId": userId])
```

**When to use named parameters**:
- Fixed number of parameters (1-5)
- Clear parameter types (String, Int, Bool, etc.)
- Clear parameter meanings (userId, groupId, text, etc.)
- Interface is relatively stable, parameters don't change frequently

**When to use dictionary parameters**:
- Many and variable number of parameters (more than 5)
- Complex parameter types (nested structures, arrays, etc.)
- Parameters may dynamically increase/decrease
- Interface parameters change frequently

#### 3.7 Task Closure Self Capture Rules

**Core Principle: Minimize self capture**

In Task closures, minimize capturing self. If you can pass through local variables, don't capture self. When you must capture self, handle it correctly.

##### 3.7.1 Three Handling Scenarios

**Scenario 1: No self needed at all (only using parameters/local variables)**

```swift
// ✅ Correct - No [weak self] needed
func requestCommunityList(type: XMCommunityListType, pageNo: Int, pageSize: Int, complete: ((Bool, [Model]) -> Void)?) {
    let typeValue = type.rawValue      // Local variable
    let isFirstPage = pageNo == 1      // Local variable
    let pageSizeValue = pageSize        // Local variable

    Task {  // No [weak self] needed
        do {
            let models = try await WJCommunityAPI.postCommunityGroupList(type: typeValue)
            await MainActor.run {
                complete?(true, models)
            }
        } catch {
            await MainActor.run {
                complete?(false, [])
            }
        }
    }
}
```

**Scenario 2: Some parameters from self, but result handling needs self**

```swift
// ✅ Correct - Define local variables outside Task, reduce self capture
func loadData() {
    let typeValue = self.type.rawValue  // Define local variable outside Task

    Task { [weak self] in
        do {
            let models = try await WJCommunityAPI.postCommunityGroupList(type: typeValue)
            await MainActor.run {
                if let self = self {  // Unwrap only inside MainActor.run, minimal scope
                    self.listData = models
                    self.tableView.reloadData()
                }
            }
        } catch {
            await MainActor.run {
                XMProgressHUD.showError("\(error.localizedDescription)")
            }
        }
    }
}

// ❌ Poor style - Capture entire self just for input parameters
Task { [weak self] in
    let models = try await WJCommunityAPI.postCommunityGroupList(type: self.type.rawValue)
    await MainActor.run {
        self?.listData = models
    }
}
```

**Scenario 3: Must use self (calling methods or accessing properties)**

```swift
// ✅ Correct - [weak self] + self? optional chaining
Task { [weak self] in
    do {
        let models = try await WJCommunityAPI.postCommunityGroupList(type: type)
        await MainActor.run {
            self?.listData = models      // Use self? optional chaining
            self?.tableView.reloadData()
        }
    } catch {
        await MainActor.run {
            XMProgressHUD.showError("\(error.localizedDescription)")
        }
    }
}
```

##### 3.7.2 Prohibit [weak self] + guard let self Pattern

**Problem Reason**:

```swift
// ❌ Unsafe pattern
Task { [weak self] in
    guard let self = self else { return }  // self is strongly captured until Task completes
    let result = try await API.call()      // self is strongly referenced during await
    self.updateUI(result)
}
```

When using `[weak self]` + `guard let self`, self is strongly referenced by the guard statement until the entire Task completes (including all await operations). This causes self to be unreleasable during network request waits, potentially causing memory leaks or controllers that cannot be released.

**Correct Pattern Comparison**:

```swift
// ✅ Correct - Use [weak self] + self? optional chaining
Task { [weak self] in
    do {
        let result = try await API.call()
        await MainActor.run {
            self?.updateUI(result)  // self? is always weak reference
        }
    } catch {
        await MainActor.run {
            XMProgressHUD.showError("\(error.localizedDescription)")
        }
    }
}

// ❌ Wrong - [weak self] + guard let self creates strong reference
Task { [weak self] in
    guard let self = self else { return }  // Dangerous! self strongly referenced during await
    let result = try await API.call()
    await MainActor.run {
        self.updateUI(result)
    }
}

// ❌ Also wrong - No [weak self], closure itself strongly references self
Task {  // Closure strongly references self
    let result = try await API.call()
    await MainActor.run {
        self?.updateUI(result)  // self? meaningless, closure already strongly referenced
    }
}
```

##### 3.7.3 Compare with Normal Closures

```swift
// Normal closure (non-Task) can safely use [weak self] + guard let
someClosure = { [weak self] in
    guard let self = self else { return }
    self.doSomething()  // Safe, closure releases immediately after synchronous execution
}

// Task closure needs special handling - Use [weak self] + self?
Task { [weak self] in
    self?.doSomething()  // Optional chaining, never upgrades to strong reference
}
```

##### 3.7.4 Quick Reference Table

| Scenario | Handling |
|----------|----------|
| Only using parameters/local variables | ❌ No `[weak self]` needed |
| Using self properties as input parameters | ✅ Extract local variables first, reduce capture |
| Calling self methods/accessing mutable properties | ✅ Use `[weak self]` + `self?` optional chaining |
| Static methods | ❌ No `[weak self]` needed |

##### 3.7.5 Key Points

- **Minimize capture principle**: Don't capture self if you can pass through local variables
- Must use `Task { [weak self] in` weak reference capture (when self is needed)
- Always use `self?.` optional chaining inside closures
- **Prohibit using `guard let self = self` to upgrade to strong reference**
- **UI operations in catch blocks must also be wrapped with `await MainActor.run`**

#### 3.8 Interface Parameter Migration Principles

**When migrating interfaces, must strictly follow these principles**:

##### 3.8.1 Keep Parameters Completely Consistent

When migrating interfaces, **parameter list, order, and types must be completely consistent with the old Moya interface**.

##### 3.8.2 Handle Hardcoded Values Internally

Hardcoded parameters in old interfaces (e.g., `sendType: 1`) should be handled internally in the method, **not exposed as method parameters**.

##### 3.8.3 Use Default Values for Optional Parameters

Optional parameters should use default values `= nil`, rather than letting the caller decide.

##### 3.8.4 Parameter Order Must Be Consistent

Method parameter order must match the old interface to avoid caller parameter errors.

##### 3.8.5 Migration Checklist

When migrating each interface, must check each item:

- [ ] Parameter names match old interface
- [ ] Parameter count matches old interface (not more, not less)
- [ ] Parameter order matches old interface
- [ ] Parameter types match old interface
- [ ] Hardcoded values handled internally, not exposed as parameters
- [ ] Optional parameters use default values `= nil`
- [ ] Return types match old interface (refer to 10. Interface Return Type Comparison Check)

#### 3.9 Empty Parameter Handling

**Prohibit defining custom empty parameter types**, directly use `ZTAPIKVParam`:

```swift
// ❌ Wrong: Don't define empty parameter types
enum ZTAPIEmptyParamXXX: ZTAPIParamProtocol {
    case empty
    public var key: String { return "" }
    public var value: Sendable { return "" }
    public static func isValid(_ params: [String: Sendable]) -> Bool { return true }
}

// ✅ Correct: Use ZTAPIKVParam
enum XXXAPI {
    enum API {
        fileprivate func build<P: ZTAPIParamProtocol>() -> ZTAPI<P> {
            ZTAPI<P>(API.baseUrl + self.url, self.method, provider: API.provider)
                .encoding(encoding)
                .timeout(30)
                .plugins(...)
        }
    }

    // No parameter interface: directly specify type, don't call .params()
    static func noParamRequest() async throws -> ResponseType {
        let api: ZTAPI<ZTAPIKVParam> = API.noParam.build()
        return try await api.response()
    }
}
```

### 4. Plugin Configuration

#### 4.1 Common Plugin Types

| Plugin Type | Purpose | Description |
| -------------- | ------------------------------- | -------------------- |
| Request header plugin | Add unified request headers (token, signature, etc.) | Required if authentication needed |
| Status code check plugin | Check business status codes | Configure based on backend specifications |
| Data extraction plugin | Extract specific fields from response | Such as auto-extract data field |
| Log plugin | Request/response logging | For debugging/development |

#### 4.2 Plugin Method Signature

**Note**: ZTAPI plugin method signature includes `request` parameter:

```swift
public protocol ZTAPIPlugin {
    func willSend(_ request: inout URLRequest) async throws
    func didReceive(_ response: HTTPURLResponse, data: Data, request: URLRequest) async throws
    func process(_ data: Data, response: HTTPURLResponse, request: URLRequest) async throws -> Data
    func didCatch(_ error: Error, request: URLRequest, response: HTTPURLResponse?) async throws
}
```

### 5. Update Call Sites

#### 5.1 Change Closure Calls to async/await

Original style:
```swift
OldAPI.shared.request_xxx(param: ["key": value]) { result in
    // success
} failure: { error in
    // failure
}
```

New style:
```swift
Task { [weak self] in
    do {
        let result = try await XXXAPI.xxx(parameters)
        await MainActor.run {
            self?.handleResult(result)
        }
    } catch {
        await MainActor.run {
            XMProgressHUD.showError(error.localizedDescription)
        }
    }
}
```

### 6. Response Parsing Methods

| Method | Return Type | Description |
| --------------------- | ----------------- | ------------------- |
| `api.response()` | `T: Decodable` | Return Decodable object |
| `api.responseDict()` | `[String: Any]` | Return dictionary |
| `api.responseArray()` | `[[String: Any]]` | Return dictionary array |

**Note**: If using data extraction plugin (such as auto-extract data field), no need to manually extract again.

### 7. Verification Checklist

- [ ] All interface parameter keys match original API exactly
- [ ] All interface parameter key casing correct
- [ ] HTTP methods correct
- [ ] Encoding methods correct
- [ ] Optional parameters correctly unwrapped
- [ ] **Fixed-parameter interfaces use named parameters, avoid using `[String: Any]`**
- [ ] All call sites updated
- [ ] **Task closures use `[weak self]` + `self?.` instead of `[weak self]` + `guard let self`**
- [ ] **UI operations in catch blocks wrapped with `await MainActor.run`**
- [ ] Delete old Moya API files
- [ ] Plugin configuration correct

### 8. Common Questions

**Q: What casing should parameter keys use?**
A: Check original implementation, maintain exactly. Don't modify on your own.

**Q: How to handle optional parameters?**
A: Use guard let to unwrap at call site, or provide default values.

**Q: Why not check HTTP status codes?**
A: ZTAPI framework automatically throws errors when HTTP status code >= 400.

### 9. Common Bug Cases

#### 9.1 Optional Characters in URL

**Problem**: Request URL contains strings like `Optional(7049)`

**Cause**: Optional type values directly placed in params dictionary in dictionary-type parameters

```swift
// ❌ Wrong pattern
let params: [String : Any] = [
    "communityId": self.communityId,  // Int? type
    "channelId": self.channelId       // Int? type
]
// URL becomes ?communityId=Optional(7049)&channelId=Optional(123)

// ✅ Correct pattern
guard let communityId = self.communityId, let channelId = self.channelId else {
    HUD.showError("Parameter error")
    return
}
let params: [String : Any] = [
    "communityId": communityId,
    "channelId": channelId
]
```

#### 9.2 true/false Characters in URL

**Problem**: GET request returns 400 error, curl shows `isOK=false` instead of `isOK=0`

**Cause**:
- Moya's URLEncoding converts Bool to `0`/`1`
- ZTAPI's ZTURLEncoding uses `"\(value)"` to convert Bool to `"true"`/`"false"`
- Server expects integers `0`/`1`

```swift
// ❌ Wrong pattern
var params: [String: Any] = ["id": contentId, "isOK": isOK]
// URL: ?id=123&isOK=false  → Server returns 400

// ✅ Correct pattern
var params: [String: Any] = ["id": contentId, "isOK": isOK ? 1 : 0]
// URL: ?id=123&isOK=0  → Server processes normally
```

**Fix points**:
- **Bool parameters in GET requests** (using ZTURLEncoding) must be manually converted to `0`/`1`
- **Bool parameters in POST requests** (using ZTJSONEncoding) can remain Bool

#### 9.3 Basic Type data Field Parsing

**Problem**: `Unsupported payload type` error

**Cause**: Server's data field is a basic type (Bool/Int/Double/String), but data extraction plugin only handles Dictionary and Array

**Solution**: Need to add support for basic types in the plugin

---

## [MUST CHECK] 10. Interface Return Type Comparison Check

**[Must Check] Whether interface return types are consistent before and after replacement**

This is a **very critical but easily overlooked** checkpoint. Old Moya interfaces usually parse responses into specific model types through response parsing layer. If new ZTAPI interfaces incorrectly use `responseDict()` to return `[String: Any]`, callers will need to readapt.

### 10.1 Check Method

**Step 1**: Check old interface's success callback return type

**Step 2**: Compare new interface's return type

**Step 3**: Choose correct parsing method based on return type

| Old Interface Return Type | New Interface Should Return | Method to Use |
|--------------|----------------|---------|
| `UserInfoModel` (custom model) | `UserInfoModel` | `api.response()` |
| `Int64` | `Int64` | `api.send()` + manual parsing |
| `String` | `String` | `api.responseDict()` + extract field |
| `[String: Any]` | `[String: Any]` | `api.responseDict()` |
| `[[String: Any]]` | `[[String: Any]]` | `api.responseArray()` |

### 10.2 Common Error Patterns

#### Error 1: Model Type Returns Dictionary

```swift
// ❌ Wrong: Old interface returns UserInfoModel, new interface returns [String: Any]
static func login(phoneNumber: String, code: String) async throws -> [String: Any] {
    return try await api.responseDict()
}

// ✅ Correct: Return UserInfoModel (model must implement Decodable)
static func login(phoneNumber: String, code: String) async throws -> UserInfoModel {
    return try await api.response()
}
```

#### Error 2: String Type Returns Dictionary

```swift
// ❌ Wrong: Old interface returns String, new interface returns [String: Any]
static func submitVerification(...) async throws -> [String: Any] {
    return try await api.responseDict()
}

// ✅ Correct: Return String directly
static func submitVerification(...) async throws -> String {
    let dict = try await api.responseDict()
    guard let trackingId = dict["trackingId"] as? String else {
        throw ZTAPIError(-1, "Invalid response")
    }
    return trackingId
}
```

### 10.3 Verification Checklist

- [ ] **[Must]** Compare old and new interface return types one by one
- [ ] **[Must]** Model type interfaces use `api.response()` (model must implement Decodable)
- [ ] **[Must]** Basic type (Int/Bool/String) interfaces use correct parsing method
- [ ] **[Must]** Dictionary type interfaces continue using `api.responseDict()`
- [ ] Update all affected caller code

### 10.4 Decodable Model Adaptation

If old interfaces use non-Decodable models (like HandyJSON), need to first convert models to Decodable:

```swift
// Old model (non-Decodable)
class OldModel: HandyJSON {
    var token: String = ""
    var userId: Int64 = 0
    required init() {}
    func mapping(mapper: HelpingMapper) {}
}

// New model (implements Decodable)
struct NewModel: Decodable {
    let token: String
    let userId: Int64
}
```

**Migration recommendations**:
1. Prioritize changing models to `struct` + `Decodable`
2. Keep field names consistent with server's JSON keys
3. Use `CodingKeys` to handle field name mismatches

---

## [MUST CHECK] 11. Interface Definition Degradation Check

**[Must Check] Prevent interface definitions from degrading to `[String: Any]`**

This is the **final checkpoint** before considering migration complete. Interface degradation means converting type-safe named parameters into generic dictionary parameters, losing compile-time type safety and code clarity.

### 11.1 What Is Interface Degradation

**Interface degradation**: When an interface that originally had clear, type-safe named parameters gets converted to use `[String: Any]` dictionary parameters.

```swift
// ✅ Type-safe - No degradation
static func sensitiveBatchAddOrUpdate(communityId: Int, list: [XMCommunitySensitiveModel]) async throws -> Bool

// ❌ Degraded - Lost type safety
static func sensitiveBatchAddOrUpdate(_ param: [String: Any]) async throws -> Bool
```

### 11.2 Why Degradation Is Unacceptable

| Aspect | Type-Safe Parameters | Degraded `[String: Any]` |
|--------|---------------------|--------------------------|
| **Compile-time checking** | ✅ Type errors caught at compile | ❌ Runtime crashes only |
| **Code clarity** | ✅ Self-documenting parameters | ❌ Need to check source for keys |
| **Refactoring safety** | ✅ IDE can rename safely | ❌ String keys break silently |
| **Call-site clarity** | ✅ Explicit parameter names | ❌ Unclear what keys are needed |
| **Debugging** | ✅ Stack trace shows actual types | ❌ Generic dictionary |

### 11.3 Degradation Detection Checklist

Before marking migration complete, check for these **degradation patterns**:

```swift
// ❌ Degradation Pattern 1: Single dictionary parameter
static func xxxMethod(_ param: [String: Any]) async throws -> ReturnType

// ❌ Degradation Pattern 2: Params wrapper with Any type
static func xxxMethod(params: [String: Any]) async throws -> ReturnType

// ❌ Degradation Pattern 3: Optional dictionary replacing concrete types
static func xxxMethod(_ param: [String: Any]?) async throws -> ReturnType
```

### 11.4 Restoration Guidelines

When interface degradation is detected, restore to type-safe parameters:

```swift
// Before (Degraded)
static func editWord(_ param: [String: Any]) async throws -> Bool {
    let api: ZTAPI<ZTAPIKVParam> = API.editWord.build()
        .params(param)
    return try await api.response()
}

// After (Restored)
static func editWord(communityId: Int, list: [XMCommunitySensitiveModel]) async throws -> Bool {
    let api: ZTAPI<ZTAPIKVParam> = API.editWord.build()
        .params(.kv("communityId", communityId),
                 .kv("list", list.map { $0.toJSON() }))
    return try await api.response()
}
```

### 11.5 When Is `[String: Any]` Acceptable

Only use dictionary parameters when:

- ✅ Interface has **many (5+) variable parameters**
- ✅ Parameter structure is **dynamic or highly complex**
- ✅ Interface is **unstable** and changes frequently

**Otherwise, always prefer type-safe named parameters.**

### 11.6 Final Migration Checklist

- [ ] All interfaces use type-safe parameters (not `[String: Any]`) unless justified
- [ ] No single-parameter dictionary patterns (`_ param: [String: Any]`)
- [ ] All parameter types are concrete (String, Int, Bool, Model, etc.) not `Any`
- [ ] Call sites use explicit parameter names, not dictionary literals
- [ ] Return types match original interface (see Section 10)
- [ ] All Task closures use `[weak self]` + `self?` pattern
- [ ] UI operations wrapped in `await MainActor.run`

**If any degradation is found, restore type-safe parameters before marking migration complete.**
