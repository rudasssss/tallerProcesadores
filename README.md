Solo usa la biblioteca estándar de Swift y `Foundation`; no hay generadores de parsers ni paquetes externos.

## Como compilar y ejecutar

```
swift build
swift run ruta test_valido.ruta            # tokens + AST + simulación
swift run ruta test_error.ruta             # errores con línea/columna/ayuda
swift run ruta test_valido.ruta --no-run   # solo análisis, sin simular
```
