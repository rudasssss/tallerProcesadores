// Parser.swift — Parser manual (descenso recursivo + Pratt) de Ruta.
//
// Sentencias: descenso recursivo. El `else` se enlaza al `if` más cercano
// porque el `if` interno consume el `else` antes de volver al externo
// (implementa la gramática "cerrada/abierta" de gramatica.md).
//
// Expresiones: parser de precedencias (Pratt) guiado por una TABLA DE
// OPERADORES en tiempo de ejecución, al estilo Swift:
//   1. La precedencia/asociatividad no están en la gramática sino en
//      `OperatorTable`, modificable con `operator ... ;` mientras se parsea.
//   2. El ESPACIADO decide prefijo / infijo / postfijo (`Token.fixity`).
//   3. Un infijo "apretado" (`a+b`) recibe un bonus de precedencia sobre uno
//      con espacios (`a + b`), de modo que `1+2 * 3` agrupa como `(1+2) * 3`.

final class Parser {
    private let tokens: [Token]
    private var pos = 0
    private(set) var table = OperatorTable()
    private(set) var errors: [RutaError] = []
    private let spacingPrecedence: Bool

    /// Bonus que gana un infijo apretado; mayor que cualquier precedencia razonable.
    private static let tightBonus = 1000

    init(tokens: [Token], spacingPrecedence: Bool = true) {
        self.tokens = tokens
        self.spacingPrecedence = spacingPrecedence
    }

    // MARK: utilidades

    private var current: Token { tokens[pos] }
    private var previous: Token { tokens[max(pos - 1, 0)] }

    private func advance() {
        if current.kind != .eof { pos += 1 }
    }

    private func check(_ k: TokenKind) -> Bool { current.kind == k }

    private func match(_ k: TokenKind) -> Bool {
        if check(k) { advance(); return true }
        return false
    }

    private func fail(_ t: Token, _ msg: String, _ hint: String? = nil) -> RutaError {
        RutaError(phase: .sintactico, line: t.line, column: t.column, message: msg, hint: hint,
                  silent: t.kind == .invalid)
    }

    /// Registra un error del parser salvo que sea eco de un error léxico ya reportado.
    private func record(_ e: RutaError) {
        if !e.silent { errors.append(e) }
    }

    /// Error situado justo después del último token consumido (p. ej. `;` faltante).
    private func failAfterPrevious(_ msg: String, _ hint: String? = nil) -> RutaError {
        let p = previous
        // Si lo que realmente aparece es un lexema inválido, el problema ya se informó.
        return RutaError(phase: .sintactico, line: p.line, column: p.endColumn, message: msg, hint: hint,
                         silent: current.kind == .invalid)
    }

    private func describe(_ t: Token) -> String {
        t.kind == .eof ? "el final del archivo" : "'\(t.lexeme)'"
    }

    private func expect(_ k: TokenKind, _ msg: String, _ hint: String? = nil) throws {
        if check(k) { advance(); return }
        // Los delimitadores que "faltan" se reportan al final de la línea anterior.
        if k == .semicolon || k == .rparen {
            throw failAfterPrevious(msg, hint)
        }
        throw fail(current, msg + " pero se encontró \(describe(current))", hint)
    }

    // MARK: programa y recuperación de errores

    func parseProgram() -> [Stmt] {
        var stmts: [Stmt] = []
        while !check(.eof) {
            let start = pos
            do {
                stmts.append(try parseStatement())
            } catch let e as RutaError {
                record(e)
                synchronize()
                if pos == start { advance() }   // garantiza progreso
            } catch {
                fatalError("error inesperado: \(error)")
            }
        }
        return stmts
    }

    /// Modo pánico: tras un error se descartan tokens hasta un punto de sincronización:
    ///   - un `;` (se consume y termina la sentencia dañada),
    ///   - un `}` o `{`, o una palabra clave que inicia sentencia,
    ///   - un identificador al comienzo de una línea nueva.
    /// Un `else` huérfano (su `if` ya fue descartado) se descarta sin avisar: informarlo
    /// sería un falso error en cascada.
    private func synchronize() {
        while !check(.eof) {
            if check(.semicolon) { advance(); return }
            if check(.kwElse) { advance(); continue }
            if check(.identifier) && current.line != previous.line { return }
            switch current.kind {
            case .rbrace, .kwForward, .kwTurn, .kwStop, .kwReturn, .kwIf, .kwRepeat, .kwOperator, .lbrace:
                return
            default:
                advance()
            }
        }
    }

    // MARK: sentencias

    private func parseStatement() throws -> Stmt {
        let t = current
        switch t.kind {
        case .kwIf:
            advance()
            let cond = try parseExpr()
            try expect(.kwThen, "se esperaba 'then' después de la condición del 'if'",
                       "Sintaxis: if <condición> then <sentencia> [else <sentencia>]")
            let thenS = try parseStatement()
            var elseS: Stmt? = nil
            // Dangling else: este `if` toma el `else` que venga ahora; si había un
            // `if` anidado en `thenS`, ese ya lo consumió antes (el más cercano gana).
            if match(.kwElse) { elseS = try parseStatement() }
            return .ifElse(cond: cond, then: thenS, else: elseS, t.loc)

        case .kwRepeat:
            advance()
            let n = try parseExpr()
            try expect(.kwTimes, "se esperaba 'times' después del número de repeticiones",
                       "Sintaxis: repeat <expresión> times <sentencia>")
            let body = try parseStatement()
            return .repeatLoop(count: n, body: body, t.loc)

        case .lbrace:
            advance()
            var list: [Stmt] = []
            while !check(.rbrace) {
                if check(.eof) {
                    throw fail(t, "la llave '{' abierta aquí nunca se cierra",
                               "Agregue '}' al final del bloque.")
                }
                let start = pos
                do {
                    list.append(try parseStatement())
                } catch let e as RutaError {
                    record(e)
                    synchronize()
                    if pos == start { advance() }
                }
            }
            advance()  // '}'
            return .block(list, t.loc)

        default:
            let s = try parseSimple()
            try expect(.semicolon, "falta ';' al final de la sentencia",
                       "Toda sentencia simple (forward, turn, stop, return base, asignación, operator) termina en ';'.")
            return s
        }
    }

    private func parseSimple() throws -> Stmt {
        let t = current
        switch t.kind {
        case .kwForward:
            advance()
            if check(.semicolon) || check(.eof) {
                throw failAfterPrevious("'forward' necesita una distancia",
                                        "Ejemplo: forward 10;  o  forward 2 * speed + 1;")
            }
            return .forward(try parseExpr(), t.loc)

        case .kwTurn:
            advance()
            if match(.kwRight) { return .turn(.right, t.loc) }
            if match(.kwLeft) { return .turn(.left, t.loc) }
            throw fail(current, "después de 'turn' se esperaba 'right' o 'left' pero se encontró \(describe(current))",
                       "Ejemplo: turn right;")

        case .kwStop:
            advance()
            return .stop(t.loc)

        case .kwReturn:
            advance()
            if !check(.kwBase) {
                throw fail(current, "después de 'return' se esperaba 'base' pero se encontró \(describe(current))",
                           "El único retorno válido es: return base;")
            }
            advance()
            return .returnBase(t.loc)

        case .identifier:
            advance()
            if match(.assign) {
                return .assign(t.lexeme, try parseExpr(), t.loc)
            }
            if let sug = closestKeyword(to: t.lexeme) {
                throw fail(t, "'\(t.lexeme)' no es un comando de Ruta",
                           "¿Quiso decir '\(sug)'? (Para asignar use: \(t.lexeme) = expresión;)")
            }
            throw fail(current, "después de la variable '\(t.lexeme)' se esperaba '=' pero se encontró \(describe(current))",
                       "Para asignar escriba: \(t.lexeme) = expresión;")

        case .kwOperator:
            return try parseOperatorDecl()

        case .kwElse:
            throw fail(t, "'else' sin un 'if' correspondiente",
                       "Cada 'else' debe seguir a la sentencia 'then' de un 'if'. Revise si sobra un ';' o falta un 'if'.")

        case .rbrace:
            throw fail(t, "'}' sin su '{' correspondiente", "Elimine la llave sobrante o abra el bloque con '{'.")

        default:
            throw fail(t, "se esperaba una sentencia pero se encontró \(describe(t))",
                       "Una sentencia empieza con: forward, turn, stop, return, if, repeat, operator, '{' o un nombre de variable.")
        }
    }

    /// operator <símbolo> infix|prefix|postfix [precedence N] [assoc left|right|none] ;
    private func parseOperatorDecl() throws -> Stmt {
        let kw = current
        advance()
        guard check(.op) || check(.assign) else {
            throw fail(current, "después de 'operator' se esperaba un símbolo de operador pero se encontró \(describe(current))",
                       "Ejemplo: operator ** infix precedence 80 assoc right;")
        }
        let sym = current.lexeme
        advance()

        let fixity: Fixity
        if match(.kwInfix) { fixity = .infix }
        else if match(.kwPrefix) { fixity = .prefix }
        else if match(.kwPostfix) { fixity = .postfix }
        else {
            throw fail(current, "se esperaba 'infix', 'prefix' o 'postfix' pero se encontró \(describe(current))",
                       "Indique la posición del operador: operator \(sym) infix ...;")
        }

        var prec: Int? = nil
        var assoc: Assoc? = nil
        while true {
            if match(.kwPrecedence) {
                guard check(.number), let v = Int(current.lexeme) else {
                    throw fail(current, "'precedence' requiere un entero (0..999) pero se encontró \(describe(current))",
                               "Ejemplo: precedence 80")
                }
                if v > 999 { throw fail(current, "precedencia \(v) fuera de rango", "Use un valor entre 0 y 999.") }
                prec = v
                advance()
            } else if match(.kwAssoc) {
                if match(.kwLeft) { assoc = .left }
                else if match(.kwRight) { assoc = .right }
                else if check(.identifier), current.lexeme == "none" { assoc = Assoc.none; advance() }
                else {
                    throw fail(current, "'assoc' requiere left, right o none pero se encontró \(describe(current))", nil)
                }
            } else {
                break
            }
        }

        // Efecto inmediato: a partir de aquí el parser usa la nueva tabla.
        switch fixity {
        case .infix:
            table.infix[sym] = OpInfo(precedence: prec ?? table.infix[sym]?.precedence ?? 50,
                                      assoc: assoc ?? table.infix[sym]?.assoc ?? .left)
        case .prefix: table.prefix.insert(sym)
        case .postfix: table.postfix.insert(sym)
        }
        return .operatorDecl(symbol: sym, fixity: fixity, precedence: prec, assoc: assoc, kw.loc)
    }

    // MARK: expresiones

    /// Precedencia efectiva de un infijo concreto (tabla + bonus por espaciado).
    private func effectivePrecedence(_ t: Token, _ info: OpInfo) -> Int {
        info.precedence + ((spacingPrecedence && t.isTight) ? Parser.tightBonus : 0)
    }

    func parseExpr(_ minPrec: Int = 0) throws -> Expr {
        var lhs = try parseUnary()
        while check(.op) {
            let t = current
            switch t.fixity {
            case .infix:
                guard let info = table.infix[t.lexeme] else {
                    throw fail(t, "operador desconocido '\(t.lexeme)'",
                               "Operadores infijos disponibles: \(table.infix.keys.sorted().joined(separator: " ")). "
                               + "Recuerde que una secuencia de símbolos es UN solo operador: '=-' o '!+' no se separan solos; use espacios. "
                               + "También puede declararlo: operator \(t.lexeme) infix precedence 50;")
                }
                let eff = effectivePrecedence(t, info)
                if eff < minPrec { return lhs }
                advance()
                let rhs = try parseExpr(info.assoc == .right ? eff : eff + 1)
                if info.assoc == .none, check(.op), current.fixity == .infix,
                   let n = table.infix[current.lexeme], effectivePrecedence(current, n) == eff {
                    throw fail(current, "'\(t.lexeme)' y '\(current.lexeme)' no son asociativos entre sí (no se pueden encadenar)",
                               "Use paréntesis: (a \(t.lexeme) b) \(current.lexeme) c")
                }
                lhs = .binary(t.lexeme, lhs, rhs, t.loc)

            case .prefix:
                throw fail(t, "el operador '\(t.lexeme)' tiene espacio a la izquierda pero no a la derecha, por lo que se lee como PREFIJO y aquí falta un operador entre dos operandos",
                           "Escriba '… \(t.lexeme) …' (espacio a ambos lados) o '…\(t.lexeme)…' (sin espacios) para que sea infijo.")

            case .postfix:
                throw fail(t, "el operador '\(t.lexeme)' tiene espacio a la derecha pero no a la izquierda, por lo que se lee como POSTFIJO y no está definido como tal",
                           "Escriba '… \(t.lexeme) …' (espacio a ambos lados) o '…\(t.lexeme)…' (sin espacios) para que sea infijo.")
            }
        }
        return lhs
    }

    /// unario := opPrefijo unario | primario opPostfijo*
    /// (los prefijos/postfijos ligan más fuerte que cualquier infijo, como en Swift)
    private func parseUnary() throws -> Expr {
        let t = current
        if t.kind == .op {
            guard t.fixity == .prefix else {
                if t.fixity == .infix {
                    throw fail(t, "operador '\(t.lexeme)' inesperado: falta un operando a su izquierda",
                               "Un operador prefijo debe ir pegado a su operando (p. ej. '-x'). Con espacios a ambos lados se considera infijo.")
                }
                throw fail(t, "operador postfijo '\(t.lexeme)' sin operando a su izquierda", nil)
            }
            guard table.prefix.contains(t.lexeme) else {
                throw fail(t, "'\(t.lexeme)' no está definido como operador prefijo",
                           "Prefijos disponibles: \(table.prefix.sorted().joined(separator: " ")). Puede declarar otro con: operator \(t.lexeme) prefix;")
            }
            advance()
            return .prefix(t.lexeme, try parseUnary(), t.loc)
        }

        var e = try parsePrimary()
        while check(.op), current.fixity == .postfix {
            let p = current
            guard table.postfix.contains(p.lexeme) else {
                throw fail(p, "el operador '\(p.lexeme)' tiene espacio solo a la derecha ('a\(p.lexeme) b'), lo que lo hace POSTFIJO, y no está definido como postfijo",
                           "Si quería una operación binaria escriba 'a \(p.lexeme) b' o 'a\(p.lexeme)b'.")
            }
            advance()
            e = .postfix(p.lexeme, e, p.loc)
        }
        return e
    }

    private func parsePrimary() throws -> Expr {
        let t = current
        switch t.kind {
        case .number:
            advance()
            return .number(Double(t.lexeme) ?? 0, t.loc)
        case .identifier:
            advance()
            return .variable(t.lexeme, t.loc)
        case .lparen:
            advance()
            let e = try parseExpr()
            if !check(.rparen) {
                throw fail(t, "el paréntesis '(' abierto aquí no se cierra",
                           "Agregue ')' después de la expresión.")
            }
            advance()
            return e
        default:
            throw fail(t, "se esperaba una expresión (número, variable o '(') pero se encontró \(describe(t))",
                       "Ejemplos de expresión: 10, speed, 10 * speed + 5, (a + b) * 2")
        }
    }
}

// MARK: - Sugerencias para comandos mal escritos

private func closestKeyword(to word: String) -> String? {
    let candidates = ["forward", "turn", "stop", "return", "if", "repeat", "operator"]
    var best: (String, Int)? = nil
    for c in candidates {
        let d = editDistance(Array(word.lowercased()), Array(c))
        if d <= 2 && (best == nil || d < best!.1) { best = (c, d) }
    }
    return best?.0
}

private func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    for i in 1...a.count {
        var cur = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        prev = cur
    }
    return prev[b.count]
}
