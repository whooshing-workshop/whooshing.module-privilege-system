import PrivilegeSystemDriver
import Foundation

/// 登录响应
///
/// 因此登录接口在返回 Token 的同时，一并返回该用户当前可用的全部角色
/// （直接任命的用户角色 + 所在群组及其祖先群组的群组角色 + 组内角色），
/// 客户端据此选择 `X-Role-Id`。
public struct LoginResponse: Content, Sendable {
    /// 登录凭据。`token` 字段为对称密钥（Base64），**仅在本响应中明文返回一次**，请客户端妥善保存
    public let token: QToken
    /// 该用户当前可用的全部角色
    public let roles: [QRole]
}

/// 账号控制器（无需认证）
///
/// - `POST /account/register`        注册：body 为 `PUser { email, hashed_password }`，`hashed_password` 为客户端 SHA512 后的 Base64
/// - `POST /account/login`           登录：body 同上，返回 `LoginResponse`；每次登录会吊销该用户之前签发的全部 Token
/// - `PUT  /account/change_password` 凭旧密码改密：body 为 `{ user: PUser(旧密码), newPassword: String(新密码哈希) }`
public struct AccountController: RouteCollection, Sendable {
    public func boot(routes: any RoutesBuilder) throws {
        let account = routes.grouped("account")
        account.post("register", use: register)
        account.post("login", use: login)
        account.put("change_password", use: changePasswordWithoutAuth)
    }

    /// 注册新用户。成功后自动获得 `nobody` 角色。邮箱重复返回 409。
    @Sendable
    func register(req: Request) async throws -> QUser {
        let infos = try req.content.decode(PUser.self)
        let result = try await PrivilegeSystem.main.account.register(for: infos)
        return result
    }

    /// 登录。密码错误 / 用户不存在均返回 401（不区分，避免枚举用户）。
    /// 登陆成功返回该用户可用的所有角色
    @Sendable
    func login(req: Request) async throws -> LoginResponse {
        let account = try req.content.decode(PUser.self)
        let token = try await PrivilegeSystem.main.account.login(by: account)

        let origin = PrivilegeSystem.main.origin
        guard let user = try await QUser.query(on: origin).filter(\.id == token.$user.id).first() else {
            throw Abort(.internalServerError, reason: "登录成功但无法加载用户信息")
        }
        let roles = try await PrivilegeSystem.main.role.roles(for: user)

        return LoginResponse(token: token, roles: roles)
    }

    /// 凭旧密码修改密码（无需登录）。旧密码错误 / 用户不存在返回 401。
    @Sendable
    func changePasswordWithoutAuth(req: Request) async throws -> QUser {
        struct PasswordChangeInput: Content {
            let user: PUser
            let newPassword: String
        }

        let input = try req.content.decode(PasswordChangeInput.self)
        return try await PrivilegeSystem.main.account.changePassword(for: input.user, to: input.newPassword)
    }
}

/// 需要 admin 保护链的账号接口
///
/// - `POST /api/account/change_password` 已登录改密：body 为新密码哈希（JSON 字符串），修改的是凭据所属用户自己的密码
///
/// 注意：该接口位于 admin 保护链下，普通用户无法使用；普通用户请走 `PUT /account/change_password`
public struct ApiAccountController: RouteCollection, Sendable {
    public func boot(routes: any RoutesBuilder) throws {
        let account = routes.grouped("account")
        account.post("change_password", use: changePassword)
    }

    @Sendable
    func changePassword(req: Request) async throws -> QUser {
        let auth = try req.auth.require(AuthData.self)
        let newPassword = try req.content.decode(String.self)
        return try await PrivilegeSystem.main.account.changePassword(for: auth.token.user, to: newPassword)
    }
}
