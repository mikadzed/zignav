const std = @import("std");
const objc = @import("objc");
const accessibility = @import("accessibility.zig");

// ============================================================================
// Overlay Window
// ============================================================================
// Creates a transparent fullscreen overlay window to display labels
// at clickable element positions using NSTextField subviews.

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
});

/// Label with its position for rendering
pub const LabelInfo = struct {
    label: []const u8,
    center: accessibility.Position,
};

/// The overlay window and content view
var overlay_window: ?objc.Object = null;
var content_view: ?objc.Object = null;
var label_fields: std.ArrayListUnmanaged(objc.Object) = .{};
var label_allocator: ?std.mem.Allocator = null;

/// Check if overlay is currently visible
pub fn isVisible() bool {
    if (overlay_window) |window| {
        return window.msgSend(c_int, "isVisible", .{}) != 0;
    }
    return false;
}

/// Show the overlay with labels at specified positions
pub fn show(labels: []const LabelInfo, allocator: std.mem.Allocator) !void {
    label_allocator = allocator;

    // Create window if needed
    if (overlay_window == null) {
        try createOverlayWindow();
    }

    // Clear existing label fields
    clearLabelFields();

    // Create NSTextField for each label
    for (labels) |info| {
        try createLabelField(info);
    }

    // Show window
    if (overlay_window) |window| {
        window.msgSend(void, "orderFrontRegardless", .{});
    }
}

/// Hide the overlay
pub fn hide() void {
    if (overlay_window) |window| {
        window.msgSend(void, "orderOut:", .{@as(?*anyopaque, null)});
    }
    clearLabelFields();
}

/// Clear all label text fields
fn clearLabelFields() void {
    if (content_view) |view| {
        // Remove all subviews
        const subviews = view.msgSend(objc.Object, "subviews", .{});
        const count = subviews.msgSend(c_long, "count", .{});
        if (count > 0) {
            // Make a copy since we're modifying while iterating
            const copy = subviews.msgSend(objc.Object, "copy", .{});
            defer copy.msgSend(void, "release", .{});

            var i: c_long = 0;
            while (i < count) : (i += 1) {
                const subview = copy.msgSend(objc.Object, "objectAtIndex:", .{@as(c_ulong, @intCast(i))});
                subview.msgSend(void, "removeFromSuperview", .{});
            }
        }
    }
    label_fields.clearRetainingCapacity();
}

/// Create the transparent overlay window
fn createOverlayWindow() !void {
    const NSWindow = objc.getClass("NSWindow") orelse return error.ClassNotFound;
    const NSScreen = objc.getClass("NSScreen") orelse return error.ClassNotFound;
    const NSColor = objc.getClass("NSColor") orelse return error.ClassNotFound;
    const NSView = objc.getClass("NSView") orelse return error.ClassNotFound;

    // Get main screen frame
    const mainScreen = NSScreen.msgSend(objc.Object, "mainScreen", .{});
    const screenFrame = mainScreen.msgSend(c.CGRect, "frame", .{});

    std.debug.print("Creating overlay window: {d:.0}x{d:.0}\n", .{ screenFrame.size.width, screenFrame.size.height });

    // Create window with borderless style (NSWindowStyleMaskBorderless = 0)
    const window = NSWindow.msgSend(objc.Object, "alloc", .{});
    _ = window.msgSend(
        objc.Object,
        "initWithContentRect:styleMask:backing:defer:",
        .{
            screenFrame,
            @as(c_ulong, 0), // Borderless
            @as(c_ulong, 2), // NSBackingStoreBuffered
            @as(c_int, 0), // Don't defer
        },
    );

    // Configure window properties
    const clearColor = NSColor.msgSend(objc.Object, "clearColor", .{});
    window.msgSend(void, "setBackgroundColor:", .{clearColor.value});
    window.msgSend(void, "setOpaque:", .{@as(c_int, 0)});
    window.msgSend(void, "setHasShadow:", .{@as(c_int, 0)});

    // Set window level above everything
    // NSStatusWindowLevel = 25, we use slightly higher
    window.msgSend(void, "setLevel:", .{@as(c_long, 101)});

    // Make it non-activating and ignore mouse events
    window.msgSend(void, "setIgnoresMouseEvents:", .{@as(c_int, 1)});

    // Don't show in Expose/Mission Control
    window.msgSend(void, "setCollectionBehavior:", .{@as(c_ulong, 1 << 4)}); // NSWindowCollectionBehaviorTransient

    // Create content view
    const view = NSView.msgSend(objc.Object, "alloc", .{});
    _ = view.msgSend(objc.Object, "initWithFrame:", .{screenFrame});
    view.msgSend(void, "setWantsLayer:", .{@as(c_int, 1)});

    window.msgSend(void, "setContentView:", .{view.value});

    overlay_window = window;
    content_view = view;

    std.debug.print("Overlay window created successfully\n", .{});
}

/// Create an NSTextField for a label
fn createLabelField(info: LabelInfo) !void {
    const NSTextField = objc.getClass("NSTextField") orelse return error.ClassNotFound;
    const NSColor = objc.getClass("NSColor") orelse return error.ClassNotFound;
    const NSFont = objc.getClass("NSFont") orelse return error.ClassNotFound;
    const NSString = objc.getClass("NSString") orelse return error.ClassNotFound;

    const view = content_view orelse return error.NoContentView;
    const allocator = label_allocator orelse return error.NoContentView;

    // macOS coordinate system has origin at bottom-left, need to flip Y
    const screen_height = getScreenHeight();
    const flipped_y = screen_height - info.center.y;

    // Calculate label dimensions
    const font_size: f64 = 12;
    const padding: f64 = 3;
    const char_width: f64 = 8;
    const width: f64 = @as(f64, @floatFromInt(info.label.len)) * char_width + padding * 2;
    const height: f64 = font_size + padding * 2 + 2;

    // Position centered on element
    const x = info.center.x - width / 2;
    const y = flipped_y - height / 2;

    const frame = c.CGRect{
        .origin = .{ .x = x, .y = y },
        .size = .{ .width = width, .height = height },
    };

    // Create text field
    const field = NSTextField.msgSend(objc.Object, "alloc", .{});
    _ = field.msgSend(objc.Object, "initWithFrame:", .{frame});

    // Create null-terminated copy of label for NSString
    const label_cstr = allocator.allocSentinel(u8, info.label.len, 0) catch return error.ClassNotFound;
    defer allocator.free(label_cstr);
    @memcpy(label_cstr, info.label);

    // Convert label to NSString
    const label_str = NSString.msgSend(
        objc.Object,
        "stringWithUTF8String:",
        .{label_cstr.ptr},
    );

    field.msgSend(void, "setStringValue:", .{label_str.value});

    // Style the field
    field.msgSend(void, "setBezeled:", .{@as(c_int, 0)});
    field.msgSend(void, "setDrawsBackground:", .{@as(c_int, 1)});
    field.msgSend(void, "setEditable:", .{@as(c_int, 0)});
    field.msgSend(void, "setSelectable:", .{@as(c_int, 0)});
    field.msgSend(void, "setAlignment:", .{@as(c_ulong, 1)}); // NSTextAlignmentCenter

    // Yellow background
    const yellow = NSColor.msgSend(
        objc.Object,
        "colorWithRed:green:blue:alpha:",
        .{ @as(f64, 1.0), @as(f64, 0.9), @as(f64, 0.0), @as(f64, 0.95) },
    );
    field.msgSend(void, "setBackgroundColor:", .{yellow.value});

    // Black text
    const black = NSColor.msgSend(objc.Object, "blackColor", .{});
    field.msgSend(void, "setTextColor:", .{black.value});

    // Bold font
    const font = NSFont.msgSend(
        objc.Object,
        "boldSystemFontOfSize:",
        .{@as(f64, font_size)},
    );
    field.msgSend(void, "setFont:", .{font.value});

    // Add border via layer
    field.msgSend(void, "setWantsLayer:", .{@as(c_int, 1)});
    const layer = field.msgSend(objc.Object, "layer", .{});
    layer.msgSend(void, "setBorderWidth:", .{@as(f64, 1.0)});

    // Border color (black via CGColor)
    const blackCG = c.CGColorCreateGenericRGB(0, 0, 0, 1);
    defer c.CGColorRelease(blackCG);
    layer.msgSend(void, "setBorderColor:", .{blackCG});

    layer.msgSend(void, "setCornerRadius:", .{@as(f64, 3.0)});

    // Add to content view
    view.msgSend(void, "addSubview:", .{field.value});

    std.debug.print("  Label '{s}' at ({d:.0}, {d:.0})\n", .{ info.label, x, y });

    // Track the field
    if (label_allocator) |alloc| {
        label_fields.append(alloc, field) catch {};
    }
}

fn getScreenHeight() f64 {
    const NSScreen = objc.getClass("NSScreen").?;
    const mainScreen = NSScreen.msgSend(objc.Object, "mainScreen", .{});
    const frame = mainScreen.msgSend(c.CGRect, "frame", .{});
    return frame.size.height;
}

/// Cleanup
pub fn deinit() void {
    hide();
    if (overlay_window) |window| {
        window.msgSend(void, "close", .{});
        overlay_window = null;
    }
    content_view = null;
    if (label_allocator) |alloc| {
        label_fields.deinit(alloc);
    }
}

// Error types
const OverlayError = error{
    ClassNotFound,
    NoContentView,
};
