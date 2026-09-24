// Highlights `executables.ex4-config`: `[machine NAME]` headers, `NAME => TARGET key=value...` entries,
// and continuation lines (starting with whitespace) that hold more `key=value` attributes.
tokenize_ex4_executables :: (buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
    pos, end := ex4_get_tokenize_range(buffer, start_offset, count);
    memset(buffer.tokens.data + pos, xx Token_Type.default, end - pos);

    known_directives :: string.["version"];

    while true {
        line, ok := ex4_next_line(buffer, *pos, end);
        if !ok break;

        comment_start, unterminated_quote := ex4_find_comment(line.text);
        ex4_mark(line, comment_start, line.text.count, .comment);

        b, e := ex4_trim_range(line.text, 0, comment_start);
        if b == e continue;

        if unterminated_quote {
            ex4_mark(line, b, e, .error);
            continue;
        }

        c := line.text[b];
        if b > 0 {
            highlight_attributes(line, b, e);
        } else if c == #char "@" {
            ex4_highlight_directive(line, b, e, known_directives);
        } else if c == #char "[" {
            highlight_machine_header(line, b, e);
        } else {
            highlight_entry(line, b, e);
        }
    }

    return .[];
}

#scope_file

highlight_machine_header :: (line: Ex4_Line, b: s64, e: s64) {
    MACHINE :: "machine";

    text := line.text;
    inner_start := b + 1;
    inner_end   := e - 1;
    keyword_end := inner_start + MACHINE.count;

    well_formed := text[e - 1] == #char "]" && keyword_end < inner_end && ascii_is_space(text[keyword_end]) &&
                   string.{ MACHINE.count, text.data + inner_start } == MACHINE;
    if !well_formed {
        ex4_mark(line, b, e, .error);
        return;
    }

    ex4_mark(line, b, keyword_end, .keyword);
    ex4_mark(line, inner_end, e, .keyword);

    name_start, name_end := ex4_trim_range(text, keyword_end, inner_end);
    if name_start == name_end {
        ex4_mark(line, keyword_end, inner_end, .error);
    } else if text[name_start] == #char "\"" {
        quote_end, closed := scan_quoted(text, name_start, name_end);
        ex4_mark(line, name_start, quote_end, ifx closed then Token_Type.string_literal else .error);
        ex4_mark(line, quote_end, name_end, .error);
    } else {
        ex4_mark(line, name_start, name_end, .identifier);
    }
}

highlight_entry :: (line: Ex4_Line, b: s64, e: s64) {
    text := line.text;

    arrow := find_arrow(text, b, e);
    if arrow < 0 {
        ex4_mark(line, b, e, .error);
        return;
    }

    name_start, name_end := ex4_trim_range(text, b, arrow);
    if text[name_start] == #char "\"" {
        quote_end, closed := scan_quoted(text, name_start, name_end);
        ex4_mark(line, name_start, quote_end, ifx closed then Token_Type.function else .error);
        ex4_mark(line, quote_end, name_end, .error);
    } else {
        ex4_mark(line, name_start, name_end, .function);
    }
    ex4_mark(line, arrow, arrow + 2, .punctuation);

    i := arrow + 2;
    while i < e && ascii_is_space(text[i])  i += 1;
    target_start := i;
    if i < e && text[i] == #char "\"" {
        quote_end, closed := scan_quoted(text, i, e);
        ex4_mark(line, i, quote_end, ifx closed then Token_Type.string_literal else .error);
        i = quote_end;
    } else {
        while i < e && !ascii_is_space(text[i])  i += 1;
    }
    if target_start == i {
        ex4_mark(line, arrow, arrow + 2, .error);
        return;
    }

    highlight_attributes(line, i, e);
}

highlight_attributes :: (line: Ex4_Line, from: s64, to: s64) {
    text := line.text;
    i := from;
    while true {
        while i < to && ascii_is_space(text[i])  i += 1;
        if i >= to return;

        key_start := i;
        while i < to && (ascii_is_alpha(text[i]) || text[i] == #char "_")  i += 1;
        key := string.{ i - key_start, text.data + key_start };

        if !key || i >= to || text[i] != #char "=" || i + 1 >= to || ascii_is_space(text[i + 1]) {
            ex4_mark(line, key_start, to, .error);
            return;
        }

        known_key := key == "type" || key == "find" || key == "args";
        ex4_mark(line, key_start, i, ifx known_key then Token_Type.attribute else .error);
        ex4_mark(line, i, i + 1, .punctuation);
        i += 1;

        if text[i] == #char "\"" {
            quote_end, closed := scan_quoted(text, i, to);
            ex4_mark(line, i, quote_end, ifx closed then Token_Type.string_literal else .error);
            i = quote_end;
        } else {
            value_start := i;
            while i < to && !ascii_is_space(text[i])  i += 1;
            ex4_mark(line, value_start, i, .value);
        }
    }
}

// `start` must point at the opening quote. Returns the offset just past the closing quote, or `to` if unclosed.
scan_quoted :: (text: string, start: s64, to: s64) -> end: s64, closed: bool {
    i := start + 1;
    while i < to {
        if text[i] == #char "\"" {
            if i + 1 < to && text[i + 1] == #char "\"" {
                i += 2;
                continue;
            }
            return i + 1, true;
        }
        i += 1;
    }
    return to, false;
}

// Finds the first `=>` outside quotes that has whitespace on both sides. Returns -1 if there is none.
find_arrow :: (text: string, from: s64, to: s64) -> s64 {
    in_quotes := false;
    i := from;
    while i < to {
        c := text[i];
        if c == #char "\"" {
            if in_quotes && i + 1 < to && text[i + 1] == #char "\"" {
                i += 2;
                continue;
            }
            in_quotes = !in_quotes;
        } else if !in_quotes && c == #char "=" && i > from && i + 2 < to &&
                  text[i + 1] == #char ">" && ascii_is_space(text[i - 1]) && ascii_is_space(text[i + 2]) {
            return i;
        }
        i += 1;
    }
    return -1;
}
