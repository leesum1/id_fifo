# sys_reg_snap: 系统寄存器历史快照追踪器

## 问题背景

在乱序执行处理器中，MSR 指令**执行时就立即更新**系统寄存器（SYS_REG）的 wire 值。当一条较年轻的 MSR 先于一条较老的指令执行时，wire 已被修改，导致较老指令在提交时无法从 wire 上采样到正确的值。

### 示例场景

```
初始状态: SYS_REG1 wire = 20

程序顺序:
  指令 1 (rid=1): ADD        ← 较老，提交时需要看到 SYS_REG1 = 20
  指令 2 (rid=2): MSR 10, SYS_REG1  ← 较年轻，执行时将 wire 改为 10
```

**实际执行**：MSR（rid=2）先执行，wire 立即变为 10。ADD（rid=1）提交时 wire = 10，但它应看到 **20**。

## 设计原理

**核心约束**：MSR 指令**顺序执行**（按程序顺序）。

**关键洞察**：每次 MSR 执行前，wire 上的值恰好是所有更老的 MSR 都已写完后的值。因此只需在每次 MSR 执行时记录 **写入前的 wire 值（pre_value）**，无需记录写入后的新值。

对于 `query_rid`，正确答案是：**最老的（最小 RID）且严格比 query_rid 年轻**的 MSR 记录的 `pre_value`。

```
记录:
  rid=2, pre=20   ← MSR(rid=2) 执行前 wire=20（所有比 rid=2 更老的 MSR 写完后）
  rid=5, pre=10   ← MSR(rid=5) 执行前 wire=10（rid=2 写完后）

查询:
  query_rid=1 → 找比 rid=1 更年轻的记录: {rid=2, rid=5} → 最老 = rid=2 → pre=20 ✓
  query_rid=3 → 找比 rid=3 更年轻的记录: {rid=5}        → 最老 = rid=5 → pre=10 ✓
  query_rid=7 → 没有更年轻的记录                         → miss, wire 正确 ✓
```

如果没有比 `query_rid` 更年轻的 MSR → miss，直接使用当前 wire（无任何 in-flight MSR 影响过此寄存器）。

## 核心概念

### RID（Resource ID）

每条指令分配唯一的 RID，用于标识程序顺序中的新老关系。RID 采用 wrap-around 设计：

- **MSB** 为 wrap bit（回绕位）
- **低位** 为序号值
- 比较规则：wrap bit 相同时，值大 = 更年轻；wrap bit 不同时，值小 = 更年轻

## API 说明

### 参数化

```systemverilog
sys_reg_snap #(
  .ID_WIDTH   (6),   // RID 位宽，MSB 为 wrap bit
  .REG_WIDTH  (64),  // 寄存器数据位宽
  .ADDR_WIDTH (8)    // 寄存器地址位宽
) snap = new("my_snap");
```

### `record_update(rid, reg_addr, pre_value)`

在 MSR 指令执行（更新 wire）**之前**调用，记录当前 wire 值。

- `pre_value`：MSR 写入前的当前 wire 值
- **约束**：同一 `(rid, reg_addr)` 对不得重复插入（会触发 `$fatal`）
- 同一 RID 写不同寄存器是合法的（一条指令可修改多个 SYS_REG）

### `get_value_at(query_rid, reg_addr, output value) → bit`

查询 `query_rid` 视角下 `reg_addr` 的正确值。

| 情况 | 返回 | value | 说明 |
|------|------|-------|------|
| 有比 query_rid 更年轻的 MSR 记录 | 1 | 最老那条记录的 pre_value | 直接使用 |
| 无比 query_rid 更年轻的 MSR 记录 | 0 | 无效 | 使用当前 wire（正确） |

### `get_snapshot_at(query_rid) → snap_queue_t`

返回 `query_rid` 视角下所有需要矫正的寄存器及其正确值。无需矫正的寄存器（wire 已正确）不包含在结果中。

### `retire(retire_rid)`

清理所有 RID ≤ `retire_rid` 的记录。已退休的记录不可能再被查询（未来的查询来自更年轻的指令），因此可以安全释放。

### 辅助函数

| 函数 | 说明 |
|------|------|
| `size()` | 当前记录数 |
| `empty()` | 是否为空 |
| `dump()` | 打印所有记录（调试用） |

## 统计信息（仅 dump 可见）

`sys_reg_snap` 内部维护了一组统计计数器（`int`），用于在调试时快速判断 record / query / retire / snapshot 的覆盖情况。

- 这些计数器**只通过 `dump()` 的 `$display` 输出暴露**，不作为稳定的对外 API 使用。
- 不要在 TB 里依赖读取这些成员变量来驱动功能逻辑，它们主要用于观测和回归定位。

计数器列表（名字与含义）：

- `stat_record_cnt`：累计 `record_update()` 调用次数
- `stat_retire_cnt`：累计 retire 掉的记录条目数（不是调用次数）
- `stat_query_hit_cnt`：累计 `get_value_at()` 命中次数
- `stat_query_miss_cnt`：累计 `get_value_at()` 未命中次数
- `stat_peak_size`：历史峰值记录数（`records.size()` 的最大值）
- `stat_snapshot_cnt`：累计 `get_snapshot_at()` 调用次数

查看方式：调用 `dump()`，输出中会包含上述 `stat_*` 字段。

## 随机压力测试（TB）约定

### 固定随机种子

随机压力测试必须可复现。

- TB 内使用固定默认种子，例如：`localparam int DEFAULT_SEED = 99;`
- 在任何随机化之前打印：`$display("SEED=%0d", DEFAULT_SEED);`
- 然后显式播种：`void'($urandom(DEFAULT_SEED));`
- 需要扩展压力时，可以通过修改 TB 常量来改变种子，不通过命令行或运行时参数注入种子

### RID 分配规则（半空间安全 + 单调）

随机测试里**禁止**直接随机生成 RID。

- RID 必须按程序顺序单调分配（monotonic allocation），以满足 wrap-around 比较的前提
- 任意时刻 live（in-flight）RID 的跨度必须不超过 RID 空间的一半，即 `2^(ID_WIDTH-1)`
  - 超过半空间会导致回绕比较语义不再可靠

### `(rid, reg_addr)` 唯一性

随机测试必须遵守实现的硬约束：同一 `(rid, reg_addr)` 对不得重复插入。

- 做随机 `record_update()` 时，需要在 TB 侧避免对同一 rid 重复写同一 reg_addr
- 允许同一 rid 写不同 reg_addr（模拟一条指令更新多个 SYS_REG）

## 使用流程

```
时间 ─────────────────────────────────────────────────────────►

  ┌─────────────────────────────────────────────────────────┐
  │ 初始状态: SYS_REG1 wire = 20                             │
  └─────────────────────────────────────────────────────────┘

  ① MSR(rid=2) 即将执行，wire 尚未被修改
     → snap.record_update(rid=2, SYS_REG1, pre=20)
     → MSR 执行，wire 变为 10

  ② ADD(rid=1) 提交，需要 SYS_REG1 的值
     → hit = snap.get_value_at(rid=1, SYS_REG1, val)
     → hit = 1: rid=2 比 rid=1 更年轻 → 返回 pre=20 ✅

  ③ MSR(rid=2) 提交
     → snap.retire(rid=2)
     → 记录清除，wire=10 即为正确的提交值
```

### 多条 MSR 场景

```
初始 wire: SYS_REG1 = 20

① MSR(rid=2) 执行前: record_update(2, REG1, pre=20)，wire 变为 10
② MSR(rid=5) 执行前: record_update(5, REG1, pre=10)，wire 变为 30
```

| 查询 | 更年轻的记录 | 最老者 | 结果 |
|------|------------|--------|------|
| `get_value_at(rid=1)` | rid=2, rid=5 | rid=2 | **hit**, val=20 |
| `get_value_at(rid=3)` | rid=5 | rid=5 | **hit**, val=10 |
| `get_value_at(rid=7)` | 无 | - | **miss**, 用 wire(30) |

## 约束与限制

1. **MSR 必须顺序执行**：这是本设计的核心前提，保证 pre_value 的语义正确
2. **`record_update` 时序**：必须在 MSR 更新 wire **之前**调用
3. **`(rid, reg_addr)` 唯一性**：同一 RID 不能对同一寄存器写入两次（断言保护）
4. **同一 RID 可写不同寄存器**：一条指令修改多个 SYS_REG 是合法的
5. **RID 空间有限**：依赖 wrap-around 比较，in-flight 指令不超过 RID 空间的一半
6. **非线程安全**：设计为单线程验证环境使用
