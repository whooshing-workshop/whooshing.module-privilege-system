import Fluent
import VaporTube
import PrivilegeSystemDriver

/// 路由总表
///
/// | 分组 | 前缀 | 保护链 | 用途 |
/// |---|---|---|---|
/// | 账号 | `/account` | 无（注册 / 登录 / 凭旧密码改密） | 面向终端用户 |
/// | 查询 | `/api/data` | admin 保护链（见下） | 模型记录与关系的只读查询 |
/// | 服务间 | `/inline` | `ServiceValidator`（X-Module-ID 必须为已登记的其它模块） | 业务模块调用的认证 / 仲裁 |
/// | 管理 | `/api` | `RoleAuthenticator → AdminAuthGuard → ApiValidator(.local) → RoleAppointmentGuard` | 角色 / 域 / 群组 / 策略 / 用户信息管理 |
///
/// 管理接口保护链要求请求头：
///   - `X-Role-Id`：本次操作使用的角色 ID，且该角色名必须为 `admin`
///   - `X-Credential`：登录返回的凭据
///   - `X-Encrypted-Token`：`Base64(AES-GCM(key = token, SHA512(token)))`
///   并且（【修复 FINDINGS #1】）该角色必须确实任命给了凭据所属的用户。
func routes(_ nexus: Nexus<VaporTube>) throws {
    // 账号：注册 / 登录 / 凭旧密码改密（无需认证）
    try nexus.tube.app.register(collection: AccountController())

    // 服务间通讯：来源模块合法性校验
    let inlineProtected = nexus.tube.app.inlineProtectGrouped()
    try inlineProtected.register(collection: ArbitrateController())

    let apiProtected = nexus.tube.app.apiProtectGrouped(for: .main, in: nexus)
    try apiProtected.register(collection: PrivilegeController())
    try apiProtected.register(collection: ApiAccountController())

    let dataRouter = apiProtected.grouped("data")
    try dataRouter.register(collection: DataController())

    apiProtected.get("test") { req in
        try req.auth.require(AuthData.self)
    }
}
