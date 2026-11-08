// swift-tools-version: 6.0
// NOVACore — платформенно-независимая логика NOVA AI (модели, Claude API, белый список
// инструментов, валидация аргументов, память, настройки). Её можно собрать и протестировать
// командой `swift test`. Само macOS-приложение (UI, голос, автоматизация) собирается через
// XcodeGen (`project.yml`) и подключает этот пакет как локальную зависимость.
import PackageDescription

let package = Package(
    name: "NOVACore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NOVACore", targets: ["NOVACore"])
    ],
    targets: [
        .target(
            name: "NOVACore",
            path: "Sources/NOVACore"
        ),
        .testTarget(
            name: "NOVACoreTests",
            dependencies: ["NOVACore"],
            path: "Tests/NOVACoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
