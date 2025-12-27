const std = @import("std");

// ============================================================================
// Label Generator
// ============================================================================
// Generates keyboard labels for UI elements in order of typing efficiency.
// Home row keys (ASDF...) are prioritized for faster access.

/// Priority order for label characters (home row first, then top row, then bottom)
const LABEL_CHARS = "asdfjklgheiwoqpruvncmxztyb";

/// Label generator that produces efficient keyboard labels
pub const LabelGenerator = struct {
    allocator: std.mem.Allocator,
    labels: std.ArrayListUnmanaged([]u8),

    pub fn init(allocator: std.mem.Allocator) LabelGenerator {
        return .{
            .allocator = allocator,
            .labels = .{},
        };
    }

    pub fn deinit(self: *LabelGenerator) void {
        for (self.labels.items) |label| {
            self.allocator.free(label);
        }
        self.labels.deinit(self.allocator);
    }

    /// Generate labels for N elements
    /// Returns slice of label strings (caller should not free individual labels)
    /// Uses single letters first (a, s, d...), then double letters (aa, as, ad...)
    /// Each label is guaranteed unique
    pub fn generate(self: *LabelGenerator, count: usize) ![]const []const u8 {
        // Clear any existing labels
        for (self.labels.items) |label| {
            self.allocator.free(label);
        }
        self.labels.clearRetainingCapacity();

        if (count == 0) return &[_][]const u8{};

        var generated: usize = 0;

        // Phase 1: Single character labels (a, s, d, f, j, k, l, g, h, e, i, w, o, q, p, r, u, v, n, c, m, x, z, t, y, b)
        for (LABEL_CHARS) |char| {
            if (generated >= count) break;

            const label = try self.allocator.alloc(u8, 1);
            label[0] = char;
            try self.labels.append(self.allocator, label);
            generated += 1;
        }

        // Phase 2: Double character labels (aa, as, ad, ...)
        if (generated < count) {
            outer: for (LABEL_CHARS) |first| {
                for (LABEL_CHARS) |second| {
                    if (generated >= count) break :outer;

                    const label = try self.allocator.alloc(u8, 2);
                    label[0] = first;
                    label[1] = second;
                    try self.labels.append(self.allocator, label);
                    generated += 1;
                }
            }
        }

        // Return as const slice
        const result: []const []const u8 = @ptrCast(self.labels.items);
        return result;
    }

    /// Get label at index
    pub fn getLabel(self: *const LabelGenerator, index: usize) ?[]const u8 {
        if (index >= self.labels.items.len) return null;
        return self.labels.items[index];
    }
};

/// Count elements matching a partial label prefix
pub fn countMatchingLabels(labels: []const []const u8, prefix: []const u8) usize {
    if (prefix.len == 0) return labels.len;

    var count: usize = 0;
    for (labels) |label| {
        if (std.mem.startsWith(u8, label, prefix)) {
            count += 1;
        }
    }
    return count;
}

/// Check if a label exactly matches the input
pub fn isExactMatch(label: []const u8, input: []const u8) bool {
    return std.mem.eql(u8, label, input);
}

/// Check if label starts with prefix
pub fn startsWithPrefix(label: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, label, prefix);
}

// ============================================================================
// Tests
// ============================================================================

test "generate single char labels" {
    var gen = LabelGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const labels = try gen.generate(5);
    try std.testing.expectEqual(@as(usize, 5), labels.len);
    try std.testing.expectEqualStrings("a", labels[0]);
    try std.testing.expectEqualStrings("s", labels[1]);
    try std.testing.expectEqualStrings("d", labels[2]);
    try std.testing.expectEqualStrings("f", labels[3]);
    try std.testing.expectEqualStrings("j", labels[4]);
}

test "generate double char labels for many elements" {
    var gen = LabelGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const labels = try gen.generate(30);
    try std.testing.expectEqual(@as(usize, 30), labels.len);

    // First 26 are single chars
    try std.testing.expectEqual(@as(usize, 1), labels[0].len);
    try std.testing.expectEqualStrings("a", labels[0]);
    try std.testing.expectEqual(@as(usize, 1), labels[25].len);
    try std.testing.expectEqualStrings("b", labels[25]);

    // After 26, double chars start
    try std.testing.expectEqual(@as(usize, 2), labels[26].len);
    try std.testing.expectEqualStrings("aa", labels[26]);
    try std.testing.expectEqualStrings("as", labels[27]);
    try std.testing.expectEqualStrings("ad", labels[28]);
    try std.testing.expectEqualStrings("af", labels[29]);
}

test "home row keys come first" {
    var gen = LabelGenerator.init(std.testing.allocator);
    defer gen.deinit();

    const labels = try gen.generate(8);

    // Home row: a, s, d, f, j, k, l, g (on QWERTY)
    try std.testing.expectEqualStrings("a", labels[0]);
    try std.testing.expectEqualStrings("s", labels[1]);
    try std.testing.expectEqualStrings("d", labels[2]);
    try std.testing.expectEqualStrings("f", labels[3]);
    try std.testing.expectEqualStrings("j", labels[4]);
    try std.testing.expectEqualStrings("k", labels[5]);
    try std.testing.expectEqualStrings("l", labels[6]);
    try std.testing.expectEqualStrings("g", labels[7]);
}

test "exact match" {
    try std.testing.expect(isExactMatch("ab", "ab"));
    try std.testing.expect(!isExactMatch("ab", "a"));
    try std.testing.expect(!isExactMatch("a", "ab"));
}

test "prefix match" {
    try std.testing.expect(startsWithPrefix("ab", "a"));
    try std.testing.expect(startsWithPrefix("ab", "ab"));
    try std.testing.expect(!startsWithPrefix("ab", "b"));
    try std.testing.expect(!startsWithPrefix("a", "ab"));
}
