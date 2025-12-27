const std = @import("std");
const accessibility = @import("accessibility.zig");
const labels = @import("labels.zig");
const overlay = @import("overlay.zig");

// ============================================================================
// Input Handler
// ============================================================================
// Handles keyboard input when the overlay is visible.
// Matches typed characters to labels and executes click actions.

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

/// Key codes for special keys
pub const Keycode = struct {
    pub const escape: u16 = 53;
    pub const @"return": u16 = 36;
    pub const tab: u16 = 48;
    pub const delete: u16 = 51;
    pub const space: u16 = 49;
};

/// Action result from key processing
pub const InputResult = enum {
    consumed, // Key was handled, don't pass to app
    passthrough, // Let the key through to the app
    dismiss, // Hide overlay and dismiss
    execute, // Execute action on matched element
};

/// Click action types
pub const ClickAction = enum {
    press, // Normal click (Return)
    show_menu, // Context menu (Shift+Return)
    cmd_click, // Cmd+click for new tab (Cmd+Return)
};

/// Input handler state
var typed_input: [32]u8 = undefined;
var typed_len: usize = 0;
var current_elements: ?[]accessibility.ClickableElement = null;
var current_labels: ?[]const []const u8 = null;
var selected_index: ?usize = null;
var allocator: ?std.mem.Allocator = null;

/// Initialize the input handler with element and label data
pub fn init(
    elements: []accessibility.ClickableElement,
    element_labels: []const []const u8,
    alloc: std.mem.Allocator,
) void {
    current_elements = elements;
    current_labels = element_labels;
    allocator = alloc;
    reset();
}

/// Reset input state (clear typed characters)
pub fn reset() void {
    typed_len = 0;
    selected_index = null;
}

/// Deinitialize
pub fn deinit() void {
    reset();
    current_elements = null;
    current_labels = null;
    allocator = null;
}

/// Get the current typed input
pub fn getTypedInput() []const u8 {
    return typed_input[0..typed_len];
}

/// Get matching labels for current input
pub fn getMatchingLabels() []const usize {
    // This would return indices of matching labels
    // For now, we just filter in place
    return &[_]usize{};
}

/// Count how many labels match the current prefix
pub fn countMatches() usize {
    const element_labels = current_labels orelse return 0;
    const input = typed_input[0..typed_len];
    return labels.countMatchingLabels(element_labels, input);
}

/// Find index of exact match, if any
pub fn findExactMatch() ?usize {
    const element_labels = current_labels orelse return null;
    const input = typed_input[0..typed_len];

    for (element_labels, 0..) |label, i| {
        if (labels.isExactMatch(label, input)) {
            return i;
        }
    }
    return null;
}

/// Find index of unique prefix match (only one label matches)
pub fn findUniquePrefixMatch() ?usize {
    const element_labels = current_labels orelse return null;
    const input = typed_input[0..typed_len];
    if (input.len == 0) return null;

    var match_index: ?usize = null;
    var match_count: usize = 0;

    for (element_labels, 0..) |label, i| {
        if (labels.startsWithPrefix(label, input)) {
            match_index = i;
            match_count += 1;
            if (match_count > 1) return null; // More than one match
        }
    }

    return if (match_count == 1) match_index else null;
}

/// Process a letter key press
pub fn processLetter(char: u8) InputResult {
    // Only accept lowercase letters
    const lower = if (char >= 'A' and char <= 'Z') char + 32 else char;
    if (lower < 'a' or lower > 'z') return .passthrough;

    // Check if adding this char would still have matches
    if (typed_len < typed_input.len - 1) {
        typed_input[typed_len] = lower;
        typed_len += 1;

        const matches = countMatches();
        std.debug.print("Typed: '{s}', matches: {}\n", .{ typed_input[0..typed_len], matches });

        if (matches == 0) {
            // No matches - undo and ignore
            typed_len -= 1;
            return .consumed;
        }

        // Only auto-execute when there's exactly ONE matching label
        // This allows typing "aa" even when "a" exists
        if (matches == 1) {
            // Find the single matching label
            if (findUniquePrefixMatch()) |idx| {
                selected_index = idx;
                std.debug.print("Unique match found at index {}\n", .{idx});
                executeAction(idx, .press);
                return .execute;
            }
        }

        // Update overlay to show filtered labels
        updateOverlayHighlights();
    }

    return .consumed;
}

/// Process delete/backspace key
pub fn processDelete() InputResult {
    if (typed_len > 0) {
        typed_len -= 1;
        std.debug.print("Deleted, typed: '{s}'\n", .{typed_input[0..typed_len]});
        updateOverlayHighlights();
    }
    return .consumed;
}

/// Process escape key
pub fn processEscape() InputResult {
    std.debug.print("Escape pressed - dismissing overlay\n", .{});
    return .dismiss;
}

/// Process tab key for cycling
pub fn processTab(shift_held: bool) InputResult {
    _ = shift_held;
    // TODO: Implement Tab cycling between elements
    return .consumed;
}

/// Process return key to execute action
pub fn processReturn(modifiers: struct { shift: bool = false, cmd: bool = false }) InputResult {
    const action: ClickAction = if (modifiers.cmd)
        .cmd_click
    else if (modifiers.shift)
        .show_menu
    else
        .press;

    // If we have a selected element, execute action
    if (selected_index) |idx| {
        executeAction(idx, action);
        return .dismiss;
    }

    // If we have exactly one match, execute on that
    if (findUniquePrefixMatch()) |idx| {
        executeAction(idx, action);
        return .dismiss;
    }

    return .consumed;
}

/// Execute an action on the element at the given index
fn executeAction(index: usize, action: ClickAction) void {
    const elements = current_elements orelse return;
    if (index >= elements.len) return;

    const element = elements[index].element;
    const action_name: [*:0]const u8 = switch (action) {
        .press => accessibility.Action.press,
        .show_menu => accessibility.Action.showMenu,
        .cmd_click => accessibility.Action.press, // Same as press, handled differently by apps
    };

    std.debug.print("Executing {s} on element {}\n", .{ action_name, index });

    element.performAction(action_name) catch |err| {
        std.debug.print("Action failed: {}\n", .{err});
    };
}

/// Update the overlay to highlight matching labels
fn updateOverlayHighlights() void {
    // TODO: Update overlay to dim non-matching labels
    // For now, just log the state
    const input = typed_input[0..typed_len];
    const matches = countMatches();
    std.debug.print("Overlay update: prefix='{s}', matches={}\n", .{ input, matches });
}

/// Convert a keycode to a character (if it's a letter)
pub fn keycodeToChar(keycode: u16) ?u8 {
    // macOS keycode to character mapping for letters
    return switch (keycode) {
        0 => 'a',
        1 => 's',
        2 => 'd',
        3 => 'f',
        4 => 'h',
        5 => 'g',
        6 => 'z',
        7 => 'x',
        8 => 'c',
        9 => 'v',
        11 => 'b',
        12 => 'q',
        13 => 'w',
        14 => 'e',
        15 => 'r',
        16 => 'y',
        17 => 't',
        18 => '1',
        19 => '2',
        20 => '3',
        21 => '4',
        22 => '6',
        23 => '5',
        24 => '=',
        25 => '9',
        26 => '7',
        27 => '-',
        28 => '8',
        29 => '0',
        31 => 'o',
        32 => 'u',
        33 => '[',
        34 => 'i',
        35 => 'p',
        37 => 'l',
        38 => 'j',
        40 => 'k',
        41 => ';',
        42 => '\\',
        43 => ',',
        44 => '/',
        45 => 'n',
        46 => 'm',
        47 => '.',
        else => null,
    };
}

/// Handle a key down event, returning whether it should be consumed
pub fn handleKeyDown(keycode: u16, shift: bool, cmd: bool) InputResult {
    // Handle special keys
    if (keycode == Keycode.escape) {
        return processEscape();
    }

    if (keycode == Keycode.@"return") {
        return processReturn(.{ .shift = shift, .cmd = cmd });
    }

    if (keycode == Keycode.tab) {
        return processTab(shift);
    }

    if (keycode == Keycode.delete) {
        return processDelete();
    }

    // Handle letter keys
    if (keycodeToChar(keycode)) |char| {
        return processLetter(char);
    }

    return .consumed;
}
