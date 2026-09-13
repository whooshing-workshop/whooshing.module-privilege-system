import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 策略一致性守卫（【修复 FINDINGS #6 / #9】）
///
/// 背景：OPA 中策略的存放路径仅由 `(moduleId, 所属角色/域 ID)` 决定（`m_<module>/role/id_<role>`），
/// 而数据库允许同一角色（或域）在同一模块下存在多条策略。这会导致：
///   - 后写入的策略在 OPA 中**覆盖**先写入的策略，数据库却两条都在；
///   - 删除其中任意一条时，OPA 路径被整体删除，数据库中残留的另一条从此不再生效（直到服务重启重新注入）；
///   - `DELETE /api/policy/*` 若传入与策略实际父级不一致的 `right`，会删掉错误的 OPA 路径。
///
/// 权限主系统在库层面无法改变这一行为，因此在 App 层强制约束：
///   **同一 (module, parent) 只允许一条策略**；创建时重复 → 409；删除时 `right` 必须等于策略的 `parent_id` → 422。
/// 需要替换策略时，先删除再创建（或使用 `replace` 语义的接口）。
enum PolicyGuards {
    /// 一批待创建的策略在“批内”不得出现同一 parent 在同一 module 下的多条策略
    ///
    /// - Parameter pairs: 每条策略的 (moduleId, parentKey)。parentKey 对于“连带创建”的场景可用批内序号代替。
    static func ensureNoDuplicateInBatch(_ pairs: [(moduleId: UUID, parentKey: String)], label: String) throws {
        var seen = Set<String>()
        for p in pairs {
            let key = "\(p.moduleId.uuidString)|\(p.parentKey)"
            guard seen.insert(key).inserted else {
                throw Abort(.conflict, reason: "同一\(label)在同一模块(\(p.moduleId))下只允许一条策略，请求中出现了重复")
            }
        }
    }

    /// 数据库中不得已存在同一 (module, parent) 的策略
    static func ensureNotExists<T: PolicyType>(
        _ type: T.Type,
        pairs: [(moduleId: UUID, parentId: UUID)],
        label: String
    ) async throws where T.Model.IDValue == UUID {
        let origin = PrivilegeSystem.main.origin
        for p in pairs {
            let existing = try await QPolicy<T>.query(on: origin)
                .filter(\.$parent.id == p.parentId)
                .filter(\.moduleId == p.moduleId)
                .all()
            guard existing.isEmpty else {
                throw Abort(
                    .conflict,
                    reason: "\(label) \(p.parentId) 在模块 \(p.moduleId) 下已存在策略 \(existing.map { $0.id.uuidString }.joined(separator: ","))；请先删除旧策略再创建（同一模块下只允许一条）"
                )
            }
        }
    }

    /// 删除策略时，请求中的所属 ID 必须与策略记录的 parent_id 一致
    static func ensureParentMatches<T: PolicyType>(_ policy: QPolicy<T>, parentId: UUID, label: String) throws where T.Model.IDValue == UUID {
        guard policy.$parent.id == parentId else {
            throw Abort(.unprocessableEntity, reason: "策略 \(policy.id) 属于\(label) \(policy.$parent.id)，与请求中的 \(parentId) 不一致")
        }
    }

    /// 把 OPA 写入失败（最常见是 Rego 语法错误）从 500 映射为 422
    ///
    /// 【修复 FINDINGS #9】库层把 OPA 拒绝策略归为内部错误（500），客户端无法区分“策略写错了”与“服务故障”。
    /// 库未导出可判别的错误类型，此处以错误描述中是否包含 "OPA" 作为判据；
    /// 若 OPA 本身不可达也会落到这里，因此 reason 中同时给出两种可能。
    static func mapOPAError(_ error: Error) -> Error {
        let text = "\(error)"
        if text.contains("OPA") {
            return Abort(.unprocessableEntity, reason: "策略未被 OPA 接受：请检查 Rego 语法（或确认 EOPA 服务可用）。详情: \(text.prefix(500))")
        }
        return error
    }

    /// 在闭包中执行策略写入并做错误映射
    static func run<R>(_ body: () async throws -> R) async throws -> R {
        do {
            return try await body()
        } catch {
            throw mapOPAError(error)
        }
    }
}
