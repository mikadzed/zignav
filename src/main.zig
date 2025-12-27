const std = @import("std");
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");

/// Recursively count all UI elements in the tree
fn countElements(element: accessibility.UIElement, allocator: std.mem.Allocator, depth: usize) usize {
    if (depth > 20) return 1; // Prevent infinite recursion

    const children = element.getChildren(allocator) catch return 1;
    defer accessibility.UIElement.freeElements(allocator, children);

    var count: usize = 1;
    for (children) |child| {
        count += countElements(child, allocator, depth + 1);
    }
    return count;
}

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

/// Called when the hotkey (Cmd+Shift+Space) is activated
fn onHotkeyActivated() void {
    std.debug.print("\n=== ZigNav Activated ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get frontmost app PID via NSWorkspace (more reliable than AXFocusedApplication)
    const pid = getFrontmostAppPid() orelse {
        std.debug.print("Could not get frontmost app PID\n", .{});
        return;
    };
    std.debug.print("Frontmost app PID: {}\n", .{pid});

    // Create accessibility element for this app
    const focused_app = accessibility.UIElement.forApplication(pid);
    defer focused_app.deinit();

    // Get app title
    if (focused_app.getTitle(allocator)) |title| {
        defer allocator.free(title);
        std.debug.print("Focused app: {s}\n", .{title});
    } else {
        std.debug.print("Focused app: (unknown)\n", .{});
    }

    // Get main window
    const main_window = focused_app.getMainWindow() catch |err| {
        std.debug.print("Could not get main window: {}\n", .{err});

        // Try getting all windows instead
        std.debug.print("Trying to list all windows...\n", .{});
        const windows = focused_app.getWindows(allocator) catch |werr| {
            std.debug.print("Could not get windows list: {}\n", .{werr});
            return;
        };
        defer accessibility.UIElement.freeElements(allocator, windows);

        std.debug.print("App has {} windows\n", .{windows.len});
        for (windows, 0..) |win, i| {
            if (win.getTitle(allocator)) |title| {
                defer allocator.free(title);
                std.debug.print("  Window {}: {s}\n", .{ i, title });
            } else {
                std.debug.print("  Window {}: (no title)\n", .{i});
            }
        }
        return;
    };
    defer main_window.deinit();

    // Get window title
    if (main_window.getTitle(allocator)) |title| {
        defer allocator.free(title);
        std.debug.print("Main window: {s}\n", .{title});
    }

    // Get window frame
    const frame = main_window.getFrame() catch |err| {
        std.debug.print("Could not get window frame: {}\n", .{err});
        return;
    };
    std.debug.print("Window at ({d:.0}, {d:.0}) size {d:.0}x{d:.0}\n", .{
        frame.origin.x,
        frame.origin.y,
        frame.size.width,
        frame.size.height,
    });

    // Count all UI elements recursively
    const total_elements = countElements(main_window, allocator, 0);
    std.debug.print("Total UI elements in tree: {}\n", .{total_elements});

    // Get direct children
    const children = main_window.getChildren(allocator) catch {
        std.debug.print("Could not get children\n", .{});
        return;
    };
    defer accessibility.UIElement.freeElements(allocator, children);

    std.debug.print("Window has {} direct children\n", .{children.len});

    std.debug.print("========================\n\n", .{});
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
