import PrivilegeSystemDriver
import Foundation

/// 服务间接口（需 `X-Module-ID` 为已登记的其它模块，见 `ServiceValidator`）
///
/// - `POST /inline/authenticate` 业务模块转发终端用户的凭据 + 加密 Token + 角色 ID，换取 `AuthData`
/// - `POST /inline/arbitrate`    业务模块提交 (moduleId, userId, roleId, resource, operation, privilegeIds) 请求仲裁，返回 `Bool`
public struct ArbitrateController: RouteCollection, Sendable {
    public func boot(routes: any RoutesBuilder) throws {
        routes.post("arbitrate", use: arbitrate)
        routes.post("authenticate", use: authenticate)
    }

    /// 身份认证
    ///
    /// 请求体：`{ "token": { "credential": String, "token_encrypted": String }, "role_id": UUID }`
    ///
    /// 校验顺序：
    ///   1. 角色存在（401）
    ///   2. 加密 Token 长度为 124（400）、凭据存在（401）、解密并比对哈希 / 有效期（401）
    ///   3. 该角色必须已任命给凭据所属用户（403）。
    ///
    /// 响应：`AuthData { key, token, role }`。
    @Sendable
    func authenticate(req: Request) async throws -> AuthData {
        let data = try req.content.decode(AuthenticateData.self)
        let result = try await PrivilegeSystem.main.account.authenticate(token: data.token, roleId: data.roleId)
        return result
    }

    /// 权限仲裁
    ///
    /// 请求体：`ArbitrateData`（camelCase）：
    /// `{ moduleId, userId, roleId, resource: GResource, operation: { rawValue }, privilegeIds: [UUID] }`
    ///
    /// 结果 = 角色策略 AND 所有域策略（用户直接域 + 所在群组及祖先群组的域）AND 所有 privilege 策略。
    /// 角色未任命给用户 → 403；用户不存在 → 404。
    @Sendable
    func arbitrate(req: Request) async throws -> Bool {
        let data = try req.content.decode(ArbitrateData.self)

        let report = try await PrivilegeSystem.main.arbitrator.judge(
            moduleId: data.moduleId,
            userId: data.userId,
            roleId: data.roleId,
            resource: data.resource,
            operation: data.operation,
            privilegeIds: .init(data.privilegeIds)
        )

        return report.result
    }
}
