const std = @import("std");
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const bias_constants = @import("bias_constants.zig");
const xxhash = @import("xxhash.zig");

pub const SetIterator = struct {
    const Self = @This();
    set: *const Set,
    iterator: AutoHashMap(u64, void).Iterator,

    pub fn next(self: *Self) ?u64 {
        if (self.iterator.next()) |entry| {
            return entry.key_ptr.*;
        }
        return null;
    }
};

pub const Set = struct {
    const Self = @This();

    set: AutoHashMap(u64, void),

    pub fn init(allocator: Allocator) Self {
        return Self{ .set = AutoHashMap(u64, void).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.set.deinit();
    }

    pub fn add(self: *Self, value: u64) !void {
        try self.set.put(value, {});
    }

    pub fn len(self: *const Self) usize {
        return self.set.count();
    }

    pub fn clear(self: *Self) void {
        self.set.clearAndFree();
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.set.clearRetainingCapacity();
    }

    pub fn iterator(self: *const Self) SetIterator {
        return SetIterator{
            .set = self,
            .iterator = self.set.iterator(),
        };
    }

    pub fn contains(self: *const Self, value: u64) bool {
        return self.set.contains(value);
    }

    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        var new_set = Self.init(allocator);
        try new_set.set.ensureTotalCapacity(@intCast(self.set.count()));

        var iter = self.iterator();
        while (iter.next()) |value| {
            try new_set.add(value);
        }

        return new_set;
    }

    pub fn serialize(self: *const Self, writer: anytype) !void {
        try writer.writeInt(u32, @intCast(self.len()), .big);

        var iter = self.iterator();
        while (iter.next()) |value| {
            try writer.writeInt(u64, value, .big);
        }
    }

    pub fn deserialize(self: *Self, reader: anytype) !void {
        const count = try reader.readInt(u32, .big);
        try self.set.ensureTotalCapacity(count);

        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const value = try reader.readInt(u64, .big);
            try self.add(value);
        }
    }
};

pub const HyperLogLogError = error{
    InvalidPrecision,
    SerializationError,
    DeserializationError,
    IncompatiblePrecision,
    OutOfMemory,
};

pub const Config = struct {
    precision: u5 = 14,
    thread_safe: bool = false,
};

/// HyperLogLog algorithm with sparse/dense hybrid mode
pub fn HyperLogLog(comptime config: Config) type {
    if (config.precision < 4 or config.precision > 18) {
        @compileError("Precision must be between 4 and 18");
    }

    const m = @as(u32, 1) << config.precision;
    const alpha_m = switch (m) {
        16 => 0.673,
        32 => 0.697,
        64 => 0.709,
        else => 0.7213 / (1.0 + 1.079 / @as(f64, @floatFromInt(m))),
    };
    const sparse_threshold = m * 3 / 4;

    return struct {
        const Self = @This();

        allocator: Allocator,
        sparse_set: Set,
        dense_buckets: []u6,
        is_sparse: bool,
        mutex: if (config.thread_safe) std.Thread.Mutex else void,

        /// Initialize a new HyperLogLog instance
        pub fn init(allocator: Allocator) !Self {
            return Self{
                .allocator = allocator,
                .sparse_set = Set.init(allocator),
                .dense_buckets = try allocator.alloc(u6, 0),
                .is_sparse = true,
                .mutex = if (config.thread_safe) std.Thread.Mutex{} else {},
            };
        }

        /// Clean up allocated memory
        pub fn deinit(self: *Self) void {
            self.sparse_set.deinit();
            self.allocator.free(self.dense_buckets);
        }

        /// Add an element using its hash value directly
        pub fn addHash(self: *Self, hash: u64) !void {
            if (config.thread_safe) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            if (self.is_sparse) {
                if (self.sparse_set.len() < sparse_threshold) {
                    try self.addToSparse(hash);
                } else {
                    try self.convertToDense();
                    self.addToDense(hash);
                }
            } else {
                self.addToDense(hash);
            }
        }

        /// Add an element by hashing the data with xxHash64
        pub fn add(self: *Self, data: []const u8) !void {
            const hash = xxhash.xxhash64(data);
            try self.addHash(hash);
        }

        /// Add multiple elements at once for better performance
        pub fn addBatch(self: *Self, items: []const []const u8) !void {
            if (config.thread_safe) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            for (items) |item| {
                const hash = xxhash.xxhash64(item);

                if (self.is_sparse) {
                    if (self.sparse_set.len() < sparse_threshold) {
                        try self.addToSparse(hash);
                    } else {
                        try self.convertToDense();
                        self.addToDense(hash);
                    }
                } else {
                    self.addToDense(hash);
                }
            }
        }

        /// Get the estimated cardinality
        pub fn count(self: *const Self) u64 {
            return self.cardinality();
        }

        /// Get the estimated cardinality with proper algorithm
        pub fn cardinality(self: *const Self) u64 {
            if (config.thread_safe) {
                @constCast(&self.mutex).lock();
                defer @constCast(&self.mutex).unlock();
            }

            if (self.is_sparse) {
                return self.cardinalitySparse();
            } else {
                return self.cardinalityDense();
            }
        }

        /// Merge another HyperLogLog into this one
        pub fn merge(self: *Self, other: *const Self) !void {
            if (config.thread_safe) {
                self.mutex.lock();
                defer self.mutex.unlock();
                @constCast(&other.mutex).lock();
                defer @constCast(&other.mutex).unlock();
            }

            if (other.is_sparse) {
                var iter = other.sparse_set.iterator();
                while (iter.next()) |hash| {
                    try self.addHash(hash);
                }
                return;
            }

            if (self.is_sparse and !other.is_sparse) {
                try self.convertToDense();
            }

            if (!self.is_sparse and !other.is_sparse) {
                for (self.dense_buckets, other.dense_buckets) |*self_bucket, other_bucket| {
                    self_bucket.* = @max(self_bucket.*, other_bucket);
                }
            }
        }

        /// Clear all data and reinitialize to sparse mode
        pub fn clear(self: *Self) void {
            if (config.thread_safe) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            self.sparse_set.clearRetainingCapacity();
            if (!self.is_sparse) {
                self.allocator.free(self.dense_buckets);
                self.dense_buckets = self.allocator.alloc(u6, 0) catch &[_]u6{};
                self.is_sparse = true;
            }
        }

        /// Serialize the HyperLogLog state
        pub fn serialize(self: *const Self, writer: anytype) !void {
            if (config.thread_safe) {
                @constCast(&self.mutex).lock();
                defer @constCast(&self.mutex).unlock();
            }

            try writer.writeInt(u32, 0x484C4C32, .big);
            try writer.writeInt(u8, 1, .big);
            try writer.writeInt(u8, config.precision, .big);
            try writer.writeInt(u8, if (self.is_sparse) 1 else 0, .big);

            if (self.is_sparse) {
                try self.sparse_set.serialize(writer);
            } else {
                for (self.dense_buckets) |bucket| {
                    try writer.writeInt(u8, bucket, .big);
                }
            }
        }

        /// Deserialize a HyperLogLog from a reader
        pub fn deserialize(allocator: Allocator, reader: anytype) !Self {
            const magic = try reader.readInt(u32, .big);
            if (magic != 0x484C4C32) {
                return HyperLogLogError.DeserializationError;
            }

            const version = try reader.readInt(u8, .big);
            if (version != 1) {
                return HyperLogLogError.DeserializationError;
            }

            const precision = try reader.readInt(u8, .big);
            if (precision != config.precision) {
                return HyperLogLogError.IncompatiblePrecision;
            }

            const is_sparse = (try reader.readInt(u8, .big)) != 0;

            var result = try Self.init(allocator);
            errdefer result.deinit();

            if (is_sparse) {
                try result.sparse_set.deserialize(reader);
                result.is_sparse = true;
            } else {
                result.dense_buckets = try allocator.alloc(u6, m);
                for (result.dense_buckets) |*bucket| {
                    bucket.* = @intCast(try reader.readInt(u8, .big));
                }
                result.is_sparse = false;
            }

            return result;
        }

        fn addToSparse(self: *Self, hash: u64) !void {
            try self.sparse_set.add(hash);
        }

        fn addToDense(self: *Self, hash: u64) void {
            const bucket_idx = @as(u32, @truncate(hash >> @as(u6, @intCast(64 - @as(u32, config.precision)))));
            const w = hash << @as(u6, @intCast(config.precision));
            const leading_zeros = if (w == 0)
                @as(u6, @intCast(64 - @as(u32, config.precision) + 1))
            else
                @as(u6, @intCast(@clz(w) + 1));

            if (leading_zeros > self.dense_buckets[bucket_idx]) {
                self.dense_buckets[bucket_idx] = leading_zeros;
            }
        }

        fn convertToDense(self: *Self) !void {
            self.dense_buckets = try self.allocator.alloc(u6, m);
            @memset(self.dense_buckets, 0);

            var iter = self.sparse_set.iterator();
            while (iter.next()) |hash| {
                self.addToDense(hash);
            }

            self.is_sparse = false;
            self.sparse_set.clearRetainingCapacity();
        }

        fn cardinalitySparse(self: *const Self) u64 {
            const set_size = self.sparse_set.len();
            if (set_size == 0) return 0;

            const m_float = @as(f64, @floatFromInt(m));

            // Build temporary dense representation
            var temp_buckets = self.allocator.alloc(u6, m) catch {
                // Simple linear counting fallback
                const n = @as(f64, @floatFromInt(set_size));
                const estimate = -m_float * @log(1.0 - n / m_float);
                return @as(u64, @intFromFloat(estimate + 0.5));
            };
            defer self.allocator.free(temp_buckets);
            @memset(temp_buckets, 0);

            // Process all hashes in sparse set
            var iter = self.sparse_set.iterator();
            while (iter.next()) |hash| {
                const bucket_idx = @as(u32, @truncate(hash >> @as(u6, @intCast(64 - @as(u32, config.precision)))));
                const w = hash << @as(u6, @intCast(config.precision));
                const leading_zeros = if (w == 0)
                    @as(u6, @intCast(64 - @as(u32, config.precision) + 1))
                else
                    @as(u6, @intCast(@clz(w) + 1));

                if (leading_zeros > temp_buckets[bucket_idx]) {
                    temp_buckets[bucket_idx] = leading_zeros;
                }
            }

            var zero_buckets: u32 = 0;
            for (temp_buckets) |bucket| {
                if (bucket == 0) {
                    zero_buckets += 1;
                }
            }

            // Threshold-based logic
            if (zero_buckets > 0) {
                // Linear counting estimate
                const H = m_float * @log(m_float / @as(f64, @floatFromInt(zero_buckets)));

                // Use threshold based on precision to decide between linear counting and HLL estimate
                const threshold = bias_constants.getThreshold(config.precision);

                if (H <= threshold) {
                    return @as(u64, @intFromFloat(H + 0.5));
                }
            }

            // HLL estimate with bias correction
            var sum: f64 = 0;
            for (temp_buckets) |bucket| {
                sum += 1.0 / math.pow(f64, 2.0, @as(f64, @floatFromInt(bucket)));
            }

            var est = alpha_m * m_float * m_float / sum;

            // Apply only when E <= 5 * m
            if (est <= 5.0 * m_float) {
                est = bias_constants.applyBiasCorrection(config.precision, est);
            }

            return @as(u64, @intFromFloat(est + 0.5));
        }

        fn cardinalityDense(self: *const Self) u64 {
            var sum: f64 = 0;
            var zero_buckets: u32 = 0;

            for (self.dense_buckets) |bucket| {
                if (bucket == 0) {
                    zero_buckets += 1;
                }
                sum += 1.0 / math.pow(f64, 2.0, @as(f64, @floatFromInt(bucket)));
            }

            const m_float = @as(f64, @floatFromInt(m));

            // Cardinality calculation
            if (zero_buckets > 0) {
                // Linear counting estimate
                const H = m_float * @log(m_float / @as(f64, @floatFromInt(zero_buckets)));

                // Use threshold based on precision to decide between linear counting and HLL estimate
                const threshold = bias_constants.getThreshold(config.precision);

                if (H <= threshold) {
                    return @as(u64, @intFromFloat(H + 0.5));
                }
            }

            // HLL estimate with bias correction
            var est = alpha_m * m_float * m_float / sum;

            // Apply only when E <= 5 * m
            if (est <= 5.0 * m_float) {
                est = bias_constants.applyBiasCorrection(config.precision, est);
            }

            return @as(u64, @intFromFloat(est + 0.5));
        }
    };
}
