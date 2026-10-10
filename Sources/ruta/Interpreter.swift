// Interpreter.swift — Simulador del robot: ejecuta el AST e imprime cada acción.

import Foundation

final class Interpreter {
    private var vars: [String: Double] = [:]
    private var x = 0.0, y = 0.0
    private var heading = 0   // grados; 0 = norte, 90 = este
    private var stopped = false
    private var steps = 0
    private let maxSteps = 1_000_000
    private let out: (String) -> Void

    init(output: @escaping (String) -> Void) { self.out = output }

    func run(_ program: [Stmt]) throws {
        out("Inicio en (0, 0) mirando al norte")
        for s in program {
            try exec(s)
            if stopped { break }
        }
        out("Fin: posición (\(formatNumber(x)), \(formatNumber(y))), rumbo \(heading)°")
    }

    private func tick(_ l: Loc) throws {
        steps += 1
        if steps > maxSteps { throw runtimeError(l, "se superó el límite de \(maxSteps) pasos", "¿Hay un 'repeat' con un contador enorme?") }
    }

    private func exec(_ s: Stmt) throws {
        if stopped { return }
        switch s {
        case .forward(let e, let l):
            try tick(l)
            let d = try eval(e)
            let rad = Double(heading) * Double.pi / 180
            x += d * sin(rad)
            y += d * cos(rad)
            out("  forward \(formatNumber(d))  -> (\(fmt(x)), \(fmt(y)))")
        case .turn(let d, let l):
            try tick(l)
            heading = ((heading + (d == .right ? 90 : -90)) % 360 + 360) % 360
            out("  turn \(d.rawValue)  -> rumbo \(heading)°")
        case .stop(let l):
            try tick(l)
            out("  stop  (el robot se detiene)")
            stopped = true
        case .returnBase(let l):
            try tick(l)
            x = 0; y = 0; heading = 0
            out("  return base  -> (0, 0)")
        case .assign(let n, let e, let l):
            try tick(l)
            let v = try eval(e)
            vars[n] = v
            out("  \(n) = \(formatNumber(v))")
        case .ifElse(let c, let t, let e, _):
            let v = try eval(c)
            if v != 0 { try exec(t) } else if let e = e { try exec(e) }
        case .repeatLoop(let n, let body, let l):
            let count = try eval(n)
            if count < 0 || count != count.rounded() {
                throw runtimeError(n.loc, "'repeat' requiere un entero no negativo, no \(formatNumber(count))", nil)
            }
            var i = 0
            while Double(i) < count && !stopped {
                try tick(l)
                try exec(body)
                i += 1
            }
        case .block(let list, _):
            for st in list { try exec(st); if stopped { break } }
        case .operatorDecl:
            break   // ya fue procesada por el parser
        }
    }

    private func fmt(_ v: Double) -> String {
        formatNumber((v * 1000).rounded() / 1000)
    }

    /// Operador declarado con `operator ...;` (o parseable) sin implementación en el simulador.
    private func noSemantics(_ l: Loc, _ op: String, _ fixity: Fixity, _ available: String) -> RutaError {
        RutaError(phase: .semantico, line: l.line, column: l.column,
                  message: "El operador \(fixity.rawValue) '\(op)' fue declarado pero no tiene una semántica implementada en el simulador",
                  hint: "La declaración 'operator' solo define sintaxis (posición, precedencia, asociatividad). "
                      + "Operadores ejecutables de tipo \(fixity.rawValue): \(available).")
    }

    private func runtimeError(_ l: Loc, _ msg: String, _ hint: String?) -> RutaError {
        RutaError(phase: .ejecucion, line: l.line, column: l.column, message: msg, hint: hint)
    }

    // MARK: expresiones

    private func eval(_ e: Expr) throws -> Double {
        switch e {
        case .number(let v, _): return v
        case .variable(let n, let l):
            guard let v = vars[n] else {
                throw runtimeError(l, "la variable '\(n)' no ha sido asignada", "Asígnela antes de usarla: \(n) = 0;")
            }
            return v
        case .prefix(let op, let sub, let l):
            let v = try eval(sub)
            switch op {
            case "-": return -v
            case "+": return v
            default: throw noSemantics(l, op, .prefix, "- +")
            }
        case .postfix(let op, let sub, let l):
            let v = try eval(sub)
            guard op == "!" else {
                throw noSemantics(l, op, .postfix, "!")
            }
            guard v >= 0, v == v.rounded(), v <= 170 else {
                throw runtimeError(l, "factorial solo definido para enteros entre 0 y 170, no \(formatNumber(v))", nil)
            }
            var r = 1.0
            if v >= 2 { for i in 2...Int(v) { r *= Double(i) } }
            return r
        case .binary(let op, let l, let r, let loc):
            let a = try eval(l), b = try eval(r)
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/", "%":
                if b == 0 { throw runtimeError(loc, "división entre cero", "Verifique que el divisor no valga 0.") }
                return op == "/" ? a / b : a.truncatingRemainder(dividingBy: b)
            case "**": return pow(a, b)
            case "<": return a < b ? 1 : 0
            case ">": return a > b ? 1 : 0
            case "<=": return a <= b ? 1 : 0
            case ">=": return a >= b ? 1 : 0
            case "==": return a == b ? 1 : 0
            case "!=": return a != b ? 1 : 0
            default:
                throw noSemantics(loc, op, .infix, "+ - * / % ** < > <= >= == !=")
            }
        }
    }
}
