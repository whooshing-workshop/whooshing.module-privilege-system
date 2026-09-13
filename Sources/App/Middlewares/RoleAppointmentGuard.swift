import PrivilegeSystemDriver
import Foundation

/// 【修复 FINDINGS #1】角色任命关系校验中间件。
///
/// 权限主系统 `/api/*` 原有的保护链为：
///
///     RoleAuthenticator(X-Role-Id 角色存在) → AdminAuthGuard(角色名 == "admin") → ApiValidator(.local: 凭据 + 加密 Token 有效)
///
/// 这条链只校验“角色存在、角色叫 admin、凭据有效”三件事，**并不校验该角色是否真的任命给了凭据所属的用户**。
/// 于是任何已注册的普通用户，只要在 `X-Role-Id` 里填入 admin 角色的 ID，就能通过全部校验并调用所有管理接口。
///
/// 本中间件挂在 `ApiValidator` 之后（此时 `AuthData` 已登录到 `req.auth`），
/// 通过 `PrivilegeSystem.role.is(roleId:appointedTo:)` 校验：
/// 角色必须以 **用户角色 / 群组角色（含祖先群组）/ 组内角色** 任意一种方式任命给了该用户，否则返回 403。
///
/// 用法（见 `routes.swift`）：
///
/// ```swift
/// let apiProtected = app.apiProtectGrouped(for: .main, in: nexus).grouped(RoleAppointmentGuard())
/// ```
public struct RoleAppointmentGuard: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // ApiValidator 成功后会 `request.auth.login(authData)`；若拿不到，说明链路配置有误，直接拒绝
        guard let auth = request.auth.get(AuthData.self) else {
            throw Abort(.unauthorized, reason: "用户身份尚未认证，RoleAppointmentGuard 必须挂在 ApiValidator 之后")
        }

        let roleId = auth.role.id
        let userId = auth.token.user.id

        let appointed: Bool
        do {
            appointed = try await PrivilegeSystem.main.role.is(roleId: roleId, appointedTo: userId)
        } catch {
            request.logger.error("校验角色任命关系失败: \(error)")
            throw Abort(.internalServerError, reason: "校验角色任命关系失败")
        }

        guard appointed else {
            request.logger.warning(
                "拒绝访问：角色未任命给该用户",
                metadata: ["role_id": .stringConvertible(roleId), "user_id": .stringConvertible(userId), "email": .string(auth.token.user.email)]
            )
            throw Abort(.forbidden, reason: "所声明的角色(X-Role-Id)并未任命给当前用户")
        }

        return try await next.respond(to: request)
    }
}
