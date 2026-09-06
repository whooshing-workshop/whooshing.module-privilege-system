import Fluent
import VaporTube
import PrivilegeSystemDriver

func routes(_ nexus: Nexus<VaporTube>) throws {
    try nexus.tube.app.register(collection: AccountController())
    
    let dataRouter = nexus.tube.app.grouped("data")
    try dataRouter.register(collection: DataController())
    
    let inlineProtected = nexus.tube.app.inlineProtectGrouped()
    try inlineProtected.register(collection: ArbitrateController())
    
    let apiProtected = nexus.tube.app.apiProtectGrouped(for: .main, in: nexus)
    try apiProtected.register(collection: PrivilegeController())
    try apiProtected.register(collection: ApiAccountController())
    apiProtected.get("test") { req in
        try req.auth.require(QRole.self)
    }
}
