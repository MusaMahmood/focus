tokenize_todo :: (using buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
    tokenizer := get_tokenizer(buffer, start_offset, count);

    while true {
        token := get_next_token(*tokenizer);
        if token.type == .eof break;

        memset(tokens.data + token.start, xx token.type, token.len);
    }

    return .[];
}

#scope_file

get_next_token :: (using tokenizer: *Tokenizer) -> Token {
    eat_white_space(tokenizer);

    token: Token;
    token.start = cast(s32) (t - buf.data);
    token.type  = .eof;
    if t >= max_t return token;

    start_t = t;

    // Look at the first char as if it's ASCII (if it isn't, this is just a text line)
    char := t.*;

    if char == {
        // Extended UTF-8 symbols like bullet points:
        case 0xE2;          parse_extended(tokenizer, *token);
        case #char "[";     parse_todo    (tokenizer, *token);
        case;               parse_line    (tokenizer, *token);
    }

    if t >= max_t then t = max_t;
    token.len = cast(s32) (t - start_t);
    return token;
}

parse_extended :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .function;
    
    // #TODO: Can check bytes 2 & 3 to see what kind of character we're seeing.
    
    t += 1;
    eat_until_newline(tokenizer);
}

parse_todo :: (using tokenizer: *Tokenizer, token: *Token) {
    old_t := t;

    eat_until_close_bracket(tokenizer);

    str: string = ---;
    str.data    = old_t;
    str.count   = t - old_t;

    str = trim_right(str);

    if t + 1 >= max_t {
        return;    
    }

    if ((t+1).* == 93) {
        token.type = .header2; t = old_t + 2;
        eat_until_newline(tokenizer); 
        return;
    }

    if str.count > 4 {
        token.type = .header; t = old_t + 1;
        eat_until_newline(tokenizer); 
        return;
    }

    if str == {
        case "[♦";     token.type = .keyword;
        case "[!";     token.type = .type; 
        case "[*";     token.type = .value;     
        case "[•";     token.type = .modifier;
        case "[.";     token.type = .attribute;
        case "[↓";     token.type = .enum_variant;
        case "[x";     token.type = .macro;
        case "[~";     token.type = .builtin_variable;
        // If not a task, then it must be a header.
        case;          token.type = .comment; t = old_t + 1;
    }

    eat_until_newline(tokenizer); 
    // #TODO: Replace this with "until_newline_or_next_token"
        // That way we can have multiple todo items per line. 
    // eat_until_newline_or_open_bracket(tokenizer);
}

eat_until_close_bracket :: (using tokenizer: *Tokenizer) {
    while t < max_t && t.* != #char "]" {
        t += 1;
    }
}

parse_line :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .default;

    t += 1;
    eat_until_newline(tokenizer);
}

Token :: struct {
    start, len: s32;
    type: Token_Type;
}
