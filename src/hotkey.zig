const std = @import("std");
const input = @import("input.zig");
const overlay = @import("overlay.zig");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub const HotkeyError = error{
    AccessibilityNotGranted,
    EventTapCreationFailed,
    RunLoopSourceCreationFailed,
};

// Modifier flags
pub const Modifiers = struct {
    command: bool = false,
    shift: bool = false,
    option: bool = false,
    control: bool = false,

    pub fn fromCGEventFlags(flags: c.CGEventFlags) Modifiers {
        return .{
            .command = (flags & c.kCGEventFlagMaskCommand) != 0,
            .shift = (flags & c.kCGEventFlagMaskShift) != 0,
            .option = (flags & c.kCGEventFlagMaskAlternate) != 0,
            .control = (flags & c.kCGEventFlagMaskControl) != 0,
        };
    }

    pub fn matches(self: Modifiers, other: Modifiers) bool {
        return self.command == other.command and
            self.shift == other.shift and
            self.option == other.option and
            self.control == other.control;
    }
};

// Hotkey definition
pub const Hotkey = struct {
    keycode: u16,
    modifiers: Modifiers,
};

// Common keycodes
pub const Keycode = struct {
    pub const space: u16 = 49;
    pub const escape: u16 = 53;
    pub const @"return": u16 = 36;
    pub const tab: u16 = 48;
};

// Default hotkey: Cmd+Shift+Space (frontmost app)
pub const default_hotkey = Hotkey{
    .keycode = Keycode.space,
    .modifiers = .{ .command = true, .shift = true },
};

// System UI hotkey: Cmd+Shift+Enter (system-wide scan)
pub const system_ui_hotkey = Hotkey{
    .keycode = Keycode.@"return",
    .modifiers = .{ .command = true, .shift = true },
};

// Module-level state
var event_tap: ?c.CFMachPortRef = null;
var run_loop_source: ?c.CFRunLoopSourceRef = null;
var is_running: bool = false;
var registered_hotkey: Hotkey = default_hotkey;
var hotkey_callback: ?*const fn () void = null;
var system_ui_callback: ?*const fn () void = null;
var dismiss_callback: ?*const fn () void = null;

// C-compatible callback
fn eventTapCallback(
    proxy: c.CGEventTapProxy,
    event_type: c.CGEventType,
    event: c.CGEventRef,
    user_info: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    _ = proxy;
    _ = user_info;

    // Re-enable if disabled by timeout
    if (event_type == c.kCGEventTapDisabledByTimeout) {
        if (event_tap) |tap| c.CGEventTapEnable(tap, true);
        return event;
    }

    // Only process key down events
    if (event_type == c.kCGEventKeyDown) {
        const keycode: u16 = @intCast(c.CGEventGetIntegerValueField(event, c.kCGKeyboardEventKeycode));
        const flags = c.CGEventGetFlags(event);
        const modifiers = Modifiers.fromCGEventFlags(flags);

        // Check if main hotkey matches (Cmd+Shift+Space)
        if (keycode == registered_hotkey.keycode and modifiers.matches(registered_hotkey.modifiers)) {
            std.debug.print("Hotkey activated!\n", .{});
            if (hotkey_callback) |cb| {
                cb();
            }
            return null;
        }

        // Check if system UI hotkey matches (Cmd+Shift+Enter)
        if (keycode == system_ui_hotkey.keycode and modifiers.matches(system_ui_hotkey.modifiers)) {
            std.debug.print("System UI hotkey activated!\n", .{});
            if (system_ui_callback) |cb| {
                cb();
            }
            return null;
        }

        // If overlay is visible, forward key events to input handler
        if (overlay.isVisible()) {
            const result = input.handleKeyDown(keycode, modifiers.shift, modifiers.command);

            switch (result) {
                .consumed => return null, // Don't pass to app
                .passthrough => return event, // Let it through
                .dismiss => {
                    if (dismiss_callback) |cb| {
                        cb();
                    }
                    return null;
                },
                .execute => {
                    // Execute happens inside input handler, then dismiss
                    if (dismiss_callback) |cb| {
                        cb();
                    }
                    return null;
                },
            }
        }
    }

    return event;
}

pub fn checkPermission() bool {
    return c.CGPreflightListenEventAccess();
}

pub fn requestPermission() void {
    _ = c.CGRequestListenEventAccess();
}

pub fn checkAccessibilityPermission() bool {
    return c.AXIsProcessTrusted();
}

/// Set a custom hotkey (optional, defaults to Cmd+Shift+Space)
pub fn setHotkey(hotkey: Hotkey) void {
    registered_hotkey = hotkey;
}

/// Set callback function to be called when hotkey is activated
pub fn setCallback(callback: ?*const fn () void) void {
    hotkey_callback = callback;
}

/// Set callback function to be called when system UI hotkey is activated
pub fn setSystemUICallback(callback: ?*const fn () void) void {
    system_ui_callback = callback;
}

/// Set callback function to be called when overlay should be dismissed
pub fn setDismissCallback(callback: ?*const fn () void) void {
    dismiss_callback = callback;
}

pub fn init() HotkeyError!void {
    if (!checkPermission()) return HotkeyError.AccessibilityNotGranted;

    const event_mask: c.CGEventMask =
        (@as(c.CGEventMask, 1) << @intCast(c.kCGEventKeyDown)) |
        (@as(c.CGEventMask, 1) << @intCast(c.kCGEventKeyUp));

    // Use kCGEventTapOptionDefault to be able to intercept (consume) events
    event_tap = c.CGEventTapCreate(
        c.kCGSessionEventTap,
        c.kCGHeadInsertEventTap,
        c.kCGEventTapOptionDefault,
        event_mask,
        eventTapCallback,
        null,
    );
    if (event_tap == null) return HotkeyError.EventTapCreationFailed;

    run_loop_source = c.CFMachPortCreateRunLoopSource(c.kCFAllocatorDefault, event_tap.?, 0);
    if (run_loop_source == null) {
        deinit();
        return HotkeyError.RunLoopSourceCreationFailed;
    }

    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), run_loop_source.?, c.kCFRunLoopCommonModes);
    c.CGEventTapEnable(event_tap.?, true);
    is_running = true;
}

pub fn run() void {
    if (is_running) c.CFRunLoopRun();
}

pub fn deinit() void {
    if (run_loop_source) |src| {
        c.CFRunLoopRemoveSource(c.CFRunLoopGetCurrent(), src, c.kCFRunLoopCommonModes);
        c.CFRelease(src);
        run_loop_source = null;
    }
    if (event_tap) |tap| {
        c.CGEventTapEnable(tap, false);
        c.CFRelease(tap);
        event_tap = null;
    }
    is_running = false;
    hotkey_callback = null;
}
