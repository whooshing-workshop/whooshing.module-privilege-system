// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "whooshing.module-privilege-system",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .executable(name: "App", targets: ["App"])
    ],
    dependencies: [
        // 💧 Vapor -- Swift 服务器端第三方框架
        .package(url: "https://github.com/vapor/vapor", from: "4.122.0"),
        // 🔵 Swift 高性能网络通讯模块
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // ⭐️ Vapor 管道通讯模块
        .package(url: "https://github.com/whooshing-workshop/whooshing.tube-vapor", from: "1.0.0"),
        // 📁 Whooshing 文件加密系统模块驱动
        .package(url: "https://github.com/whooshing-workshop/whooshing.driver-file-storage.git", from: "1.1.3"),
        // 🪩 Whooshing 权限系统模块驱动
        .package(url: "https://github.com/whooshing-workshop/whooshing.driver-privilege-system.git", from: "1.0.8"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "VaporTube", package: "whooshing.tube-vapor"),
                .product(name: "FileStorageDriver", package: "whooshing.driver-file-storage"),
                .product(name: "PrivilegeSystemDriver", package: "whooshing.driver-privilege-system")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("DisableOutwardActorInference"),
        .enableExperimentalFeature("StrictConcurrency")
    ]
}
