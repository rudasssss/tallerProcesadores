// swift-tools-version:5.9
import PackageDescription

// Procesador del lenguaje Ruta. Sin dependencias externas.
// Los fuentes siguen la convención de SPM: Sources/<nombre-del-target>/
let package = Package(
    name: "ruta",
    targets: [
        .executableTarget(
            name: "ruta"
            // path por defecto: Sources/ruta
        )
    ]
)
