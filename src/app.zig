const std = @import("std");
const objc = @import("objc");
const hotkey = @import("hotkey.zig");
const accessibility = @import("accessibility.zig");
const labels = @import("labels.zig");
const overlay = @import("overlay.zig");
const input = @import("input.zig");

// ============================================================================
// Application State Machine
// ============================================================================
// Manages the application lifecycle and state transitions.
// States: Idle -> Scanning -> ShowingLabels -> Executing -> Idle
//
// This centralizes all state management and ensures clean transitions.

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
});

/// Application states
pub const State = enum {
    /// Waiting for hotkey activation
    idle,
    /// Collecting accessibility elements from frontmost app
    scanning,
    /// Overlay visible, accepting keyboard input
    showing_labels,
    /// Executing action on selected element
    executing,
};

/// Application context holding all state
pub const App = struct {
    allocator: std.mem.Allocator,
    state: State,

    // Resources (owned when in showing_labels state)
    clickable_elements: ?[]accessibility.ClickableElement,
    label_generator: ?labels.LabelGenerator,
    label_infos: ?[]overlay.LabelInfo,

    const Self = @This();

    /// Initialize the application
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .state = .idle,
            .clickable_elements = null,
            .label_generator = null,
            .label_infos = null,
        };
    }

    /// Cleanup all resources
    pub fn deinit(self: *Self) void {
        self.cleanupResources();
        overlay.deinit();
        input.deinit();
        hotkey.deinit();
    }

    /// Get current state
    pub fn getState(self: *const Self) State {
        return self.state;
    }

    /// Handle hotkey activation
    pub fn onHotkeyActivated(self: *Self) void {
        switch (self.state) {
            .idle => {
                // Start scanning
                self.transitionTo(.scanning);
                self.scan();
            },
            .showing_labels => {
                // Toggle off - hide overlay
                self.transitionTo(.idle);
            },
            .scanning, .executing => {
                // Ignore hotkey while busy
            },
        }
    }

    /// Handle dismiss request (Escape, or after action)
    pub fn onDismiss(self: *Self) void {
        if (self.state == .showing_labels or self.state == .executing) {
            self.transitionTo(.idle);
        }
    }

    /// Handle action execution complete
    pub fn onActionComplete(self: *Self) void {
        if (self.state == .executing) {
            self.transitionTo(.idle);
        }
    }

    /// Transition to a new state
    fn transitionTo(self: *Self, new_state: State) void {
        const old_state = self.state;

        // Exit actions for old state
        switch (old_state) {
            .showing_labels => {
                overlay.hide();
                input.deinit();
                self.cleanupResources();
            },
            .executing => {
                overlay.hide();
                input.deinit();
                self.cleanupResources();
            },
            else => {},
        }

        self.state = new_state;
        std.debug.print("State: {} -> {}\n", .{ old_state, new_state });

        // Entry actions for new state
        switch (new_state) {
            .idle => {
                // Nothing to do
            },
            .scanning => {
                // Scan happens immediately after transition
            },
            .showing_labels => {
                // Overlay already shown in scan()
            },
            .executing => {
                // Action execution happens in input handler
            },
        }
    }

    /// Scan frontmost app for clickable elements
    fn scan(self: *Self) void {
        std.debug.print("\n=== ZigNav Activated ===\n", .{});

        // Get frontmost app PID
        const pid = getFrontmostAppPid() orelse {
            std.debug.print("Could not get frontmost app PID\n", .{});
            self.transitionTo(.idle);
            return;
        };

        // Create accessibility element for this app
        const focused_app = accessibility.UIElement.forApplication(pid);
        defer focused_app.deinit();

        // Enable manual accessibility for Electron apps
        focused_app.enableManualAccessibility();

        // Get app title for logging
        if (focused_app.getTitle(self.allocator)) |title| {
            defer self.allocator.free(title);
            std.debug.print("App: {s}\n", .{title});
        }

        // Get main window
        const main_window = focused_app.getMainWindow() catch |err| {
            std.debug.print("Could not get main window: {}\n", .{err});
            self.transitionTo(.idle);
            return;
        };
        defer main_window.deinit();

        // Collect clickable elements
        const clickable = accessibility.collectClickableElements(main_window, self.allocator, 50) catch |err| {
            std.debug.print("Could not collect clickable elements: {}\n", .{err});
            self.transitionTo(.idle);
            return;
        };

        if (clickable.len == 0) {
            std.debug.print("No clickable elements found\n", .{});
            accessibility.freeClickableElements(self.allocator, clickable);
            self.transitionTo(.idle);
            return;
        }

        std.debug.print("Found {} clickable elements\n", .{clickable.len});

        // Store clickable elements
        self.clickable_elements = clickable;

        // Generate labels
        std.debug.print("\n--- Element to Label Mapping ---\n", .{});

        self.label_generator = labels.LabelGenerator.init(self.allocator);
        const element_labels = self.label_generator.?.generate(clickable.len) catch {
            std.debug.print("Could not generate labels\n", .{});
            self.cleanupResources();
            self.transitionTo(.idle);
            return;
        };

        // Build LabelInfo array for overlay
        const label_infos = self.allocator.alloc(overlay.LabelInfo, clickable.len) catch {
            std.debug.print("Could not allocate label infos\n", .{});
            self.cleanupResources();
            self.transitionTo(.idle);
            return;
        };

        for (clickable, 0..) |elem, i| {
            label_infos[i] = .{
                .label = element_labels[i],
                .x = elem.frame.origin.x + elem.frame.size.width / 2,
                .bottom_y = elem.frame.origin.y + elem.frame.size.height,
            };

            // Log label -> element mapping
            const title = elem.element.getTitle(self.allocator);
            if (title) |t| {
                defer self.allocator.free(t);
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

        self.label_infos = label_infos;

        // Initialize input handler
        input.init(clickable, element_labels, self.allocator);

        // Show overlay
        overlay.show(label_infos, self.allocator) catch |err| {
            std.debug.print("Could not show overlay: {}\n", .{err});
            self.cleanupResources();
            self.transitionTo(.idle);
            return;
        };

        std.debug.print("Overlay shown with {} labels\n", .{label_infos.len});
        self.state = .showing_labels;
    }

    /// Cleanup owned resources
    fn cleanupResources(self: *Self) void {
        if (self.label_generator) |*gen| {
            gen.deinit();
            self.label_generator = null;
        }

        if (self.label_infos) |infos| {
            self.allocator.free(infos);
            self.label_infos = null;
        }

        if (self.clickable_elements) |elems| {
            accessibility.freeClickableElements(self.allocator, elems);
            self.clickable_elements = null;
        }
    }
};

/// Get frontmost application PID using NSWorkspace
fn getFrontmostAppPid() ?c.pid_t {
    const NSWorkspace = objc.getClass("NSWorkspace") orelse return null;
    const workspace = NSWorkspace.msgSend(objc.Object, "sharedWorkspace", .{});

    const frontAppPtr = workspace.msgSend(?*anyopaque, "frontmostApplication", .{});
    if (frontAppPtr == null) return null;

    const frontApp = objc.Object{ .value = @ptrCast(@alignCast(frontAppPtr.?)) };
    const pid = frontApp.msgSend(c_int, "processIdentifier", .{});
    return @intCast(pid);
}

// Global app instance (needed for callbacks)
var global_app: ?*App = null;

/// Set the global app instance for callbacks
pub fn setGlobalApp(app: *App) void {
    global_app = app;
}

/// Callback for hotkey activation
pub fn hotkeyCallback() void {
    if (global_app) |app| {
        app.onHotkeyActivated();
    }
}

/// Callback for dismiss
pub fn dismissCallback() void {
    if (global_app) |app| {
        app.onDismiss();
    }
}
