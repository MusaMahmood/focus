// Highlights `.ex4-theme` and `settings.ex4-config` files: `@directive value`, `[section]`, `Key: value`,
// `Ctrl-Shift-W  action` lines under `[hotkeys]` (Ex4 1.17+) and `[global_hotkeys]` (Ex4 1.20.10+),
// and `#` comments.
tokenize_ex4_config :: (buffer: *Buffer, start_offset := -1, count := -1) -> [] Buffer_Region {
    pos, end := ex4_get_tokenize_range(buffer, start_offset, count);
    memset(buffer.tokens.data + pos, xx Token_Type.default, end - pos);

    known_directives :: string.["version", "name", "base"];

    color_ranges: *[..] Offset_Range;
    if buffer.lang == .Ex4_Theme && start_offset < 0 {
        theme_extra := get_ex4_theme_extra(buffer);
        array_reset_keeping_memory(*theme_extra.color_ranges);
        color_ranges = *theme_extra.color_ranges;
    }
    in_color_section := false;
    hotkey_actions: [] string;   // the section's actions; empty outside a hotkeys section

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
        if c == #char "@" {
            ex4_highlight_directive(line, b, e, known_directives);
        } else if c == #char "[" {
            ex4_mark(line, b, e, ifx line.text[e - 1] == #char "]" then Token_Type.keyword else .error);
            section := string.{ e - b, line.text.data + b };
            in_color_section = section == "[colors]" || section == "[ex4]";
            if section == "[hotkeys]"              hotkey_actions = EX4_HOTKEY_ACTIONS;
            else if section == "[global_hotkeys]"  hotkey_actions = EX4_GLOBAL_HOTKEY_ACTIONS;
            else                                   hotkey_actions = .[];
        } else if hotkey_actions.count {
            highlight_hotkey_binding(line, b, e, hotkey_actions);
        } else {
            highlight_key_value(line, b, e, ifx in_color_section then color_ranges else null);
        }
    }

    return .[];
}

get_ex4_theme_extra :: (buffer: *Buffer) -> *Ex4_Theme_Extra {
    assert(context.allocator.proc == focus_allocator.proc);
    if buffer.extra && buffer.extra.type != .ex4_theme {
        free_buffer_extra(buffer.extra);
        buffer.extra = null;
    }
    if !buffer.extra then buffer.extra = New(Ex4_Theme_Extra);
    return cast(*Ex4_Theme_Extra) buffer.extra;
}

Ex4_Line :: struct {
    text:   string;
    tokens: [] Token_Type;
    offset: s64;
}

ex4_get_tokenize_range :: (buffer: *Buffer, start_offset: s64, count: s64) -> start: s64, end: s64 {
    if start_offset < 0 return 0, buffer.bytes.count;
    start := clamp(start_offset, 0, buffer.bytes.count);
    end   := clamp(start + count, start, buffer.bytes.count);
    return start, end;
}

// Returned lines exclude the trailing `\n` and `\r`.
ex4_next_line :: (buffer: *Buffer, pos: *s64, end: s64) -> Ex4_Line, bool {
    if pos.* >= end return .{}, false;

    line_start := pos.*;
    i := line_start;
    while i < end && buffer.bytes[i] != #char "\n"  i += 1;
    pos.* = i + 1;

    line_end := i;
    if line_end > line_start && buffer.bytes[line_end - 1] == #char "\r"  line_end -= 1;

    line: Ex4_Line;
    line.text   = string.{ line_end - line_start, buffer.bytes.data  + line_start };
    line.tokens = .{ line_end - line_start, buffer.tokens.data + line_start };
    line.offset = line_start;
    return line, true;
}

ex4_mark :: (line: Ex4_Line, from: s64, to: s64, type: Token_Type) {
    if to <= from return;
    memset(line.tokens.data + from, xx type, to - from);
}

ex4_trim_range :: (text: string, from: s64, to: s64) -> from: s64, to: s64 {
    while from < to && ascii_is_space(text[from])   from += 1;
    while to > from && ascii_is_space(text[to - 1]) to -= 1;
    return from, to;
}

// Mirrors Ex4's strip_comment: `#` opens a comment only outside quotes, at the start of the line or after whitespace.
// Inside quotes `""` is a literal quote.
ex4_find_comment :: (text: string) -> comment_start: s64, unterminated_quote: bool {
    in_quotes := false;
    i := 0;
    while i < text.count {
        c := text[i];
        if c == #char "\"" {
            if in_quotes && i + 1 < text.count && text[i + 1] == #char "\"" {
                i += 2;
                continue;
            }
            in_quotes = !in_quotes;
        } else if c == #char "#" && !in_quotes && (i == 0 || ascii_is_space(text[i - 1])) {
            return i, false;
        }
        i += 1;
    }
    return text.count, in_quotes;
}

ex4_highlight_directive :: (line: Ex4_Line, b: s64, e: s64, known_directives: [] string) {
    name_end := b + 1;
    while name_end < e && !ascii_is_space(line.text[name_end])  name_end += 1;
    name := string.{ name_end - b - 1, line.text.data + b + 1 };

    known := array_find(known_directives, name);
    ex4_mark(line, b, name_end, ifx known then Token_Type.directive else .error);
    if !known return;

    value_start, value_end := ex4_trim_range(line.text, name_end, e);
    if name == "version" {
        is_number := value_start < value_end;
        for value_start..value_end-1  if !ascii_is_digit(line.text[it]) is_number = false;
        ex4_mark(line, value_start, value_end, ifx is_number then Token_Type.number else .error);
    } else {
        ex4_mark(line, value_start, value_end, .value);
    }
}

#scope_file

// Mirrors Ex4's hotkey_parse_line and parse_key_combo: modifiers joined to the key by '-', whitespace,
// then the action. An empty modifier is the '-' key itself, as in `Ctrl--`. Key names are not
// checked; Ex4 accepts any Dear ImGui key name.
highlight_hotkey_binding :: (line: Ex4_Line, b: s64, e: s64, actions: [] string) {
    split := e;
    while split > b && !ascii_is_space(line.text[split - 1])  split -= 1;
    if split == b {
        ex4_mark(line, b, e, .error);
        return;
    }

    action := string.{ e - split, line.text.data + split };
    ex4_mark(line, split, e, ifx array_find(actions, action) then Token_Type.function else .error);

    combo_start, combo_end := ex4_trim_range(line.text, b, split);
    i := combo_start;
    while true {
        dash := i;
        while dash < combo_end && line.text[dash] != #char "-"  dash += 1;
        if dash == combo_end || dash == i  break;

        modifier := to_lower_copy(string.{ dash - i, line.text.data + i },, temp);
        ex4_mark(line, i, dash, ifx array_find(EX4_HOTKEY_MODIFIERS, modifier) then Token_Type.value else .error);
        ex4_mark(line, dash, dash + 1, .punctuation);
        i = dash + 1;
    }
    if i == combo_end  ex4_mark(line, combo_start, combo_end, .error);   // modifiers but no key
}

EX4_HOTKEY_MODIFIERS :: string.["ctrl", "control", "cmd", "command", "shift", "alt", "opt", "option"];

// Keep in step with hotkey_actions_build in Ex4's src/ui/imgui_keyboard.jai.
EX4_HOTKEY_ACTIONS :: string.[
    "program_exit", "minimize_to_tray", "switch_to_password_mode", "switch_to_bitlocker_ui",
    "bitlocker_open_channel", "bitlocker_close_channel", "toggle_show_password", "toggle_show_history",
    "lock_password_mode", "dismiss", "password_mode_submit", "unlock_all_drives", "toggle_debug_panel",
    "toggle_style_editor", "toggle_frame_times", "save", "create_new_entry", "copy", "copy_alt",
    "copy_username", "set_keyboard_search_focus", "show_in_file_explorer", "launch_as_administrator",
    "search_reset", "delete_password_entry", "increment_search_filter", "search_exact_match_toggle",
    "search_match_whole_word_toggle", "search_sort_type_toggle", "search_sort_order_toggle",
    "search_refresh_results", "search_backend_toggle", "open_selected_path_in_terminal", "open_selected_path_in_elevated_terminal",
    "open_selected_path_in_focus", "open_selected_path_in_vscode", "open_selected_path_in_10x_editor",
    "next_item", "previous_item", "selected_item_up", "selected_item_down", "selected_item_up_multi",
    "selected_item_down_multi", "scroll_up_page", "scroll_down_page", "scroll_up_page_alt",
    "scroll_down_page_alt", "decrease_font_size", "increase_font_size", "reset_window",
];

// Keep in step with global_hotkey_actions_build in Ex4's src/ui/imgui_keyboard.jai.
EX4_GLOBAL_HOTKEY_ACTIONS :: string.["bring_to_foreground", "open_password_mode"];

highlight_key_value ::(line: Ex4_Line, b: s64, e: s64, color_ranges: *[..] Offset_Range) {
    colon := b;
    while colon < e && line.text[colon] != #char ":"  colon += 1;
    if colon == e {
        ex4_mark(line, b, e, .error);
        return;
    }

    key_start, key_end := ex4_trim_range(line.text, b, colon);
    ex4_mark(line, key_start, key_end, ifx key_start < key_end then Token_Type.function else .error);
    ex4_mark(line, colon, colon + 1, .punctuation);

    i := colon + 1;
    while i < e {
        while i < e && ascii_is_space(line.text[i])  i += 1;
        word_start := i;
        while i < e && !ascii_is_space(line.text[i]) i += 1;
        if word_start == i break;

        word := string.{ i - word_start, line.text.data + word_start };
        is_color := is_hex_color(word);
        ex4_mark(line, word_start, i, ifx is_number(word) || is_color then Token_Type.number else .value);
        if is_color && color_ranges then array_add(color_ranges, .{ xx (line.offset + word_start), xx (line.offset + i) });
    }
}

is_number :: (s: string) -> bool {
    i := 0;
    if i < s.count && (s[i] == #char "-" || s[i] == #char "+")  i += 1;

    digits := 0;
    seen_dot := false;
    while i < s.count {
        c := s[i];
        if ascii_is_digit(c) {
            digits += 1;
        } else if c == #char "." && !seen_dot {
            seen_dot = true;
        } else {
            return false;
        }
        i += 1;
    }
    return digits > 0;
}

is_hex_color :: (s: string) -> bool {
    if s.count != 6 && s.count != 8 return false;
    for 0..s.count-1  if !is_hex(s[it]) return false;
    return true;
}
