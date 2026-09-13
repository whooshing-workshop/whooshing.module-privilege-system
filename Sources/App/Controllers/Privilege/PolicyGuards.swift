import PrivilegeSystemDriver
import VaporTube
import Foundation

/// 策略守卫（【修复 FINDINGS #6 / #9】）
///
/// 历史：旧版 toolbox-privilege-system 的 OPA 策略路径只由 `(module_id, 角色/域 ID)` 决定，同一角色在同一模块下的多条策略会在 OPA
/// 中互相覆盖，因此 App 层曾在这里强制“同一 (module, parent) 只允许一条策略”（`ensureNotExists` → 409）。
///
/// 自 toolbox-privilege-system V1.1.1.2 起，OPA 路径已带上 `policy_id`（`m_<module>.role.v_<role>.p_<policy>`），
/// 同一角色 / 域在同一模块下可以有多条策略，仲裁时逐条求值并按 **AND** 合并（任一策略拒绝即拒绝；零条策略视为拒绝）。
///
///   1. 删除策略时，请求中的所属 ID（`right`）必须与策略记录的 `parent_id` 一致，否则拒绝（422），
///      避免按错误的 (module, parent, policy) 组合去删 OPA 路径；
///   2. OPA 拒绝策略（最常见是 Rego 语法错误）时，把库层的内部错误映射为 422，
///      让客户端能区分“策略写错了”与“服务故障”。
enum PolicyGuards {
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
