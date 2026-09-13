import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 策略控制器：为已存在的域 / 角色单独追加或删除策略。
///
/// 若需要在创建域 / 角色的同时绑定策略，请使用
/// `PUT /domain/with_policies` 或 `PUT /role/with_policies`。
///
/// 路由：
///
///     PUT    /policy/domain              body: [ { left: [PPolicy], right: domainId } ]  → true
///     PUT    /policy/domain/returning    同上                                            → { domainId: [QPolicy] }
///     DELETE /policy/domain              body: { left: QPolicy<Domain>, right: domainId } → true
///     PUT    /policy/role                body: [ { left: [PPolicy], right: roleId } ]    → true
///     PUT    /policy/role/returning      同上                                            → { roleId: [QPolicy] }
///     DELETE /policy/role                body: { left: QPolicy<Role>, right: roleId }    → true
///
/// `PPolicy = { module_id: UUID, policy: String }`，`policy` 为 Rego 规则本体
/// （服务端自动包装 `package` / `import data.utils.pg` / `default allow := false`）。
///
/// 多策略语义：同一角色 / 域在同一模块下可以有多条策略，仲裁时逐条求值并按 **AND** 合并
/// （任一策略拒绝即拒绝；零条策略视为拒绝）。每条策略在 OPA 中有独立路径（含 policy_id），可独立增删。
///
/// 错误约定（详见 `PolicyGuards`）：删除时 `right` 与策略 `parent_id` 不一致 → 422；Rego 语法错误 → 422。
public struct PolicyController: RouteCollection, Sendable {
    static let policy = PrivilegeSystem.main.policy

    public func boot(routes: any RoutesBuilder) throws {
        let policy = routes.grouped("policy")

        policy.group("domain") { router in
            router.put(use: createDomainPolicies)
            router.put("returning", use: createDomainPoliciesReturning)
            router.delete(use: deleteDomainPolicy)
        }

        policy.group("role") { router in
            router.put(use: createRolePolicies)
            router.put("returning", use: createRolePoliciesReturning)
            router.delete(use: deleteRolePolicy)
        }
    }

}

// MARK: - 域策略

public extension PolicyController {
    /// 为已存在的域批量创建并绑定策略（关系右侧为域 ID）
    @Sendable
    func createDomainPolicies(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, UUID>>.self)
        try await PolicyGuards.run {
            try await Self.policy.create(to: Domain.self, relations: relations)
        }
        return true
    }

    /// 为已存在的域批量创建并绑定策略，并返回按域 ID 分组的策略数据
    @Sendable
    func createDomainPoliciesReturning(req: Request) async throws -> [String: [QPolicy<Domain>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, UUID>>.self)
        let result = try await PolicyGuards.run {
            try await Self.policy.createWithReturning(to: Domain.self, relations: relations)
        }
        return .init(uniqueKeysWithValues: result.map { ($0.key.uuidString, $0.value) })
    }

    /// 删除域策略：left 为完整的 QPolicy<Domain>（可从 DataController 查询获得），right 为其从属的域 ID
    @Sendable
    func deleteDomainPolicy(req: Request) async throws -> Bool {
        let relation = try req.content.decode(OTORelation<QPolicy<Domain>, UUID>.self)
        // 【修复 FINDINGS #6】right 必须与策略实际父级一致，否则会删掉错误的 OPA 路径
        try PolicyGuards.ensureParentMatches(relation.left, parentId: relation.right, label: "域")
        try await Self.policy.delete(from: Domain.self, policy: relation)
        return true
    }
}

// MARK: - 角色策略

public extension PolicyController {
    /// 为已存在的角色批量创建并绑定策略（关系右侧为角色 ID）
    @Sendable
    func createRolePolicies(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Role>, UUID>>.self)
        try await PolicyGuards.run {
            try await Self.policy.create(to: Role.self, relations: relations)
        }
        return true
    }

    /// 为已存在的角色批量创建并绑定策略，并返回按角色 ID 分组的策略数据
    @Sendable
    func createRolePoliciesReturning(req: Request) async throws -> [String: [QPolicy<Role>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Role>, UUID>>.self)
        let result = try await PolicyGuards.run {
            try await Self.policy.createWithReturning(to: Role.self, relations: relations)
        }
        return .init(uniqueKeysWithValues: result.map { ($0.key.uuidString, $0.value) })
    }

    /// 删除角色策略：left 为完整的 QPolicy<Role>（可从 DataController 查询获得），right 为其从属的角色 ID
    @Sendable
    func deleteRolePolicy(req: Request) async throws -> Bool {
        let relation = try req.content.decode(OTORelation<QPolicy<Role>, UUID>.self)
        // 【修复 FINDINGS #6】right 必须与策略实际父级一致，否则会删掉错误的 OPA 路径
        try PolicyGuards.ensureParentMatches(relation.left, parentId: relation.right, label: "角色")
        try await Self.policy.delete(from: Role.self, policy: relation)
        return true
    }
}
