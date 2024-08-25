tokenize_compute :: (using buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
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
    
    char := t.*;
    
    if char == {
        case #char "/";  parse_slash_or_comment(tokenizer, *token);
        case;            parse_line            (tokenizer, *token);
    }
    
    if t >= max_t then t = max_t;
    token.len = cast(s32)(t - start_t);
    
    return token;
}

parse_slash_or_comment :: (using tokenizer: *Tokenizer, token: *Token) {
    token.type = .operation;

    t += 1;
    if t >= max_t return;

    if t.* == {
        case #char "/";
            token.type = .comment;
            t += 1;
            while t < max_t && t.* != #char "\n" t += 1;
        case #char "*";
            token.type = .multiline_comment;
            t += 1;
            while t + 1 < max_t {
                if t.* == #char "*" && << (t + 1) == #char "/" {
                  t += 2;
                  break;
                }
                t += 1;
            }
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
