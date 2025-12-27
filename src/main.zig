const std = @import("std");
const objc = @import("objc");
const hotkey = @import("hotkey.zig");

pub fn main() !void {
    _ = objc.Class;
    std.debug.print("ZigNav starting...\n", .{});

    if (!hotkey.checkPermission()) {
        std.debug.print("Input monitoring permission not granted.\n", .{});
        hotkey.requestPermission();
        std.debug.print("Please grant permission and restart.\n", .{});
        return;
    }

    std.debug.print("Listening for Cmd+Shift+Space (Ctrl+C to exit)...\n", .{});

    hotkey.init() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };

    defer hotkey.deinit();

    hotkey.run();
}
