const std = @import("std");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

// ============================================================================
// Error Types
// ============================================================================

pub const AccessibilityError = error{
    Failure,
    IllegalArgument,
    InvalidUIElement,
    InvalidUIElementObserver,
    CannotComplete,
    AttributeUnsupported,
    ActionUnsupported,
    NotificationUnsupported,
    NotImplemented,
    NotificationAlreadyRegistered,
    NotificationNotRegistered,
    APIDisabled,
    NoValue,
    ParameterizedAttributeUnsupported,
    NotEnoughPrecision,
    UnknownError,
    OutOfMemory,
};

// AXValueType constants (can't use C enum directly)
const kAXValueTypeCGPoint: c.AXValueType = 1;
const kAXValueTypeCGSize: c.AXValueType = 2;

fn axErrorToZig(ax_error: c.AXError) AccessibilityError!void {
    return switch (ax_error) {
        c.kAXErrorSuccess => {},
        c.kAXErrorFailure => error.Failure,
        c.kAXErrorIllegalArgument => error.IllegalArgument,
        c.kAXErrorInvalidUIElement => error.InvalidUIElement,
        c.kAXErrorInvalidUIElementObserver => error.InvalidUIElementObserver,
        c.kAXErrorCannotComplete => error.CannotComplete,
        c.kAXErrorAttributeUnsupported => error.AttributeUnsupported,
        c.kAXErrorActionUnsupported => error.ActionUnsupported,
        c.kAXErrorNotificationUnsupported => error.NotificationUnsupported,
        c.kAXErrorNotImplemented => error.NotImplemented,
        c.kAXErrorNotificationAlreadyRegistered => error.NotificationAlreadyRegistered,
        c.kAXErrorNotificationNotRegistered => error.NotificationNotRegistered,
        c.kAXErrorAPIDisabled => error.APIDisabled,
        c.kAXErrorNoValue => error.NoValue,
        c.kAXErrorParameterizedAttributeUnsupported => error.ParameterizedAttributeUnsupported,
        c.kAXErrorNotEnoughPrecision => error.NotEnoughPrecision,
        else => error.UnknownError,
    };
}

// ============================================================================
// CFString Helper
// ============================================================================

fn cfstr(s: [*:0]const u8) c.CFStringRef {
    return c.CFStringCreateWithCString(c.kCFAllocatorDefault, s, c.kCFStringEncodingUTF8);
}

// ============================================================================
// Attribute Names (as C strings - will be converted to CFString at runtime)
// ============================================================================

pub const Attribute = struct {
    pub const role: [*:0]const u8 = "AXRole";
    pub const subrole: [*:0]const u8 = "AXSubrole";
    pub const title: [*:0]const u8 = "AXTitle";
    pub const description: [*:0]const u8 = "AXDescription";
    pub const value: [*:0]const u8 = "AXValue";
    pub const parent: [*:0]const u8 = "AXParent";
    pub const children: [*:0]const u8 = "AXChildren";
    pub const position: [*:0]const u8 = "AXPosition";
    pub const size: [*:0]const u8 = "AXSize";
    pub const enabled: [*:0]const u8 = "AXEnabled";
    pub const focused: [*:0]const u8 = "AXFocused";
    pub const windows: [*:0]const u8 = "AXWindows";
    pub const focusedApplication: [*:0]const u8 = "AXFocusedApplication";
    pub const focusedWindow: [*:0]const u8 = "AXFocusedWindow";
    pub const mainWindow: [*:0]const u8 = "AXMainWindow";
    pub const frontmost: [*:0]const u8 = "AXFrontmost";
};

pub const Role = struct {
    pub const application: [*:0]const u8 = "AXApplication";
    pub const window: [*:0]const u8 = "AXWindow";
    pub const button: [*:0]const u8 = "AXButton";
    pub const textField: [*:0]const u8 = "AXTextField";
    pub const staticText: [*:0]const u8 = "AXStaticText";
    pub const link: [*:0]const u8 = "AXLink";
    pub const checkBox: [*:0]const u8 = "AXCheckBox";
    pub const radioButton: [*:0]const u8 = "AXRadioButton";
    pub const popUpButton: [*:0]const u8 = "AXPopUpButton";
    pub const menuButton: [*:0]const u8 = "AXMenuButton";
    pub const group: [*:0]const u8 = "AXGroup";
    pub const scrollArea: [*:0]const u8 = "AXScrollArea";
    pub const table: [*:0]const u8 = "AXTable";
    pub const list: [*:0]const u8 = "AXList";
    pub const row: [*:0]const u8 = "AXRow";
    pub const cell: [*:0]const u8 = "AXCell";
    pub const image: [*:0]const u8 = "AXImage";
    pub const toolbar: [*:0]const u8 = "AXToolbar";
    pub const tabGroup: [*:0]const u8 = "AXTabGroup";
};

pub const Action = struct {
    pub const press: [*:0]const u8 = "AXPress";
    pub const cancel: [*:0]const u8 = "AXCancel";
    pub const showMenu: [*:0]const u8 = "AXShowMenu";
};

// ============================================================================
// Geometry Types
// ============================================================================

pub const Position = struct {
    x: f64,
    y: f64,
};

pub const Size = struct {
    width: f64,
    height: f64,
};

pub const Rect = struct {
    origin: Position,
    size: Size,

    pub fn center(self: Rect) Position {
        return .{
            .x = self.origin.x + self.size.width / 2.0,
            .y = self.origin.y + self.size.height / 2.0,
        };
    }
};

// ============================================================================
// UIElement Wrapper
// ============================================================================

pub const UIElement = struct {
    ref: c.AXUIElementRef,

    /// Create system-wide accessibility element
    pub fn systemWide() UIElement {
        return .{ .ref = c.AXUIElementCreateSystemWide() };
    }

    /// Create accessibility element for a specific application by PID
    pub fn forApplication(pid: c.pid_t) UIElement {
        return .{ .ref = c.AXUIElementCreateApplication(pid) };
    }

    /// Release the underlying reference
    pub fn deinit(self: UIElement) void {
        if (self.ref != null) {
            c.CFRelease(@ptrCast(self.ref));
        }
    }

    /// Get raw attribute value (caller must CFRelease)
    pub fn copyAttributeValue(self: UIElement, attribute: [*:0]const u8) AccessibilityError!c.CFTypeRef {
        const attr_str = cfstr(attribute);
        defer if (attr_str != null) c.CFRelease(@ptrCast(attr_str));

        var value: c.CFTypeRef = null;
        const err = c.AXUIElementCopyAttributeValue(self.ref, attr_str, &value);
        try axErrorToZig(err);
        return value;
    }

    /// Get position as Position struct
    pub fn getPosition(self: UIElement) AccessibilityError!Position {
        const value = try self.copyAttributeValue(Attribute.position);
        defer if (value != null) c.CFRelease(value);

        const ax_value: c.AXValueRef = @ptrCast(value);
        var point: c.CGPoint = undefined;

        if (c.AXValueGetValue(ax_value, kAXValueTypeCGPoint, &point) == 0) {
            return error.Failure;
        }

        return Position{ .x = point.x, .y = point.y };
    }

    /// Get size as Size struct
    pub fn getSize(self: UIElement) AccessibilityError!Size {
        const value = try self.copyAttributeValue(Attribute.size);
        defer if (value != null) c.CFRelease(value);

        const ax_value: c.AXValueRef = @ptrCast(value);
        var size: c.CGSize = undefined;

        if (c.AXValueGetValue(ax_value, kAXValueTypeCGSize, &size) == 0) {
            return error.Failure;
        }

        return Size{ .width = size.width, .height = size.height };
    }

    /// Get bounding rectangle
    pub fn getFrame(self: UIElement) AccessibilityError!Rect {
        const pos = try self.getPosition();
        const size = try self.getSize();
        return Rect{ .origin = pos, .size = size };
    }

    /// Get role as CFStringRef (caller must release)
    pub fn getRole(self: UIElement) AccessibilityError!c.CFStringRef {
        const value = try self.copyAttributeValue(Attribute.role);
        return @ptrCast(value);
    }

    /// Check if element has a specific role
    pub fn hasRole(self: UIElement, role: [*:0]const u8) bool {
        const element_role = self.getRole() catch return false;
        defer if (element_role != null) c.CFRelease(@ptrCast(element_role));

        const role_str = cfstr(role);
        defer if (role_str != null) c.CFRelease(@ptrCast(role_str));

        if (element_role == null or role_str == null) return false;
        return c.CFEqual(@ptrCast(element_role), @ptrCast(role_str)) != 0;
    }

    /// Get focused application from system-wide element
    pub fn getFocusedApplication(self: UIElement) AccessibilityError!UIElement {
        const value = try self.copyAttributeValue(Attribute.focusedApplication);
        return UIElement{ .ref = @ptrCast(@alignCast(value)) };
    }

    /// Get the main/focused window of an application
    pub fn getMainWindow(self: UIElement) AccessibilityError!UIElement {
        const value = self.copyAttributeValue(Attribute.mainWindow) catch |err| {
            // Fallback to focusedWindow if mainWindow fails
            if (err == error.AttributeUnsupported or err == error.NoValue) {
                const focused = try self.copyAttributeValue(Attribute.focusedWindow);
                return UIElement{ .ref = @ptrCast(@alignCast(focused)) };
            }
            return err;
        };
        return UIElement{ .ref = @ptrCast(@alignCast(value)) };
    }

    /// Get title as a Zig string (caller owns the memory)
    pub fn getTitle(self: UIElement, allocator: std.mem.Allocator) ?[]u8 {
        const value = self.copyAttributeValue(Attribute.title) catch return null;
        defer if (value != null) c.CFRelease(value);

        const cf_string: c.CFStringRef = @ptrCast(value);
        if (cf_string == null) return null;

        const length = c.CFStringGetLength(cf_string);
        const max_size: usize = @intCast(c.CFStringGetMaximumSizeForEncoding(length, c.kCFStringEncodingUTF8) + 1);

        const buffer = allocator.alloc(u8, max_size) catch return null;

        if (c.CFStringGetCString(cf_string, buffer.ptr, @intCast(max_size), c.kCFStringEncodingUTF8) == 0) {
            allocator.free(buffer);
            return null;
        }

        // Find actual string length
        const actual_len = std.mem.indexOfScalar(u8, buffer, 0) orelse max_size;
        if (actual_len == max_size) {
            return buffer;
        }

        // Try to resize in place - resize returns bool in Zig 0.15
        if (allocator.resize(buffer, actual_len)) {
            return buffer[0..actual_len];
        }

        // If resize failed, copy to new buffer and free original
        const result = allocator.alloc(u8, actual_len) catch {
            allocator.free(buffer);
            return null;
        };
        @memcpy(result, buffer[0..actual_len]);
        allocator.free(buffer);
        return result;
    }

    /// Get children elements
    pub fn getChildren(self: UIElement, allocator: std.mem.Allocator) AccessibilityError![]UIElement {
        const value = try self.copyAttributeValue(Attribute.children);
        defer if (value != null) c.CFRelease(value);

        const array: c.CFArrayRef = @ptrCast(@alignCast(value));
        if (array == null) return &[_]UIElement{};

        const count: usize = @intCast(c.CFArrayGetCount(array));
        if (count == 0) return &[_]UIElement{};

        const children = allocator.alloc(UIElement, count) catch return error.OutOfMemory;
        errdefer allocator.free(children);

        for (0..count) |i| {
            const child_ref = c.CFArrayGetValueAtIndex(array, @intCast(i));
            _ = c.CFRetain(child_ref);
            children[i] = UIElement{ .ref = @ptrCast(@alignCast(child_ref)) };
        }

        return children;
    }

    /// Get windows for an application
    pub fn getWindows(self: UIElement, allocator: std.mem.Allocator) AccessibilityError![]UIElement {
        const value = try self.copyAttributeValue(Attribute.windows);
        defer if (value != null) c.CFRelease(value);

        const array: c.CFArrayRef = @ptrCast(@alignCast(value));
        if (array == null) return &[_]UIElement{};

        const count: usize = @intCast(c.CFArrayGetCount(array));
        if (count == 0) return &[_]UIElement{};

        const windows = allocator.alloc(UIElement, count) catch return error.OutOfMemory;
        errdefer allocator.free(windows);

        for (0..count) |i| {
            const window_ref = c.CFArrayGetValueAtIndex(array, @intCast(i));
            _ = c.CFRetain(window_ref);
            windows[i] = UIElement{ .ref = @ptrCast(@alignCast(window_ref)) };
        }

        return windows;
    }

    /// Free a list of UIElements
    pub fn freeElements(allocator: std.mem.Allocator, elements: []UIElement) void {
        for (elements) |elem| {
            elem.deinit();
        }
        allocator.free(elements);
    }

    /// Perform an action on the element
    pub fn performAction(self: UIElement, action: [*:0]const u8) AccessibilityError!void {
        const action_str = cfstr(action);
        defer if (action_str != null) c.CFRelease(@ptrCast(action_str));

        const err = c.AXUIElementPerformAction(self.ref, action_str);
        try axErrorToZig(err);
    }
};

// ============================================================================
// Permission Helpers
// ============================================================================

/// Check if accessibility API access is granted
pub fn isAccessibilityEnabled() bool {
    return c.AXIsProcessTrusted() != 0;
}

/// Request accessibility permission (shows system dialog)
pub fn requestAccessibilityPermission() void {
    const prompt_key = cfstr("AXTrustedCheckOptionPrompt");
    defer if (prompt_key != null) c.CFRelease(@ptrCast(prompt_key));

    const keys = [_]c.CFStringRef{prompt_key};
    const values = [_]c.CFTypeRef{@ptrCast(c.kCFBooleanTrue)};

    const options = c.CFDictionaryCreate(
        c.kCFAllocatorDefault,
        @ptrCast(@constCast(&keys)),
        @ptrCast(@constCast(&values)),
        1,
        &c.kCFTypeDictionaryKeyCallBacks,
        &c.kCFTypeDictionaryValueCallBacks,
    );
    defer if (options != null) c.CFRelease(@ptrCast(options));

    _ = c.AXIsProcessTrustedWithOptions(options);
}
