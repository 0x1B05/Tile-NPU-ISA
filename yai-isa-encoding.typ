#import "yai-isa-style.typ": *

#show: setup

#align(center)[
  #v(18mm)
  #text(size: 22pt, weight: "bold")[Tile NPU 指令编码设计]
  #v(5mm)
  #text(size: 12pt)[指令格式与操作码分配 (草案)]
  #v(12mm)
  #line(length: 55%, stroke: 1.2pt + rgb("446e9b"))
]

#outline()

= 编码总则

== 指令字与类别位

所有指令定长 32-bit. 指令字最低两位 `[1:0]` 为类别标签:

#manual-table(
  columns: (1fr, 2fr, 3.5fr),
  caption: [类别位分配],
)[
  | `[1:0]` | 功能域         | 内容                                                              |
  | ------- | -------------- | ----------------------------------------------------------------- |
  | `11`    | 标量           | RV64IM, 译码按 RISC-V 规范                                        |
  | `00`    | 通用逐元素计算 | 逐元素算术/位运算/移位/比较/select/fmadd/特殊函数/mask 及广播变体 |
  | `01`    | 数据传输与重排 | 访存, fill, copy, 行和 lane 搬运, 转置                            |
  | `10`    | 跨域计算与控制 | mma, bdot, 规约, 转换, 量化, 配置, 同步, kernel.end               |
]

== 公共骨架 (T_R3, T_R4, T_RX, T_U)

```
  31   28 27  23 22  18 17  15 14  12 11   7 6    2 1  0
 [ op ][ B  ][ A  ][C3][m3][ f5 ][ D  ][ q ]
```

#manual-table(
  columns: (1.1fr, 1fr, 4fr),
  caption: [公共骨架字段],
)[
  | 位段      | 名称  | 含义                                                                                     |
  | --------- | ----- | ---------------------------------------------------------------------------------------- |
  | `[1:0]`   | q     | 类别标签 (见上表)                                                                        |
  | `[6:2]`   | D     | 目的寄存器编号, 5 bit; Tile/Acc 只用低 4 bit, 最高位为 0                                 |
  | `[11:7]`  | f5    | funct5, 类内操作选择; T_R4 中作为第三源 (C 或 M) 寄存器编号; 索引类立即数 (行号/lane 号) |
  | `[14:12]` | mode  | 变体选择: sat/wrap, 广播方向, 索引来源 (imm/xS), 访存形式等, 按 op 类解释                |
  | `[17:15]` | COND  | 比较条件 (仅 cmp 类); 其他指令为 0                                                       |
  | `[22:18]` | A     | 第一源寄存器编号, 5 bit                                                                  |
  | `[27:23]` | B     | 第二源寄存器编号, 5 bit; T_RX 中此槽位为 Scalar 源 `xS`                                  |
  | `[31:28]` | op    | 主操作码, 4 bit, 每个类别 16 个操作码类                                                  |
]

编码规则:

- 指令不包含 dtype 信息; 操作数元素类型由绑定的配置寄存器 (TC/AC/BC/VC) 给出.
- `op` 与 `f5` 两级构成操作码: `op` 为指令类, `f5` 为类内操作; 操作码类不足 16 时不再细分.
- 每个类别有独立的操作码命名空间; `q` 与 `op` 共同确定格式与译码模板.
- 编号位不足一个寄存器宽度的操作数 (Tile/Acc 4 bit) 写入字段低位, 高位为 0.
- mode 与 COND 在所有格式中占据相同位段.

== 立即数编码

- fill 立即数: T_U 立即数形式中 imm 占 `[27:12]` 共 16 bit. 整数域按目的 dtype 符号扩展; f32 域按 BF16 位模式解释为 f32 (BF16 可精确表示 0.0, -inf, 1.0 等常用值). *[待确认]*
- `cfg.seti` 立即数: 占 `[31:12]` 共 20 bit, 按目标字段宽度符号截断; 超过 20 bit 的配置值 (如 stride) 必须使用 `cfg.setx`.
- mask 的 fill 值: 以 `[17:12]` 的 6-bit 编码; 整数域符号扩展, f32 域从特殊值表 (0, +1, -1, +inf, -inf, qNaN) 选择. *[待确认]*

= 00: 通用逐元素计算

== T_R3: 三源逐元素

格式: `D = op(A, B)` 及其广播变体. `A` 在 `[22:18]`, `B` 在 `[27:23]`, 广播方向与 sat/wrap 由 mode 选择.

mode 编码:

#manual-table(
  columns: (1fr, 3fr),
  caption: [T_R3 mode 编码],
)[
  | mode    | 含义                                                          |
  | ------- | ------------------------------------------------------------- |
  | `00-`   | 普通形式 `D, A, B`                                            |
  | `01-`   | `.brow` 形式 `D, A, B[rb]`, 行号 rb 为立即数, 写入 `f5` 槽位  |
  | `10-`   | `.byrow` 形式 `D, A, S` (B 槽位为向量源)                      |
  | `11-`   | `.bycol` 形式 `D, A, S` (B 槽位为向量源)                      |
  | `--0`   | `wrap` (8-bit 域回绕) / 默认 (32-bit 域)                      |
  | `--1`   | `sat` (8-bit 域饱和)                                          |
]

#manual-table(
  columns: (1.2fr, 1fr, 2.2fr, 2.6fr),
  caption: [T_R3 操作码分配 (q = 00)],
)[
  | op      | f5          | 汇编形式                      | 含义                                               |
  | ------- | ----------- | ----------------------------- | -------------------------------------------------- |
  | `0000`  | `00000`     | `{t,a,b,v}add(.sat/.wrap)`    | 逐元素加法; 8-bit 域由 mode 最低位选 sat/wrap      |
  | `0000`  | `00001`     | `{t,a,b,v}sub(.sat/.wrap)`    | 逐元素减法                                         |
  | `0000`  | `00010`     | `{a,v}mul`                    | 逐元素乘法 (32-bit 域, wrap32/f32 规则)            |
  | `0000`  | `00011`     | `{a,v}div`                    | 逐元素除法 (仅 f32)                                |
  | `0001`  | `00000`     | `{t,a,b,v}min`                | 逐元素取小                                         |
  | `0001`  | `00001`     | `{t,a,b,v}max`                | 逐元素取大                                         |
  | `0010`  | `00000`     | `{t,a,b,v}and`                | 逐元素按位与 (不带类型后缀)                        |
  | `0010`  | `00001`     | `{t,a,b,v}or`                 | 逐元素按位或                                       |
  | `0010`  | `00010`     | `{t,a,b,v}xor`                | 逐元素按位异或                                     |
  | `0010`  | `00011`     | `{t,a,b,v}not`                | 逐元素按位取反 (单源, B 槽位为 0)                  |
  | `0011`  | `00000`     | `{t,a,b,v}shl`                | 逐元素左移 (整数域)                                |
  | `0011`  | `00001`     | `{t,a,b,v}shr`                | 逐元素逻辑右移                                     |
  | `0011`  | `00010`     | `{t,a,b,v}sra`                | 逐元素算术右移                                     |
  | `0100`  | `00000`     | `{a,v}abs`                    | 逐元素绝对值 (i32/f32)                             |
  | `0100`  | `00001`     | `{a,v}neg`                    | 逐元素取负 (i32/f32)                               |
]

广播变体与基础形式共享 op 与 f5, 仅 mode 不同. 汇编示例:

```asm
tadd.sat.i8        t0, t1, t2          # op=0000, f5=00000, mode=001
tadd.brow.sat.i8   t0, t1, t2[3]       # op=0000, f5=3,      mode=011
aaddv.byrow.f32    a0, a1, v0          # op=0000, f5=00000, mode=101
amulv.bycol.f32    a0, a1, v0          # op=0000, f5=00010, mode=111
```

== T_R4: 四源

`f5` 槽位作为第三源寄存器 (M 或 C).

#manual-table(
  columns: (1.2fr, 2.4fr, 2.6fr),
  caption: [T_R4 操作码分配 (q = 00)],
)[
  | op      | 汇编形式                        | 含义                                             |
  | ------- | ------------------------------- | ------------------------------------------------ |
  | `0101`  | `{t,a,b,v}select D, M, A, B`    | 按位选择: M 非零选 A, 否则选 B; M 为 u8/u32 mask |
  | `0110`  | `{a,v}fmadd.f32 D, A, B, C`     | f32 融合乘加, 单次舍入                           |
]

== T_RX: 寄存器 + Scalar 源

`B` 槽位 `[27:23]` 改写为 Scalar 源 `xS` (5 bit).

#manual-table(
  columns: (1.2fr, 1fr, 2.2fr, 2.6fr),
  caption: [T_RX 操作码分配 (q = 00)],
)[
  | op      | f5          | 汇编形式               | 含义                                     |
  | ------- | ----------- | ---------------------- | ---------------------------------------- |
  | `1000`  | `00000`     | `{t,a,b,v}addx`        | 逐元素加 Scalar 值; 8-bit 域 mode 选 sat |
  | `1000`  | `00001`     | `{t,a,b,v}subx`        | 逐元素减 Scalar 值                       |
  | `1000`  | `00010`     | `{a,v}mulx`            | 逐元素乘 Scalar 值                       |
  | `1000`  | `00011`     | `{a,v}divx`            | 逐元素除 Scalar 值 (仅 f32)              |
  | `1001`  | `00000`     | `{t,a,b,v}minx`        | 逐元素与 Scalar 值取小                   |
  | `1001`  | `00001`     | `{t,a,b,v}maxx`        | 逐元素与 Scalar 值取大                   |
  | `1010`  | `00000`     | `{t,a,b,v}andx`        | 逐元素与 Scalar 值按位与                 |
  | `1010`  | `00001`     | `{t,a,b,v}orx`         | 逐元素与 Scalar 值按位或                 |
  | `1010`  | `00010`     | `{t,a,b,v}xorx`        | 逐元素与 Scalar 值按位异或               |
  | `1011`  | `00000`     | `{t,a,b,v}shlx`        | 逐元素按 Scalar 值左移                   |
  | `1011`  | `00001`     | `{t,a,b,v}shrx`        | 逐元素按 Scalar 值逻辑右移               |
  | `1011`  | `00010`     | `{t,a,b,v}srax`        | 逐元素按 Scalar 值算术右移               |
]

== CMP: 比较

`f5` 选择寄存器形式 (`cmp`) 或 Scalar 形式 (`cmpx`, xS 占 B 槽位); 条件由 COND 给出.

#manual-table(
  columns: (1.2fr, 1fr, 2.4fr, 2.4fr),
  caption: [CMP 操作码与 COND 分配 (q = 00)],
)[
  | op      | f5      | 汇编形式              | 含义                                   |
  | ------- | ------- | --------------------- | -------------------------------------- |
  | `1100`  | `00000` | `{a,v}cmp.COND`       | 寄存器比较, 生成 u32 mask              |
  | `1100`  | `00001` | `{a,v}cmpx.COND`      | 与 Scalar 值比较, 生成 u32 mask        |
]

#manual-table(
  columns: (1fr, 2fr, 2.5fr),
  caption: [COND 编码],
)[
  | COND    | 汇编    | 含义                                   |
  | ------- | ------- | -------------------------------------- |
  | `000`   | `eq`    | 相等 (整数与 f32)                      |
  | `001`   | `ne`    | 不等 (仅整数; f32 由 eq 取反获得)      |
  | `010`   | `lt`    | 小于 (整数与 f32)                      |
  | `011`   | `ge`    | 大于等于 (仅整数; gt/le 交换操作数)    |
  | `100`   | `le`    | 小于等于 (仅 f32, `.le.f32`)           |
  | `101`   | `unord` | 无序 (仅 f32, `.unord.f32`)            |
  | `11-`   | —       | 预留                                   |
]

== SPEC: 近似特殊函数

`D = f(A)`, A 槽位 `[22:18]` 为源.

#manual-table(
  columns: (1.2fr, 1fr, 2.2fr, 2.6fr),
  caption: [SPEC 操作码分配 (q = 00)],
)[
  | op      | f5          | 汇编形式            | 含义              |
  | ------- | ----------- | ------------------- | ----------------- |
  | `1101`  | `00000`     | `{a,v}exp2.approx`  | 逐元素 2 的幂     |
  | `1101`  | `00001`     | `{a,v}rcp.approx`   | 逐元素倒数        |
  | `1101`  | `00010`     | `{a,v}rsqrt.approx` | 逐元素倒数平方根  |
]

== MASK: 结构化掩码

mask 需要目的, 源, 边界参数与 fill 值, 使用扩展布局:

```
 31   28 27  23 22  18 17    12 11   7 6    2 1  0
 [ op ][ xP1 ][ S  ][  fill  ][ f5 ][ D  ][ q ]
```

#manual-table(
  columns: (1.2fr, 1fr, 2.6fr, 2.6fr),
  caption: [MASK 操作码分配 (q = 00)],
)[
  | op      | f5      | 汇编形式                          | 含义                                  |
  | ------- | ------- | --------------------------------- | ------------------------------------- |
  | `1110`  | `00000` | `{t,a}mask.tail D, S, xRows, xCols, fill` | 保留坐标小于边界的源元素   |
  | `1110`  | `00001` | `{t,a}mask.tril D, S, xDelta, fill`       | 下三角 (j - i <= xDelta)   |
  | `1110`  | `00010` | `{t,a}mask.triu D, S, xDelta, fill`       | 上三角 (j - i >= xDelta)   |
  | `1110`  | `00011` | `{b,v}mask.tail D, S, xLen, fill`         | 保留 lane < xLen 的源元素  |
]

`xP1` 为第一个边界参数 (xRows/xDelta/xLen, 取 Scalar 编号); tail 的第二个边界 xCols 写入 `xP1` 的配对约定 *[待确认: 两参数均由 Scalar 提供]*; `fill` 为 6-bit 立即数, 按总则的 mask fill 编码解释.

= 01: 数据传输与重排

== T_M: 访存

T_M 操作数密集, 使用独立布局:

```
 31  27 26  22 21  17 16  12 11   7 6    2 1  0
 [ op ][xCol][xRow][xBase][descJ][ D  ][ q ]
```

#manual-table(
  columns: (1.2fr, 3fr, 2.6fr),
  caption: [T_M 操作码分配 (q = 01)],
)[
  | op      | 汇编形式                              | 含义                             |
  | ------- | ------------------------------------- | -------------------------------- |
  | `00000` | `tload tD, tmJ, xBase, xRow, xCol`    | 按 TM 读取到 Tile 有效区域       |
  | `00001` | `tstore tS, tmJ, xBase, xRow, xCol`   | 将 Tile 有效区域写入 TM          |
  | `00010` | `aload aD, tmJ, xBase, xRow, xCol`    | 按 TM 读取到 Acc 有效区域        |
  | `00011` | `astore aS, tmJ, xBase, xRow, xCol`   | 将 Acc 有效区域写入 TM           |
  | `00100` | `tload.row tD[rd], tmJ, ...`          | 读取到 Tile 指定行; rd 取 xCol 槽位 *[待确认]* |
  | `00101` | `tstore.row tS[rs], tmJ, ...`         | 将 Tile 指定行写入 TM            |
  | `00110` | `aload.row aD[rd], tmJ, ...`          | 读取到 Acc 指定行                |
  | `00111` | `astore.row aS[rs], tmJ, ...`         | 将 Acc 指定行写入 TM             |
  | `01000` | `bload bD, vmJ, xBase, xIndex`        | 按 VM 读取 Vec8                  |
  | `01001` | `bstore bS, vmJ, xBase, xIndex`       | 将 Vec8 写入 VM                  |
  | `01010` | `vload vD, vmJ, xBase, xIndex`        | 按 VM 读取 Vec32                 |
  | `01011` | `vstore vS, vmJ, xBase, xIndex`       | 将 Vec32 写入 VM                 |
]

向量形式 (`bload` 等) 的 `xRow` 槽位为 `xIndex`, `xCol` 槽位为 0. `descJ` 5 bit: `tm0..15` 与 `vm0..31` 共用槽位, 由 op 区分描述符类型.

== T_U: 初始化, 复制与转置

`f5` 选择操作; 立即数形式的 imm 占 `[27:12]` (16 bit, 见总则).

#manual-table(
  columns: (1.2fr, 1fr, 2.6fr, 2.6fr),
  caption: [T_U 操作码分配 (q = 01)],
)[
  | op      | f5          | 汇编形式            | 含义                                    |
  | ------- | ----------- | ------------------- | --------------------------------------- |
  | `0000`  | `00000`     | `{t,a,b,v}fill`     | 立即数填入有效区域 (imm 形式)           |
  | `0000`  | `00001`     | `{t,a,b,v}fillx`    | 用 Scalar 值填充 (xS 占 B 槽位)         |
  | `0001`  | `00000`     | `{t,a,b,v}copy D, S`| 复制同域寄存器的有效数据 (S 占 A 槽位)  |
  | `0010`  | `00000`     | `ttranspose tD, tS` | Tile 转置 (仅 8-bit Tile)               |
]

== T_RXM: 行搬运与 lane 操作

索引 (行号/lane 号) 可来自立即数或 Scalar: mode 最低位选择来源, 为 0 时索引为 `f5` 槽位的立即数, 为 1 时索引取 `f5` 槽位的 Scalar 编号.

#manual-table(
  columns: (1.2fr, 1fr, 2.8fr, 2.4fr),
  caption: [行搬运与 lane 操作操作码分配 (q = 01)],
)[
  | op      | f5        | 汇编形式                    | 含义                                     |
  | ------- | --------- | --------------------------- | ---------------------------------------- |
  | `0011`  | rd        | `{t,a}insert.row tD[rd], S` | 将向量写入矩阵指定行 (S 占 A 槽位)       |
  | `0100`  | rs        | `{t,a}extract.row D, S[rs]` | 将矩阵指定行读入向量 (S 占 A 槽位)       |
  | `0101`  | lane      | `{b,v}extract xD, S[lane]`  | 将指定 lane 提取到 Scalar (xD 占 D 槽位) |
  | `0110`  | lane      | `{b,v}insert D[lane], xS`   | 将 Scalar 值写入指定 lane                |
  | `0111`  | lane      | `{b,v}broadcast D, S[lane]` | 将源的一个 lane 广播到目的有效区域       |
]

= 10: 跨域计算与控制

== MMA 与 BDOT

T_R3 形态: `aD, tA, tB` 或 `vD, bA, tB`.

#manual-table(
  columns: (1.2fr, 1fr, 1.2fr, 2.8fr),
  caption: [MMA/BDOT 操作码分配 (q = 10)],
)[
  | op      | f5        | mode        | 汇编形式                  |
  | ------- | --------- | ----------- | ------------------------- |
  | `0000`  | `00000`   | `00`        | `mma.nn.zero.i8.i32`      |
  | `0000`  | `00000`   | `01`        | `mma.nn.acc.i8.i32`       |
  | `0000`  | `00001`   | `00`        | `mma.nt.zero.i8.i32`      |
  | `0000`  | `00001`   | `01`        | `mma.nt.acc.i8.i32`       |
  | `0001`  | `00000`   | `00`        | `bdot.nn.i8.i32`          |
  | `0001`  | `00001`   | `00`        | `bdot.nt.i8.i32`          |
]

mode 最低位: 0 = zero (写新 Acc), 1 = acc (累加); f5: 00000 = nn, 00001 = nt (右 Tile 逻辑转置).

== RED: 规约

T_U 形态: `vD, aS` 或 `xD, vS`.

#manual-table(
  columns: (1.2fr, 1fr, 2.4fr, 2.6fr),
  caption: [RED 操作码分配 (q = 10)],
)[
  | op      | f5          | 汇编形式                 | 含义                            |
  | ------- | ----------- | ------------------------ | ------------------------------- |
  | `0010`  | `00000`     | `areduce.rows.sum.f32`   | Acc 按行求和到 Vec32            |
  | `0010`  | `00001`     | `areduce.rows.max.f32`   | Acc 按行取最大                  |
  | `0010`  | `00010`     | `areduce.rows.min.f32`   | Acc 按行取最小                  |
  | `0010`  | `00011`     | `areduce.rows.sumsq.f32` | Acc 按行平方和                  |
  | `0011`  | `00000`     | `vreduce.sum.f32`        | Vec32 求和到 Scalar             |
  | `0011`  | `00001`     | `vreduce.max.f32`        | Vec32 取最大到 Scalar           |
  | `0011`  | `00010`     | `vreduce.min.f32`        | Vec32 取最小到 Scalar           |
  | `0011`  | `00011`     | `vreduce.sumsq.f32`      | Vec32 平方和到 Scalar           |
  | `0011`  | `00100`     | `vreduce.argmax.f32`     | argmax, 输出索引与位模式两个 Scalar; 变体布局 *[待确认]* |
]

== CVT: 类型转换与扩大

T_U 形态: `D, S`.

#manual-table(
  columns: (1.2fr, 1fr, 2.4fr, 2.6fr),
  caption: [CVT 操作码分配 (q = 10)],
)[
  | op      | f5          | 汇编形式         | 含义                          |
  | ------- | ----------- | ---------------- | ----------------------------- |
  | `0100`  | `00000`     | `acvt.i32.f32`   | Acc 中 i32 逐元素转 f32       |
  | `0100`  | `00001`     | `vcvt.i32.f32`   | Vec32 中 i32 逐 lane 转 f32   |
  | `0100`  | `00010`     | `twiden.i8.i32`  | Tile 的 i8 符号扩展到 Acc i32 |
]

== QNT: 量化与反量化

T_R3 双目的变体: bits 与 scale 是两个显式目的/源. 目的寄存器按助记符首字母写入 D 槽位, scale 寄存器写入 A 槽位.

#manual-table(
  columns: (1.2fr, 1fr, 3fr, 2.4fr),
  caption: [QNT 操作码分配 (q = 10)],
)[
  | op      | f5          | 汇编形式                              | 含义                            |
  | ------- | ----------- | ------------------------------------- | ------------------------------- |
  | `0101`  | `00000`     | `tquant.rows.q8s32 tD, vScale, aS`    | Acc 按行量化到 Tile + Vec32 scale |
  | `0101`  | `00001`     | `vquant.q8s32 bD, vScale[lane], vS`   | Vec32 量化到 Vec8 + scale lane    |
  | `0101`  | `00010`     | `tdequant.rows.f32 aD, tS, vScale`    | 按行 scale 将 Tile 反量化到 f32 Acc |
  | `0101`  | `00011`     | `bdequant.f32 vD, bS, vScale[lane]`   | 将 Vec8 反量化到 f32 Vec32        |
]

`vquant`/`bdequant` 的 scale lane 号写入 `f5` 槽位 (立即数).

== T_C: 配置

独立布局:

```
 31     12 11   7 6    2 1  0
 [  imm  ][field][ C  ][ q ]
```

#manual-table(
  columns: (1.2fr, 3fr, 2.6fr),
  caption: [T_C 操作分配 (q = 10)],
)[
  | 形式        | 布局                                        | 含义                                     |
  | ----------- | ------------------------------------------- | ---------------------------------------- |
  | `cfg.seti`  | `op` 于 `[31:28]`, imm 于 `[27:12]`         | 立即数写入配置字段 (20 bit, 符号截断)    |
  | `cfg.setx`  | 同上, `[11:7]` 为 Scalar 编号               | 从 Scalar 写入完整配置值                 |
  | `cfg.copy`  | `[6:2]` = `C_D`, `[11:7]` = `C_S`           | 复制同类型配置寄存器全部字段             |
  | `cfg.get`   | `[6:2]` = `xD`, `[11:7]` = `C`, `[16:12]` = field | 读取配置字段到 Scalar                |
]

`field` 字段编号 (5 bit) 映射: 0 = dtype, 1 = rows, 2 = cols, 3 = layout, 4 = len, 5 = storage_dtype, 6 = transform, 7 = flags, 8 = row_stride_bytes, 9 = col_stride_bytes, 10 = length, 11 = stride_bytes; 其余预留. *[待确认]*

== T_S: 同步与系统

近零操作数, 以 op + f5 区分:

#manual-table(
  columns: (1.2fr, 1fr, 2.2fr, 2.6fr),
  caption: [T_S 操作码分配 (q = 10)],
)[
  | op      | f5          | 汇编形式    | 含义                             |
  | ------- | ----------- | ----------- | -------------------------------- |
  | `1111`  | `00000`     | `fence.mem` | 等待此前访存完成并达到约定可见点 |
  | `1111`  | `00001`     | `fence.sa`  | 等待此前 SA 操作完成             |
  | `1111`  | `00010`     | `fence.all` | 等待此前全部后端工作完成         |
  | `1111`  | `00011`     | `kernel.end`| 报告 kernel 完成, 隐含 fence.all |
  | `1110`  | `00000`     | `getcap`    | 查询资源规格, 扩展和数值能力; 操作数与返回字段待定义 |
]

= 待确认的设计点

1. 两级操作码: `op[31:28]` (16 类) + `f5[11:7]` (32 操作). 是否接受; 或改为扁平 7-9 bit 操作码.
2. fill 的 f32 立即数: 以 BF16 位模式编码 (可精确表示 0.0/-inf/1.0 等常用值), 整数按 16-bit 符号扩展. 是否接受.
3. mask 的两个边界参数: tail 需要 xRows 与 xCols 两个 Scalar 参数, 当前只有 `xP1` 一个槽位; 是由两个 Scalar 寄存器提供, 还是第二个参数改为立即数.
4. `tload.row` 的行号 rd: 建议取 `xCol` 槽位 (行形式的列坐标通常闲置或由行号复用), 或单列一个 5-bit 索引槽位压缩 `descJ`.
5. mask fill 的 6-bit 特殊值表 (0, +1, -1, ±inf, qNaN) 与整数符号扩展的混合编码.
6. `vreduce.argmax` 变体布局: 输出为两个 Scalar (xIndex, xValue), 建议 D 槽位为 xIndex, A 槽位为 xValue, vS 占 B 槽位.
7. T_C `field` 编号映射: 是否按上文 0-11 分配.
