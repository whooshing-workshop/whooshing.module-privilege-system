# Whooshing 权限主系统服务模块
基于 [Vapor](https://vapor.codes/) 以及 [Nexus](https://github.com/whooshing-workshop/whooshing.nexus) / [VaporTube](https://github.com/whooshing-workshop/whooshing.tube-vapor) 构建的 **权限主系统（PrivilegeSystem）服务模块**。

本模块是 Whooshing 系统中全局唯一的认证与授权中心：负责账号注册与登录、用户资料、角色、群组、域及其策略的管理，并向其他业务模块（如以 [whooshing.template-privilege-module](https://github.com/whooshing-workshop/whooshing.template-privilege-module) 为模版构建的模块）提供 **身份认证** 与 **权限仲裁** 的服务间接口。核心权限逻辑由 [whooshing.toolbox-privilege-system](https://github.com/whooshing-workshop/whooshing.toolbox-privilege-system) 提供，本模块仅负责将其以 HTTP 路由的形式对外暴露。

已集成以下 Whooshing 核心库：

- [whooshing.tube-vapor](https://github.com/whooshing-workshop/whooshing.tube-vapor)（含 [whooshing.nexus](https://github.com/whooshing-workshop/whooshing.nexus)）
- [whooshing.driver-privilege-system](https://github.com/whooshing-workshop/whooshing.driver-privilege-system)（`PrivilegeSystemDriver`）
- [whooshing.driver-file-storage](https://github.com/whooshing-workshop/whooshing.driver-file-storage)
- [whooshing.toolbox-privilege-system](https://github.com/whooshing-workshop/whooshing.toolbox-privilege-system)
- [whooshing.toolbox-file-storage](https://github.com/whooshing-workshop/whooshing.toolbox-file-storage)
- [whooshing.toolbox-basic](https://github.com/whooshing-workshop/whooshing.toolbox-basic)

本项目高度依赖 [Vapor](https://vapor.codes/)，另请参阅 [Vapor 官方文档](https://docs.vapor.codes/)

--------

### 项目简介

模块启动后会：

1. 初始化 `PrivilegeSystem.main`（连接 `default/privilege_system` 数据库与 EOPA）以及 `FileStorage.default`；
2. 若 `nobody` 角色（无任何权限的默认角色）不存在则自动创建；
3. 注册账号、数据查询、服务间接口与管理 API 四组路由；
4. 在独立调试模式下额外加载用于模拟 Manager 的 `DebugingModuleController`。

默认集成：

- ✅ Vapor 启动框架与 Nexus 服务模块创建机制
- ✅ 环境变量自动识别与配置切换（生产 / 开发 / 测试）
- ✅ 权限主系统（`PrivilegeSystem.main`），基于 OPA 的策略仲裁
- ✅ 账号注册 / 登录 / 改密，管理员账号命令行创建
- ✅ 面向业务模块的 `/inline/authenticate` 与 `/inline/arbitrate` 服务间接口
- ✅ 仅限 `admin` 角色访问的 `/api` 管理接口（域、群组、角色、策略、用户资料）
- ✅ 文件加密存储模块（`FileStorage.default`）

------

### 快速开始

1. **克隆本项目**

   ```sh
   git clone https://github.com/whooshing-workshop/whooshing.module-privilege-system.git
   cd whooshing.module-privilege-system
   ```

2. **准备外部依赖**

   独立调试模式需要本机运行：

   * **PostgreSQL**（默认 `localhost:5432`，用户 `postgres` / 密码 `password`），并预先创建 `postgres`、`privilege_system`、`file_storage` 三个数据库
   * **EOPA / OPA**（默认 `http://localhost:8181`），用于权限仲裁

3. **调整调试参数**

   在 [entrypoint.swift](Sources/App/entrypoint.swift) 的 `DebuggingParameters` 中调整数据库、文件存储与权限主系统的连接参数：

   ```swift
   /// 服务监听的端口号（默认 6501，以便与业务模块的 6500 同机联调）
   static let port = 6501

   /// 权限主系统：EOPA 连接参数与角色保留名
   /// reservedRoleName 中的名称（默认 "admin"）不能通过 API 直接创建角色
   static let privilegeSystemParas = Environment.PS(
       eopa: .init(scheme: .http, port: 8181, host: "localhost"),
       reservedRoleName: ["admin"]
   )

   /// 文件加密存储：加密文件默认保存在 ~/app_file_storage
   static let fileStorageParas = Environment.FS(
       dir: URL.homeDirectoryURL.appending(component: "app_file_storage")
   )

   /// 允许访问 /inline 路由的来源模块 ID 白名单，第一项即本模块 ID
   static let serviceIds = [ ... ]
   ```

   **这些参数仅在独立测试环境中被使用，生产环境中所有配置均由 Whooshing 系统通过环境变量提供**

4. **模块配置**

   在 [configure.yaml](configure.yaml) 中根据你的需求进行配置

   > 关于具体的配置细节，请详细参照其中的注释文档

5. **运行项目**

   使用 Xcode 或命令行运行：

   ```sh
   swift run App serve --env development
   ```

   或指定环境：

   ```sh
   swift run App serve --env production
   ```

   Xcode 启动默认即为开发环境 (development)。将 `Woo.testingAllowed` 设为 `false` 可禁止模块进入独立调试 / 测试模式

6. **创建管理员账号**

   `admin` 为保留角色名，无法通过 API 创建，请使用内置命令初始化管理员：

   ```sh
   swift run App create-admin --email admin@example.com --pass <密码>
   # 或省略参数，进入交互式输入（密码不回显）
   swift run App create-admin
   ```

------

### 项目结构预览

```
├── Package.swift                        // Swift Package 描述文件
├── configure.yaml                       // Whooshing 系统部署配置
├── pm2.config.json                      // pm2 进程配置
├── Sources/App
│   ├── entrypoint.swift                 // 项目入口、运行模式识别与调试参数
│   ├── configure.swift                  // 命令注册、路由注册
│   ├── routes.swift                     // 路由分组（公开 / data / inline / api）
│   ├── Drivers
│   │   ├── DriverInit.swift             // 驱动预热
│   │   ├── FileStorage.swift            // 文件加密存储单例
│   │   └── PrivilegeSystem.swift        // 权限主系统单例
│   └── Controllers
│       ├── AccountController.swift      // 账号注册 / 登录 / 改密
│       ├── ArbitrateController.swift    // 服务间认证与仲裁接口
│       ├── DataController.swift         // 只读查询接口
│       ├── PrivilegeController.swift    // 管理接口总控制器
│       ├── Privilege/                   // 域、群组、角色、策略、用户资料、资料切片控制器
│       └── Commands/CreateAdmin.swift   // create-admin 命令
└── Tests/AppTests                       // 测试代码
```

--------

### 路由说明

#### 公开路由

```swift
AccountController 提供:
    - POST /account/register          注册账号，Body 为 PUser（email + hashedPassword），返回 QUser
    - POST /account/login             登录，Body 为 PUser，返回 QToken（凭据与 Token）
    - PUT  /account/change_password   凭旧密码修改密码，Body 为 { user: PUser, newPassword: String }
```

#### 数据查询路由（`/data`）

由 `DataController` 提供，均为 `GET`，可通过 query 参数过滤：

```
模型记录:
    - GET /data/domain                       ?id
    - GET /data/group                        ?id ?parent_id ?name
    - GET /data/role                         ?id ?name
    - GET /data/user                         ?id ?email
    - GET /data/user_info                    ?id ?user_id
    - GET /data/policy/domain                ?id ?parent_id ?module_id
    - GET /data/policy/role                  ?id ?parent_id ?module_id
    - GET /data/info_slice/address           ?id ?user_info_id
    - GET /data/info_slice/phone             ?id ?user_info_id
    - GET /data/info_slice/alternate_email   ?id ?user_info_id

模型关系:
    - GET /data/relation/domain_user         ?domain_id ?user_id
    - GET /data/relation/domain_group        ?domain_id ?group_id
    - GET /data/relation/user_group          ?user_id   ?group_id
    - GET /data/relation/user_role           ?user_id   ?role_id
    - GET /data/relation/role_group          ?role_id   ?group_id
    - GET /data/relation/role_user_in_group  ?role_id   ?user_in_group_id
```

#### 服务间路由（`/inline`）

经 `inlineProtectGrouped()` 保护，请求头需携带在 Manager 中登记的 `X-Module-ID`。业务模块的 `ApiValidator(.remote)` 与 `Arbitrator(.remote)` 即调用这两个接口：

```swift
ArbitrateController 提供:
    - POST /inline/authenticate   Body 为 AuthenticateData（token + role_id），返回 AuthData
    - POST /inline/arbitrate      Body 为 ArbitrateData，返回 Bool（是否放行）
```

#### 管理路由（`/api`）

经 `apiProtectGrouped(for: .main, in: nexus)` 保护，需携带 `X-Credential`、`X-Encrypted-Token` 与 `X-Role-Id` 三个请求头，且所用角色必须为 `admin`：

```swift
ApiAccountController 提供:
    - POST /api/account/change_password    以当前登录身份修改密码

PrivilegeController 汇总以下子控制器:
    - /api/domain        域的创建 / 删除 / 改名 / 改简介，用户与群组的指派与解除
    - /api/group         群组的创建 / 删除 / 改名 / 改简介 / 移动，用户加入与踢出，成员查询
    - /api/role          角色的创建 / 删除 / 改名 / 改简介，对用户 / 群组 / 群组内用户的任命与解除，任命关系校验
    - /api/policy        域策略与角色策略的创建 / 删除
    - /api/user_info     用户资料的创建 / 删除 / 更新
    - /api/info_slice    地址 / 电话 / 备用邮箱等资料切片的创建 / 删除 / 更新
```

> 各接口的请求体与响应体均为 [whooshing.toolbox-privilege-system](https://github.com/whooshing-workshop/whooshing.toolbox-privilege-system) 中的 DTO 类型（`PDomain` / `QRole` / `PPolicy<Role>` 等），具体字段请参阅对应控制器源码。

-------

### 单元测试支持

项目已包含测试目标，可在 AppTests 中添加 Vapor 路由测试：

```sh
swift test
```

-----

### 运行环境

* **macOS** (> 13.0)
* **iOS** (> 16.0)
* **Linux** (> 20)
* **Swift** (> 6.3)
* **watchOS** (> 6.0) **[未测试]**
* **tvOS** (> 13) **[未测试]**

-------

### 注意事项

- `/inline/authenticate` 与 `/api` 的身份验证依赖用户登录时获得的 `QToken`：`X-Credential` 为凭据原文，`X-Encrypted-Token` 为 Token 密钥**加密自身哈希**后的 base64 密文，而非 Token 原文。
- `admin` 属于 `reservedRoleName`，只能通过 `create-admin` 命令创建；`nobody` 角色在启动时自动创建，独立调试模式下使用固定 ID（`Woo.nobodyRoleId`）以便测试。
- `/data` 下的查询接口当前未设置身份验证，部署到公开网络前请按需为其增加保护。

------

### 联系与反馈

如有使用问题或建议，请通过 [GitHub Issues](https://github.com/whooshing-workshop/whooshing.module-privilege-system/issues) 提交反馈。

或发至邮箱 [contact@official.whooshings.space](mailto:contact@official.whooshings.space)
