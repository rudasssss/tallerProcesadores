// main.swift
//
// Desde aquí arranca todo: lee el archivo, lo pasa por el lexer, después por el
// parser y, si no hubo errores, lo ejecuta en el simulador.
//
// Uso:  swift run ruta <archivo.ruta> [--strict] [--no-run]
//   --strict  los espacios ya no cambian la precedencia (a+b vale lo mismo que a + b)
//   --no-run  solo analiza y muestra tokens y árbol, sin mover al robot

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

// Guardamos las líneas del archivo para poder mostrar la línea donde está el error.
// Las separamos a mano porque en Swift "\r\n" (fin de línea de Windows) cuenta como
// un solo caracter y con split normal no se cortaban bien.
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

// Muestra un error así: el mensaje, la línea del programa, una ^ debajo de donde
// falló y, si hay, una ayuda.
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

// Paso 1: análisis léxico (de texto a tokens)
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

// Paso 2: análisis sintáctico (revisar que los tokens sigan la gramática)
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

// Paso 3: si todo salió bien, ponemos a andar al robot en el simulador
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
