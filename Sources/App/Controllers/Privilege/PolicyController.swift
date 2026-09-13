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

    /// 通用前置校验：批内不重复 + 数据库中不存在
    static func precheck<T: PolicyType>(
        _ type: T.Type,
        relations: OrderedSet<MTORelation<PPolicy<T>, UUID>>,
        label: String
    ) async throws where T.Model.IDValue == UUID {
        var pairs: [(moduleId: UUID, parentId: UUID)] = []
        for r in relations {
            for p in r.left {
                pairs.append((p.moduleId, r.right))
            }
        }
        try PolicyGuards.ensureNoDuplicateInBatch(pairs.map { (moduleId: $0.moduleId, parentKey: $0.parentId.uuidString) }, label: label)
        try await PolicyGuards.ensureNotExists(T.self, pairs: pairs, label: label)
    }
}

// MARK: - 域策略

public extension PolicyController {
    /// 为已存在的域批量创建并绑定策略（关系右侧为域 ID）
    @Sendable
    func createDomainPolicies(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, UUID>>.self)
        try await Self.precheck(Domain.self, relations: relations, label: "域")
        try await PolicyGuards.run {
            try await Self.policy.create(to: Domain.self, relations: relations)
        }
        return true
    }

    /// 为已存在的域批量创建并绑定策略，并返回按域 ID 分组的策略数据
    @Sendable
    func createDomainPoliciesReturning(req: Request) async throws -> [String: [QPolicy<Domain>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, UUID>>.self)
        try await Self.precheck(Domain.self, relations: relations, label: "域")
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
        try await Self.precheck(Role.self, relations: relations, label: "角色")
        try await PolicyGuards.run {
            try await Self.policy.create(to: Role.self, relations: relations)
        }
        return true
    }

    /// 为已存在的角色批量创建并绑定策略，并返回按角色 ID 分组的策略数据
    @Sendable
    func createRolePoliciesReturning(req: Request) async throws -> [String: [QPolicy<Role>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Role>, UUID>>.self)
        try await Self.precheck(Role.self, relations: relations, label: "角色")
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
