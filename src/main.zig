const std = @import("std");
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");
const labels = @import("labels.zig");
const overlay = @import("overlay.zig");

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

/// Called when the hotkey (Cmd+Shift+Space) is activated
fn onHotkeyActivated() void {
    std.debug.print("\n=== ZigNav Activated ===\n", .{});

    // Toggle overlay visibility
    if (overlay.isVisible()) {
        std.debug.print("Hiding overlay\n", .{});
        overlay.hide();
        cleanupOverlayData();
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

    // Collect clickable elements
    const clickable = accessibility.collectClickableElements(main_window, allocator, 15) catch |err| {
        std.debug.print("Could not collect clickable elements: {}\n", .{err});
        return;
    };
    defer accessibility.freeClickableElements(allocator, clickable);

    if (clickable.len == 0) {
        std.debug.print("No clickable elements found\n", .{});
        return;
    }

    std.debug.print("Found {} clickable elements\n", .{clickable.len});

    // Generate labels (use global generator so strings persist)
    if (global_label_gen != null) {
        global_label_gen.?.deinit();
    }
    global_label_gen = labels.LabelGenerator.init(allocator);
    const element_labels = global_label_gen.?.generate(clickable.len) catch {
        std.debug.print("Could not generate labels\n", .{});
        return;
    };

    // Build LabelInfo array for overlay
    const label_infos = allocator.alloc(overlay.LabelInfo, clickable.len) catch {
        std.debug.print("Could not allocate label infos\n", .{});
        return;
    };

    for (clickable, 0..) |elem, i| {
        label_infos[i] = .{
            .label = element_labels[i],
            .center = elem.frame.center(),
        };
    }

    // Store for later cleanup
    overlay_label_infos = label_infos;

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
    if (overlay_label_infos) |infos| {
        if (global_gpa) |*gpa| {
            gpa.allocator().free(infos);
        }
        overlay_label_infos = null;
    }
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

    // Register callback for hotkey activation
    hotkey.setCallback(onHotkeyActivated);

    std.debug.print("Listening for Cmd+Shift+Space (Ctrl+C to exit)...\n", .{});

    hotkey.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    defer hotkey.deinit();

    hotkey.run();
}
