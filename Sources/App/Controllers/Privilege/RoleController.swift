import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 角色控制器：角色的增删改、任命（用户 / 群组 / 组内）与任命关系判定。
///
/// 路由（均位于 admin 保护链 `/api` 下）：
///
///     PUT    /role                          body: [PRole]                                    → [QRole]
///     PUT    /role/with_policies            body: [ { left: [PPolicy], right: PRole } ]      → true
///     PUT    /role/with_policies/returning  同上                                              → { roleId: [QPolicy] }
///     DELETE /role                          body: [UUID]                                     → true（级联删除策略与任命关系）
///     POST   /role/:roleId/name             body: String                                     → QRole
///     POST   /role/:roleId/summary          body: String?                                    → QRole
///     POST   /role/appoint/user             body: [ { left: [roleId], right: [userId] } ]    → true
///     POST   /role/appoint/group            body: [ { left: [roleId], right: [groupId] } ]   → true
///     POST   /role/appoint/user_in_group    body: [ { left: [roleId], right: [userInGroupId] } ] → true
///     POST   /role/dismiss/{user|group|user_in_group}  同上                                  → true
///     GET    /role/is/appointed?role_id&user_id        任意方式任命                            → Bool
///     GET    /role/is/user_role?role_id&user_id        直接任命                                → Bool
///     GET    /role/is/group_role?role_id&group_id      群组任命                                → Bool
///     GET    /role/verify/group_role?role_id&user_id           用户经哪些群组获得该群组角色     → [QGroup]
///     GET    /role/verify/user_in_group_role?role_id&user_id   用户在哪些群组被任命该组内角色   → [QGroup]
public struct RoleController: RouteCollection, Sendable {
    static let role = PrivilegeSystem.main.role

    public func boot(routes: any RoutesBuilder) throws {
        let role = routes.grouped("role")
        role.put(use: create)
        role.delete(use: delete)

        // 角色连带策略一同创建
        role.group("with_policies") { router in
            router.put(use: createWithPolicies)
            router.put("returning", use: createWithPoliciesReturning)
        }

        role.group(":roleId") { router in
            router.post("name", use: updateName)
            router.post("summary", use: updateSummary)
        }

        role.group("appoint") { router in
            router.post("user", use: appointUser)
            router.post("group", use: appointGroup)
            router.post("user_in_group", use: appointUserInGroup)
        }

        role.group("dismiss") { router in
            router.post("user", use: dismissUser)
            router.post("group", use: dismissGroup)
            router.post("user_in_group", use: dismissUserInGroup)
        }

        // 任命关系判定
        role.group("is") { router in
            router.get("appointed", use: isAppointed)
            router.get("user_role", use: isUserRoleAppointed)
            router.get("group_role", use: isGroupRoleAppointed)
        }

        // 任命关系验证（返回命中的群组）
        role.group("verify") { router in
            router.get("group_role", use: verifyGroupRole)
            router.get("user_in_group_role", use: verifyUserInGroupRole)
        }
    }
}

// MARK: - 增

public extension RoleController {
    @Sendable
    func create(req: Request) async throws -> [QRole] {
        let roles = try req.content.decode(OrderedSet<PRole>.self)
        return try await Self.role.create(roles: roles)
    }

    /// 创建角色，同时为其绑定角色策略（不返回详细数据）
    @Sendable
    func createWithPolicies(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Role>, PRole>>.self)
        try await PolicyGuards.run { try await Self.role.create(relations: relations) }
        return true
    }

    /// 创建角色，同时为其绑定角色策略，并返回按角色 ID 分组的策略数据
    @Sendable
    func createWithPoliciesReturning(req: Request) async throws -> [String: [QPolicy<Role>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Role>, PRole>>.self)
        let result = try await PolicyGuards.run { try await Self.role.createWithReturning(relations: relations) }
        return .init(uniqueKeysWithValues: result.map { ($0.key.uuidString, $0.value) })
    }
}

// MARK: - 删

public extension RoleController {
    @Sendable
    func delete(req: Request) async throws -> Bool {
        let ids = try req.content.decode(OrderedSet<UUID>.self)
        try await Self.role.delete(roleIds: ids)
        return true
    }
}

// MARK: - 改

public extension RoleController {
    @Sendable
    func updateName(req: Request) async throws -> QRole {
        let roleId = try parameter("roleId", from: req) { UUID(uuidString: $0) }
        let name = try req.content.decode(String.self)
        let updater = PRole.Updater(roleId: roleId).update(name: name)
        return try await Self.role.update(with: updater)
    }

    @Sendable
    func updateSummary(req: Request) async throws -> QRole {
        let roleId = try parameter("roleId", from: req) { UUID(uuidString: $0) }
        let summary = try req.content.decode(String?.self)
        let updater = PRole.Updater(roleId: roleId).update(summary: summary)
        return try await Self.role.update(with: updater)
    }
}

// MARK: - 模型关系（任命）

public extension RoleController {
    @Sendable
    func appointUser(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.appoint(roleToUser: relations)
        return true
    }

    @Sendable
    func appointGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.appoint(roleToGroup: relations)
        return true
    }

    /// 右侧为 user_in_group 关系 ID（可通过 POST /group/query 获取）
    @Sendable
    func appointUserInGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.appoint(roleToUserInGroup: relations)
        return true
    }
}

// MARK: - 模型关系（解除任命）

public extension RoleController {
    @Sendable
    func dismissUser(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.dismiss(roleFromUser: relations)
        return true
    }

    @Sendable
    func dismissGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.dismiss(roleFromGroup: relations)
        return true
    }

    @Sendable
    func dismissUserInGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.role.dismiss(roleFromUserInGroup: relations)
        return true
    }
}

// MARK: - 任命判定 / 验证
//
// 以下为“判定类”接口而非模型记录查询，因此保留在本控制器中；
// 模型记录与关系记录的查询请使用 DataController（/data/...）。

public extension RoleController {
    /// 判定角色是否（以任意方式）被任命给了用户
    /// GET /role/is/appointed?role_id=XXX&user_id=XXX
    @Sendable
    func isAppointed(req: Request) async throws -> Bool {
        let roleId = try req.query.get(UUID.self, at: "role_id")
        let userId = try req.query.get(UUID.self, at: "user_id")
        return try await Self.role.is(roleId: roleId, appointedTo: userId)
    }

    /// 判定角色是否被直接任命给了用户
    /// GET /role/is/user_role?role_id=XXX&user_id=XXX
    @Sendable
    func isUserRoleAppointed(req: Request) async throws -> Bool {
        let roleId = try req.query.get(UUID.self, at: "role_id")
        let userId = try req.query.get(UUID.self, at: "user_id")
        return try await Self.role.is(userRoleId: roleId, appointedTo: userId)
    }

    /// 判定角色是否被任命给了群组
    /// GET /role/is/group_role?role_id=XXX&group_id=XXX
    @Sendable
    func isGroupRoleAppointed(req: Request) async throws -> Bool {
        let roleId = try req.query.get(UUID.self, at: "role_id")
        let groupId = try req.query.get(UUID.self, at: "group_id")
        return try await Self.role.is(groupRoleId: roleId, appointedTo: groupId)
    }

    /// 验证用户通过哪些群组获得了该群组角色
    /// GET /role/verify/group_role?role_id=XXX&user_id=XXX
    @Sendable
    func verifyGroupRole(req: Request) async throws -> [QGroup] {
        let roleId = try req.query.get(UUID.self, at: "role_id")
        let userId = try req.query.get(UUID.self, at: "user_id")
        return try await Self.role.verify(groupRoleId: roleId, appointedTo: userId)
    }

    /// 验证用户在哪些群组中被任命了该组内角色
    /// GET /role/verify/user_in_group_role?role_id=XXX&user_id=XXX
    @Sendable
    func verifyUserInGroupRole(req: Request) async throws -> [QGroup] {
        let roleId = try req.query.get(UUID.self, at: "role_id")
        let userId = try req.query.get(UUID.self, at: "user_id")
        return try await Self.role.verify(userInGroupRoleId: roleId, appointedTo: userId)
    }
}
