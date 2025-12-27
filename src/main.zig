const std = @import("std");
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");

/// Called when the hotkey (Cmd+Shift+Space) is activated
fn onHotkeyActivated() void {
    std.debug.print("\n=== ZigNav Activated ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const system = accessibility.UIElement.systemWide();
    defer system.deinit();

    const focused_app = system.getFocusedApplication() catch |err| {
        std.debug.print("Could not get focused app: {} (run from standalone terminal)\n", .{err});
        return;
    };
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

    // Count children (UI elements)
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
