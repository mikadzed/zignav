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
    x: f64, // Center X of element
    top_y: f64, // Top Y of element (for popover positioning)
    bottom_y: f64, // Bottom Y of element (for popunder positioning)
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

    // Appear on all Spaces and don't show in Expose/Mission Control
    // NSWindowCollectionBehaviorCanJoinAllSpaces (1) | NSWindowCollectionBehaviorTransient (16) = 17
    window.msgSend(void, "setCollectionBehavior:", .{@as(c_ulong, 1 | 16)});

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

    // Label dimensions - compact size for better visibility
    const font_size: f64 = 11;
    const padding_v: f64 = 1;
    const width: f64 = 24; // Fixed width for all boxes
    const height: f64 = font_size + padding_v * 2 + 2;

    // Position label horizontally centered
    const x = info.x - width / 2;

    // Determine if element is near bottom of screen (e.g., Dock items)
    // If element's bottom is in the lower 100px of screen, show label above
    const near_bottom = info.bottom_y > (screen_height - 100);

    const y = if (near_bottom) blk: {
        // Popover: label BOTTOM at element TOP
        // In flipped coords: element top_y becomes (screen_height - top_y)
        const flipped_top = screen_height - info.top_y;
        break :blk flipped_top; // Directly adjacent to element
    } else blk: {
        // Popunder: label TOP at element BOTTOM
        const flipped_bottom = screen_height - info.bottom_y;
        break :blk flipped_bottom - height; // Directly adjacent to element
    };

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

    // #fdf4b7 background with slight transparency
    // RGB: 253/255=0.992, 244/255=0.957, 183/255=0.718
    const bg_color = NSColor.msgSend(
        objc.Object,
        "colorWithRed:green:blue:alpha:",
        .{ @as(f64, 0.992), @as(f64, 0.957), @as(f64, 0.718), @as(f64, 0.85) },
    );
    field.msgSend(void, "setBackgroundColor:", .{bg_color.value});

    // Dark gray text for better readability
    const text_color = NSColor.msgSend(
        objc.Object,
        "colorWithRed:green:blue:alpha:",
        .{ @as(f64, 0.2), @as(f64, 0.2), @as(f64, 0.2), @as(f64, 1.0) },
    );
    field.msgSend(void, "setTextColor:", .{text_color.value});

    // Bold font (smaller)
    const font = NSFont.msgSend(
        objc.Object,
        "boldSystemFontOfSize:",
        .{@as(f64, font_size)},
    );
    field.msgSend(void, "setFont:", .{font.value});

    // Add border via layer
    field.msgSend(void, "setWantsLayer:", .{@as(c_int, 1)});
    const layer = field.msgSend(objc.Object, "layer", .{});
    layer.msgSend(void, "setBorderWidth:", .{@as(f64, 0.5)});

    // Subtle border color
    const borderCG = c.CGColorCreateGenericRGB(0.4, 0.4, 0.4, 0.6);
    defer c.CGColorRelease(borderCG);
    layer.msgSend(void, "setBorderColor:", .{borderCG});

    layer.msgSend(void, "setCornerRadius:", .{@as(f64, 2.0)});

    // Add to content view
    view.msgSend(void, "addSubview:", .{field.value});

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
