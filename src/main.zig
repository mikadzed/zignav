const std = @import("std");
const posix = std.posix;
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");
const labels = @import("labels.zig");
const overlay = @import("overlay.zig");
const input = @import("input.zig");

/// Get frontmost application PID using NSWorkspace
fn getFrontmostAppPid() ?c.pid_t {
    const NSWorkspace = objc.getClass("NSWorkspace") orelse return null;
    const workspace = NSWorkspace.msgSend(objc.Object, "sharedWorkspace", .{});

    // frontmostApplication returns NSRunningApplication*
    const frontAppPtr = workspace.msgSend(?*anyopaque, "frontmostApplication", .{});
    if (frontAppPtr == null) return null;

    const frontApp = objc.Object{ .value = @ptrCast(@alignCast(frontAppPtr.?)) };
    const pid = frontApp.msgSend(c_int, "processIdentifier", .{});
    return @intCast(pid);
}

// Persistent state for overlay (needs to outlive the callback)
var global_gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;
var overlay_label_infos: ?[]overlay.LabelInfo = null;
var global_label_gen: ?labels.LabelGenerator = null;
var global_clickable: ?[]accessibility.ClickableElement = null;
var global_element_labels: ?[]const []const u8 = null;

/// Dismiss the overlay and cleanup
fn dismissOverlay() void {
    overlay.hide();
    input.deinit();
    cleanupOverlayData();
}

/// Called when the hotkey (Cmd+Shift+Space) is activated
fn onHotkeyActivated() void {
    std.debug.print("\n=== ZigNav Activated ===\n", .{});

    // Toggle overlay visibility
    if (overlay.isVisible()) {
        std.debug.print("Hiding overlay\n", .{});
        dismissOverlay();
        return;
    }

    // Initialize allocator if needed
    if (global_gpa == null) {
        global_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    }
    const allocator = global_gpa.?.allocator();

    // Get frontmost app PID via NSWorkspace
    const pid = getFrontmostAppPid() orelse {
        std.debug.print("Could not get frontmost app PID\n", .{});
        return;
    };

    // Create accessibility element for this app
    const focused_app = accessibility.UIElement.forApplication(pid);
    defer focused_app.deinit();

    // Enable manual accessibility for Electron apps
    // This forces Electron to populate its accessibility tree with DOM elements
    focused_app.enableManualAccessibility();

    // Get app title for logging
    if (focused_app.getTitle(allocator)) |title| {
        defer allocator.free(title);
        std.debug.print("App: {s}\n", .{title});
    }

    // Get main window
    const main_window = focused_app.getMainWindow() catch |err| {
        std.debug.print("Could not get main window: {}\n", .{err});
        return;
    };
    defer main_window.deinit();

    // Clean up previous clickable elements if any
    if (global_clickable) |old_clickable| {
        accessibility.freeClickableElements(allocator, old_clickable);
        global_clickable = null;
    }

    // Collect clickable elements (depth 50 for deep web content in Electron apps)
    const clickable = accessibility.collectClickableElements(main_window, allocator, 50) catch |err| {
        std.debug.print("Could not collect clickable elements: {}\n", .{err});
        return;
    };

    if (clickable.len == 0) {
        std.debug.print("No clickable elements found\n", .{});
        accessibility.freeClickableElements(allocator, clickable);
        return;
    }

    std.debug.print("Found {} clickable elements\n", .{clickable.len});

    // Store clickable elements globally for input handler
    global_clickable = clickable;

    // Log each element with its assigned label
    std.debug.print("\n--- Element to Label Mapping ---\n", .{});

    // Generate labels (use global generator so strings persist)
    if (global_label_gen != null) {
        global_label_gen.?.deinit();
    }
    global_label_gen = labels.LabelGenerator.init(allocator);
    const element_labels = global_label_gen.?.generate(clickable.len) catch {
        std.debug.print("Could not generate labels\n", .{});
        return;
    };

    // Store labels globally for input handler
    global_element_labels = element_labels;

    // Build LabelInfo array for overlay
    const label_infos = allocator.alloc(overlay.LabelInfo, clickable.len) catch {
        std.debug.print("Could not allocate label infos\n", .{});
        return;
    };

    for (clickable, 0..) |elem, i| {
        label_infos[i] = .{
            .label = element_labels[i],
            .x = elem.frame.origin.x + elem.frame.size.width / 2, // Center X
            .bottom_y = elem.frame.origin.y + elem.frame.size.height, // Bottom Y
        };

        // Log label -> element mapping
        const title = elem.element.getTitle(allocator);
        if (title) |t| {
            defer allocator.free(t);
            std.debug.print("[{s}] \"{s}\" at ({d:.0}, {d:.0}) {d:.0}x{d:.0}\n", .{
                element_labels[i],
                t,
                elem.frame.origin.x,
                elem.frame.origin.y,
                elem.frame.size.width,
                elem.frame.size.height,
            });
        } else {
            std.debug.print("[{s}] (no title) at ({d:.0}, {d:.0}) {d:.0}x{d:.0}\n", .{
                element_labels[i],
                elem.frame.origin.x,
                elem.frame.origin.y,
                elem.frame.size.width,
                elem.frame.size.height,
            });
        }
    }

    // Store for later cleanup
    overlay_label_infos = label_infos;

    // Initialize input handler with elements and labels
    input.init(clickable, element_labels, allocator);
    input.setDismissCallback(dismissOverlay);

    // Show overlay
    overlay.show(label_infos, allocator) catch |err| {
        std.debug.print("Could not show overlay: {}\n", .{err});
        return;
    };

    std.debug.print("Overlay shown with {} labels\n", .{label_infos.len});
}

fn cleanupOverlayData() void {
    if (global_label_gen != null) {
        global_label_gen.?.deinit();
        global_label_gen = null;
    }
    global_element_labels = null;

    if (overlay_label_infos) |infos| {
        if (global_gpa) |*gpa| {
            gpa.allocator().free(infos);
        }
        overlay_label_infos = null;
    }

    if (global_clickable) |clickable| {
        if (global_gpa) |*gpa| {
            accessibility.freeClickableElements(gpa.allocator(), clickable);
        }
        global_clickable = null;
    }
}

/// Full cleanup on app termination
fn cleanupAll() void {
    std.debug.print("\nCleaning up...\n", .{});

    // Hide overlay and cleanup input
    if (overlay.isVisible()) {
        overlay.hide();
    }
    input.deinit();
    overlay.deinit();

    // Cleanup overlay data
    cleanupOverlayData();

    // Cleanup hotkey
    hotkey.deinit();

    // Cleanup allocator
    if (global_gpa) |*gpa| {
        _ = gpa.deinit();
        global_gpa = null;
    }

    std.debug.print("Cleanup complete.\n", .{});
}

/// Signal handler for SIGINT/SIGTERM
fn handleSignal(sig: c_int) callconv(.c) void {
    _ = sig;
    // Stop the run loop
    const cf_run_loop = @cImport(@cInclude("CoreFoundation/CoreFoundation.h"));
    cf_run_loop.CFRunLoopStop(cf_run_loop.CFRunLoopGetCurrent());
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

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

pub fn main() !void {
    _ = objc.Class;
    std.debug.print("ZigNav starting...\n", .{});

    // Initialize as a proper macOS app (required for accessibility to work)
    const NSApp = objc.getClass("NSApplication").?;
    const app = NSApp.msgSend(objc.Object, "sharedApplication", .{});
    _ = app.msgSend(objc.Object, "setActivationPolicy:", .{@as(c_long, 1)}); // NSApplicationActivationPolicyAccessory

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

    // Register callbacks
    hotkey.setCallback(onHotkeyActivated);
    hotkey.setDismissCallback(dismissOverlay);

    std.debug.print("Listening for Cmd+Shift+Space (Ctrl+C to exit)...\n", .{});

    // Setup signal handlers for clean shutdown
    setupSignalHandlers();

    hotkey.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    // Run the event loop (blocks until stopped)
    hotkey.run();

    // Cleanup everything on exit
    cleanupAll();
}
