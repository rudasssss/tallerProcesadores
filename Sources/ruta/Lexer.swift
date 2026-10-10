// Lexer.swift — Analizador léxico manual de Ruta.
//
// Idea tomada de Swift: cada token de operador recuerda si tenía espacio
// (o puntuación de apertura/cierre) a su izquierda y a su derecha. Con eso
// se clasifica en prefijo / infijo / postfijo (ver `Token.fixity`).

enum TokenKind: String {
    // Palabras reservadas
    case kwForward = "FORWARD", kwTurn = "TURN", kwRight = "RIGHT", kwLeft = "LEFT"
    case kwStop = "STOP", kwReturn = "RETURN", kwBase = "BASE"
    case kwIf = "IF", kwThen = "THEN", kwElse = "ELSE"
    case kwRepeat = "REPEAT", kwTimes = "TIMES"
    case kwOperator = "OPERATOR", kwInfix = "INFIX", kwPrefix = "PREFIX", kwPostfix = "POSTFIX"
    case kwPrecedence = "PRECEDENCE", kwAssoc = "ASSOC"
    // Léxicos con valor
    case number = "NUMBER", identifier = "IDENT", op = "OP"
    // Puntuación
    case assign = "ASSIGN", lparen = "LPAREN", rparen = "RPAREN"
    case lbrace = "LBRACE", rbrace = "RBRACE", semicolon = "SEMI"
    /// Lexema inválido ya reportado por el lexer; el parser lo trata como punto de resincronización.
    case invalid = "INVALID"
    case eof = "EOF"
}

let keywords: [String: TokenKind] = [
    "forward": .kwForward, "turn": .kwTurn, "right": .kwRight, "left": .kwLeft,
    "stop": .kwStop, "return": .kwReturn, "base": .kwBase,
    "if": .kwIf, "then": .kwThen, "else": .kwElse,
    "repeat": .kwRepeat, "times": .kwTimes,
    "operator": .kwOperator, "infix": .kwInfix, "prefix": .kwPrefix, "postfix": .kwPostfix,
    "precedence": .kwPrecedence, "assoc": .kwAssoc,
]

struct Token {
    let kind: TokenKind
    let lexeme: String
    let line: Int
    let column: Int
    /// true si NO hay "ligadura" a la izquierda (inicio, espacio, comentario o `( [ { , ;`).
    let spaceBefore: Bool
    /// true si NO hay "ligadura" a la derecha (fin, espacio, comentario o `) ] } , ;`).
    let spaceAfter: Bool

    var endColumn: Int { column + lexeme.unicodeScalars.count }
    var loc: Loc { Loc(line: line, column: column) }

    /// Regla de Swift:
    ///   `a + b` y `a+b`  -> infijo   (ambos lados iguales)
    ///   `a +b`           -> prefijo  (espacio solo a la izquierda)
    ///   `a+ b`           -> postfijo (espacio solo a la derecha)
    var fixity: Fixity {
        if spaceBefore == spaceAfter { return .infix }
        return spaceBefore ? .prefix : .postfix
    }

    /// Operador infijo sin espacios a ningún lado (`a+b`): se une más fuerte.
    var isTight: Bool { !spaceBefore && !spaceAfter }
}

struct Lexer {
    private let src: [Unicode.Scalar]
    private var pos = 0
    private var line = 1
    private var col = 1
    private var afterComment = false
    private(set) var errors: [RutaError] = []

    private static let opChars: Set<Unicode.Scalar> = Set("+-*/%<>=!&|^~?".unicodeScalars)
    private static let openPunct: Set<Unicode.Scalar> = Set("({[,;".unicodeScalars)
    private static let closePunct: Set<Unicode.Scalar> = Set(")}],;".unicodeScalars)

    init(source: String) {
        var scalars = Array(source.unicodeScalars)
        // Los editores de Windows (Notepad, PowerShell) pueden anteponer un BOM UTF-8 (U+FEFF).
        if scalars.first == Unicode.Scalar(0xFEFF) { scalars.removeFirst() }
        self.src = scalars
    }

    // MARK: utilidades

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        let i = pos + offset
        return i < src.count ? src[i] : nil
    }

    private mutating func advance() {
        let c = src[pos]
        pos += 1
        if c == "\n" { line += 1; col = 1 } else { col += 1 }
    }

    private static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r"
    }
    private static func isDigit(_ c: Unicode.Scalar) -> Bool { c >= "0" && c <= "9" }
    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_"
    }

    private mutating func error(_ l: Int, _ c: Int, _ msg: String, _ hint: String?) {
        errors.append(RutaError(phase: .lexico, line: l, column: c, message: msg, hint: hint))
    }

    // MARK: ciclo principal

    mutating func tokenize() -> [Token] {
        var tokens: [Token] = []
        while true {
            skipTrivia()
            guard let c = peek() else { break }
            let startLine = line, startCol = col
            let before = leftIsOpen()

            if Lexer.isDigit(c) {
                tokens.append(lexNumber(startLine, startCol, before))
            } else if Lexer.isLetter(c) {
                tokens.append(lexWord(startLine, startCol, before))
            } else if Lexer.opChars.contains(c) {
                tokens.append(lexOperator(startLine, startCol, before))
            } else {
                var kind: TokenKind?
                switch c {
                case "(": kind = .lparen
                case ")": kind = .rparen
                case "{": kind = .lbrace
                case "}": kind = .rbrace
                case ";": kind = .semicolon
                default: kind = nil
                }
                advance()
                if let k = kind {
                    tokens.append(Token(kind: k, lexeme: String(c), line: startLine, column: startCol,
                                        spaceBefore: before, spaceAfter: rightIsOpen()))
                } else {
                    error(startLine, startCol, "carácter no reconocido '\(c)'",
                          "Ruta solo admite letras, dígitos, operadores (+ - * / % < > = ! ...) y los signos ( ) { } ;")
                    tokens.append(Token(kind: .invalid, lexeme: String(c), line: startLine, column: startCol,
                                        spaceBefore: before, spaceAfter: rightIsOpen()))
                }
            }
            afterComment = false
        }
        tokens.append(Token(kind: .eof, lexeme: "", line: line, column: col, spaceBefore: true, spaceAfter: true))
        return tokens
    }

    // MARK: espacios y comentarios

    private mutating func skipTrivia() {
        while let c = peek() {
            if Lexer.isWhitespace(c) {
                advance()
            } else if c == "/" && peek(1) == "/" {
                afterComment = true
                while let d = peek(), d != "\n" { advance() }
            } else if c == "/" && peek(1) == "*" {
                let l = line, cl = col
                advance(); advance()
                var closed = false
                while let d = peek() {
                    if d == "*" && peek(1) == "/" { advance(); advance(); closed = true; break }
                    advance()
                }
                afterComment = true
                if !closed {
                    error(l, cl, "comentario de bloque sin cerrar",
                          "Cierre el comentario con '*/' (se abrió con '/*' aquí).")
                }
            } else {
                break
            }
        }
    }

    /// ¿Lo que hay a la izquierda del token actual cuenta como "espacio"?
    private func leftIsOpen() -> Bool {
        if afterComment || pos == 0 { return true }
        let p = src[pos - 1]
        return Lexer.isWhitespace(p) || Lexer.openPunct.contains(p)
    }

    /// ¿Lo que hay a la derecha de la posición actual cuenta como "espacio"?
    private func rightIsOpen() -> Bool {
        guard let n = peek() else { return true }
        if Lexer.isWhitespace(n) || Lexer.closePunct.contains(n) { return true }
        if n == "/" && (peek(1) == "/" || peek(1) == "*") { return true }
        return false
    }

    // MARK: tokens concretos

    private mutating func lexNumber(_ l: Int, _ c: Int, _ before: Bool) -> Token {
        var text = ""
        while let d = peek(), Lexer.isDigit(d) { text.unicodeScalars.append(d); advance() }
        if peek() == ".", let n = peek(1), Lexer.isDigit(n) {
            text.unicodeScalars.append("."); advance()
            while let d = peek(), Lexer.isDigit(d) { text.unicodeScalars.append(d); advance() }
        }
        if let n = peek(), Lexer.isLetter(n) {
            // 12abc: consumir el resto para no producir errores en cascada
            var bad = text
            while let d = peek(), Lexer.isLetter(d) || Lexer.isDigit(d) { bad.unicodeScalars.append(d); advance() }
            error(l, c, "número mal formado '\(bad)'",
                  "Un identificador no puede empezar con dígito; separe el número de la letra o renombre la variable.")
            return Token(kind: .invalid, lexeme: bad, line: l, column: c, spaceBefore: before, spaceAfter: rightIsOpen())
        }
        return Token(kind: .number, lexeme: text, line: l, column: c, spaceBefore: before, spaceAfter: rightIsOpen())
    }

    private mutating func lexWord(_ l: Int, _ c: Int, _ before: Bool) -> Token {
        var text = ""
        while let d = peek(), Lexer.isLetter(d) || Lexer.isDigit(d) { text.unicodeScalars.append(d); advance() }
        let kind = keywords[text] ?? .identifier
        return Token(kind: kind, lexeme: text, line: l, column: c, spaceBefore: before, spaceAfter: rightIsOpen())
    }

    /// Como en Swift: una secuencia maximal de caracteres de operador es UN token.
    private mutating func lexOperator(_ l: Int, _ c: Int, _ before: Bool) -> Token {
        var text = ""
        while let d = peek(), Lexer.opChars.contains(d) {
            if d == "/" && (peek(1) == "/" || peek(1) == "*") { break }   // empieza un comentario
            text.unicodeScalars.append(d)
            advance()
        }
        let kind: TokenKind = (text == "=") ? .assign : .op
        return Token(kind: kind, lexeme: text, line: l, column: c, spaceBefore: before, spaceAfter: rightIsOpen())
    }
}
