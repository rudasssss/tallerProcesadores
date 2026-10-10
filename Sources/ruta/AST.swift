// AST.swift — Árbol de sintaxis abstracta, errores y tabla de operadores de Ruta.

struct Loc {
    let line: Int
    let column: Int
}

/// Error léxico / sintáctico / de ejecución con posición y ayuda.
struct RutaError: Error {
    enum Phase: String {
        case lexico = "léxico"
        case sintactico = "sintáctico"
        case ejecucion = "ejecución"
        case semantico = "semántico, en tiempo de ejecución"
    }
    let phase: Phase
    let line: Int
    let column: Int
    let message: String
    let hint: String?
    /// true si el problema ya fue reportado por una fase anterior (p. ej. el lexer):
    /// el parser solo se resincroniza y NO lo vuelve a informar (evita cascadas).
    var silent: Bool = false
}

enum Fixity: String {
    case prefix, infix, postfix
}

enum Assoc: String {
    case left, right, none
}

enum Direction: String {
    case left, right
}

/// Información de un operador infijo. La precedencia NO está en la gramática:
/// vive en esta tabla, que el programa puede modificar con `operator ...;`.
struct OpInfo {
    var precedence: Int
    var assoc: Assoc
}

struct OperatorTable {
    var infix: [String: OpInfo] = [
        "*": OpInfo(precedence: 70, assoc: .left),
        "/": OpInfo(precedence: 70, assoc: .left),
        "%": OpInfo(precedence: 70, assoc: .left),
        "+": OpInfo(precedence: 60, assoc: .left),
        "-": OpInfo(precedence: 60, assoc: .left),
        "<": OpInfo(precedence: 40, assoc: .none),
        ">": OpInfo(precedence: 40, assoc: .none),
        "<=": OpInfo(precedence: 40, assoc: .none),
        ">=": OpInfo(precedence: 40, assoc: .none),
        "==": OpInfo(precedence: 30, assoc: .none),
        "!=": OpInfo(precedence: 30, assoc: .none),
    ]
    var prefix: Set<String> = ["-", "+"]
    var postfix: Set<String> = ["!"]
}

indirect enum Expr {
    case number(Double, Loc)
    case variable(String, Loc)
    case prefix(String, Expr, Loc)
    case postfix(String, Expr, Loc)
    case binary(String, Expr, Expr, Loc)

    var loc: Loc {
        switch self {
        case .number(_, let l), .variable(_, let l), .prefix(_, _, let l),
             .postfix(_, _, let l), .binary(_, _, _, let l):
            return l
        }
    }

    /// Forma S-expression, útil para ver cómo quedó agrupada la expresión.
    var sexp: String {
        switch self {
        case .number(let v, _): return formatNumber(v)
        case .variable(let n, _): return n
        case .prefix(let op, let e, _): return "(\(op)prefijo \(e.sexp))"
        case .postfix(let op, let e, _): return "(\(e.sexp) \(op)postfijo)"
        case .binary(let op, let l, let r, _): return "(\(op) \(l.sexp) \(r.sexp))"
        }
    }
}

indirect enum Stmt {
    case forward(Expr, Loc)
    case turn(Direction, Loc)
    case stop(Loc)
    case returnBase(Loc)
    case assign(String, Expr, Loc)
    case ifElse(cond: Expr, then: Stmt, else: Stmt?, Loc)
    case repeatLoop(count: Expr, body: Stmt, Loc)
    case block([Stmt], Loc)
    case operatorDecl(symbol: String, fixity: Fixity, precedence: Int?, assoc: Assoc?, Loc)
}

func formatNumber(_ v: Double) -> String {
    if v == v.rounded() && abs(v) < 1e15 { return String(Int(v)) }
    return String(v)
}

// MARK: - Impresión del AST

func renderAST(_ stmts: [Stmt]) -> String {
    var out = "Programa\n"
    for s in stmts { out += render(s, indent: 1) }
    return out
}

private func render(_ s: Stmt, indent: Int) -> String {
    let pad = String(repeating: "  ", count: indent)
    switch s {
    case .forward(let e, _):
        return "\(pad)Forward  \(e.sexp)\n"
    case .turn(let d, _):
        return "\(pad)Turn     \(d.rawValue)\n"
    case .stop:
        return "\(pad)Stop\n"
    case .returnBase:
        return "\(pad)ReturnBase\n"
    case .assign(let n, let e, _):
        return "\(pad)Assign   \(n) = \(e.sexp)\n"
    case .ifElse(let c, let t, let e, _):
        var out = "\(pad)If       \(c.sexp)\n\(pad)  then:\n" + render(t, indent: indent + 2)
        if let e = e { out += "\(pad)  else:\n" + render(e, indent: indent + 2) }
        return out
    case .repeatLoop(let n, let b, _):
        return "\(pad)Repeat   \(n.sexp) veces\n" + render(b, indent: indent + 1)
    case .block(let list, _):
        var out = "\(pad)Block\n"
        for x in list { out += render(x, indent: indent + 1) }
        return out
    case .operatorDecl(let sym, let fx, let p, let a, _):
        let ps = p.map { " precedence \($0)" } ?? ""
        let asx = a.map { " assoc \($0.rawValue)" } ?? ""
        return "\(pad)OperatorDecl \(sym) \(fx.rawValue)\(ps)\(asx)\n"
    }
}
