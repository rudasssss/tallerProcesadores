// main.swift — Punto de entrada del procesador de Ruta.
//
// Uso:  swift run ruta <archivo.ruta> [--strict] [--no-run]
//   --strict  desactiva la precedencia por espaciado (a+b == a + b)
//   --no-run  solo analiza (tokens + AST), no simula el robot

import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first(where: { !$0.hasPrefix("--") }) else {
    fail("Uso: ruta <archivo.ruta> [--strict] [--no-run]")
}
let spacingPrecedence = !args.contains("--strict")
let runProgram = !args.contains("--no-run")

guard let data = FileManager.default.contents(atPath: path),
      let source = String(data: data, encoding: .utf8) else {
    fail("No se pudo leer el archivo '\(path)'")
}

// Líneas del fuente para mostrar el contexto del error. Se separa a mano por scalars:
// en Swift "\r\n" es un solo Character, así no dependemos de Foundation para CRLF.
let sourceLines: [String] = {
    var lines: [String] = []
    var cur = String.UnicodeScalarView()
    for u in source.unicodeScalars {
        if u == "\n" { lines.append(String(cur)); cur = String.UnicodeScalarView() }
        else if u != "\r" { cur.append(u) }
    }
    lines.append(String(cur))
    return lines
}()

func report(_ e: RutaError) {
    print("error[\(e.phase.rawValue)] línea \(e.line), columna \(e.column): \(e.message)")
    if e.line >= 1 && e.line <= sourceLines.count {
        let text = sourceLines[e.line - 1]
        let num = String(e.line)
        let gutter = String(repeating: " ", count: num.count)
        print("  \(num) | \(text)")
        print("  \(gutter) | \(String(repeating: " ", count: max(e.column - 1, 0)))^")
    }
    if let h = e.hint { print("  ayuda: \(h)") }
    print("")
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

// 1. Análisis léxico
var lexer = Lexer(source: source)
let tokens = lexer.tokenize()

print("=== TOKENS ===")
print("\(pad("POS", 8)) \(pad("TOKEN", 11)) \(pad("LEXEMA", 12)) NOTAS")
for t in tokens {
    var note = ""
    if t.kind == .op { note = "\(t.fixity.rawValue) (espacio izq=\(t.spaceBefore), der=\(t.spaceAfter))" }
    print("\(pad("\(t.line):\(t.column)", 8)) \(pad(t.kind.rawValue, 11)) \(pad(t.lexeme, 12)) \(note)")
}
print("")

var errorCount = lexer.errors.count
lexer.errors.forEach(report)

// 2. Análisis sintáctico
let parser = Parser(tokens: tokens, spacingPrecedence: spacingPrecedence)
let program = parser.parseProgram()
parser.errors.forEach(report)
errorCount += parser.errors.count

if errorCount > 0 {
    print("Se encontraron \(errorCount) error(es); no se ejecuta el programa.")
    exit(1)
}

print("=== AST ===")
print(renderAST(program))

// 3. Ejecución (simulador del robot)
if runProgram {
    print("=== EJECUCIÓN ===")
    do {
        try Interpreter(output: { print($0) }).run(program)
    } catch let e as RutaError {
        report(e)
        exit(1)
    } catch {
        fail("error inesperado: \(error)")
    }
}
