rule token = parse
	| "#" {comment lexbuf}
	| [' ' '\t'] {token lexbuf}
	| '\n' {FCParser.EOL}
	| '/' {FCParser.SLASH}
	| '-'?['0'-'9']+ as n {FCParser.Z (Z.of_string n)}
	| ['a'-'z' 'A'-'Z' '0'-'9' '_' '.']+ as s {FCParser.PolyName s}
	| "<=" {FCParser.LE} | "<" {FCParser.LT} | ">=" {FCParser.GE} | ">" {FCParser.GT} | "=" {FCParser.EQ} | "≠" {FCParser.NEQ}
	| eof {FCParser.EOF}
and comment = parse
	| "\n" {token lexbuf}
	| _ {comment lexbuf}
