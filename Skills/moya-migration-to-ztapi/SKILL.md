---
name: moya-migration-to-ztapi
description: Complete guide for migrating network layer from Moya to ZTAPI, including execution workflow and reference manual
---

# Network Layer Migration: Moya to ZTAPI

This Skill provides a complete guide for migrating the network layer from Moya to ZTAPI.

**Quick Start**: Tell me the module name you want to migrate, and I will guide you through the migration.

---

## Execution Workflow

Follow these steps in order. Complete the checklist after each step before proceeding.

### Step 1: Analyze Old Moya API File

**Goal**: Fully understand the old API structure and generate information tables needed for migration.

**Actions**:

1. Read the old Moya API file and locate:
   - Interface definitions (`case` statements) in `enum` or `struct`
   - baseURL definition
   - List of plugins used
   - `target` type or interface path definitions

2. Extract all interface information and generate the following table:

| Interface Name | Return Type | Parameters | HTTP Method | URL |
| --- | --- | --- | --- | --- |
| `request_login` | `UserInfoModel` | `account, password` | `.post` | `/user/login` |

3. Extract plugin list:

| Plugin Name | Description |
| --- | --- |
| `RequestHeaderPlugin` | Add token request header |

**Notes**:
- Extract return types from `success: @escaping (Type) -> Void`
- Parameter key casing must be accurately recorded (e.g., `RoomId` vs `roomId`)
- baseURL may come from a config class or environment variable

**[MUST CHECK] Checklist**:
- [ ] Interface information table complete
- [ ] Return types recorded
- [ ] Parameter key casing recorded
- [ ] Plugin list recorded

**Completion标志**: Generated interface comparison table and plugin list

---

### Step 2: Create New API File Skeleton

**Goal**: Create the basic structure of the new API file.

**Actions**:

1. Create file (same name as old API, remove `Net` or `Client` suffix):
   - Old: `UserNetAPI.swift` or `UserAPIClient.swift`
   - New: `UserAPI.swift`

2. Write file skeleton:

```swift
//
//  XXXAPI.swift
//  ProjectName
//
//  Created by zt
//

import Foundation
import ZTAPI

enum XXXAPI {
    enum API {
        case custom(url: String, method: ZTHTTPMethod)

        private static var baseUrl: String {
            // TODO: Configure baseUrl
        }

        private static var provider: any ZTAPIProvider {
            // TODO: Configure provider
        }

        fileprivate func build<P: ZTAPIParamProtocol>() -> ZTAPI<P> {
            let encoding: ZTParameterEncoding = self.method == .get ? ZTURLEncoding() : ZTJSONEncoding()
            return ZTAPI<P>(API.baseUrl + self.url, self.method, provider: API.provider)
                .encoding(encoding)
                .timeout(30)
                .plugins(/* TODO: Configure plugins */)
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
    }

    // MARK: - Interface Methods
}
```

3. Configure baseUrl, provider, and plugins

**[MUST CHECK] Checklist**:
- [ ] baseUrl matches old API
- [ ] provider correctly configured
- [ ] Plugins configured

**Completion标志**: File skeleton created, compiles without errors

---

### Step 3: Define Interface Endpoints (API enum)

**Goal**: Define URLs and HTTP methods for all interfaces in the `API` enum.

**Actions**:

For each interface in the table generated in Step 1, add a definition in the `API` enum:

```swift
static var login = API.custom(url: "\(API_USER)/login", method: .post)
```

**[MUST CHECK] Checklist**:
- [ ] All interfaces defined
- [ ] URLs correct
- [ ] HTTP methods correct

**Completion标志**: All interface endpoints defined

---

### Step 4: Implement Interface Methods

**Goal**: Implement async methods for each interface.

**Determine return type and parsing method**:

| Old Interface Return Type | New Interface Return Type | Method to Use |
| --- | --- | --- |
| Custom model (Decodable) | Same model | `api.response()` |
| `Int64` / `Int` | Same type | `api.send()` + manual parsing |
| `String` | `String` | `api.responseDict()` + extract field |
| `[String: Any]` | `[String: Any]` | `api.responseDict()` |
| `[[String: Any]]` | `[[String: Any]]` | `api.responseArray()` |

**Determine parameter approach**:
- Fixed parameters (1-5) → Use named parameters
- Many or variable parameters → Use dictionary parameters

**Method examples**:

```swift
// Named parameter example
static func login(account: String, password: String) async throws -> UserInfoModel {
    let api: ZTAPI<ZTAPIKVParam> = API.login.build()
        .params(["account": account, "password": password.md5()])
    return try await api.response()
}

// Dictionary parameter example
static func updateProfile(_ param: [String: Any]) async throws -> UserInfoModel {
    let api: ZTAPI<ZTAPIKVParam> = API.updateProfile.build()
        .params(param)
    return try await api.response()
}
```

**[MUST CHECK] Checklist**:
- [ ] Return types match old interfaces
- [ ] Parameter keys match old interfaces exactly (including casing)
- [ ] Fixed-parameter interfaces use named parameters
- [ ] Bool parameters in GET requests converted to `0`/`1`

**Completion标志**: All interface methods implemented

---

### Step 5: Update Call Sites

**Goal**: Change all code calling the old API to call the new API.

**Actions**:

1. Search for old API call sites:

```bash
grep -r "OldAPI\.shared\.request" --include="*.swift"
grep -r "OldAPI\." --include="*.swift"
```

2. Update call sites one by one

**Old style (Moya + closure)**:
```swift
OldAPI.shared.request_login(param: ["account": account, "password": pwd]) { result in
    // Handle result
} failure: { error in
    // Handle error
}
```

**New style (async/await)**:
```swift
Task { [weak self] in
    do {
        let result = try await NewAPI.login(account: account, password: pwd)
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

**[MUST CHECK] Checklist**:
- [ ] All call sites updated
- [ ] Task closures use `[weak self]` + `self?`
- [ ] UI updates in MainActor.run

**Completion标志**: Search for old API calls returns no results, project compiles

---

### Step 6: Verify and Cleanup

**Goal**: Ensure migration is complete, delete old files.

**Actions**:

1. Compile verify (Cmd + B)
2. Search for remaining references: `grep -r "OldAPI" --include="*.swift"`
3. Delete old API files
4. Clean Build Folder and recompile

**[MUST CHECK] Checklist**:
- [ ] Compiles without errors
- [ ] No remaining old API references
- [ ] Old API files deleted

**Completion标志**: Project compiles successfully, migration complete

---

## Overview Checklist

**Analysis Phase**:
- [ ] Interface information table generated
- [ ] Plugin list recorded

**File Creation**:
- [ ] baseUrl correct
- [ ] provider correct
- [ ] Plugins configured

**Interface Definitions**:
- [ ] URLs correct
- [ ] HTTP methods correct
- [ ] Interface count complete

**Interface Implementation**:
- [ ] Return types consistent
- [ ] Parameter keys consistent (including casing)
- [ ] GET request Bool parameters converted

**Call Site Updates**:
- [ ] Old API calls replaced
- [ ] Using `[weak self]` + `self?`
- [ ] UI updates in MainActor.run

**Verification Cleanup**:
- [ ] Compiles successfully
- [ ] No remaining references
- [ ] Old files deleted

---

## Reference Documentation

For detailed specifications, see: `references/moya-migration-to-ztapi.md`

Contents include:
- Parameter complete alignment principle
- Parameter case sensitivity
- HTTP method alignment
- Encoding method selection
- Task closure self capture rules
- Interface parameter migration principles
- Common bug cases
- Interface return type comparison checks
