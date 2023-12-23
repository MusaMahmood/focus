highlight_todo_syntax :: (using buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = cast(string)bytes;
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;

    while true {
        token := get_next_token(*tokenizer);
        if token.type == .eof break;

        color := COLOR_MAP[token.type];
        memset(colors.data + token.start, xx color, token.len);
    }
    
    return .[];
}

#scope_file

get_next_token :: (using tokenizer: *Tokenizer) -> Token {
    eat_white_space(tokenizer);

    token : Token;
    token.start = cast(s32) (t-buf.data);
    token.type  = .eof;
    if t >= max_t return token;

    start_t = t;

    // Look at the first char as if it's ASCII. If it isn't this is just a text line:
    char := <<t; // get char at mem address t (assuming its single byte). 
    // print("Type of char: %", type_of(char));
    if char == {
        // for now, any line that starts with a [, highlight as critical. 
        case 0xE2;          parse_extended(tokenizer, *token); 
        // case ... parse_bullet .... 
        case #char "[";     parse_todo(tokenizer, *token);
        case;               parse_line(tokenizer, *token); // default case
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t-start_t);
    return token;
}

parse_extended :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .bullet;
    // TODO: Check bytes 2 & 3, make different types of bullets.
    t += 1;
    eat_until_newline(tokenizer); 
}

parse_todo :: (using tokenizer: *Tokenizer, token: *Token) {
    old_t := t;

    // TODO: Check for second bracket

    eat_until_close_bracket(tokenizer);

    str: string = ---;
    str.data    = old_t;
    str.count   = t - old_t;

    str = trim_right(str);

    if t+1 >= max_t {
        return;    
    }

    if (<<(t+1) == 93) {
        token.type = .header2; t = old_t + 2;
        eat_until_newline(tokenizer); 
        return;
    }

    if str.count > 4 {
        token.type = .header1; t = old_t + 1;
        eat_until_newline(tokenizer); 
        return;
    }

    if str == {
        case "[♦";     token.type = .milestone;
        case "[!";     token.type = .critical; 
        case "[*";     token.type = .important;     
        case "[•";     token.type = .in_progress;
        case "[.";     token.type = .in_progress;
        case "[↓";     token.type = .low_priority;
        case "[x";     token.type = .completed;
        case "[M";     token.type = .missed;
        case "[~";     token.type = .missed;
        // If not a task, then it must be a header.
        case;          token.type = .todo; t = old_t + 1;
    }

    // keep going until eol:
    eat_until_newline(tokenizer); 
    // TODO: Replace this with "until_newline_or_next_token"
        // That way we can have multiple todo items per line. 
    // eat_until_newline_or_open_bracket(tokenizer); 
}

parse_critical :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .critical;

    t += 1;
    eat_until_newline(tokenizer);
}

parse_line :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .line;

    t += 1;
    eat_until_newline(tokenizer);
}

eat_until_close_bracket :: (using tokenizer: *Tokenizer) {
    while t < max_t && <<t != #char "]" {
        t += 1;
    }
}

eat_until_newline :: (using tokenizer: *Tokenizer) {
    while t < max_t && <<t != #char "\n" {
        t += 1;
    }
}

eat_until_newline_or_open_bracket :: (using tokenizer: *Tokenizer) {
    while t < max_t && !(<<t == #char "\n" || <<t == #char "[") {
        t += 1;
    }
}

eat_white_space :: (using tokenizer: *Tokenizer) {
    while t < max_t && is_space(<< t) {
        t += 1;
    }
}

Tokenizer :: struct {
    buf: string;
    max_t:   *u8;
    start_t: *u8;  // cursor when starting parsing new token
    t:       *u8;  // cursor

    last_tokens : [1]Token;
}

Token :: struct {
    start, len: s32;
    type: Type;

    Type :: enum u16 {
        eof;

        line; // default, no formatting. 
        header1;
        header2;

        milestone;
        critical;
        important;
        in_progress;
        todo;
        low_priority;
        missed;
        completed;
        bullet;
    }
}

COLOR_MAP :: Color.[
    .CODE_COMMENT,  // EOF, not used

    .TODO_DEFAULT,           // line
    .TODO_HEADER1,           // header (one bracket)
    .TODO_HEADER2,

    .TODO_MILESTONE,
    .TODO_CRITICAL,          // critical
    .TODO_IMPORTANT,         // important
    .TODO_IN_PROGRESS,       // in_progress
    .TODO_STANDARD,          // todo
    .TODO_LOW_PRIORITY,      // low_priority
    .TODO_MISSED,            // missed
    .TODO_COMPLETED,         // completed
    .TODO_BULLET,            // bullet
];
