import PrivilegeSystemDriver
import Foundation

/// 权限系统总控制器：统一注册各权限子控制器（增删改与关系设置）。
///
/// 子控制器：
///   - `DomainController`     域：增删改、指派用户 / 群组
///   - `GroupController`      群组：层级增删改、加入 / 踢出用户、移动、组内关系查询
///   - `RoleController`       角色：增删改、任命用户 / 群组 / 组内、任命判定
///   - `PolicyController`     为已有角色 / 域追加或删除策略
///   - `InfoSliceController`  用户附加信息切片（地址 / 电话 / 备用邮箱）
///   - `UserInfoController`   用户主信息
///
/// 查询 API 统一由 DataController 提供（见 routes.swift 中的 `/api/data` 分组）。
public struct PrivilegeController: RouteCollection, Sendable {
    public func boot(routes: any RoutesBuilder) throws {
        try routes.register(collection: DomainController())
        try routes.register(collection: GroupController())
        try routes.register(collection: RoleController())
        try routes.register(collection: PolicyController())
        try routes.register(collection: InfoSliceController())
        try routes.register(collection: UserInfoController())
    }
}
