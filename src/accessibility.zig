const std = @import("std");

pub const c = @cImport({
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
    pub const menuBar: [*:0]const u8 = "AXMenuBar";
    pub const extrasMenuBar: [*:0]const u8 = "AXExtrasMenuBar";
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
    pub const menuBar: [*:0]const u8 = "AXMenuBar";
    pub const menuBarItem: [*:0]const u8 = "AXMenuBarItem";
    pub const menu: [*:0]const u8 = "AXMenu";
    pub const menuItem: [*:0]const u8 = "AXMenuItem";
    pub const group: [*:0]const u8 = "AXGroup";
    pub const scrollArea: [*:0]const u8 = "AXScrollArea";
    pub const table: [*:0]const u8 = "AXTable";
    pub const list: [*:0]const u8 = "AXList";
    pub const row: [*:0]const u8 = "AXRow";
    pub const cell: [*:0]const u8 = "AXCell";
    pub const image: [*:0]const u8 = "AXImage";
    pub const toolbar: [*:0]const u8 = "AXToolbar";
    pub const tabGroup: [*:0]const u8 = "AXTabGroup";
    pub const dockItem: [*:0]const u8 = "AXDockItem";
};

pub const Action = struct {
    pub const press: [*:0]const u8 = "AXPress";
    pub const cancel: [*:0]const u8 = "AXCancel";
    pub const showMenu: [*:0]const u8 = "AXShowMenu";
};

pub const Subrole = struct {
    pub const menuItem: [*:0]const u8 = "AXMenuItemMarkChar";
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

    /// Retain the element (increase reference count) and return a new UIElement
    pub fn retain(self: UIElement) UIElement {
        if (self.ref != null) {
            _ = c.CFRetain(@ptrCast(self.ref));
        }
        return .{ .ref = self.ref };
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

    /// Get the menu bar of an application
    pub fn getMenuBar(self: UIElement) AccessibilityError!UIElement {
        const value = try self.copyAttributeValue(Attribute.menuBar);
        return UIElement{ .ref = @ptrCast(@alignCast(value)) };
    }

    /// Get the extras menu bar (system tray area) of an application
    pub fn getExtrasMenuBar(self: UIElement) AccessibilityError!UIElement {
        const value = try self.copyAttributeValue(Attribute.extrasMenuBar);
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

    /// Check if an action can be performed on this element
    pub fn canPerformAction(self: UIElement, action: [*:0]const u8) bool {
        // Get the list of available actions
        var actions: c.CFArrayRef = null;
        const err = c.AXUIElementCopyActionNames(self.ref, &actions);
        if (err != c.kAXErrorSuccess or actions == null) return false;
        defer c.CFRelease(@ptrCast(actions));

        // Create CFString for the action we're looking for
        const action_str = cfstr(action);
        defer if (action_str != null) c.CFRelease(@ptrCast(action_str));
        if (action_str == null) return false;

        // Check if the action is in the list
        const count = c.CFArrayGetCount(actions);
        var i: c.CFIndex = 0;
        while (i < count) : (i += 1) {
            const item = c.CFArrayGetValueAtIndex(actions, i);
            if (c.CFEqual(item, @ptrCast(action_str)) != 0) {
                return true;
            }
        }
        return false;
    }

    /// Set an attribute value on the element
    pub fn setAttributeValue(self: UIElement, attribute: [*:0]const u8, value: c.CFTypeRef) AccessibilityError!void {
        const attr_str = cfstr(attribute);
        defer if (attr_str != null) c.CFRelease(@ptrCast(attr_str));

        const err = c.AXUIElementSetAttributeValue(self.ref, attr_str, value);
        try axErrorToZig(err);
    }

    /// Enable manual accessibility for Electron apps
    /// This forces Electron to populate its accessibility tree with DOM elements
    pub fn enableManualAccessibility(self: UIElement) void {
        const attr = cfstr("AXManualAccessibility");
        defer if (attr != null) c.CFRelease(@ptrCast(attr));

        // Set to true - errors are ignored as native apps don't support this attribute
        _ = c.AXUIElementSetAttributeValue(self.ref, attr, @ptrCast(c.kCFBooleanTrue));
    }

    /// Check if this menu item has a submenu (has AXMenu child)
    pub fn hasSubmenu(self: UIElement, allocator: std.mem.Allocator) bool {
        const children = self.getChildren(allocator) catch return false;
        defer UIElement.freeElements(allocator, children);

        for (children) |child| {
            if (child.hasRole(Role.menu)) {
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Clickable Element Collection
// ============================================================================

/// Roles that are considered clickable/interactive
const CLICKABLE_ROLES = [_][*:0]const u8{
    // Native macOS roles
    Role.button,
    Role.link,
    Role.checkBox,
    Role.radioButton,
    Role.popUpButton,
    Role.menuButton,
    Role.textField,
    Role.cell,
    Role.row,
    "AXMenuItem",
    "AXMenuBarItem",
    "AXTab",
    "AXDisclosureTriangle",
    "AXIncrementor",
    "AXSlider",
    "AXComboBox",
    "AXColorWell",
    "AXSegmentedControl",
    // Web/Electron specific roles (inside AXWebArea)
    "AXImage",
    "AXTextArea",
};

/// A clickable element with its frame
pub const ClickableElement = struct {
    element: UIElement,
    frame: Rect,
};

/// Check if a role string matches any clickable role
fn isClickableRole(role_str: c.CFStringRef) bool {
    if (role_str == null) return false;

    for (CLICKABLE_ROLES) |clickable_role| {
        const cf_role = cfstr(clickable_role);
        defer if (cf_role != null) c.CFRelease(@ptrCast(cf_role));

        if (cf_role != null and c.CFEqual(@ptrCast(role_str), @ptrCast(cf_role)) != 0) {
            return true;
        }
    }
    return false;
}

/// Check if an element supports the AXPress action (more reliable for web elements)
fn supportsPressAction(element: UIElement) bool {
    var actions: c.CFArrayRef = null;
    const err = c.AXUIElementCopyActionNames(element.ref, &actions);
    if (err != c.kAXErrorSuccess or actions == null) return false;
    defer c.CFRelease(@ptrCast(actions));

    const press_action = cfstr(Action.press);
    defer if (press_action != null) c.CFRelease(@ptrCast(press_action));

    const count = c.CFArrayGetCount(actions);
    var i: c.CFIndex = 0;
    while (i < count) : (i += 1) {
        const action = c.CFArrayGetValueAtIndex(actions, i);
        if (c.CFEqual(action, @ptrCast(press_action)) != 0) {
            return true;
        }
    }
    return false;
}

/// Get the main screen bounds
fn getScreenBounds() Rect {
    const display = c.CGMainDisplayID();
    const bounds = c.CGDisplayBounds(display);
    return .{
        .origin = .{ .x = bounds.origin.x, .y = bounds.origin.y },
        .size = .{ .width = bounds.size.width, .height = bounds.size.height },
    };
}

/// Check if an element frame is visible on screen (with some margin for partially visible)
fn isVisibleOnScreen(frame: Rect, screen: Rect) bool {
    // Element must be at least partially within screen bounds
    // Allow some margin for elements that are slightly off-screen
    const margin: f64 = 50;

    const elem_right = frame.origin.x + frame.size.width;
    const elem_bottom = frame.origin.y + frame.size.height;
    const screen_right = screen.origin.x + screen.size.width + margin;
    const screen_bottom = screen.origin.y + screen.size.height + margin;

    // Check if element is within screen bounds (with margin)
    return frame.origin.x < screen_right and
        elem_right > screen.origin.x - margin and
        frame.origin.y < screen_bottom and
        elem_bottom > screen.origin.y - margin;
}

/// Recursively collect clickable elements from the UI tree
pub fn collectClickableElements(
    root: UIElement,
    allocator: std.mem.Allocator,
    max_depth: usize,
) ![]ClickableElement {
    var elements = std.ArrayListUnmanaged(ClickableElement){};
    errdefer {
        for (elements.items) |elem| {
            elem.element.deinit();
        }
        elements.deinit(allocator);
    }

    const screen_bounds = getScreenBounds();
    try collectClickableElementsRecursive(root, allocator, &elements, 0, max_depth, screen_bounds);

    // Deduplicate elements that are at the same position (nested clickables)
    var deduped = std.ArrayListUnmanaged(ClickableElement){};
    errdefer {
        for (deduped.items) |elem| {
            elem.element.deinit();
        }
        deduped.deinit(allocator);
    }

    for (elements.items) |elem| {
        var dominated = false;
        // Check if another element at same position exists with better size
        for (deduped.items) |existing| {
            if (framesOverlap(elem.frame, existing.frame)) {
                dominated = true;
                break;
            }
        }
        if (!dominated) {
            try deduped.append(allocator, elem);
        } else {
            // Release the duplicate element
            elem.element.deinit();
        }
    }

    elements.deinit(allocator);
    return deduped.toOwnedSlice(allocator);
}

/// Check if two frames significantly overlap (likely same element)
fn framesOverlap(a: Rect, b: Rect) bool {
    const tolerance: f64 = 10; // pixels
    return @abs(a.origin.x - b.origin.x) < tolerance and
        @abs(a.origin.y - b.origin.y) < tolerance and
        @abs(a.size.width - b.size.width) < tolerance and
        @abs(a.size.height - b.size.height) < tolerance;
}

fn collectClickableElementsRecursive(
    element: UIElement,
    allocator: std.mem.Allocator,
    result: *std.ArrayListUnmanaged(ClickableElement),
    depth: usize,
    max_depth: usize,
    screen_bounds: Rect,
) !void {
    if (depth > max_depth) return;

    // Check if this element is clickable (by role OR by having AXPress action)
    const role = element.getRole() catch null;
    defer if (role != null) c.CFRelease(@ptrCast(role));

    const is_clickable = isClickableRole(role) or supportsPressAction(element);

    if (is_clickable) {
        // Get frame, skip if unavailable or too small
        const frame = element.getFrame() catch null;
        if (frame) |f| {
            // Skip elements that are too small to be useful (< 5x5 pixels)
            // Also skip elements that are not visible on screen
            if (f.size.width >= 5 and f.size.height >= 5 and isVisibleOnScreen(f, screen_bounds)) {
                // Retain the element reference since we're storing it
                if (element.ref != null) {
                    _ = c.CFRetain(@ptrCast(element.ref));
                }
                try result.append(allocator, .{
                    .element = element,
                    .frame = f,
                });
            }
        }
    }

    // Recurse into children
    const children = element.getChildren(allocator) catch return;
    defer UIElement.freeElements(allocator, children);

    for (children) |child| {
        try collectClickableElementsRecursive(child, allocator, result, depth + 1, max_depth, screen_bounds);
    }
}

/// Free collected clickable elements
pub fn freeClickableElements(allocator: std.mem.Allocator, elements: []ClickableElement) void {
    for (elements) |elem| {
        elem.element.deinit();
    }
    allocator.free(elements);
}

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

// ============================================================================
// Menu Bar and Dock Element Collection
// ============================================================================

/// Collect clickable elements from the menu bar and Dock only
/// frontmost_pid: PID of the frontmost application (for menu bar)
/// dock_pid: PID of the Dock application
pub fn collectMenuBarAndDockElements(
    allocator: std.mem.Allocator,
    frontmost_pid: c.pid_t,
    dock_pid: ?c.pid_t,
) ![]ClickableElement {
    var all_elements = std.ArrayListUnmanaged(ClickableElement){};
    errdefer {
        for (all_elements.items) |elem| {
            elem.element.deinit();
        }
        all_elements.deinit(allocator);
    }

    // 1. Collect menu bar items from frontmost application
    {
        const app_element = UIElement.forApplication(frontmost_pid);
        defer app_element.deinit();

        // Try to get the menu bar
        if (app_element.getMenuBar()) |menu_bar| {
            defer menu_bar.deinit();
            std.debug.print("Collecting menu bar items...\n", .{});

            // Get menu bar children (menu bar items like File, Edit, etc.)
            if (menu_bar.getChildren(allocator)) |menu_items| {
                defer UIElement.freeElements(allocator, menu_items);

                for (menu_items) |item| {
                    // Check if the item has a valid frame
                    const frame = item.getFrame() catch continue;

                    // Skip items with zero size or off-screen
                    if (frame.size.width <= 0 or frame.size.height <= 0) continue;
                    if (frame.origin.x < 0 or frame.origin.y < 0) continue;

                    // Check if it has AXPress action
                    if (!item.canPerformAction(Action.press)) continue;

                    // Retain and add to list
                    const retained = item.retain();
                    try all_elements.append(allocator, .{
                        .element = retained,
                        .frame = frame,
                    });
                }
                std.debug.print("  Menu bar: {} items\n", .{all_elements.items.len});
            } else |_| {}
        } else |_| {
            std.debug.print("Could not access menu bar\n", .{});
        }
    }

    // 2. Collect Dock items
    if (dock_pid) |pid| {
        const dock_app = UIElement.forApplication(pid);
        defer dock_app.deinit();

        std.debug.print("Collecting Dock items...\n", .{});
        const dock_start = all_elements.items.len;

        // The Dock's main "list" contains the dock items
        // We need to traverse the Dock's children to find the list
        if (dock_app.getChildren(allocator)) |dock_children| {
            defer UIElement.freeElements(allocator, dock_children);

            for (dock_children) |child| {
                // Recursively collect from dock children (lists contain dock items)
                try collectDockItems(allocator, child, &all_elements);
            }
        } else |_| {}

        std.debug.print("  Dock: {} items\n", .{all_elements.items.len - dock_start});
    }

    std.debug.print("Total menu bar + Dock elements: {}\n", .{all_elements.items.len});
    return all_elements.toOwnedSlice(allocator);
}

/// Recursively collect dock items from a Dock UI element
fn collectDockItems(
    allocator: std.mem.Allocator,
    element: UIElement,
    elements: *std.ArrayListUnmanaged(ClickableElement),
) !void {
    // Check if this element is clickable
    const frame = element.getFrame() catch return;

    // Skip elements with zero size
    if (frame.size.width <= 0 or frame.size.height <= 0) return;

    // Check if it's a pressable element
    if (element.canPerformAction(Action.press)) {
        const retained = element.retain();
        try elements.append(allocator, .{
            .element = retained,
            .frame = frame,
        });
        return; // Don't recurse into clickable items
    }

    // Recurse into children
    const children = element.getChildren(allocator) catch return;
    defer UIElement.freeElements(allocator, children);

    for (children) |child| {
        try collectDockItems(allocator, child, elements);
    }
}

// ============================================================================
// Visible Menu Item Collection (for cascading menu navigation)
// ============================================================================

/// Collect visible menu items from the frontmost application
/// This is used after a menu bar item has been pressed to find the dropdown menu items
pub fn collectVisibleMenuItems(
    allocator: std.mem.Allocator,
    frontmost_pid: c.pid_t,
) ![]ClickableElement {
    var menu_items = std.ArrayListUnmanaged(ClickableElement){};
    errdefer {
        for (menu_items.items) |elem| {
            elem.element.deinit();
        }
        menu_items.deinit(allocator);
    }

    const app_element = UIElement.forApplication(frontmost_pid);
    defer app_element.deinit();

    // Get the menu bar and look for open menus
    if (app_element.getMenuBar()) |menu_bar| {
        defer menu_bar.deinit();

        // Get menu bar children (menu bar items)
        if (menu_bar.getChildren(allocator)) |menu_bar_items| {
            defer UIElement.freeElements(allocator, menu_bar_items);

            // Each menu bar item may have an AXMenu child when opened
            for (menu_bar_items) |menu_bar_item| {
                try collectMenuItemsFromElement(allocator, menu_bar_item, &menu_items);
            }
        } else |_| {}
    } else |_| {}

    std.debug.print("Found {} visible menu items\n", .{menu_items.items.len});
    return menu_items.toOwnedSlice(allocator);
}

/// Recursively collect menu items from an element (looking for AXMenu and AXMenuItem)
fn collectMenuItemsFromElement(
    allocator: std.mem.Allocator,
    element: UIElement,
    items: *std.ArrayListUnmanaged(ClickableElement),
) !void {
    // Check if this element is a menu item with valid frame
    if (element.hasRole(Role.menuItem)) {
        const frame = element.getFrame() catch return;

        // Skip items with zero/invalid size
        if (frame.size.width > 0 and frame.size.height > 0) {
            // Check if it has AXPress action (some menu items are just separators)
            if (element.canPerformAction(Action.press)) {
                const retained = element.retain();
                try items.append(allocator, .{
                    .element = retained,
                    .frame = frame,
                });
            }
        }
    }

    // Check if this is a menu (container for menu items)
    const is_menu = element.hasRole(Role.menu);

    // If it's a menu or menu bar item, look for children
    if (is_menu or element.hasRole(Role.menuBarItem)) {
        const children = element.getChildren(allocator) catch return;
        defer UIElement.freeElements(allocator, children);

        for (children) |child| {
            try collectMenuItemsFromElement(allocator, child, items);
        }
    }
}
