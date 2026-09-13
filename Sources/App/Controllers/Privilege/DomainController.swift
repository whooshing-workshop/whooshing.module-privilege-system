import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 域控制器：域的增删改与指派（用户 / 群组）。
///
/// 域是“限制性”的权限单元：用户（直接被指派、或经所在群组及其全部祖先群组被指派）持有的**每一个**域，
/// 其在目标模块下的策略都必须放行，仲裁才会通过；域在某模块下没有策略时视为拒绝。
///
/// 路由（均位于 admin 保护链 `/api` 下）：
///
///     PUT    /domain                          body: [PDomain]                                  → [QDomain]
///     PUT    /domain/with_policies            body: [ { left: [PPolicy], right: PDomain } ]    → true
///     PUT    /domain/with_policies/returning  同上                                              → { domainId: [QPolicy] }
///     DELETE /domain                          body: [UUID]                                     → true（级联删除策略与指派）
///     POST   /domain/:domainId/name           body: String                                     → QDomain
///     POST   /domain/:domainId/summary        body: String?                                    → QDomain
///     POST   /domain/assign/user              body: [ { left: [domainId], right: [userId] } ]  → true
///     POST   /domain/assign/group             body: [ { left: [domainId], right: [groupId] } ] → true
///     POST   /domain/unassign/{user|group}    同上                                              → true
public struct DomainController: RouteCollection, Sendable {
    static let domain = PrivilegeSystem.main.domain

    /// 【修复 FINDINGS #6】“连带策略创建”时，同一个域在同一模块下只允许一条策略（批内校验）
    static func precheck(_ relations: OrderedSet<MTORelation<PPolicy<Domain>, PDomain>>) throws {
        var pairs: [(moduleId: UUID, parentKey: String)] = []
        for (i, r) in relations.enumerated() {
            for p in r.left { pairs.append((p.moduleId, "#\(i)")) }
        }
        try PolicyGuards.ensureNoDuplicateInBatch(pairs, label: "域")
    }

    public func boot(routes: any RoutesBuilder) throws {
        let domain = routes.grouped("domain")
        domain.put(use: create)
        domain.delete(use: delete)

        // 域连带策略一同创建
        domain.group("with_policies") { router in
            router.put(use: createWithPolicies)
            router.put("returning", use: createWithPoliciesReturning)
        }

        domain.group(":domainId") { router in
            router.post("name", use: updateName)
            router.post("summary", use: updateSummary)
        }

        domain.group("assign") { router in
            router.post("user", use: assignUser)
            router.post("group", use: assignGroup)
        }

        domain.group("unassign") { router in
            router.post("user", use: unassignUser)
            router.post("group", use: unassignGroup)
        }
    }
}

// MARK: - 增

public extension DomainController {
    @Sendable
    func create(req: Request) async throws -> [QDomain] {
        let domains = try req.content.decode(OrderedSet<PDomain>.self)
        return try await Self.domain.create(domains: domains)
    }

    /// 创建域，同时为其绑定域策略（不返回详细数据）
    @Sendable
    func createWithPolicies(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, PDomain>>.self)
        try Self.precheck(relations)
        // 【修复 FINDINGS #9】Rego 语法错误 → 422
        try await PolicyGuards.run { try await Self.domain.create(relations: relations) }
        return true
    }

    /// 创建域，同时为其绑定域策略，并返回按域 ID 分组的策略数据
    @Sendable
    func createWithPoliciesReturning(req: Request) async throws -> [String: [QPolicy<Domain>]] {
        let relations = try req.content.decode(OrderedSet<MTORelation<PPolicy<Domain>, PDomain>>.self)
        try Self.precheck(relations)
        // 【修复 FINDINGS #9】Rego 语法错误 → 422
        let result = try await PolicyGuards.run { try await Self.domain.createWithReturning(relations: relations) }
        return .init(uniqueKeysWithValues: result.map { ($0.key.uuidString, $0.value) })
    }
}

// MARK: - 删

public extension DomainController {
    @Sendable
    func delete(req: Request) async throws -> Bool {
        let ids = try req.content.decode(OrderedSet<UUID>.self)
        try await Self.domain.delete(domainIds: ids)
        return true
    }
}

// MARK: - 改

public extension DomainController {
    @Sendable
    func updateName(req: Request) async throws -> QDomain {
        let domainId = try parameter("domainId", from: req) { UUID(uuidString: $0) }
        let name = try req.content.decode(String.self)
        let updater = PDomain.Updater(domainId: domainId).update(name: name)
        return try await Self.domain.update(with: updater)
    }

    @Sendable
    func updateSummary(req: Request) async throws -> QDomain {
        let domainId = try parameter("domainId", from: req) { UUID(uuidString: $0) }
        let summary = try req.content.decode(String?.self)
        let updater = PDomain.Updater(domainId: domainId).update(summary: summary)
        return try await Self.domain.update(with: updater)
    }
}

// MARK: - 模型关系

public extension DomainController {
    @Sendable
    func assignUser(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.domain.assign(domainToUser: relations)
        return true
    }

    @Sendable
    func assignGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.domain.assign(domainToGroup: relations)
        return true
    }
}

public extension DomainController {
    @Sendable
    func unassignUser(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.domain.unassign(domainFromUser: relations)
        return true
    }

    @Sendable
    func unassignGroup(req: Request) async throws -> Bool {
        let relations = try req.content.decode(OrderedSet<MTMRelation<UUID, UUID>>.self)
        try await Self.domain.unassign(domainFromGroup: relations)
        return true
    }
}
