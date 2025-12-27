const std = @import("std");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub const HotkeyError = error{
    AccessibilityNotGranted,
    EventTapCreationFailed,
    RunLoopSourceCreationFailed,
};

// Module-level state (C callbacks can't capture closures)
var event_tap: ?c.CFMachPortRef = null;
var run_loop_source: ?c.CFRunLoopSourceRef = null;
var is_running: bool = false;

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

    // Print key events
    if (event_type == c.kCGEventKeyDown or event_type == c.kCGEventKeyUp) {
        const keycode: u16 = @intCast(c.CGEventGetIntegerValueField(event, c.kCGKeyboardEventKeycode));
        std.debug.print("Key {s}: keycode={d}\n", .{
            if (event_type == c.kCGEventKeyDown) "down" else "up",
            keycode,
        });
    }

    return event;
}

pub fn checkPermission() bool {
    return c.CGPreflightListenEventAccess();
}

pub fn requestPermission() void {
    _ = c.CGRequestListenEventAccess();
}

pub fn init() HotkeyError!void {
    if (!checkPermission()) return HotkeyError.AccessibilityNotGranted;

    const event_mask: c.CGEventMask =
        (@as(c.CGEventMask, 1) << @intCast(c.kCGEventKeyDown)) |
        (@as(c.CGEventMask, 1) << @intCast(c.kCGEventKeyUp));

    event_tap = c.CGEventTapCreate(
        c.kCGSessionEventTap,
        c.kCGHeadInsertEventTap,
        c.kCGEventTapOptionListenOnly,
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
}
