const std = @import("std");
const objc = @import("objc");

pub fn main() !void {
    _ = objc.Class;
    std.debug.print("Hello from ZigNav\n", .{});
}
