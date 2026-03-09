# id_fifo: 参数化 ID 索引 FIFO

## 概述

`id_fifo` 是一个 SystemVerilog 验证工具类，提供以 ID 为索引的 FIFO 队列，支持回绕（wrap-around）感知的 ID 新老比较。常用于追踪乱序执行环境中的 in-flight 指令或事务。

- 可用来记录 rid、pc、inst 之间的关系，在 commit 可以对指令内容进行检查
- 可用来记录 rid、lid、sid 之间的关系
- 可用来记录 lid 与 load uop 的关系
- 可用来记录 sid 与 store uop 的关系

## 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `T` | `logic [7:0]` | payload 数据类型，支持任意 struct / 内建类型 |
| `ID_WIDTH` | `8` | ID 位宽；**MSB 为回绕位（wrap bit）** |

## 配置项

| 字段 | 默认 | 说明 |
|------|------|------|
| `enable_log` | 0 | 开启后每次操作打印 `$display` 日志 |
| `enable_assert` | 0 | 开启后对非法操作触发 `$error` / `$fatal` |
| `allow_dup` | 0 | 允许重复 ID（影响 `delete_by_id` 行为） |

## 快速开始

```systemverilog
typedef struct { logic [31:0] pc; } instr_t;

id_fifo #(.T(instr_t), .ID_WIDTH(6)) fifo = new("rob");
fifo.enable_log  = 1;
fifo.enable_assert = 1;

fifo.push(6'd3, '{pc: 32'h1000});
fifo.push(6'd5, '{pc: 32'h1004});

entry = fifo.peek_oldest();        // 查看最老的条目
fifo.flush_younger(6'd4);          // 冲刷比 rid=4 更年轻的条目
fifo.delete_by_id(6'd3);           // 删除 rid=3
```

## ID 回绕比较

ID 的 MSB 为 wrap bit，其余位为序号值。比较规则：

| wrap bit 关系 | 判断 younger（更年轻）的规则 |
|--------------|--------------------------|
| 相同 | 序号值更大的为 younger |
| 不同（已回绕） | 序号值更小的为 younger |

```
例：ID_WIDTH=4，序号范围 0-7，wrap bit = bit[3]
程序顺序：... 5(0b0101), 6(0b0110), 7(0b0111), 8(0b1000), 9(0b1001) ...
is_younger(8, 7) = 1  ← 8 已回绕（wrap=1），val=0 < val=7
is_younger(6, 7) = 0  ← 6 未回绕，val=6 < val=7，6 更老
```

## API 说明

### `push(id, data)`

将条目追加到队列尾部（最年轻位置）。

- `allow_dup=0`（默认）：不检查重复 ID
- `allow_dup=1`：允许同一 ID 多次入队

### `peek_oldest() → entry_t`

返回最老的条目（index 0），**不移除**。队列为空时若 `enable_assert=1` 触发 `$fatal`。

### `peek_by_id(id) → entry_t`

返回第一个（最老）ID 匹配的条目，**不移除**。未找到时若 `enable_assert=1` 触发 `$fatal`。

### `peek_all_by_id(id) → entry_queue_t`

返回**所有** ID 匹配的条目队列（按插入顺序）。`allow_dup=1` 时使用。

### `delete_by_id(id)`

删除 ID 匹配的条目：

| `allow_dup` | 行为 |
|-------------|------|
| `0`（默认） | 删除第一个匹配 |
| `1` | 删除所有匹配 |

未找到时若 `enable_assert=1` 触发 `$error`。

### `flush_younger(id)`

移除所有 ID **严格比 `id` 更年轻**的条目。常用于分支预测失败后的回滚。

### `flush_younger_or_eq(id)`

移除所有 ID **年轻于或等于 `id`** 的条目。常用于 retire 时清理。

### 辅助函数

| 函数 | 说明 |
|------|------|
| `size() → int` | 当前条目数 |
| `empty() → bit` | 是否为空 |
| `dump()` | 打印所有条目（调试用） |

## 统计信息（仅 dump 可见）

`id_fifo` 内部维护了一组统计计数器（`int`），用于在调试时快速判断是否发生了预期的操作序列。

- 这些计数器**只通过 `dump()` 的 `$display` 输出暴露**，不作为稳定的对外 API 使用。
- 不要在 TB 里依赖读取这些成员变量来驱动功能逻辑，它们的存在主要用于观测和回归定位。

计数器列表（名字与含义）：

- `stat_push_cnt`：累计 `push()` 调用次数
- `stat_delete_cnt`：累计 `delete_by_id()` 调用次数
- `stat_flush_cnt`：累计 flush 调用次数，包含 `flush_younger()` 与 `flush_younger_or_eq()`
- `stat_peak_size`：历史峰值队列长度（`entries.size()` 的最大值）
- `stat_wrap_cnt`：在 `push()` 过程中检测到的 wrap bit 跳变次数

查看方式：调用 `dump()`，输出中会包含上述 `stat_*` 字段。

## 随机压力测试（TB）约定

### 固定随机种子

随机压力测试必须可复现。

- TB 内使用固定默认种子，例如：`localparam int DEFAULT_SEED = 42;`
- 在任何随机化之前打印：`$display("SEED=%0d", DEFAULT_SEED);`
- 然后显式播种：`void'($urandom(DEFAULT_SEED));`
- 需要扩展压力时，可以通过修改 TB 常量来改变种子，不通过命令行或运行时参数注入种子

### ID 分配规则（半空间安全 + 单调）

随机测试里**禁止**直接随机生成 ID。

- ID 必须按程序顺序单调分配（monotonic allocation），以满足 wrap-around 比较的前提
- 任意时刻 live（in-flight）ID 的跨度必须不超过 ID 空间的一半，即 `2^(ID_WIDTH-1)`
  - 超过半空间会导致 `is_younger()` 的回绕比较语义不再可靠
- 做随机操作时，允许随机选择 push/delete/flush 的时机与 payload，但 ID/RID 的生成必须保持上述约束

## 使用示例

### 基本 push / delete

```systemverilog
fifo.push(6'd1, data_a);
fifo.push(6'd3, data_b);
fifo.push(6'd5, data_c);

fifo.delete_by_id(6'd3);  // 移除 rid=3
// 队列: [rid=1, rid=5]
```

### 分支预测失败回滚

```systemverilog
// rid=4 的分支预测失败，清除 rid>4 的所有指令
fifo.flush_younger(6'd4);
```

### 重复 ID 支持

```systemverilog
fifo.allow_dup = 1;
fifo.push(6'd2, data_x);
fifo.push(6'd2, data_y);  // 合法

entries = fifo.peek_all_by_id(6'd2);  // 返回两条
fifo.delete_by_id(6'd2);              // 两条全删
```

### ID 回绕场景

```systemverilog
// ID_WIDTH=4，序号已回绕
fifo.push(4'd7, data_old);  // 0b0111，较老
fifo.push(4'd8, data_new);  // 0b1000，已回绕，较年轻

// 清除比 rid=7 更年轻的条目（rid=8 会被清除）
fifo.flush_younger(4'd7);
```

## 约束与限制

1. **ID 空间**：in-flight 条目的 ID 跨度不能超过 ID 空间的一半（`2^(ID_WIDTH-1)`），否则回绕比较结果不正确
2. **非线程安全**：设计为单线程验证环境使用
3. **`peek_by_id` 在 `allow_dup=1` 时只返回第一个匹配**，需要全部结果时使用 `peek_all_by_id`
