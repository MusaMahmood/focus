highlight_build_output_messages :: (using buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
    tokenizer: Tokenizer = ---;
    tokenizer.buf   = cast(string)bytes;
    tokenizer.max_t = bytes.data + bytes.count;
    tokenizer.t     = bytes.data;
    
    // last_token: Token;
    
    while true {
        token := get_next_token(*tokenizer);
        if token.type == .eof break;

        // using tokenizer;

        // last_token = token;

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
        case #char "[";     parse_log_message(tokenizer, *token);
        case;               parse_line(tokenizer, *token); // default case
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t-start_t);
    
    return token;
}

parse_log_message :: (using tokenizer: *Tokenizer, token: *Token) {
    old_t := t;
    
    eat_until_close_bracket_or_newline(tokenizer);
    msg_tag := string.{t-old_t-1, old_t+1};
    
    if msg_tag == {
        case "info"; #through;
        case "Info"; #through;
        case "INFO"; {
            token.type = .line;
        }
        case "debug"; #through;
        case "Debug"; #through;
        case "DEBUG";
            token.type = .milestone;
        case "warning"; #through;
        case "Warning"; #through;
        case "WARNING"; 
            token.type = .important;
        case "error"; #through;
        case "Error"; #through;
        case "ERROR";
            token.type = .critical;
        case;
            token.type = .line;
    }
    
    // token.type = .header1;
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

eat_until_close_bracket_or_newline :: (using tokenizer: *Tokenizer) {
    while t < max_t && !(<<t == #char "\n" || <<t == #char "]")  {
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

        in_progress;
        important;
        critical;
        milestone;
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
    .TODO_IMPORTANT,         // important
    .TODO_CRITICAL,          // critical
    .TODO_IN_PROGRESS,       // in_progress
    .TODO_STANDARD,          // todo
    .TODO_LOW_PRIORITY,      // low_priority
    .TODO_MISSED,            // missed
    .TODO_COMPLETED,         // completed
    .TODO_BULLET,            // bullet
];
