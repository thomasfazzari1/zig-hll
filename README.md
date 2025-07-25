# Zig HyperLogLog (zig-hll)
[![CI](https://github.com/thomasfazzari1/zig-hll/workflows/CI/badge.svg)](https://github.com/thomasfazzari1/zig-hll/actions)
[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange.svg)](https://ziglang.org/download/)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

A fast, memory-efficient HyperLogLog cardinality estimation library for Zig.

## Features

- **Hybrid sparse/dense modes** - Automatic memory optimization
- **High accuracy** - Uses bias correction for superior estimates
- **Thread-safe operations** - Optional concurrent access support
- **Serialization** - Persist and restore HLL state
- **Zero dependencies** - Pure Zig implementation

## Quick Start

Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .@"zig-hll" = .{
        .url = "https://github.com/thomasfazzari1/zig-hll/archive/main.tar.gz",
        .hash = "...",
    },
},
```

## Usage

```zig
const std = @import("std");
const HyperLogLog = @import("zig-hll").HyperLogLog;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create HLL with precision 14 (standard)
    const HLL = HyperLogLog(.{ .precision = 14 });
    var hll = try HLL.init(gpa.allocator());
    defer hll.deinit();

    // Add some data
    try hll.add("user123");
    try hll.add("user456");
    try hll.add("user123"); // duplicate

    // Get cardinality estimate
    const count = hll.count();
    std.debug.print("Estimated unique items: {}\n", .{count});
}
```

## Configuration

```zig
// Basic usage
const HLL = HyperLogLog(.{ .precision = 14 });

// Thread-safe version
const ThreadSafeHLL = HyperLogLog(.{ .precision = 14, .thread_safe = true });

// High precision (more memory, better accuracy)
const HighPrecisionHLL = HyperLogLog(.{ .precision = 16 });
```

## Precision Guide

| Precision | Memory (Dense) | Standard Error |
| --------- | -------------- | -------------- |
| 10        | 1 KB           | 3.2%           |
| 12        | 4 KB           | 1.6%           |
| 14        | 16 KB          | 0.8%           |
| 16        | 64 KB          | 0.4%           |

## Performance Benchmark

```bash
zig build benchmark
```

Generates a detailed report in `tests/benchmark_results.md`

See [benchmark results](tests/benchmark_results.md) for a comprehensive output example ran on my machine

## API

### Core Operations

- `init(allocator)` - Create new HLL
- `add(data)` - Add element
- `addHash(hash)` - Add pre-hashed element
- `count()` - Get cardinality estimate
- `merge(other)` - Combine two HLLs
- `clear()` - Reset to empty state

### Serialization

- `serialize(writer)` - Save state
- `deserialize(allocator, reader)` - Restore state

## Building

```bash
zig build test      # Run tests
zig build example   # Run example
zig build benchmark # Performance tests
zig build docs      # Generate documentation
```

## License

This project is licensed under the Apache License 2.0 - See [LICENSE](LICENSE) for details.

## References

- **LogLog-Beta Algorithm reference**: [LogLog-Beta and More: A New Algorithm for Cardinality Estimation Based on LogLog Counting](https://arxiv.org/pdf/1612.02284)
- **xxHash Implementation used in this project**: [zig-xxHash by The-King-of-Toasters](https://github.com/The-King-of-Toasters/zig-xxHash)
