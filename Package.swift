// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyTasks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MyTasks", path: "Sources/MyTasks"),
        .testTarget(name: "MyTasksTests", dependencies: ["MyTasks"], path: "Tests/MyTasksTests"),
    ]
)
