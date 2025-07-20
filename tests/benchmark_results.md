# HyperLogLog Performance Benchmarks

Generated: 1753025416

## System Information

| Component             | Details                                        |
| --------------------- | ---------------------------------------------- |
| **CPU Architecture**  | x86_64                                         |
| **Operating System**  | Linux                                          |
| **Optimization Mode** | ReleaseFast                                    |
| **Zig Version**       | 0.13.0                                         |
| **CPU Features**      | AVX2, SSE4.2, x86_64                           |
| **Endianness**        | Little Endian                                  |
| **Pointer Size**      | 64 bits                                        |
| **CPU Model**         | 11th Gen Intel(R) Core(TM) i7-1185G7 @ 3.00GHz |
| **Kernel Version**    | 6.14.0-24-generic                              |
| **Build Mode**        | Native optimized                               |

## Performance Analysis Across Precisions

| Test Scenario | Precision | Items  | Estimate | Error% | Time (ms) | Ops/sec  | Memory | Mode   |
| ------------- | --------- | ------ | -------- | ------ | --------- | -------- | ------ | ------ |
| 1000 items    | 10        | 1000   | 1003     | 0.30%  | 0.28ms    | 3588178  | 1024B  | dense  |
| 1000 items    | 12        | 1000   | 989      | 1.10%  | 0.19ms    | 5166170  | 8064B  | sparse |
| 1000 items    | 14        | 1000   | 991      | 0.90%  | 0.19ms    | 5195831  | 8064B  | sparse |
| 1000 items    | 16        | 1000   | 998      | 0.20%  | 0.21ms    | 4842967  | 8064B  | sparse |
| 10000 items   | 10        | 10000  | 10231    | 2.31%  | 0.50ms    | 20092950 | 1024B  | dense  |
| 10000 items   | 12        | 10000  | 9972     | 0.28%  | 0.66ms    | 15144654 | 4096B  | dense  |
| 10000 items   | 14        | 10000  | 9997     | 0.03%  | 0.98ms    | 10156079 | 80064B | sparse |
| 10000 items   | 16        | 10000  | 10018    | 0.18%  | 0.96ms    | 10391316 | 80064B | sparse |
| 100000 items  | 10        | 100000 | 96317    | 3.68%  | 4.08ms    | 24502195 | 1024B  | dense  |
| 100000 items  | 12        | 100000 | 98658    | 1.34%  | 3.61ms    | 27705919 | 4096B  | dense  |
| 100000 items  | 14        | 100000 | 100214   | 0.21%  | 4.48ms    | 22346274 | 16384B | dense  |
| 100000 items  | 16        | 100000 | 100519   | 0.52%  | 7.53ms    | 13287292 | 65536B | dense  |

## Sparse to Dense Transition Analysis

### Precision 12

| Items | Mode   | Estimate | Error% | Memory (bytes) |
| ----- | ------ | -------- | ------ | -------------- |
| 100   | sparse | 98       | 2.00%  | 800            |
| 500   | sparse | 495      | 1.00%  | 4000           |
| 1000  | sparse | 983      | 1.70%  | 8000           |
| 1536  | sparse | 1510     | 1.69%  | 12288          |
| 2972  | sparse | 2951     | 0.71%  | 23776          |
| 3172  | dense  | 3177     | 0.16%  | 4096           |
| 6144  | dense  | 6088     | 0.91%  | 4096           |

### Precision 14

| Items | Mode   | Estimate | Error% | Memory (bytes) |
| ----- | ------ | -------- | ------ | -------------- |
| 100   | sparse | 99       | 1.00%  | 800            |
| 500   | sparse | 496      | 0.80%  | 4000           |
| 1000  | sparse | 992      | 0.80%  | 8000           |
| 6144  | sparse | 6111     | 0.54%  | 49152          |
| 12188 | sparse | 12117    | 0.58%  | 97504          |
| 12388 | dense  | 12329    | 0.48%  | 16384          |
| 24576 | dense  | 24534    | 0.17%  | 16384          |

## Batch vs Individual Operations

| Operation Type     | Size  | Time (ms) | Ops/sec  | Mode   |
| ------------------ | ----- | --------- | -------- | ------ |
| Individual (1000)  | 1000  | 0.13      | 7479935  | sparse |
| Batch (1000)       | 1000  | 0.16      | 6148889  | sparse |
| Individual (5000)  | 5000  | 0.33      | 14961862 | dense  |
| Batch (5000)       | 5000  | 0.35      | 14100315 | dense  |
| Individual (10000) | 10000 | 0.43      | 23177334 | dense  |
| Batch (10000)      | 10000 | 0.43      | 23453533 | dense  |

## Merge Operations (Precision 12)

| Merge Type      | Time (ms) | Final Mode | Estimate |
| --------------- | --------- | ---------- | -------- |
| Sparse + Sparse | 0.090     | sparse     | 1964     |
| Dense + Dense   | 0.003     | dense      | 198011   |

## Thread Safety Performance Impact

| Mode        | Time (ms) | Ops/sec  | Overhead |
| ----------- | --------- | -------- | -------- |
| Standard    | 2.96      | 16886643 | -        |
| Thread-safe | 2.86      | 17476279 | 3.4%     |

## High Cardinality Performance (Millions of Elements)

| Precision | Cardinality | Estimate | Error% | Time (s) | Ops/sec  | Memory (MB) | Mode  |
| --------- | ----------- | -------- | ------ | -------- | -------- | ----------- | ----- |
| 12        | 1M          | 1009434  | 0.94%  | 0.05     | 20792698 | 0.00        | dense |
| 12        | 5M          | 5033674  | 0.67%  | 0.28     | 18026624 | 0.00        | dense |
| 12        | 10M         | 9850008  | 1.50%  | 0.59     | 17086707 | 0.00        | dense |
| 14        | 1M          | 998393   | 0.16%  | 0.06     | 17922088 | 0.02        | dense |
| 14        | 5M          | 4983035  | 0.34%  | 0.29     | 17022549 | 0.02        | dense |
| 14        | 10M         | 9847643  | 1.52%  | 0.52     | 19345909 | 0.02        | dense |
| 16        | 1M          | 995174   | 0.48%  | 0.07     | 14011101 | 0.06        | dense |
| 16        | 5M          | 5006540  | 0.13%  | 0.25     | 20364364 | 0.06        | dense |
| 16        | 10M         | 9995587  | 0.04%  | 0.62     | 16080362 | 0.06        | dense |

## High Cardinality Accuracy Analysis

| Precision | 1M Error% | 5M Error% | 10M Error% | 1M Mem (MB) | 5M Mem (MB) | 10M Mem (MB) |
| --------- | --------- | --------- | ---------- | ----------- | ----------- | ------------ |
| 12        | 3.40%     | 2.61%     | 0.21%      | 0.00        | 0.00        | 0.00         |
| 14        | 1.83%     | 0.19%     | 0.56%      | 0.02        | 0.02        | 0.02         |
| 16        | 0.63%     | 0.01%     | 0.26%      | 0.06        | 0.06        | 0.06         |

## Accuracy & Memory Efficiency by Precision

| Precision | Sparse Error% | Dense Error% | Sparse Mem (bytes) | Dense Mem (bytes) |
| --------- | ------------- | ------------ | ------------------ | ----------------- |
| 8         | 0.00          | 4.67         | 0                  | 256               |
| 10        | 0.00          | 0.80         | 0                  | 1024              |
| 12        | 0.80          | 0.35         | 8000               | 4096              |
| 14        | 1.10          | 1.48         | 8000               | 80000             |
| 16        | 0.30          | 0.19         | 8000               | 80000             |
