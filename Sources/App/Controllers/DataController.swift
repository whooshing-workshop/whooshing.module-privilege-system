import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 只读查询控制器。
///
/// 【修复 FINDINGS #3】原挂载于根路径 `/data`（匿名可读）；现挂载于 admin 保护链下，前缀为 `/api/data`，
/// 需要 `X-Role-Id`(admin) / `X-Credential` / `X-Encrypted-Token` 三个请求头。
///
/// 查询参数均为可选过滤条件，全部省略时返回全表；参数值不是合法 UUID 时该条件被忽略（Vapor `req.query[UUID.self]` 返回 nil）。
/// 所有响应中的关系字段（`users` / `roles` / `policies` …）均为未加载状态 `{ "loaded": false, "value": null }`。
public struct DataController: RouteCollection, Sendable {
    /// 查询 API 设计：
    ///
    ///     查询模型记录:
    ///         所有: http://URL/api/data/MODEL_NAME
    ///         条件: http://URL/api/data/MODEL_NAME?id=XXX
    ///     查询模型关系:
    ///         所有: http://URL/api/data/relation/RELATION_NAME
    ///         条件: http://URL/api/data/relation/RELATION_NAME?LEFT_ID=XXX
    ///         条件: http://URL/api/data/relation/RELATION_NAME?RIGHT_ID=XXX
    ///
    /// 关系记录的编码统一为 `{ id, primary_id, secondary_id, create_at }`：
    ///     domain_user:        primary = user,   secondary = domain
    ///     domain_group:       primary = domain, secondary = group
    ///     user_group:         primary = user,   secondary = group（另含 roles 关系字段：组内角色）
    ///     user_role:          primary = user,   secondary = role
    ///     role_group:         primary = role,   secondary = group
    ///     role_user_in_group: primary = role,   secondary = user_in_group（即 user_group 关系记录的 id）
    ///
    /// 模型记录:
    ///     - GET /domain                      ?id
    ///     - GET /group                       ?id ?parent_id ?name
    ///     - GET /role                        ?id ?name
    ///     - GET /user                        ?id ?email
    ///     - GET /user_info                   ?id ?user_id
    ///     - GET /policy/domain               ?id ?parent_id ?module_id
    ///     - GET /policy/role                 ?id ?parent_id ?module_id
    ///     - GET /info_slice/address          ?id ?user_info_id
    ///     - GET /info_slice/phone            ?id ?user_info_id
    ///     - GET /info_slice/alternate_email  ?id ?user_info_id
    ///
    /// 模型关系:
    ///     - GET /relation/domain_user        ?domain_id ?user_id
    ///     - GET /relation/domain_group       ?domain_id ?group_id
    ///     - GET /relation/user_group         ?user_id   ?group_id
    ///     - GET /relation/user_role          ?user_id   ?role_id
    ///     - GET /relation/role_group         ?role_id   ?group_id
    ///     - GET /relation/role_user_in_group ?role_id   ?user_in_group_id
    public func boot(routes: any RoutesBuilder) throws {
        // 模型记录
        routes.get("domain", use: fetchDomain)
        routes.get("group", use: fetchGroup)
        routes.get("role", use: fetchRole)
        routes.get("user", use: fetchUser)
        routes.get("user_info", use: fetchUserInfo)

        let policy = routes.grouped("policy")
        policy.get("domain", use: fetchDomainPolicy)
        policy.get("role", use: fetchRolePolicy)

        let slice = routes.grouped("info_slice")
        slice.get("address", use: fetchAddressSlice)
        slice.get("phone", use: fetchPhoneSlice)
        slice.get("alternate_email", use: fetchAlternateEmailSlice)

        // 模型关系
        let relation = routes.grouped("relation")
        relation.get("domain_user", use: fetchRelDomainUser)
        relation.get("domain_group", use: fetchRelDomainGroup)
        relation.get("user_group", use: fetchRelUserGroup)
        relation.get("user_role", use: fetchRelUserRole)
        relation.get("role_group", use: fetchRelRoleGroup)
        relation.get("role_user_in_group", use: fetchRelRoleUserInGroup)
    }
}

// MARK: - Domain

public extension DataController {
    @Sendable
    func fetchDomain(req: Request) async throws -> [QDomain] {
        let id = req.query[UUID.self, at: "id"]
        var query = QDomain.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        return try await query.all()
    }
}

// MARK: - Group

public extension DataController {
    @Sendable
    func fetchGroup(req: Request) async throws -> [QGroup] {
        let id = req.query[UUID.self, at: "id"]
        let parentId = req.query[UUID.self, at: "parent_id"]
        let name = req.query[String.self, at: "name"]
        var query = QGroup.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let parentId = parentId { query = query.filter(\.$parent.id == parentId) }
        if let name = name { query = query.filter(\.name == name) }
        return try await query.all()
    }
}

// MARK: - Role

public extension DataController {
    @Sendable
    func fetchRole(req: Request) async throws -> [QRole] {
        let id = req.query[UUID.self, at: "id"]
        let name = req.query[String.self, at: "name"]
        var query = QRole.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let name = name { query = query.filter(\.name == name) }
        return try await query.all()
    }
}

// MARK: - User

public extension DataController {
    @Sendable
    func fetchUser(req: Request) async throws -> [QUser] {
        let id = req.query[UUID.self, at: "id"]
        let email = req.query[String.self, at: "email"]
        var query = QUser.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let email = email { query = query.filter(\.email == email) }
        return try await query.all()
    }
}

// MARK: - UserInfo

public extension DataController {
    @Sendable
    func fetchUserInfo(req: Request) async throws -> [QUserInfo] {
        let id = req.query[UUID.self, at: "id"]
        let userId = req.query[UUID.self, at: "user_id"]
        var query = QUserInfo.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let userId = userId { query = query.filter(\.$user.id == userId) }
        return try await query.all()
    }
}

// MARK: - Policy

public extension DataController {
    @Sendable
    func fetchDomainPolicy(req: Request) async throws -> [QPolicy<Domain>] {
        try await fetchPolicy(Domain.self, req: req)
    }

    @Sendable
    func fetchRolePolicy(req: Request) async throws -> [QPolicy<Role>] {
        try await fetchPolicy(Role.self, req: req)
    }

    internal func fetchPolicy<T: PolicyType>(
        _ type: T.Type,
        req: Request
    ) async throws -> [QPolicy<T>] where T.Model.IDValue == UUID {
        let id = req.query[UUID.self, at: "id"]
        let parentId = req.query[UUID.self, at: "parent_id"]
        let moduleId = req.query[UUID.self, at: "module_id"]
        var query = QPolicy<T>.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let parentId = parentId { query = query.filter(\.$parent.id == parentId) }
        if let moduleId = moduleId { query = query.filter(\.moduleId == moduleId) }
        return try await query.all()
    }
}

// MARK: - InfoSlice

public extension DataController {
    @Sendable
    func fetchAddressSlice(req: Request) async throws -> [QInfoSlice<Address>] {
        try await fetchInfoSlice(Address.self, req: req)
    }

    @Sendable
    func fetchPhoneSlice(req: Request) async throws -> [QInfoSlice<Phone>] {
        try await fetchInfoSlice(Phone.self, req: req)
    }

    @Sendable
    func fetchAlternateEmailSlice(req: Request) async throws -> [QInfoSlice<AlternateEmail>] {
        try await fetchInfoSlice(AlternateEmail.self, req: req)
    }

    internal func fetchInfoSlice<T: UserInfoModel>(
        _ type: T.Type,
        req: Request
    ) async throws -> [QInfoSlice<T>] {
        let id = req.query[UUID.self, at: "id"]
        let userInfoId = req.query[UUID.self, at: "user_info_id"]
        var query = QInfoSlice<T>.query(on: PrivilegeSystem.main.origin)
        if let id = id { query = query.filter(\.id == id) }
        if let userInfoId = userInfoId { query = query.filter(\.$userInfo.id == userInfoId) }
        return try await query.all()
    }
}

// MARK: - Relations

public extension DataController {
    @Sendable
    func fetchRelDomainUser(req: Request) async throws -> [UserTDomain] {
        let domainId = req.query[UUID.self, at: "domain_id"]
        let userId = req.query[UUID.self, at: "user_id"]
        var query = UserTDomain.query(on: PrivilegeSystem.main.origin)
        if let domainId = domainId { query = query.filter(\.domainId == domainId) }
        if let userId = userId { query = query.filter(\.userId == userId) }
        return try await query.all()
    }

    @Sendable
    func fetchRelDomainGroup(req: Request) async throws -> [DomainTGroup] {
        let domainId = req.query[UUID.self, at: "domain_id"]
        let groupId = req.query[UUID.self, at: "group_id"]
        var query = DomainTGroup.query(on: PrivilegeSystem.main.origin)
        if let domainId = domainId { query = query.filter(\.domainId == domainId) }
        if let groupId = groupId { query = query.filter(\.groupId == groupId) }
        return try await query.all()
    }

    @Sendable
    func fetchRelUserGroup(req: Request) async throws -> [UserTGroup] {
        let userId = req.query[UUID.self, at: "user_id"]
        let groupId = req.query[UUID.self, at: "group_id"]
        var query = UserTGroup.query(on: PrivilegeSystem.main.origin)
        if let userId = userId { query = query.filter(\.userId == userId) }
        if let groupId = groupId { query = query.filter(\.groupId == groupId) }
        return try await query.all()
    }

    @Sendable
    func fetchRelUserRole(req: Request) async throws -> [UserTRole] {
        let userId = req.query[UUID.self, at: "user_id"]
        let roleId = req.query[UUID.self, at: "role_id"]
        var query = UserTRole.query(on: PrivilegeSystem.main.origin)
        if let userId = userId { query = query.filter(\.userId == userId) }
        if let roleId = roleId { query = query.filter(\.roleId == roleId) }
        return try await query.all()
    }

    @Sendable
    func fetchRelRoleGroup(req: Request) async throws -> [RoleTGroup] {
        let roleId = req.query[UUID.self, at: "role_id"]
        let groupId = req.query[UUID.self, at: "group_id"]
        var query = RoleTGroup.query(on: PrivilegeSystem.main.origin)
        if let roleId = roleId { query = query.filter(\.roleId == roleId) }
        if let groupId = groupId { query = query.filter(\.groupId == groupId) }
        return try await query.all()
    }

    @Sendable
    func fetchRelRoleUserInGroup(req: Request) async throws -> [RoleTUserInGroup] {
        let roleId = req.query[UUID.self, at: "role_id"]
        let userInGroupId = req.query[UUID.self, at: "user_in_group_id"]
        var query = RoleTUserInGroup.query(on: PrivilegeSystem.main.origin)
        if let roleId = roleId { query = query.filter(\.roleId == roleId) }
        if let userInGroupId = userInGroupId { query = query.filter(\.userInGroupId == userInGroupId) }
        return try await query.all()
    }
}
