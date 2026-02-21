# JsonDemo 工程索引

> 创建时间: 2025-01-14
> 作者: zt
> 说明: 本文档记录工程的分层、模块、文件、类结构，便于快速查找和理解

---

## 一、工程概述

**工程名称**: JsonDemo
**工程类型**: iOS App (UIKit)
**主要功能**: 演示自定义网络请求框架 ZTAPI 的使用
**核心依赖**:
- Alamofire 5.10.2 - 网络请求底层
- SwiftyJSON 5.0.2 - JSON 解析
- ZTJSON (本地) - 自定义 JSON 宏

---

## 二、分层结构

```
JsonDemo/
├── 入口层 (Entry)
│   └── AppDelegate.swift
├── 视图层 (View)
│   └── ViewController.swift
├── 网络层 (Network)
│   ├── ZTAPI.swift           # 核心 API 类
│   └── ZTAPIProvider.swift   # Provider 协议与实现
├── 数据层 (Model)
│   └── Model.swift           # 数据模型定义
├── 视图模型层 (ViewModel)
│   └── VM.swift              # API 调用封装
└── 测试层 (Test)
    └── ZTAPITests.swift      # 测试套件
```

---

## 三、模块详情

### 3.1 入口层 (Entry)

| 文件 | 类/结构 | 说明 |
|------|---------|------|
| `AppDelegate.swift` | `AppDelegate` | 应用入口，初始化 UIWindow 并设置根视图控制器 |

**依赖关系**: 无

---

### 3.2 视图层 (View)

| 文件 | 类/结构 | 说明 |
|------|---------|------|
| `ViewController.swift` | `ViewController` | 主页面，包含运行测试的按钮，App 启动时自动运行测试 |

**依赖关系**:
- 依赖 `VM` - 虽然声明了但当前未使用
- 依赖 `ZTAPITests` - 运行测试套件

---

### 3.3 网络层 (Network)

#### 3.3.1 ZTAPI.swift - 核心 API 类

| 类型 | 名称 | 说明 |
|------|------|------|
| `extension Result` | `onSuccess`, `onFailure` | Result 链式调用扩展 |
| `extension Dictionary` | `get(_:)` | 字典泛型取值 |
| `struct` | `ZTAPIError` | API 错误类型 |
| `enum` | `ZTAPIHeader` | HTTP Header 枚举 |
| `enum` | `ZTAPIKVParam` | 键值对参数枚举 |
| `protocol` | `ZTParameterEncoding` | 参数编码协议 |
| `struct` | `ZTURLEncoding` | URL 编码实现 |
| `struct` | `ZTJSONEncoding` | JSON 编码实现 |
| `struct` | `ZTAPIParseConfig` | 数据解析配置 |
| `enum` | `ZTHTTPMethod` | HTTP 方法枚举 |
| `class` | `ZTAPI<P>` | 核心网络请求类，支持泛型参数 |

**主要功能**:
- 链式调用构建请求 (`param`, `params`, `header`, `encoding`, `timeout`, `retry`)
- 异步发送请求 (`send()`)
- Combine Publisher 支持 (`publisher`)

**依赖关系**:
- SwiftyJSON
- ZTJSON
- Combine

---

#### 3.3.2 ZTAPIProvider.swift - Provider 协议与实现

| 类型 | 名称 | 说明 |
|------|------|------|
| `protocol` | `ZTAPIRetryPolicy` | 重试策略协议 |
| `struct` | `ZTFixedRetryPolicy` | 固定次数重试策略 |
| `struct` | `ZTExponentialBackoffRetryPolicy` | 指数退避重试策略 |
| `struct` | `ZTConditionalRetryPolicy` | 自定义条件重试策略 |
| `protocol` | `ZTAPIPlugin` | 插件协议 |
| `struct` | `ZTLogPlugin` | 日志插件 |
| `struct` | `ZTAuthPlugin` | 认证插件（自动添加 Token） |
| `struct` | `ZTTokenRefreshPlugin` | Token 刷新插件 |
| `protocol` | `ZTAPIProvider` | 网络请求提供者协议 |
| `class` | `ZTAlamofireProvider` | 基于 Alamofire 的 Provider 实现 |
| `class` | `ZTStubProvider` | 测试用 Stub Provider |

**主要功能**:
- 重试机制（固定延迟、指数退避、自定义条件）
- 插件系统（日志、认证、Token 刷新）
- Provider 抽象层，支持切换底层实现

**依赖关系**:
- Alamofire

---

### 3.4 数据层 (Model)

#### 3.4.1 Model.swift - 数据模型定义

| 类型 | 名称 | 说明 |
|------|------|------|
| `struct` | `TransformDouble` | Double 类型转换器 |
| `struct` | `TransformHttp` | URL 类型转换器 |
| `struct` | `Company` | 公司信息模型 |
| `class` | `BaseAddress` | 地址基类 |
| `class` | `Address` | 地址模型（继承 BaseAddress） |
| `struct` | `Geo` | 地理坐标模型 |
| `class` | `User` | 用户模型 |
| `class` | `NestAddress` | 嵌套地址模型（扁平化解析） |

**主要功能**:
- 使用 `@ZTJSON` 宏自动生成 JSON 解析代码
- 支持嵌套对象解析
- 支持自定义转换器
- 支持 XPath 风格的路径解析（如 `address/geo/lat`）

**依赖关系**:
- Alamofire（当前导入但未使用，可移除）
- ZTJSON
- SwiftyJSON

---

### 3.5 视图模型层 (ViewModel)

#### 3.5.1 VM.swift - API 调用封装

| 类型 | 名称 | 说明 |
|------|------|------|
| `extension ZTAPIHeader` | `contentType`, `auth` | 通用 Header 静态属性 |
| `enum` | `UserCenterAPI` | 用户中心 API 定义 |
| `enum` | `UserAPIParam` | 用户 API 参数枚举（使用 @ZTAPIParam 宏） |
| `class` | `VM` | ViewModel，封装业务逻辑 |

**UserCenterAPI 提供的接口**:
- `login(userName:password:)` - 登录接口
- `login2(userName:password:)` - 登录接口（使用枚举参数）
- `userInfo(userId:)` - 获取用户信息
- `userList` - 获取用户列表

**依赖关系**:
- ZTJSON
- SwiftyJSON

---

### 3.6 测试层 (Test)

#### 3.6.1 ZTAPITests.swift - 测试套件

| 类型 | 名称 | 说明 |
|------|------|------|
| `class` | `ZTAPITests` | 完整的测试套件 |

**测试用例** (共 21 个):

| 测试方法 | 说明 |
|---------|------|
| `testZTAPIErrorDescription` | 测试错误描述 |
| `testZTAPIHeader` | 测试 Header |
| `testZTAPIKVParam` | 测试参数 |
| `testZTURLEncodingGET` | 测试 URL 编码 (GET) |
| `testZTURLEncodingPOST` | 测试 URL 编码 (POST) |
| `testZTJSONEncoding` | 测试 JSON 编码 |
| `testZTAPIParseConfig` | 测试解析配置 |
| `testZTAPIChaining` | 测试链式调用 |
| `testResultExtensions` | 测试 Result 扩展 |
| `testZTAPIWithStubProvider` | 测试 Stub Provider |
| `testZTAPIInvalidURL` | 测试无效 URL |
| `testZTAPIPublisher` | 测试 Publisher |
| `testPublisherMultipleSubscriptions` | 测试多次订阅 |
| `testDifferentPublisherInstances` | 测试不同 Publisher 实例 |
| `testPublisherNoExecutionWithoutSubscription` | 测试未订阅时不执行 |
| `testStubProviderDelay` | 测试延迟 |
| `testRealAPI` | 测试真实 API (jsonplaceholder) |
| `testTimeout` | 测试超时 |
| `testFixedRetryPolicy` | 测试固定重试 |
| `testExponentialBackoffRetry` | 测试指数退避 |
| `testConditionalRetry` | 测试自定义重试 |
| `testProviderLevelRetry` | 测试 Provider 级别重试 |
| `testRetryThenSuccess` | 测试重试后成功 |
| `testRequestRetryOverrideProvider` | 测试请求级别覆盖 |
| `testNonRetryableError` | 测试不可重试错误 |
| `testTimeoutAndRetry` | 测试超时+重试组合 |
| `testNoRetryPolicy` | 测试无重试策略 |
| `testMultipleRequestsDifferentRetries` | 测试不同请求不同重试 |
| `testTimeoutAppliedToRequest` | 测试超时设置 |
| `testChainingOrder` | 测试链式调用顺序 |

**依赖关系**:
- Foundation
- SwiftyJSON
- ZTJSON
- Combine
- OSLog
- UIKit

---

## 四、数据流向

```
ViewController
    │
    ├──> VM.performLogin()
    │         │
    │         └──> UserCenterAPI.login() / userInfo() / userList
    │                   │
    │                   └──> ZTAPI.send()
    │                         │
    │                         ├──> ZTAPIProvider.request()
    │                         │         │
    │                         │         └──> Alamofire (网络请求)
    │                         │
    │                         └──> JSON 解析 (SwiftyJSON + ZTJSON)
    │                                   │
    │                                   └──> Model (User, Address, etc.)
    │
    └──> ZTAPITests.runAllTests() (自动运行测试)
```

---

## 五、注意事项

1. **宏依赖**: ZTJSON 是本地依赖，使用 `@ZTJSON`、`@ZTJSONKey`、`@ZTJSONTransformer` 等宏
2. **宏依赖**: UserAPIParam 使用 `@ZTAPIParam` 宏，自动生成参数协议实现
3. **Sendable**: ZTAPI 使用 `@unchecked Sendable` 标记，需注意并发安全
4. **自动测试**: App 启动时自动运行测试套件，结果输出到控制台

---

## 六、变更记录

| 日期 | 变更内容 |
|------|----------|
| 2025-01-14 | 创建工程索引文档 |
