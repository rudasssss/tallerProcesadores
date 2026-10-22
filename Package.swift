// swift-tools-version:5.9
import PackageDescription

// Configuración del paquete del procesador de Ruta. No usamos librerías externas.
// El código está en Sources/ruta/, que es donde Swift lo busca por defecto.
let package = Package(
    name: "ruta",
    targets: [
        .executableTarget(
            name: "ruta"
            // no hace falta poner la ruta, usa Sources/ruta
        )
    ]
)
