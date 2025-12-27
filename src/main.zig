const std = @import("std");
const posix = std.posix;
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");
const input = @import("input.zig");
const app = @import("app.zig");

// ============================================================================
// Main Entry Point
// ============================================================================
// Initializes the application, checks permissions, and starts the event loop.

const c = @cImport({
    @cInclude("CoreFoundation/CoreFoundation.h");
});

/// Global allocator
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};

/// Global app instance
var application: app.App = undefined;

/// Signal handler for SIGINT/SIGTERM
fn handleSignal(sig: c_int) callconv(.c) void {
    _ = sig;
    c.CFRunLoopStop(c.CFRunLoopGetCurrent());
}

/// Setup signal handlers
fn setupSignalHandlers() void {
    const act = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = 0,
        .flags = 0,
    };

    posix.sigaction(posix.SIG.INT, &act, null);
    posix.sigaction(posix.SIG.TERM, &act, null);
}

pub fn main() !void {
    _ = objc.Class;
    std.debug.print("ZigNav starting...\n", .{});

    // Initialize as a proper macOS app (required for accessibility to work)
    const NSApp = objc.getClass("NSApplication").?;
    const ns_app = NSApp.msgSend(objc.Object, "sharedApplication", .{});
    _ = ns_app.msgSend(objc.Object, "setActivationPolicy:", .{@as(c_long, 1)}); // NSApplicationActivationPolicyAccessory

    // Log permission status
    const input_monitoring = hotkey.checkPermission();
    const accessibility_perm = accessibility.isAccessibilityEnabled();

    std.debug.print("Permission status:\n", .{});
    std.debug.print("  Input Monitoring: {}\n", .{input_monitoring});
    std.debug.print("  Accessibility: {}\n", .{accessibility_perm});

    if (!input_monitoring) {
        std.debug.print("\nInput Monitoring permission required.\n", .{});
        std.debug.print("Opening System Preferences > Privacy & Security > Input Monitoring...\n", .{});
        hotkey.requestPermission();
        std.debug.print("Grant permission to 'zignav' and restart the app.\n", .{});
        return;
    }

    if (!accessibility_perm) {
        std.debug.print("\nAccessibility permission required.\n", .{});
        std.debug.print("Go to: System Settings > Privacy & Security > Accessibility\n", .{});
        accessibility.requestAccessibilityPermission();
        std.debug.print("Grant permission and restart the app.\n", .{});
        return;
    }

    std.debug.print("All permissions granted.\n", .{});

    // Initialize the application state machine
    application = app.App.init(gpa.allocator());
    app.setGlobalApp(&application);

    // Register callbacks with hotkey module
    hotkey.setCallback(app.hotkeyCallback);
    hotkey.setDismissCallback(app.dismissCallback);

    // Set dismiss callback for input handler (timer-triggered actions)
    input.setDismissCallback(app.dismissCallback);

    std.debug.print("Listening for Cmd+Shift+Space (Ctrl+C to exit)...\n", .{});

    // Setup signal handlers for clean shutdown
    setupSignalHandlers();

    // Initialize hotkey listener
    hotkey.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    // Run the event loop (blocks until stopped)
    hotkey.run();

    // Cleanup
    std.debug.print("\nCleaning up...\n", .{});
    application.deinit();
    _ = gpa.deinit();
    std.debug.print("Cleanup complete.\n", .{});
}
