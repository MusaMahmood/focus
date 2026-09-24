draw_ex4_theme_swatches :: (editor: *Editor, buffer: *Buffer, visible_range: Offset_Range, text_origin: Vector2) {
    theme_extra := get_ex4_theme_extra_if_present(buffer);
    if !theme_extra return;

    draw_color_swatches(editor, buffer, theme_extra.color_ranges, visible_range, text_origin);
}

draw_focus_config_swatches :: (editor: *Editor, buffer: *Buffer, visible_range: Offset_Range, text_origin: Vector2) {
    if !buffer.extra || buffer.extra.type != .focus_config return;
    config_extra := cast(*Focus_Config_Extra) buffer.extra;
    if config_extra.colors_section_start < 0 return;

    section_end := ifx config_extra.colors_section_end >= 0 then config_extra.colors_section_end else buffer.bytes.count;
    end := min(min(cast(s64) visible_range.end, section_end), buffer.bytes.count);

    pos := max(cast(s64) visible_range.start, config_extra.colors_section_start);
    while pos > config_extra.colors_section_start && buffer.bytes[pos - 1] != #char "\n"  pos -= 1;

    ranges: [..] Offset_Range;
    ranges.allocator = temp;

    while pos < end {
        line_end := pos;
        while line_end < buffer.bytes.count && buffer.bytes[line_end] != #char "\n"  line_end += 1;

        range, found := find_focus_config_color_value(buffer, pos, line_end);
        if found then array_add(*ranges, range);

        pos = line_end + 1;
    }

    draw_color_swatches(editor, buffer, ranges, visible_range, text_origin);
}

maybe_draw_ex4_theme_color_picker :: (active_editor_rect: Rect) {
    if config.settings.color_preview_popup == .disabled return;

    editor_id := get_visible_editor_id(editors.active_pane);
    if editor_id < 0 return;

    editor, buffer := get_editor_and_buffer(editor_id);
    if buffer.readonly return;

    theme_extra := get_ex4_theme_extra_if_present(buffer);
    if !theme_extra return;

    range, found := find_color_on_cursor_line(editor, buffer, theme_extra);
    if !found return;

    padding := floor(12 * dpi_scale);
    rect := shrink(active_editor_rect, padding);
    if status_bar_is_drawn_at_the_bottom() {
        _, rect = cut_bottom(rect, status_bar_height);
    }
    size := floor(min(min(rect.w, rect.h) * 0.4, 260 * dpi_scale));
    rect = cut_bottom(cut_right(rect, size), size);

    draw_color_picker(editor_id, editor, buffer, rect, range);
}

#scope_file

draw_color_swatches :: (editor: *Editor, buffer: *Buffer, ranges: [] Offset_Range, visible_range: Offset_Range, text_origin: Vector2) {
    size   := floor(char_x_advance);
    border := max(floor(dpi_scale), 1);

    Simp.set_shader_for_color(enable_blend = true);
    for range : ranges {
        if range.end   < visible_range.start continue;
        if range.start > visible_range.end   break;
        if range.end   > buffer.bytes.count  break;  // stale until the next retokenize

        color, ok := hex_to_color_vec4(get_range_as_string(buffer, range));
        if !ok continue;

        coords := offset_to_coords(editor, buffer, range.end);
        swatch := make_rect(
            text_origin.x + (coords.col + 0.5) * char_x_advance,
            text_origin.y - coords.line * line_height + (line_height - size) / 2,
            size,
            size,
        );

        // The background layer makes translucent colors read against the editor rather than the border.
        draw_rect_raw(expand(swatch, border), Color.UI_DIM);
        draw_rect_raw(swatch, Color.BACKGROUND_0);
        draw_rect_with_raw_color(swatch, color);
    }
}

get_ex4_theme_extra_if_present :: (buffer: *Buffer) -> *Ex4_Theme_Extra {
    if buffer.lang != .Ex4_Theme || !buffer.extra || buffer.extra.type != .ex4_theme return null;
    return cast(*Ex4_Theme_Extra) buffer.extra;
}

// Scans bytes rather than using line tables, which may be stale while the picker is editing the buffer.
find_color_on_cursor_line :: (editor: *Editor, buffer: *Buffer, theme_extra: *Ex4_Theme_Extra) -> Offset_Range, bool {
    pos := clamp(editor.cursors[editor.main_cursor].pos, 0, cast(s32) buffer.bytes.count);

    line_start := pos;
    while line_start > 0 && buffer.bytes[line_start - 1] != #char "\n"  line_start -= 1;
    line_end := pos;
    while line_end < buffer.bytes.count && buffer.bytes[line_end] != #char "\n"  line_end += 1;

    for theme_extra.color_ranges {
        if it.end > buffer.bytes.count break;
        if it.start >= line_start && it.end <= line_end return it, true;
        if it.start > line_end break;
    }
    return .{}, false;
}

// Matches `name: RRGGBB[AA]` within [line_start, line_end). `$references` and malformed values yield nothing.
find_focus_config_color_value :: (buffer: *Buffer, line_start: s64, line_end: s64) -> Offset_Range, bool {
    bytes := buffer.bytes;

    i := line_start;
    while i < line_end && ascii_is_space(bytes[i])  i += 1;
    if i >= line_end || bytes[i] == #char "#" || bytes[i] == #char "[" return .{}, false;

    while i < line_end && bytes[i] != #char ":"  i += 1;
    i += 1;
    while i < line_end && ascii_is_space(bytes[i])  i += 1;

    value_start := i;
    while i < line_end && is_hex(bytes[i])  i += 1;
    count := i - value_start;
    if count != 6 && count != 8 return .{}, false;
    if i < line_end && !ascii_is_space(bytes[i]) return .{}, false;

    return .{ xx value_start, xx i }, true;
}
