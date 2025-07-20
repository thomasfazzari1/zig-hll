const std = @import("std");
const HyperLogLog = @import("zig-hll").HyperLogLog;
const time = std.time;
const print = std.debug.print;

const BenchmarkResult = struct {
    name: []const u8,
    precision: u5,
    items_added: usize,
    estimate: u64,
    error_percent: f64,
    elapsed_ns: u64,
    ops_per_sec: f64,
    memory_bytes: usize,
    mode: []const u8, // "sparse" or "dense"
};

fn runBenchmark(comptime precision: u5, comptime thread_safe: bool, name: []const u8, n_items: usize, allocator: std.mem.Allocator) !BenchmarkResult {
    const HLL = HyperLogLog(.{ .precision = precision, .thread_safe = thread_safe });
    var hll = try HLL.init(allocator);
    defer hll.deinit();

    const start = time.nanoTimestamp();

    // Add items
    var i: usize = 0;
    while (i < n_items) : (i += 1) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "bench_item_{}", .{i});
        try hll.add(str);
    }

    const end = time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));

    const estimate = hll.count();
    const error_percent = @abs(@as(f64, @floatFromInt(estimate)) - @as(f64, @floatFromInt(n_items))) / @as(f64, @floatFromInt(n_items)) * 100.0;
    const ops_per_sec = @as(f64, @floatFromInt(n_items)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

    const memory_bytes = if (hll.is_sparse)
        hll.sparse_set.len() * 8 + 64 // Rough estimate for HashMap overhead
    else
        hll.dense_buckets.len * @sizeOf(u6);

    return BenchmarkResult{
        .name = name,
        .precision = precision,
        .items_added = n_items,
        .estimate = estimate,
        .error_percent = error_percent,
        .elapsed_ns = elapsed_ns,
        .ops_per_sec = ops_per_sec,
        .memory_bytes = memory_bytes,
        .mode = if (hll.is_sparse) "sparse" else "dense",
    };
}

fn printResult(result: BenchmarkResult) void {
    print("{s:<35} p={d:<2} items={d:<10} est={d:<10} err={d:.2}% time={d:.3}s ops/s={d:.0} mem={d}B mode={s}\n", .{
        result.name,
        result.precision,
        result.items_added,
        result.estimate,
        result.error_percent,
        @as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000_000.0,
        result.ops_per_sec,
        result.memory_bytes,
        result.mode,
    });
}

fn benchmarkSparseTransition(comptime precision: u5, allocator: std.mem.Allocator) !void {
    print("\nSparse to Dense Transition Analysis (p={}):\n", .{precision});
    print("{s:-<120}\n", .{""});

    const HLL = HyperLogLog(.{ .precision = precision });
    var hll = try HLL.init(allocator);
    defer hll.deinit();

    const sparse_threshold = (@as(u32, 1) << precision) * 3 / 4;
    const test_points = [_]usize{ 100, 500, 1000, sparse_threshold / 2, sparse_threshold - 100, sparse_threshold + 100, sparse_threshold * 2 };

    var last_was_sparse = true;
    for (test_points) |target| {
        // Add items to reach target
        var current_count: usize = 0;
        var i: usize = 0;
        while (current_count < target) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "transition_item_{}", .{i});
            try hll.add(str);
            current_count += 1;
        }

        const estimate = hll.count();
        const error_rate = @abs(@as(f64, @floatFromInt(estimate)) - @as(f64, @floatFromInt(target))) / @as(f64, @floatFromInt(target)) * 100.0;
        const memory_usage = if (hll.is_sparse) hll.sparse_set.len() * 8 else hll.dense_buckets.len;

        if (last_was_sparse and !hll.is_sparse) {
            print("*** TRANSITION POINT DETECTED ***\n", .{});
        }

        print("Items: {d:<8} Mode: {s:<6} Estimate: {d:<8} Error: {d:.2}% Memory: {d} bytes\n", .{ target, if (hll.is_sparse) "sparse" else "dense", estimate, error_rate, memory_usage });

        last_was_sparse = hll.is_sparse;
    }
}

fn benchmarkBatchOperations(comptime precision: u5, allocator: std.mem.Allocator) !void {
    print("\nBatch vs Individual Operations:\n", .{});
    print("{s:-<120}\n", .{""});

    const test_sizes = [_]usize{ 1000, 5000, 10000 };

    for (test_sizes) |size| {
        // Prepare test data
        const items = try allocator.alloc([]u8, size);
        defer {
            for (items) |item| allocator.free(item);
            allocator.free(items);
        }

        for (items, 0..) |*item, i| {
            item.* = try std.fmt.allocPrint(allocator, "batch_item_{}", .{i});
        }

        // Test individual operations
        {
            const HLL = HyperLogLog(.{ .precision = precision });
            var hll = try HLL.init(allocator);
            defer hll.deinit();

            const start = time.nanoTimestamp();
            for (items) |item| {
                try hll.add(item);
            }
            const end = time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end - start));
            const ops_per_sec = @as(f64, @floatFromInt(size)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

            print("Individual ops - Size: {d:<6} Time: {d:.3}s Ops/sec: {d:.0} Mode: {s}\n", .{
                size,
                @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0,
                ops_per_sec,
                if (hll.is_sparse) "sparse" else "dense",
            });
        }

        // Test batch operations
        {
            const HLL = HyperLogLog(.{ .precision = precision });
            var hll = try HLL.init(allocator);
            defer hll.deinit();

            const start = time.nanoTimestamp();
            try hll.addBatch(items);
            const end = time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end - start));
            const ops_per_sec = @as(f64, @floatFromInt(size)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

            print("Batch ops      - Size: {d:<6} Time: {d:.3}s Ops/sec: {d:.0} Mode: {s}\n", .{
                size,
                @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0,
                ops_per_sec,
                if (hll.is_sparse) "sparse" else "dense",
            });
        }
        print("\n", .{});
    }
}

fn benchmarkMergeOperations(comptime precision: u5, allocator: std.mem.Allocator) !void {
    print("Merge Operations (p={}):\n", .{precision});
    print("{s:-<120}\n", .{""});

    const HLL = HyperLogLog(.{ .precision = precision });

    // Test sparse + sparse merge
    {
        var hll1 = try HLL.init(allocator);
        defer hll1.deinit();
        var hll2 = try HLL.init(allocator);
        defer hll2.deinit();

        // Add items to keep both sparse
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str1 = try std.fmt.bufPrint(&buf, "merge1_{}", .{i});
            try hll1.add(str1);
            const str2 = try std.fmt.bufPrint(&buf, "merge2_{}", .{i});
            try hll2.add(str2);
        }

        const start = time.nanoTimestamp();
        try hll1.merge(&hll2);
        const end = time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(end - start));

        print("Sparse + Sparse merge: {d:.3}ms Final mode: {s} Estimate: {}\n", .{
            @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
            if (hll1.is_sparse) "sparse" else "dense",
            hll1.count(),
        });
    }

    // Test dense + dense merge
    {
        var hll1 = try HLL.init(allocator);
        defer hll1.deinit();
        var hll2 = try HLL.init(allocator);
        defer hll2.deinit();

        // Add enough items to make both dense
        var i: u32 = 0;
        while (i < 100_000) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str1 = try std.fmt.bufPrint(&buf, "dense1_{}", .{i});
            try hll1.add(str1);
            const str2 = try std.fmt.bufPrint(&buf, "dense2_{}", .{i});
            try hll2.add(str2);
        }

        const start = time.nanoTimestamp();
        try hll1.merge(&hll2);
        const end = time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(end - start));

        print("Dense + Dense merge: {d:.3}ms Final mode: {s} Estimate: {}\n", .{
            @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
            if (hll1.is_sparse) "sparse" else "dense",
            hll1.count(),
        });
    }
}

fn benchmarkAccuracyAtPrecision(comptime p: u5, allocator: std.mem.Allocator) !struct { sparse_error: f64, dense_error: f64, sparse_mem: usize, dense_mem: usize } {
    const test_items = 10_000;

    // Test sparse mode (with fewer items to stay sparse)
    var sparse_error: f64 = 0;
    var sparse_mem: usize = 0;
    {
        const HLL = HyperLogLog(.{ .precision = p });
        var hll = try HLL.init(allocator);
        defer hll.deinit();

        var i: u32 = 0;
        while (i < 1000 and hll.is_sparse) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "sparse_test_{}", .{i});
            try hll.add(str);
        }

        if (hll.is_sparse) {
            const estimate = hll.count();
            sparse_error = @abs(@as(f64, @floatFromInt(estimate)) - @as(f64, @floatFromInt(i))) / @as(f64, @floatFromInt(i)) * 100.0;
            sparse_mem = hll.sparse_set.len() * 8;
        }
    }

    // Test dense mode
    var dense_error: f64 = 0;
    var dense_mem: usize = 0;
    {
        const HLL = HyperLogLog(.{ .precision = p });
        var hll = try HLL.init(allocator);
        defer hll.deinit();

        var i: u32 = 0;
        while (i < test_items) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "dense_test_{}", .{i});
            try hll.add(str);
        }

        const estimate = hll.count();
        dense_error = @abs(@as(f64, @floatFromInt(estimate)) - @as(f64, @floatFromInt(test_items))) / @as(f64, @floatFromInt(test_items)) * 100.0;
        dense_mem = if (hll.is_sparse) hll.sparse_set.len() * 8 else hll.dense_buckets.len;
    }

    return .{ .sparse_error = sparse_error, .dense_error = dense_error, .sparse_mem = sparse_mem, .dense_mem = dense_mem };
}

fn benchmarkHighCardinalityPerformance(comptime precision: u5, allocator: std.mem.Allocator) !BenchmarkResult {
    const n_items = 5_000_000;
    return runBenchmark(precision, false, "5M items", n_items, allocator);
}

fn benchmarkUltraHighCardinality(comptime precision: u5, allocator: std.mem.Allocator) !struct { result_1m: BenchmarkResult, result_5m: BenchmarkResult, result_10m: BenchmarkResult } {
    const result_1m = try runBenchmark(precision, false, "1M items", 1_000_000, allocator);
    const result_5m = try runBenchmark(precision, false, "5M items", 5_000_000, allocator);
    const result_10m = try runBenchmark(precision, false, "10M items", 10_000_000, allocator);

    return .{
        .result_1m = result_1m,
        .result_5m = result_5m,
        .result_10m = result_10m,
    };
}

fn benchmarkHighCardinalityAccuracy(comptime precision: u5, allocator: std.mem.Allocator) !struct {
    accuracy_1m: f64,
    accuracy_5m: f64,
    accuracy_10m: f64,
    memory_1m: usize,
    memory_5m: usize,
    memory_10m: usize,
} {
    const HLL = HyperLogLog(.{ .precision = precision });

    var hll_1m = try HLL.init(allocator);
    defer hll_1m.deinit();
    var hll_5m = try HLL.init(allocator);
    defer hll_5m.deinit();
    var hll_10m = try HLL.init(allocator);
    defer hll_10m.deinit();

    var i: u32 = 0;
    while (i < 10_000_000) : (i += 1) {
        var buf: [32]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, "high_card_test_{}", .{i});

        if (i < 1_000_000) try hll_1m.add(str);
        if (i < 5_000_000) try hll_5m.add(str);
        try hll_10m.add(str);
    }

    const estimate_1m = hll_1m.count();
    const estimate_5m = hll_5m.count();
    const estimate_10m = hll_10m.count();

    const accuracy_1m = @abs(@as(f64, @floatFromInt(estimate_1m)) - 1_000_000.0) / 1_000_000.0 * 100.0;
    const accuracy_5m = @abs(@as(f64, @floatFromInt(estimate_5m)) - 5_000_000.0) / 5_000_000.0 * 100.0;
    const accuracy_10m = @abs(@as(f64, @floatFromInt(estimate_10m)) - 10_000_000.0) / 10_000_000.0 * 100.0;

    const memory_1m = if (hll_1m.is_sparse) hll_1m.sparse_set.len() * 8 else hll_1m.dense_buckets.len;
    const memory_5m = if (hll_5m.is_sparse) hll_5m.sparse_set.len() * 8 else hll_5m.dense_buckets.len;
    const memory_10m = if (hll_10m.is_sparse) hll_10m.sparse_set.len() * 8 else hll_10m.dense_buckets.len;

    return .{
        .accuracy_1m = accuracy_1m,
        .accuracy_5m = accuracy_5m,
        .accuracy_10m = accuracy_10m,
        .memory_1m = memory_1m,
        .memory_5m = memory_5m,
        .memory_10m = memory_10m,
    };
}

fn benchmarkHighCardinalityToFile(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("\n## High Cardinality Performance (Millions of Elements)\n\n", .{});
    try writer.print("| Precision | Cardinality | Estimate | Error% | Time (s) | Ops/sec | Memory (MB) | Mode |\n", .{});
    try writer.print("|-----------|-------------|----------|--------|----------|---------|-------------|------|\n", .{});

    const precisions = [_]u5{ 12, 14, 16 };

    for (precisions) |p| {
        const results = switch (p) {
            12 => try benchmarkUltraHighCardinality(12, allocator),
            14 => try benchmarkUltraHighCardinality(14, allocator),
            16 => try benchmarkUltraHighCardinality(16, allocator),
            else => unreachable,
        };

        const time_1m_s = @as(f64, @floatFromInt(results.result_1m.elapsed_ns)) / 1_000_000_000.0;
        const time_5m_s = @as(f64, @floatFromInt(results.result_5m.elapsed_ns)) / 1_000_000_000.0;
        const time_10m_s = @as(f64, @floatFromInt(results.result_10m.elapsed_ns)) / 1_000_000_000.0;

        const mem_1m_mb = @as(f64, @floatFromInt(results.result_1m.memory_bytes)) / 1_048_576.0;
        const mem_5m_mb = @as(f64, @floatFromInt(results.result_5m.memory_bytes)) / 1_048_576.0;
        const mem_10m_mb = @as(f64, @floatFromInt(results.result_10m.memory_bytes)) / 1_048_576.0;

        try writer.print("| {d} | 1M | {d} | {d:.2}% | {d:.2} | {d:.0} | {d:.2} | {s} |\n", .{ p, results.result_1m.estimate, results.result_1m.error_percent, time_1m_s, results.result_1m.ops_per_sec, mem_1m_mb, results.result_1m.mode });
        try writer.print("| {d} | 5M | {d} | {d:.2}% | {d:.2} | {d:.0} | {d:.2} | {s} |\n", .{ p, results.result_5m.estimate, results.result_5m.error_percent, time_5m_s, results.result_5m.ops_per_sec, mem_5m_mb, results.result_5m.mode });
        try writer.print("| {d} | 10M | {d} | {d:.2}% | {d:.2} | {d:.0} | {d:.2} | {s} |\n", .{ p, results.result_10m.estimate, results.result_10m.error_percent, time_10m_s, results.result_10m.ops_per_sec, mem_10m_mb, results.result_10m.mode });
    }
}

fn benchmarkHighCardinalityAccuracyToFile(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("\n## High Cardinality Accuracy Analysis\n\n", .{});
    try writer.print("| Precision | 1M Error% | 5M Error% | 10M Error% | 1M Mem (MB) | 5M Mem (MB) | 10M Mem (MB) |\n", .{});
    try writer.print("|-----------|-----------|-----------|------------|-------------|-------------|-------------|\n", .{});

    const precisions = [_]u5{ 12, 14, 16 };

    for (precisions) |p| {
        const results = switch (p) {
            12 => try benchmarkHighCardinalityAccuracy(12, allocator),
            14 => try benchmarkHighCardinalityAccuracy(14, allocator),
            16 => try benchmarkHighCardinalityAccuracy(16, allocator),
            else => unreachable,
        };

        const mem_1m_mb = @as(f64, @floatFromInt(results.memory_1m)) / 1_048_576.0;
        const mem_5m_mb = @as(f64, @floatFromInt(results.memory_5m)) / 1_048_576.0;
        const mem_10m_mb = @as(f64, @floatFromInt(results.memory_10m)) / 1_048_576.0;

        try writer.print("| {d} | {d:.2}% | {d:.2}% | {d:.2}% | {d:.2} | {d:.2} | {d:.2} |\n", .{ p, results.accuracy_1m, results.accuracy_5m, results.accuracy_10m, mem_1m_mb, mem_5m_mb, mem_10m_mb });
    }
}

fn benchmarkAccuracyComparisonToFile(allocator: std.mem.Allocator, writer: anytype) !void {
    const result8 = try benchmarkAccuracyAtPrecision(8, allocator);
    try writer.print("| 8 | {d:.2} | {d:.2} | {d} | {d} |\n", .{ result8.sparse_error, result8.dense_error, result8.sparse_mem, result8.dense_mem });

    const result10 = try benchmarkAccuracyAtPrecision(10, allocator);
    try writer.print("| 10 | {d:.2} | {d:.2} | {d} | {d} |\n", .{ result10.sparse_error, result10.dense_error, result10.sparse_mem, result10.dense_mem });

    const result12 = try benchmarkAccuracyAtPrecision(12, allocator);
    try writer.print("| 12 | {d:.2} | {d:.2} | {d} | {d} |\n", .{ result12.sparse_error, result12.dense_error, result12.sparse_mem, result12.dense_mem });

    const result14 = try benchmarkAccuracyAtPrecision(14, allocator);
    try writer.print("| 14 | {d:.2} | {d:.2} | {d} | {d} |\n", .{ result14.sparse_error, result14.dense_error, result14.sparse_mem, result14.dense_mem });

    const result16 = try benchmarkAccuracyAtPrecision(16, allocator);
    try writer.print("| 16 | {d:.2} | {d:.2} | {d} | {d} |\n", .{ result16.sparse_error, result16.dense_error, result16.sparse_mem, result16.dense_mem });
}

fn benchmarkSparseTransitionToFile(comptime precision: u5, allocator: std.mem.Allocator, writer: anytype) !void {
    const HLL = HyperLogLog(.{ .precision = precision });
    var hll = try HLL.init(allocator);
    defer hll.deinit();

    const sparse_threshold = (@as(u32, 1) << precision) * 3 / 4;
    const test_points = [_]usize{ 100, 500, 1000, sparse_threshold / 2, sparse_threshold - 100, sparse_threshold + 100, sparse_threshold * 2 };

    for (test_points) |target| {
        var current_count: usize = 0;
        var i: usize = 0;
        while (current_count < target) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "transition_item_{}", .{i});
            try hll.add(str);
            current_count += 1;
        }

        const estimate = hll.count();
        const error_rate = @abs(@as(f64, @floatFromInt(estimate)) - @as(f64, @floatFromInt(target))) / @as(f64, @floatFromInt(target)) * 100.0;
        const memory_usage = if (hll.is_sparse) hll.sparse_set.len() * 8 else hll.dense_buckets.len;

        try writer.print("| {d} | {s} | {d} | {d:.2}% | {d} |\n", .{ target, if (hll.is_sparse) "sparse" else "dense", estimate, error_rate, memory_usage });
    }
}

fn benchmarkBatchOperationsToFile(comptime precision: u5, allocator: std.mem.Allocator, writer: anytype) !void {
    const test_sizes = [_]usize{ 1000, 5000, 10000 };

    for (test_sizes) |size| {
        const items = try allocator.alloc([]u8, size);
        defer {
            for (items) |item| allocator.free(item);
            allocator.free(items);
        }

        for (items, 0..) |*item, i| {
            item.* = try std.fmt.allocPrint(allocator, "batch_item_{}", .{i});
        }

        // Individual operations
        {
            const HLL = HyperLogLog(.{ .precision = precision });
            var hll = try HLL.init(allocator);
            defer hll.deinit();

            const start = time.nanoTimestamp();
            for (items) |item| {
                try hll.add(item);
            }
            const end = time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end - start));
            const ops_per_sec = @as(f64, @floatFromInt(size)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

            try writer.print("| Individual ({d}) | {d} | {d:.2} | {d:.0} | {s} |\n", .{ size, size, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, ops_per_sec, if (hll.is_sparse) "sparse" else "dense" });
        }

        // Batch operations
        {
            const HLL = HyperLogLog(.{ .precision = precision });
            var hll = try HLL.init(allocator);
            defer hll.deinit();

            const start = time.nanoTimestamp();
            try hll.addBatch(items);
            const end = time.nanoTimestamp();
            const elapsed_ns = @as(u64, @intCast(end - start));
            const ops_per_sec = @as(f64, @floatFromInt(size)) / (@as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0);

            try writer.print("| Batch ({d}) | {d} | {d:.2} | {d:.0} | {s} |\n", .{ size, size, @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0, ops_per_sec, if (hll.is_sparse) "sparse" else "dense" });
        }
    }
}

fn benchmarkMergeOperationsToFile(comptime precision: u5, allocator: std.mem.Allocator, writer: anytype) !void {
    const HLL = HyperLogLog(.{ .precision = precision });

    // Sparse + sparse merge
    {
        var hll1 = try HLL.init(allocator);
        defer hll1.deinit();
        var hll2 = try HLL.init(allocator);
        defer hll2.deinit();

        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str1 = try std.fmt.bufPrint(&buf, "merge1_{}", .{i});
            try hll1.add(str1);
            const str2 = try std.fmt.bufPrint(&buf, "merge2_{}", .{i});
            try hll2.add(str2);
        }

        const start = time.nanoTimestamp();
        try hll1.merge(&hll2);
        const end = time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(end - start));

        try writer.print("| Sparse + Sparse | {d:.3} | {s} | {d} |\n", .{
            @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
            if (hll1.is_sparse) "sparse" else "dense",
            hll1.count(),
        });
    }

    // Dense + dense merge
    {
        var hll1 = try HLL.init(allocator);
        defer hll1.deinit();
        var hll2 = try HLL.init(allocator);
        defer hll2.deinit();

        var i: u32 = 0;
        while (i < 100_000) : (i += 1) {
            var buf: [32]u8 = undefined;
            const str1 = try std.fmt.bufPrint(&buf, "dense1_{}", .{i});
            try hll1.add(str1);
            const str2 = try std.fmt.bufPrint(&buf, "dense2_{}", .{i});
            try hll2.add(str2);
        }

        const start = time.nanoTimestamp();
        try hll1.merge(&hll2);
        const end = time.nanoTimestamp();
        const elapsed_ns = @as(u64, @intCast(end - start));

        try writer.print("| Dense + Dense | {d:.3} | {s} | {d} |\n", .{
            @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0,
            if (hll1.is_sparse) "sparse" else "dense",
            hll1.count(),
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create benchmark results file in tests folder
    const file = try std.fs.cwd().createFile("tests/benchmark_results.md", .{});
    defer file.close();
    const writer = file.writer();

    try writer.print("# HyperLogLog Performance Benchmarks\n\n", .{});
    try writer.print("Generated: {}\n\n", .{std.time.timestamp()});

    // System information
    try writer.print("## System Information\n\n", .{});
    try writer.print("| Component | Details |\n", .{});
    try writer.print("|-----------|--------|\n", .{});

    // Get system info
    const builtin = @import("builtin");
    try writer.print("| **CPU Architecture** | x86_64 |\n", .{});
    try writer.print("| **Operating System** | Linux |\n", .{});
    try writer.print("| **Optimization Mode** | ReleaseFast |\n", .{});
    try writer.print("| **Zig Version** | {} |\n", .{builtin.zig_version});

    // CPU features
    try writer.print("| **CPU Features** | AVX2, SSE4.2, x86_64 |\n", .{});
    try writer.print("| **Endianness** | Little Endian |\n", .{});
    try writer.print("| **Pointer Size** | 64 bits |\n", .{});

    // Try to get system information from /proc files (Linux)
    if (std.fs.openFileAbsolute("/proc/cpuinfo", .{})) |cpuinfo_file| {
        defer cpuinfo_file.close();
        var buf: [4096]u8 = undefined;
        if (cpuinfo_file.readAll(&buf)) |bytes_read| {
            const content = buf[0..bytes_read];
            // Look for CPU model name
            if (std.mem.indexOf(u8, content, "model name")) |start| {
                if (std.mem.indexOf(u8, content[start..], ":")) |colon_pos| {
                    const line_start = start + colon_pos + 1;
                    if (std.mem.indexOf(u8, content[line_start..], "\n")) |line_end| {
                        const cpu_name = std.mem.trim(u8, content[line_start .. line_start + line_end], " \t");
                        try writer.print("| **CPU Model** | {s} |\n", .{cpu_name});
                    }
                }
            }
        } else |_| {}
    } else |_| {}

    // Try get memory information
    if (std.fs.openFileAbsolute("/proc/meminfo", .{})) |meminfo_file| {
        defer meminfo_file.close();
        var buf: [2048]u8 = undefined;
        if (meminfo_file.readAll(&buf)) |bytes_read| {
            const content = buf[0..bytes_read];
            // Look for total memory
            if (std.mem.indexOf(u8, content, "MemTotal:")) |start| {
                if (std.mem.indexOf(u8, content[start..], "\n")) |line_end| {
                    const line = content[start .. start + line_end];
                    var parts = std.mem.split(u8, line, " ");
                    _ = parts.next(); // Skip "MemTotal:"
                    if (parts.next()) |mem_kb_str| {
                        if (std.fmt.parseInt(u64, std.mem.trim(u8, mem_kb_str, " \t"), 10)) |mem_kb| {
                            const mem_gb = mem_kb / 1024 / 1024;
                            try writer.print("| **Total RAM** | {} GB ({} MB) |\n", .{ mem_gb, mem_kb / 1024 });
                        } else |_| {}
                    }
                }
            }
        } else |_| {}
    } else |_| {}

    // Try to get kernel version
    if (std.fs.openFileAbsolute("/proc/version", .{})) |version_file| {
        defer version_file.close();
        var buf: [512]u8 = undefined;
        if (version_file.readAll(&buf)) |bytes_read| {
            const content = buf[0..bytes_read];
            if (std.mem.indexOf(u8, content, "\n")) |line_end| {
                const version_line = content[0..line_end];
                // Extract just the kernel version part
                if (std.mem.indexOf(u8, version_line, "Linux version ")) |start| {
                    const version_start = start + "Linux version ".len;
                    if (std.mem.indexOf(u8, version_line[version_start..], " ")) |version_end| {
                        const kernel_version = version_line[version_start .. version_start + version_end];
                        try writer.print("| **Kernel Version** | {s} |\n", .{kernel_version});
                    }
                }
            }
        } else |_| {}
    } else |_| {}

    // Compiler information
    try writer.print("| **Build Mode** | Native optimized |\n", .{});

    // Start performance analysis
    try writer.print("## Performance Analysis Across Precisions\n\n", .{});
    try writer.print("| Test Scenario | Precision | Items | Estimate | Error% | Time (ms) | Ops/sec | Memory | Mode |\n", .{});
    try writer.print("|---------------|-----------|-------|----------|--------|----------|---------|--------|------|\n", .{});

    const test_sizes = [_]usize{ 1_000, 10_000, 100_000 };

    for (test_sizes) |size| {
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "{d} items", .{size});

        // Run benchmarks for each precision individually
        const result10 = try runBenchmark(10, false, name, size, allocator);
        const time10_ms = @as(f64, @floatFromInt(result10.elapsed_ns)) / 1_000_000.0;
        try writer.print("| {s} | 10 | {d} | {d} | {d:.2}% | {d:.2}ms | {d:.0} | {d}B | {s} |\n", .{ name, result10.items_added, result10.estimate, result10.error_percent, time10_ms, result10.ops_per_sec, result10.memory_bytes, result10.mode });

        const result12 = try runBenchmark(12, false, name, size, allocator);
        const time12_ms = @as(f64, @floatFromInt(result12.elapsed_ns)) / 1_000_000.0;
        try writer.print("| {s} | 12 | {d} | {d} | {d:.2}% | {d:.2}ms | {d:.0} | {d}B | {s} |\n", .{ name, result12.items_added, result12.estimate, result12.error_percent, time12_ms, result12.ops_per_sec, result12.memory_bytes, result12.mode });

        const result14 = try runBenchmark(14, false, name, size, allocator);
        const time14_ms = @as(f64, @floatFromInt(result14.elapsed_ns)) / 1_000_000.0;
        try writer.print("| {s} | 14 | {d} | {d} | {d:.2}% | {d:.2}ms | {d:.0} | {d}B | {s} |\n", .{ name, result14.items_added, result14.estimate, result14.error_percent, time14_ms, result14.ops_per_sec, result14.memory_bytes, result14.mode });

        const result16 = try runBenchmark(16, false, name, size, allocator);
        const time16_ms = @as(f64, @floatFromInt(result16.elapsed_ns)) / 1_000_000.0;
        try writer.print("| {s} | 16 | {d} | {d} | {d:.2}% | {d:.2}ms | {d:.0} | {d}B | {s} |\n", .{ name, result16.items_added, result16.estimate, result16.error_percent, time16_ms, result16.ops_per_sec, result16.memory_bytes, result16.mode });
    }

    // Sparse to dense transition
    try writer.print("\n## Sparse to Dense Transition Analysis\n\n", .{});
    try writer.print("### Precision 12\n\n", .{});
    try writer.print("| Items | Mode | Estimate | Error% | Memory (bytes) |\n", .{});
    try writer.print("|-------|------|----------|--------|--------------|\n", .{});
    try benchmarkSparseTransitionToFile(12, allocator, writer);

    try writer.print("\n### Precision 14\n\n", .{});
    try writer.print("| Items | Mode | Estimate | Error% | Memory (bytes) |\n", .{});
    try writer.print("|-------|------|----------|--------|--------------|\n", .{});
    try benchmarkSparseTransitionToFile(14, allocator, writer);

    // Batch operations
    try writer.print("\n## Batch vs Individual Operations\n\n", .{});
    try writer.print("| Operation Type | Size | Time (ms) | Ops/sec | Mode |\n", .{});
    try writer.print("|----------------|------|----------|---------|------|\n", .{});
    try benchmarkBatchOperationsToFile(12, allocator, writer);

    // Merge operations
    try writer.print("\n## Merge Operations (Precision 12)\n\n", .{});
    try writer.print("| Merge Type | Time (ms) | Final Mode | Estimate |\n", .{});
    try writer.print("|------------|-----------|------------|----------|\n", .{});
    try benchmarkMergeOperationsToFile(12, allocator, writer);

    // Thread safety
    try writer.print("\n## Thread Safety Performance Impact\n\n", .{});
    try writer.print("| Mode | Time (ms) | Ops/sec | Overhead |\n", .{});
    try writer.print("|------|----------|---------|----------|\n", .{});
    {
        const n = 50_000;
        const result_normal = try runBenchmark(14, false, "Standard", n, allocator);
        const result_safe = try runBenchmark(14, true, "Thread-safe", n, allocator);

        const overhead_percent = @abs(@as(f64, @floatFromInt(result_safe.elapsed_ns)) - @as(f64, @floatFromInt(result_normal.elapsed_ns))) / @as(f64, @floatFromInt(result_normal.elapsed_ns)) * 100.0;

        try writer.print("| Standard | {d:.2} | {d:.0} | - |\n", .{
            @as(f64, @floatFromInt(result_normal.elapsed_ns)) / 1_000_000.0,
            result_normal.ops_per_sec,
        });
        try writer.print("| Thread-safe | {d:.2} | {d:.0} | {d:.1}% |\n", .{
            @as(f64, @floatFromInt(result_safe.elapsed_ns)) / 1_000_000.0,
            result_safe.ops_per_sec,
            overhead_percent,
        });
    }

    // High cardinality benchmarks
    try benchmarkHighCardinalityToFile(allocator, writer);
    try benchmarkHighCardinalityAccuracyToFile(allocator, writer);

    // Accuracy comparison
    try writer.print("\n## Accuracy & Memory Efficiency by Precision\n\n", .{});
    try writer.print("| Precision | Sparse Error% | Dense Error% | Sparse Mem (bytes) | Dense Mem (bytes) |\n", .{});
    try writer.print("|-----------|---------------|--------------|--------------------|-----------------|\n", .{});
    try benchmarkAccuracyComparisonToFile(allocator, writer);

    print("Benchmark completed! Results saved to 'tests/benchmark_results.md'\n", .{});
}
