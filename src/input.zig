const std = @import("std");
const accessibility = @import("accessibility.zig");
const labels = @import("labels.zig");
const overlay = @import("overlay.zig");

// ============================================================================
// Input Handler
// ============================================================================
// Handles keyboard input when the overlay is visible.
// Matches typed characters to labels and executes click actions.
// Uses debounce (100ms) to distinguish single vs double letter labels.

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

/// Debounce delay in seconds (200ms)
const DEBOUNCE_DELAY: f64 = 0.2;

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
    menu_continue, // Execute action and re-scan for submenu items
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

/// Debounce timer state
var debounce_timer: ?c.CFRunLoopTimerRef = null;
var pending_action_index: ?usize = null;
var pending_action_shift: bool = false; // Whether shift was held when action was queued
var dismiss_callback_ptr: ?*const fn () void = null;
var menu_continue_callback_ptr: ?*const fn () void = null;

/// Menu mode - when true, actions return menu_continue instead of execute
var is_menu_mode: bool = false;

/// Timer callback - fires after debounce delay to execute single-letter action
fn debounceTimerCallback(_: c.CFRunLoopTimerRef, _: ?*anyopaque) callconv(.c) void {
    if (pending_action_index) |idx| {
        const action: ClickAction = if (pending_action_shift) .show_menu else .press;
        std.debug.print("Debounce timer fired - executing {s} on index {}\n", .{ if (pending_action_shift) "show_menu" else "press", idx });
        executeAction(idx, action);
        pending_action_index = null;

        // In menu mode, only continue if the item has a submenu
        if (is_menu_mode) {
            const elements = current_elements orelse {
                if (dismiss_callback_ptr) |cb| cb();
                cancelDebounceTimer();
                return;
            };
            const alloc = allocator orelse {
                if (dismiss_callback_ptr) |cb| cb();
                cancelDebounceTimer();
                return;
            };

            if (idx < elements.len and elements[idx].element.hasSubmenu(alloc)) {
                std.debug.print("Menu item has submenu - continuing\n", .{});
                if (menu_continue_callback_ptr) |cb| cb();
            } else {
                std.debug.print("Menu item has no submenu - dismissing\n", .{});
                if (dismiss_callback_ptr) |cb| cb();
            }
        } else {
            if (dismiss_callback_ptr) |cb| cb();
        }
    }
    cancelDebounceTimer();
}

/// Start debounce timer for potential single-letter match
fn startDebounceTimer(action_index: usize, shift_held: bool) void {
    cancelDebounceTimer();
    pending_action_index = action_index;
    pending_action_shift = shift_held;

    var context = c.CFRunLoopTimerContext{
        .version = 0,
        .info = null,
        .retain = null,
        .release = null,
        .copyDescription = null,
    };

    const fire_time = c.CFAbsoluteTimeGetCurrent() + DEBOUNCE_DELAY;
    debounce_timer = c.CFRunLoopTimerCreate(
        c.kCFAllocatorDefault,
        fire_time,
        0, // Don't repeat
        0,
        0,
        debounceTimerCallback,
        &context,
    );

    if (debounce_timer) |timer| {
        c.CFRunLoopAddTimer(c.CFRunLoopGetCurrent(), timer, c.kCFRunLoopCommonModes);
    }
}

/// Cancel any pending debounce timer
fn cancelDebounceTimer() void {
    if (debounce_timer) |timer| {
        c.CFRunLoopTimerInvalidate(timer);
        c.CFRelease(@ptrCast(timer));
        debounce_timer = null;
    }
    pending_action_index = null;
    pending_action_shift = false;
}

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

/// Set dismiss callback for timer-triggered actions
pub fn setDismissCallback(callback: ?*const fn () void) void {
    dismiss_callback_ptr = callback;
}

/// Set menu continue callback for menu navigation mode
pub fn setMenuContinueCallback(callback: ?*const fn () void) void {
    menu_continue_callback_ptr = callback;
}

/// Set menu mode - when true, executing an action triggers re-scan for submenus
pub fn setMenuMode(enabled: bool) void {
    is_menu_mode = enabled;
}

/// Check if menu mode is enabled
pub fn getMenuMode() bool {
    return is_menu_mode;
}

/// Reset input state (clear typed characters)
pub fn reset() void {
    typed_len = 0;
    selected_index = null;
    cancelDebounceTimer();
}

/// Deinitialize
pub fn deinit() void {
    reset();
    current_elements = null;
    current_labels = null;
    allocator = null;
    dismiss_callback_ptr = null;
    menu_continue_callback_ptr = null;
    is_menu_mode = false;
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

/// Process a letter key press (shift_held triggers right-click/show_menu instead of press)
pub fn processLetter(char: u8, shift_held: bool) InputResult {
    // Only accept lowercase letters
    const lower = if (char >= 'A' and char <= 'Z') char + 32 else char;
    if (lower < 'a' or lower > 'z') return .passthrough;

    // Cancel any pending debounce timer - user is typing more
    cancelDebounceTimer();

    // Check if adding this char would still have matches
    if (typed_len < typed_input.len - 1) {
        typed_input[typed_len] = lower;
        typed_len += 1;

        const input = typed_input[0..typed_len];
        const matches = countMatches();
        std.debug.print("Typed: '{s}', matches: {}, shift: {}\n", .{ input, matches, shift_held });

        if (matches == 0) {
            // No matches - undo and ignore
            typed_len -= 1;
            return .consumed;
        }

        // Check for exact match
        const exact_match_idx = findExactMatch();
        const has_exact = exact_match_idx != null;

        if (matches == 1 and has_exact) {
            // Only one match and it's exact - execute immediately
            const idx = exact_match_idx.?;
            selected_index = idx;
            const action: ClickAction = if (shift_held) .show_menu else .press;
            std.debug.print("Exact unique match at index {} - executing {s}\n", .{ idx, if (shift_held) "show_menu" else "press" });
            executeAction(idx, action);

            // In menu mode, only continue if the item has a submenu
            if (is_menu_mode) {
                const elements = current_elements orelse return .execute;
                const alloc = allocator orelse return .execute;
                if (idx < elements.len and elements[idx].element.hasSubmenu(alloc)) {
                    std.debug.print("Menu item has submenu - continuing\n", .{});
                    return .menu_continue;
                } else {
                    std.debug.print("Menu item has no submenu - dismissing\n", .{});
                    return .execute;
                }
            }
            return .execute;
        }

        if (has_exact and matches > 1) {
            // Exact match exists but there are also longer labels (e.g., "a" matches but "aa", "ab" also exist)
            // Start debounce timer - if no more keys within 100ms, execute the exact match
            const idx = exact_match_idx.?;
            std.debug.print("Exact match at index {} with {} total matches - starting debounce\n", .{ idx, matches });
            startDebounceTimer(idx, shift_held);
            return .consumed;
        }

        // No exact match yet, just update display
        updateOverlayHighlights();
    }

    return .consumed;
}

/// Process delete/backspace key
pub fn processDelete() InputResult {
    cancelDebounceTimer();
    if (typed_len > 0) {
        typed_len -= 1;
        std.debug.print("Deleted, typed: '{s}'\n", .{typed_input[0..typed_len]});
        updateOverlayHighlights();
    }
    return .consumed;
}

/// Process escape key
pub fn processEscape() InputResult {
    cancelDebounceTimer();
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

    // Check for exact match first (e.g., "f" when there's also "fa", "fb", etc.)
    if (findExactMatch()) |idx| {
        std.debug.print("Exact match on Return: index {}\n", .{idx});
        executeAction(idx, action);
        return .dismiss;
    }

    // If we have exactly one prefix match, execute on that
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

    // Handle letter keys (pass shift for right-click action)
    if (keycodeToChar(keycode)) |char| {
        return processLetter(char, shift);
    }

    return .consumed;
}
