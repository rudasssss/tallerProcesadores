# Ruta — Diseño formal del lenguaje

Lenguaje de control para un robot de entregas en el campus. Este documento es la **Parte 1** del taller (papel); la **Parte 2** es el procesador en Swift (`Sources/ruta/`).

Ejemplo de programa Ruta:

```
speed = 3;
distance = 10 * speed + 5;      // comentario
forward distance;
if distance > 20 then turn right; else stop;
repeat 4 times { forward 2; turn left; }
return base;
```

---

## 1. Gramática libre de contexto

Convenciones: los **terminales** (tokens) van en `minúsculas negrita-código` o entre comillas; los no terminales entre `<...>` (BNF) o en `snake_case` (EBNF). `ε` es la cadena vacía.

### 1.1 BNF

Versión **final, no ambigua** (con las dos ambigüedades ya resueltas; ver §2).

```bnf
<programa>       ::= <lista_sent>
<lista_sent>     ::= <sent> <lista_sent> | ε

; --- Sentencias (resuelve el "dangling else") ---
<sent>           ::= <sent_cerrada> | <sent_abierta>

<sent_cerrada>   ::= <simple> ";"
                   | <bloque>
                   | "if" <expr> "then" <sent_cerrada> "else" <sent_cerrada>
                   | "repeat" <expr> "times" <sent_cerrada>

<sent_abierta>   ::= "if" <expr> "then" <sent>
                   | "if" <expr> "then" <sent_cerrada> "else" <sent_abierta>
                   | "repeat" <expr> "times" <sent_abierta>

<bloque>         ::= "{" <lista_sent> "}"

<simple>         ::= "forward" <expr>
                   | "turn" <giro>
                   | "stop"
                   | "return" "base"
                   | IDENT "=" <expr>
                   | <decl_op>

<giro>           ::= "right" | "left"

<decl_op>        ::= "operator" OP <posicion> <opciones>
<posicion>       ::= "infix" | "prefix" | "postfix"
<opciones>       ::= "precedence" NUMBER <opc_assoc> | <opc_assoc>
<opc_assoc>      ::= "assoc" <modo> | ε
<modo>           ::= "left" | "right" | IDENT          ; IDENT debe ser "none"

; --- Expresiones, gramática ESTRATIFICADA (resuelve la precedencia) ---
<expr>           ::= <igualdad>
<igualdad>       ::= <igualdad> ("==" | "!=") <relacional> | <relacional>
<relacional>     ::= <relacional> ("<" | ">" | "<=" | ">=") <suma> | <suma>
<suma>           ::= <suma> ("+" | "-") <termino>         | <termino>
<termino>        ::= <termino> ("*" | "/" | "%") <unario> | <unario>
<unario>         ::= ("-" | "+") <unario> | <postfijo>
<postfijo>       ::= <postfijo> "!" | <primario>
<primario>       ::= NUMBER | IDENT | "(" <expr> ")"
```

> Nota: en `<relacional>` e `<igualdad>` la recursión izquierda permite `a < b < c`; el procesador es más estricto y lo rechaza (asociatividad *none*), ver §4.

### 1.2 EBNF

`{ x }` = cero o más, `[ x ]` = opcional, `( a | b )` = agrupación.

```ebnf
programa    = { sentencia } ;

sentencia   = simple , ";"
            | si
            | repetir
            | bloque ;

si          = "if" , expr , "then" , sentencia , [ "else" , sentencia ] ;
repetir     = "repeat" , expr , "times" , sentencia ;
bloque      = "{" , { sentencia } , "}" ;

simple      = "forward" , expr
            | "turn" , ( "right" | "left" )
            | "stop"
            | "return" , "base"
            | IDENT , "=" , expr
            | decl_op ;

decl_op     = "operator" , OP , ( "infix" | "prefix" | "postfix" ) ,
              [ "precedence" , NUMBER ] ,
              [ "assoc" , ( "left" | "right" | IDENT ) ] ;

(* Expresiones, versión "dinámica" de Ruta (la que implementa Parser.swift) *)
expr        = unario , { OP_infijo , unario } ;
unario      = OP_prefijo , unario
            | primario , { OP_postfijo } ;
primario    = NUMBER | IDENT | "(" , expr , ")" ;
```

En esta EBNF `expr` es deliberadamente **plana**: la gramática no dice qué operador liga más fuerte. Eso lo decide el parser con una tabla de operadores y con el espaciado (§5). La gramática estratificada de §1.1 es la versión "estática" equivalente cuando la tabla es la de fábrica y no hay espaciado significativo.

El `[ "else" , sentencia ]` de la EBNF, por sí solo, **sigue siendo ambiguo**; la EBNF se desambigua con la regla *"el `else` pertenece al `if` más cercano sin `else`"* (parser voraz), que es exactamente lo que formaliza la BNF de `<sent_cerrada>/<sent_abierta>`.

---

## 2. Ambigüedades

### 2.1 Precedencia de operadores

**Gramática original (ambigua):**

```bnf
<expr> ::= <expr> "+" <expr>
         | <expr> "*" <expr>
         | "(" <expr> ")"
         | NUMBER | IDENT
```

Para la cadena `10 * speed + 5` existen **dos árboles de derivación distintos**:

**Árbol A** — agrupa como `(10 * speed) + 5` (el esperado):

```
expr
├── expr
│   ├── expr ── 10
│   ├── *
│   └── expr ── speed
├── +
└── expr ── 5
```

**Árbol B** — agrupa como `10 * (speed + 5)`:

```
expr
├── expr ── 10
├── *
└── expr
    ├── expr ── speed
    ├── +
    └── expr ── 5
```

Con `speed = 2` el árbol A da `25` y el B da `70`: la ambigüedad cambia el significado, así que hay que eliminarla.

**Solución: estratificar por niveles de precedencia** y usar recursión izquierda para la asociatividad izquierda (ya escrita en §1.1):

```bnf
<suma>    ::= <suma> ("+" | "-") <termino> | <termino>
<termino> ::= <termino> ("*" | "/" | "%") <unario> | <unario>
```

Derivación única de `10 * speed + 5` con la gramática nueva:

```
suma
├── suma
│   └── termino
│       ├── termino
│       │   └── unario ── postfijo ── primario ── 10
│       ├── *
│       └── unario ── postfijo ── primario ── speed
├── +
└── termino
    └── unario ── postfijo ── primario ── 5
```

El `*` solo puede aparecer **por debajo** de `<suma>`; el árbol B es imposible porque `speed + 5` no es un `<termino>` salvo entre paréntesis. La recursión izquierda fuerza `a - b - c = (a - b) - c`.

### 2.2 "Dangling else"

**Gramática original (ambigua):**

```bnf
<sent> ::= "if" <expr> "then" <sent>
         | "if" <expr> "then" <sent> "else" <sent>
         | <simple> ";"
         | ...
```

Cadena: `if a then if b then forward 1; else stop;`

**Árbol 1** — el `else` pertenece al `if` interno (lo usual):

```
sent
└── if a then
    └── sent
        └── if b then  sent(forward 1;)  else  sent(stop;)
```

**Árbol 2** — el `else` pertenece al `if` externo:

```
sent
└── if a then
    ├── sent
    │   └── if b then  sent(forward 1;)
    └── else  sent(stop;)
```

Ambos son derivaciones válidas de la misma cadena: los dos `if` compiten por el único `else`.

**Solución: separar sentencias "cerradas" (el `if` tiene su `else` o no es un `if`) de "abiertas" (hay un `if` sin `else` pendiente).** Regla clave: en `if … then X else …` el `X` debe ser *cerrada*; así un `else` nunca puede saltar por encima de un `if` sin cerrar.

```bnf
<sent>         ::= <sent_cerrada> | <sent_abierta>
<sent_cerrada> ::= "if" <expr> "then" <sent_cerrada> "else" <sent_cerrada> | <simple> ";" | <bloque> | ...
<sent_abierta> ::= "if" <expr> "then" <sent>
                 | "if" <expr> "then" <sent_cerrada> "else" <sent_abierta>
```

Derivación única de la misma cadena con la gramática nueva:

```
sent
└── sent_abierta                      (if a then sent)
    ├── if a then
    └── sent
        └── sent_cerrada
            └── if b then  sent_cerrada(forward 1;)  else  sent_cerrada(stop;)
```

El árbol 2 (`if a then <if b then X> else Y`) **ya no se puede derivar**: para que el `else` cuelgue de `a`, el `then` de `a` tendría que ser una `<sent_cerrada>`, pero `if b then forward 1;` (sin `else`) es una `<sent_abierta>`. Por tanto el único árbol válido es el de arriba. Resultado: el `else` es del `if b` (el más cercano) y `if a` queda abierto. Si el programador quiere el otro significado, usa bloque: `if a then { if b then forward 1; } else stop;`.

**En el parser** (`Parser.swift`, `parseStatement`): descenso recursivo, tras parsear el `then` se hace `if match(.kwElse)`. Como el `if` interno se parsea *primero* y consume el `else`, el `if` externo nunca lo ve: se obtiene el árbol 1 sin necesidad de construir las categorías cerrada/abierta.

---

## 3. Vocabulario léxico

Los espacios en blanco (`[ \t\r\n]+`) y los comentarios se descartan (los comentarios cuentan como espacio para clasificar operadores, §5).

| Token | Patrón (regex) | Lexemas válidos |
|---|---|---|
| `FORWARD` | `forward` | `forward` |
| `TURN` | `turn` | `turn` |
| `RIGHT` / `LEFT` | `right` / `left` | `right`, `left` |
| `STOP` | `stop` | `stop` |
| `RETURN` | `return` | `return` |
| `BASE` | `base` | `base` |
| `IF` / `THEN` / `ELSE` | `if` / `then` / `else` | `if`, `then`, `else` |
| `REPEAT` / `TIMES` | `repeat` / `times` | `repeat`, `times` |
| `OPERATOR` | `operator` | `operator` |
| `INFIX` / `PREFIX` / `POSTFIX` | `infix` / `prefix` / `postfix` | `infix`, `prefix`, `postfix` |
| `PRECEDENCE` / `ASSOC` | `precedence` / `assoc` | `precedence`, `assoc` |
| `NUMBER` | `[0-9]+(\.[0-9]+)?` | `0`, `10`, `42`, `3.14` |
| `IDENT` | `[A-Za-z_][A-Za-z0-9_]*` (que no sea palabra reservada) | `speed`, `dist_1`, `_tmp`, `Base2` |
| `OP` | `[-+*/%<>=!&\|^~?]+` (secuencia maximal; excluye `=` solo y no incluye `//` ni `/*`) | `+`, `-`, `*`, `/`, `%`, `<`, `>=`, `==`, `!=`, `!`, `**` |
| `ASSIGN` | `=` | `=` |
| `LPAREN` / `RPAREN` | `\(` / `\)` | `(`, `)` |
| `LBRACE` / `RBRACE` | `\{` / `\}` | `{`, `}` |
| `SEMI` | `;` | `;` |
| *(comentario de línea)* descartado | `//[^\n]*` | `// vuelve pronto` |
| *(comentario de bloque)* descartado | `/\*([^*]\|\*+[^*/])*\*+/` | `/* nota */` |
| *(espacio)* descartado | `[ \t\r\n]+` | ` `, `\n` |
| `EOF` | fin de entrada | — |

Reglas de desempate: (1) se toma el **lexema más largo** (`<=` es un token, no `<` y `=`; `forwardx` es `IDENT`); (2) a igual longitud, **palabra reservada** gana a `IDENT`.

Errores léxicos que reporta el procesador (con línea y columna): carácter no reconocido (`@`, `$`, `"`…), número mal formado (`12abc`), comentario de bloque sin cerrar.

---

## 4. Operadores y errores sintácticos

Operadores de fábrica (tabla modificable, §5):

| Posición | Operadores | Precedencia / asociatividad |
|---|---|---|
| infijo | `*` `/` `%` | 70, izquierda |
| infijo | `+` `-` | 60, izquierda |
| infijo | `<` `>` `<=` `>=` | 40, no asociativo |
| infijo | `==` `!=` | 30, no asociativo |
| prefijo | `-` `+` | ligan más que cualquier infijo |
| postfijo | `!` (factorial) | ligan más que prefijo |

Los errores sintácticos se imprimen como `línea:columna`, mensaje, la línea fuente con `^` y una **ayuda**. Tras un error el parser hace *recuperación en modo pánico* (salta hasta `;` o hasta la siguiente sentencia) para reportar varios errores en una sola pasada.

---

## 5. Requisito de Swift: operadores según espaciado y precedencia dinámica

En Swift la gramática base **no** fija la precedencia de los operadores: la define el programador (`precedencegroup`) y el espaciado decide si un operador es prefijo, infijo o postfijo. Ruta imita ambas ideas.

### 5.1 Fijación por espaciado (Lexer)

Cada token `OP` guarda `spaceBefore` y `spaceAfter`: *no hay ligadura* si el vecino es espacio/comentario/inicio/fin o puntuación de apertura (`( { ,  ;` a la izquierda) o cierre (`) } , ;` a la derecha). Clasificación (`Token.fixity`, igual que Swift):

| Escritura | Espacios izq/der | Fijación | Significado |
|---|---|---|---|
| `a + b` | sí / sí | **infijo** | suma |
| `a+b` | no / no | **infijo** (apretado) | suma |
| `a +b` | sí / no | **prefijo** | `a` seguido de `+b` ⇒ error: falta operador |
| `a+ b` | no / sí | **postfijo** | `a+` seguido de `b` ⇒ error: `+` no es postfijo |
| `-x`, `(-x)`, `= -x` | sí / no | prefijo | negación |
| `n!;`, `n! + 1` | no / sí | postfijo | factorial |

Y una secuencia de símbolos es **un único operador** (como en Swift): `x=-1` se lee `x` `=-` `1` ⇒ error "operador desconocido '=-'" con la ayuda de separar con espacios.

### 5.2 Precedencia en una tabla, no en la gramática (Parser)

`expr` es plana (§1.2) y `Parser.parseExpr` es un parser de precedencias (Pratt) que consulta `OperatorTable`. El programa puede **redeclarar** la tabla en cualquier punto y surte efecto desde ahí hasta el final del archivo:

```
operator ** infix precedence 80 assoc right;   // nuevo operador (2 ** 3 ** 2 = 2 ** 9)
operator + infix precedence 90;                // ahora + liga más que *
```

El simulador implementa la semántica de `** + - * / % < > <= >= == != !` (prefijo `- +`); otros símbolos se pueden declarar y parsear, pero fallan en ejecución con un mensaje explicativo.

### 5.3 Precedencia por espaciado

Un infijo **apretado** (`a+b`, sin espacios) recibe un bonus de +1000 sobre uno con espacios, de modo que el espaciado visual coincide con la agrupación:

| Fuente | Agrupación | Valor |
|---|---|---|
| `1 + 2*3` | `1 + (2*3)` | 7 |
| `1+2 * 3` | `(1+2) * 3` | 9 |
| `10 * speed + 5` | `(10*speed)+5` | normal |

Se desactiva con `--strict` (`swift run ruta prog.ruta --strict`), en cuyo caso solo manda la tabla.

---

## 6. Uso del procesador

```
swift build
swift run ruta test_valido.ruta            # tokens + AST + simulación
swift run ruta test_error.ruta             # errores con línea/columna/ayuda
swift run ruta test_valido.ruta --no-run   # sin simular
swift run ruta test_valido.ruta --strict   # sin precedencia por espaciado
```

Solo se usa la biblioteca estándar de Swift y `Foundation` (disponible en Windows, Linux y macOS) para leer el archivo, `sin`/`cos`/`pow` y `exit`. No hay generadores de parsers ni paquetes externos.
