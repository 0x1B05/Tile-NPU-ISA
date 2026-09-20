#import "yai-isa-style.typ": *

#show: setup

#align(center)[
  #v(18mm)
  #text(size: 22pt, weight: "bold")[Tile NPU 指令编码设计]
  #v(5mm)
  #text(size: 12pt)[指令格式与操作码分配]
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
  | `[1:0]`  | 功能域          | 内容                                                               |
  | -------- | --------------- | ------------------------------------------------------------------ |
  | `11`     | 标量            | RV64IM, 译码按 RISC-V 规范                                         |
  | `00`     | 通用逐元素计算  | 逐元素算术/位运算/移位/比较/select/fmadd/特殊函数/mask 及广播变体  |
  | `01`     | 数据传输与重排  | 访存, fill, copy, 行和 lane 搬运, 转置                             |
  | `10`     | 跨域计算与控制  | mma, bdot, 规约, 转换, 量化, 配置, 同步, kernel.end                |
]

#note[
  设计理念: 操作码分层 (`op[31:28]` 大类 + 类内子操作码); 静态信息 (dtype, shape, 描述符) 放配置寄存器, 动态信息 (操作数, 行号, 边界) 放指令和 Scalar 操作数.
]

== 操作码结构 (按格式)

#manual-table(
  columns: (1.2fr, 2fr, 3.4fr),
  caption: [各格式的操作码结构],
)[
  | 格式  | 操作码结构              | 说明                                                           |
  | ----- | ----------------------- | -------------------------------------------------------------- |
  | T_R3  | `op4 + funct5`          | 三源计算; funct5 为类内操作选择                                |
  | T_R4  | `op4 + funct5`          | 四源计算; funct5 槽位作为第三源 (C/M) 寄存器                   |
  | T_RX  | `op4 + funct5`          | 寄存器 + Scalar 源; funct5 为类内操作选择                      |
  | T_U   | `op4 + funct5`          | 一元/两元操作; funct5 为类内操作选择; argmax 为 T_U2 变体      |
  | T_M   | `op4 + mode1`           | 访存; 坐标打包为 `xRowCol`, 不使用 funct5                      |
  | T_MR  | `op4 + mode1`           | 行访存; 坐标打包为 `xRowCol`, rd/rs 独立字段                   |
  | T_C   | `op4 + field + imm/xS`  | 配置; seti/setx/copy/get 各占一个 op 类, field 为全局字段编号  |
  | T_S   | `op4 + funct5`          | 同步与系统; funct5 区分 fence/getcap/kernel.end                |
]

== 指令格式位段

公共骨架 (T_R3, T_R4, T_RX, T_U):

```
31   28 27   23 22   18 17   15 14   12 11     7 6   2 1   0
[ op  ] [  B  ] [  A  ] [ SUB ] [ m3  ] [funct5] [ D ] [ q ]
```

#manual-table(
  columns: (1fr, 1fr, 1fr, 4fr),
  caption: [公共骨架字段],
)[
  | 位段       | 名称    | 位宽  | 含义                                                                                                            |
  | ---------- | ------- | ----- | --------------------------------------------------------------------------------------------------------------- |
  | `[1:0]`    | q       | 2bit  | 类别标签                                                                                                        |
  | `[6:2]`    | D       | 5bit  | 目的寄存器编号; Tile/Acc 只用低 4 bit, 最高位为 0                                                               |
  | `[11:7]`   | funct5  | 5bit  | 类内具体操作选择; T_R4 中作为第三源 (C 或 M); 广播行号 rb/索引类立即数                                          |
  | `[14:12]`  | mode    | 3bit  | 变体选择: 广播方向, 源形式 (reg/xS 或 imm/xS), 按 op 类解释                                                     |
  | `[17:15]`  | SUB     | 3bit  | 物理共享子字段; cmp 类中别名 COND (比较条件), brow BIT/SHIFT 类中 `SUB[1:0]` 为 BITOP/SHIFTOP, 其余为 0 或保留  |
  | `[22:18]`  | A       | 5bit  | 第一源寄存器编号, 5 bit                                                                                         |
  | `[27:23]`  | B       | 5bit  | 第二源寄存器编号, 5 bit; T_RX 中此槽位为 Scalar 源 `xS`                                                         |
  | `[31:28]`  | op      | 4bit  | 主操作码, 4 bit, 区分大类, 每个类别 16 个操作码类                                                               |
]

寄存器编号位宽: Tile/Acc/TM 描述符 4 bit, Vec8/Vec32/Scalar/VM 描述符 5 bit.

全部非标量格式的位段布局汇总如下.

T_U-imm (fill 立即数形式):

```
31   28 27   12 11   7 6   2 1   0
[ op  ] [ imm ] [ f5 ] [ D ] [ q ]
```

MASK (结构化掩码):

```
31   28 27   23 22   18 17   12 11   7 6   2 1   0
[ op  ] [xBnd ] [  S  ] [fill ] [ f5 ] [ D ] [ q ]
```

T_M (整块与向量访存):

```
31   28 27   23 22      18 17   13 12  11    7 6   2 1   0
[ op  ] [xBase] [xRC/xIdx] [ rsv ] [m] [descJ] [ D ] [ q ]
```

T_MR (行访存):

```
31   28 27   23 22   18 17   13 12  11    7 6   2 1   0
[ op  ] [xBase] [ xRC ] [rd/rs] [m] [descJ] [ D ] [ q ]
```

T_C (配置):

```
31   28 27    12 11    7 6   2 1   0
[ op  ] [imm/xS] [field] [ C ] [ q ]
```

T_S (同步与系统):

```
31   28 27      12 11   7 6   2 1   0
[ op  ] [reserved] [ f5 ] [ D ] [ q ]
```

== 立即数编码

=== fill 立即数 (16 bit)

T_U 立即数形式中 imm 占 `[27:12]` 共 16 bit. 整数域按目的 dtype 解释 (i8/i32 符号扩展, u8/u32 零扩展); f32 域携带一个 16-bit BF16 位模式, 执行时按 `f32_bits = bf16_imm << 16` 精确扩展为 f32.

#manual-table(
  columns: (1.2fr, 1.2fr, 2.8fr),
  caption: [BF16 立即数常用值],
)[
  | BF16 位模式  | f32 结果  | 说明       |
  | ------------ | --------- | ---------- |
  | `0x0000`     | `+0.0`    |            |
  | `0x8000`     | `-0.0`    |            |
  | `0x3f80`     | `+1.0`    |            |
  | `0xbf80`     | `-1.0`    |            |
  | `0x7f80`     | `+inf`    |            |
  | `0xff80`     | `-inf`    |            |
  | `0x7fc0`     | qNaN      | canonical  |
]

#note[
  该字段只能携带 BF16 可表示值. 汇编器接受常量形式但内部明确执行 BF16 转换, 对不能精确表示的字面量给出警告或错误; 任意 32-bit f32 位模式可以使用 `fillx.f32` 由 Scalar 提供.
]

=== mask fill 编码 (6 bit)

mask 的 fill 值占 `[17:12]` 共 6 bit, 按目的 dtype 解释:

#manual-table(
  columns: (1.2fr, 3.6fr),
  caption: [mask fill6 解释],
)[
  | 目的 dtype  | 解释                                  |
  | ----------- | ------------------------------------- |
  | `i8/i32`    | 6-bit 二进制补码, 符号扩展到目标宽度  |
  | `u8/u32`    | 6-bit 无符号值, 零扩展到目标宽度      |
  | `f32`       | 按特殊值表解释 (见下)                 |
]

#manual-table(
  columns: (1.2fr, 1.4fr, 2.6fr),
  caption: [mask fill6 的 f32 特殊值表],
)[
  | fill6   | f32 结果  | 说明       |
  | ------- | --------- | ---------- |
  | `0x00`  | `+0.0`    |            |
  | `0x01`  | `-0.0`    |            |
  | `0x02`  | `+1.0`    |            |
  | `0x03`  | `-1.0`    |            |
  | `0x04`  | `+inf`    |            |
  | `0x05`  | `-inf`    |            |
  | `0x06`  | qNaN      | canonical  |
  | 其余    | 预留      |            |
]

6-bit 只覆盖常见值; 任意 fill 值使用 `maskx` 形式, 由 Scalar 提供完整值.

=== `cfg.seti` 立即数

占 `[27:12]` 共 16 bit, 按目标字段宽度符号截断; 超过该宽度的配置值 (如 stride) 必须使用 `cfg.setx`.

== Scalar 打包操作数

二维边界与坐标打包到一个 64-bit Scalar 寄存器:

#manual-table(
  columns: (1.2fr, 1.8fr, 1.6fr, 2.4fr),
  caption: [Scalar 打包操作数],
)[
  | 打包名     | 低 32 bit `[31:0]`  | 高 32 bit `[63:32]`  | 语义域            |
  | ---------- | ------------------- | -------------------- | ----------------- |
  | `xBounds`  | `nRows`             | `nCols`              | 寄存器内坐标边界  |
  | `xRowCol`  | `row`               | `col`                | 内存 view 坐标    |
]

#note[
  - `xRowCol` 是内存 view 坐标, 寻址范围与 TM.rows/cols 同量级 (可达数千), 需要全 32 bit.
  - `xBounds` 是寄存器内坐标边界, 只与寄存器内行列号 (0..31) 比较, 有效范围 0..32. 若将寄存器内行列号放在指令内, 指令空间不够, 且扩展性不高.
]

= 00: 通用逐元素计算

== 骨架与 op 类总表

`q = 00` 的 op 类 (4 bit, 16 类):

#manual-table(
  columns: (1fr, 1.6fr, 3.6fr),
  caption: [00 类别 op 类分配],
)[
  | op      | 类      | 覆盖                                                  |
  | ------- | ------- | ----------------------------------------------------- |
  | `0000`  | ADD     | `{t,a,b,v}add`, `addx`                                |
  | `0001`  | SUB     | `{t,a,b,v}sub`, `subx`                                |
  | `0010`  | MUL     | `{a,v}mul`, `mulx`, 广播变体                          |
  | `0011`  | DIV     | `{a,v}div`, `divx`, 广播变体 (仅 f32)                 |
  | `0100`  | MIN     | `{t,a,b,v}min`, `minx`, 广播变体                      |
  | `0101`  | MAX     | `{t,a,b,v}max`, `maxx`, 广播变体                      |
  | `0110`  | BIT     | `{t,a,b,v}and/or/xor/not`, `andx/orx/xorx`, 广播变体  |
  | `0111`  | SHIFT   | `{t,a,b,v}shl/shr/sra`, `shlx/shrx/srax`, 广播变体    |
  | `1000`  | ABSNEG  | `{a,v}abs`, `{a,v}neg`                                |
  | `1001`  | SPEC    | `{a,v}exp2.approx`, `rcp.approx`, `rsqrt.approx`      |
  | `1010`  | CMP     | `{a,v}cmp.COND`, `{a,v}cmpx.COND`                     |
  | `1011`  | SELECT  | `{t,a,b,v}select`                                     |
  | `1100`  | FMADD   | `{a,v}fmadd.f32`                                      |
  | `1101`  | MASK    | `{t,a,b,v}mask.*`, `maskx.*`                          |
  | `111-`  | 预留    |                                                       |
]

== mode 编码

#manual-table(
  columns: (1fr, 3.6fr),
  caption: [00 类别 mode 编码],
)[
  | mode 位      | 含义                                                                                                                          |
  | ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
  | `[2]` src    | 源形式: plain 时选择第二源为 B 寄存器 (0) 或 Scalar `xS` (1);#linebreak() brow 时选择 rb 为立即数 (0) 或 Scalar 编号 (1), 均取自 f5 槽位  |
  | `[1:0]` dir  | 操作形态: `00` plain, `01` brow, `10` byrow, `11` bycol                                                                       |
]

== SUB 按类解释

物理字段 `[17:15]` 命名为 `SUB` (共享子字段, 3 bit), 语义按指令族解释; 比较指令中别名 `COND`. `SUB[1:0]` 的低 2 bit 在 brow 的 BIT/SHIFT 类中用作操作选择, 编码 `11` 保留.

#manual-table(
  columns: (1.4fr, 3.6fr),
  caption: [00 类别 SUB 按类解释],
)[
  | 指令族         | `SUB` 含义                                                                    |
  | -------------- | ----------------------------------------------------------------------------- |
  | ADD, SUB       | 保留为 0                                                                      |
  | BIT 非 brow    | 保留为 0; 操作由 f5 选择                                                      |
  | SHIFT 非 brow  | 保留为 0; 操作由 f5 选择                                                      |
  | BIT brow       | `SUB[1:0]` = BITOP: `00` and, `01` or, `10` xor, `11` 保留; `SUB[2]` 为 0     |
  | SHIFT brow     | `SUB[1:0]` = SHIFTOP: `00` shl, `01` shr, `10` sra, `11` 保留; `SUB[2]` 为 0  |
  | CMP            | `SUB` = COND 比较条件 (见 CMP 节的 COND 编码表)                               |
  | 其余类         | 为 0 或保留                                                                   |
]

#note[
  解码顺序: `mode == BROW` 必须先于 f5 解释. class 为 BIT 或 SHIFT 且 `mode == BROW` 时, f5 表示行号 rb, 操作选择读 `SUB[1:0]`; 其他情况下 f5 表示操作, `SUB` 按上表处理. 非零的无效组合 (如 BITOP/SHIFTOP 编码 `11`) 必须被汇编器拒绝, 解码器按保留编码处理.
]

brow BIT/SHIFT 的编码示例:

```asm
tand.brow tD, tA, tB[rb]    # op=BIT,   mode=BROW, f5=rb, SUB[1:0]=00 (and)
tor.brow  tD, tA, tB[rb]    # op=BIT,   mode=BROW, f5=rb, SUB[1:0]=01 (or)
txor.brow tD, tA, tB[rb]    # op=BIT,   mode=BROW, f5=rb, SUB[1:0]=10 (xor)

tshl.brow tD, tA, tB[rb]    # op=SHIFT, mode=BROW, f5=rb, SUB[1:0]=00 (shl)
tshr.brow tD, tA, tB[rb]    # op=SHIFT, mode=BROW, f5=rb, SUB[1:0]=01 (shr)
tsra.brow tD, tA, tB[rb]    # op=SHIFT, mode=BROW, f5=rb, SUB[1:0]=10 (sra)
```

== 各 op 类指令

=== ADD, SUB, MUL, DIV, MIN, MAX (单操作类)

`D = op(A, B)`; f5 空闲, 在 brow 形式 (`dir = 01`) 中作为行号 rb (5-bit 立即数) 或 rb 的 Scalar 编号 (由 mode.src 选择).

#manual-table(
  columns: (1.6fr, 1.4fr, 3.2fr),
  caption: [单操作类汇编形式],
)[
  | 汇编形式                          | op       | 含义                                                     |
  | --------------------------------- | -------- | -------------------------------------------------------- |
  | `tadd.sat.i8 t0, t1, t2`          | ADD      | Tile 逐元素饱和加; mode.dir=00, 配置 `arith_mode = sat`  |
  | `tadd.wrap.i8 t0, t1, t2`         | ADD      | Tile 逐元素回绕加; 配置 `arith_mode = wrap`              |
  | `aadd.f32 a0, a1, a2`             | ADD      | Acc 逐元素 f32 加                                        |
  | `vaddx.f32 v0, v1, x4`            | ADD      | Vec32 逐元素加 Scalar 值; mode.src=1                     |
  | `tadd.brow.sat.i8 t0, t1, t2[3]`  | ADD      | 右矩阵第 3 行广播后逐元素饱和加; f5=3, dir=01            |
  | `aaddv.byrow.f32 a0, a1, v0`      | ADD      | 按行广播 Vec32 后逐元素加; dir=10                        |
  | `amulv.bycol.f32 a0, a1, v0`      | MUL      | 按列广播 Vec32 后逐元素乘; dir=11                        |
  | `adiv.f32 / adivx.f32`            | DIV      | 仅 f32                                                   |
  | `tmin/tmax`, `{a,v}min/max`       | MIN/MAX  | 逐元素取小/取大                                          |
]

=== BIT (按位)

`D = A bitop B`; f5 为操作选择; 不带类型后缀, 对域内任意 dtype 按位操作.

#manual-table(
  columns: (1fr, 1.6fr, 3fr),
  caption: [BIT 类 f5 编码 (op = 0110)],
)[
  | f5       | 汇编形式                | 含义                                    |
  | -------- | ----------------------- | --------------------------------------- |
  | `00000`  | `{t,a,b,v}and`, `andx`  | 按位与                                  |
  | `00001`  | `{t,a,b,v}or`, `orx`    | 按位或                                  |
  | `00010`  | `{t,a,b,v}xor`, `xorx`  | 按位异或                                |
  | `00011`  | `{t,a,b,v}not`          | 按位取反 (单源, 无 x 形式, B 槽位为 0)  |
]

brow 形式 (`dir = 01`) 中 f5 为行号 rb (立即数或 Scalar 编号, 由 mode.src 选择), 操作选择移入 `SUB[1:0]` 为 BITOP (`00` and, `01` or, `10` xor, `11` 保留).

=== SHIFT (移位)

`D = shiftop(A, B)`; f5 为操作选择 (仅整数域).

#manual-table(
  columns: (1fr, 1.6fr, 3fr),
  caption: [SHIFT 类 f5 编码 (op = 0111)],
)[
  | f5       | 汇编形式                | 含义      |
  | -------- | ----------------------- | --------- |
  | `00000`  | `{t,a,b,v}shl`, `shlx`  | 左移      |
  | `00001`  | `{t,a,b,v}shr`, `shrx`  | 逻辑右移  |
  | `00010`  | `{t,a,b,v}sra`, `srax`  | 算术右移  |
]

brow 形式中 f5 为行号 rb, 操作选择移入 `SUB[1:0]` 为 SHIFTOP (`00` shl, `01` shr, `10` sra, `11` 保留).

=== ABSNEG (一元)

`D = f(A)`; f5 为操作选择 (仅 `{a,v}`, i32/f32).

#manual-table(
  columns: (1fr, 1.6fr, 3fr),
  caption: [ABSNEG 类 f5 编码 (op = 1000)],
)[
  | f5       | 汇编形式    | 含义          |
  | -------- | ----------- | ------------- |
  | `00000`  | `{a,v}abs`  | 逐元素绝对值  |
  | `00001`  | `{a,v}neg`  | 逐元素取负    |
]

=== SPEC (近似特殊函数)

`D = f(A)`; f5 为操作选择.

#manual-table(
  columns: (1fr, 1.6fr, 3fr),
  caption: [SPEC 类 f5 编码 (op = 1001)],
)[
  | f5       | 汇编形式             | 含义              |
  | -------- | -------------------- | ----------------- |
  | `00000`  | `{a,v}exp2.approx`   | 逐元素 2 的幂     |
  | `00001`  | `{a,v}rcp.approx`    | 逐元素倒数        |
  | `00010`  | `{a,v}rsqrt.approx`  | 逐元素倒数平方根  |
]

=== CMP (比较)

`D = predicate(A, B/xS)`, 生成 u32 mask; f5 选择源形式, 条件由 COND 给出.

#manual-table(
  columns: (1fr, 1.8fr, 3fr),
  caption: [CMP 类 f5 编码 (op = 1010)],
)[
  | f5       | 汇编形式          | 含义                             |
  | -------- | ----------------- | -------------------------------- |
  | `00000`  | `{a,v}cmp.COND`   | 寄存器比较, 生成 u32 mask        |
  | `00001`  | `{a,v}cmpx.COND`  | 与 Scalar 值比较 (xS 占 B 槽位)  |
]

#manual-table(
  columns: (1fr, 1.4fr, 3fr),
  caption: [CMP 类 COND 编码],
)[
  | COND   | 汇编     | 含义                          |
  | ------ | -------- | ----------------------------- |
  | `000`  | `eq`     | 相等 (整数与 f32)             |
  | `001`  | `ne`     | 不等 (仅整数)                 |
  | `010`  | `lt`     | 小于 (整数与 f32)             |
  | `011`  | `ge`     | 大于等于 (仅整数)             |
  | `100`  | `le`     | 小于等于 (仅 f32, `.le.f32`)  |
  | `101`  | `unord`  | 无序 (仅 f32, `.unord.f32`)   |
  | `11-`  | —        | 预留                          |
]

=== SELECT (T_R4)

`D = M ? A : B`, 按位选择, 与元素 dtype 无关; f5 槽位为 M 寄存器编号.

```asm
tselect tD, tM, tA, tB    # op = 1011, f5 = tM
aselect aD, aM, aA, aB
bselect bD, bM, bA, bB
vselect vD, vM, vA, vB
```

mask 操作数为 u8 (t/b) 或 u32 (a/v) 值; M 非零时选择 A, 否则选择 B; 两个数据源均被读取.

=== FMADD (T_R4)

`D = fma(A, B, C)`, f32 融合乘加, 单次舍入; f5 槽位为 C 寄存器编号.

```asm
afmadd.f32 aD, aA, aB, aC    # op = 1100, f5 = aC
vfmadd.f32 vD, vA, vB, vC
```

=== MASK (结构化掩码)

mask 使用扩展布局; 边界由打包 Scalar 提供 (见总则的 Scalar 打包操作数), fill 为 6-bit 编码 (见总则的 mask fill6).

#manual-table(
  columns: (1fr, 2.6fr, 3fr),
  caption: [MASK 类 f5 编码 (op = 1101)],
)[
  | f5       | 汇编形式                              | 含义                          |
  | -------- | ------------------------------------- | ----------------------------- |
  | `00000`  | `{t,a}mask.tail D, S, xBounds, fill`  | 保留行列坐标小于边界的源元素  |
  | `00001`  | `{t,a}mask.tril D, S, xBounds, fill`  | 下三角 (j - i <= xDelta)      |
  | `00010`  | `{t,a}mask.triu D, S, xBounds, fill`  | 上三角 (j - i >= xDelta)      |
  | `00011`  | `{b,v}mask.tail D, S, xLen, fill`     | 保留 lane < xLen 的源元素     |
]

`xBnd` 槽位为打包 Scalar 编号: tail 为 `xBounds` (`[31:0]` = nRows, `[63:32]` = nCols), tril/triu 为 xDelta (取低 32 bit), 向量 tail 为 xLen (取低 32 bit).

`maskx` 形式: 同名指令加 `x` 后缀 (`maskx.tail` 等), fill 由 Scalar 提供 (写 xBnd 槽位), 覆盖任意 fill 值; mode.src 位区分 fill 来源 (0 = fill6 立即数, 1 = Scalar).

= 01: 数据传输与重排

== T_M: 访存 (整块与向量)

`op4 + mode1`, 不使用 funct5; mode 字段位于 `[12]`, 与公共骨架的 mode `[14:12]` 低位对齐, mode1 预留为 0. 矩阵与向量形式由 op 区分.

内存行列坐标打包为 `xRowCol` (`[31:0]` = row, `[63:32]` = col), 占 `[22:18]` 槽位; 向量形式该槽位为 `xIndex`. 这样向量访存不再浪费一个恒为 0 的 `xCol` 槽位, 矩阵访存的行/列坐标也各占一个独立打包寄存器.

#manual-table(
  columns: (1fr, 3fr, 3.2fr),
  caption: [T_M 操作码分配],
)[
  | op      | 汇编形式                          | 含义                        |
  | ------- | --------------------------------- | --------------------------- |
  | `0000`  | `tload tD, tmJ, xBase, xRowCol`   | 按 TM 读取到 Tile 有效区域  |
  | `0001`  | `tstore tS, tmJ, xBase, xRowCol`  | 将 Tile 有效区域写入 TM     |
  | `0010`  | `aload aD, tmJ, xBase, xRowCol`   | 按 TM 读取到 Acc 有效区域   |
  | `0011`  | `astore aS, tmJ, xBase, xRowCol`  | 将 Acc 有效区域写入 TM      |
  | `1000`  | `bload bD, vmJ, xBase, xIndex`    | 按 VM 读取 Vec8             |
  | `1001`  | `bstore bS, vmJ, xBase, xIndex`   | 将 Vec8 写入 VM             |
  | `1010`  | `vload vD, vmJ, xBase, xIndex`    | 按 VM 读取 Vec32            |
  | `1011`  | `vstore vS, vmJ, xBase, xIndex`   | 将 Vec32 写入 VM            |
]

`descJ` 槽位: `tm0..15` (4 bit) 与 `vm0..31` (5 bit) 共用, 由 op 区分描述符类型; 矩阵形式的 `[22:18]` 槽位为打包 `xRowCol`, 向量形式为 `xIndex`; `[17:13]` 保留.

== T_MR: 行访存

行访存保留完整的动态二维坐标: 内存行列坐标打包为 `xRowCol` (`[31:0]` = row, `[63:32]` = col), 占 `[22:18]` 槽位; 目标行号 rd/rs 为独立 5-bit 字段 `[17:13]`. `op4 + mode1`, 不使用 funct5; mode 字段位于 `[12]`, 与公共骨架的 mode `[14:12]` 低位对齐, mode1 选择 rd/rs 来源 (0 = 立即数, 1 = Scalar).

#manual-table(
  columns: (1fr, 3.2fr, 3fr),
  caption: [T_MR 操作码分配],
)[
  | op      | 汇编形式                                  | 含义                   |
  | ------- | ----------------------------------------- | ---------------------- |
  | `0100`  | `tload.row tD[rd], tmJ, xBase, xRowCol`   | 读取到 Tile 指定行     |
  | `0101`  | `tstore.row tS[rs], tmJ, xBase, xRowCol`  | 将 Tile 指定行写入 TM  |
  | `0110`  | `aload.row aD[rd], tmJ, xBase, xRowCol`   | 读取到 Acc 指定行      |
  | `0111`  | `astore.row aS[rs], tmJ, xBase, xRowCol`  | 将 Acc 指定行写入 TM   |
]

#note[
  行访存的地址计算中, `rd/rs` 是寄存器行号; 内存行坐标由 `xRowCol` 提供: `CD[rd,j] ← memory[xBase + xRow × TM.row_stride_bytes + (xCol+j) × TM.col_stride_bytes]`.
]

#note[
  mode1 区分 rd/rs 的两种来源, 因为行号在两类场景中性质不同.
  + 软件流水与分块搬运中, 循环展开后的行号是编译期常量, 立即数形式不需要为此占用 Scalar 寄存器, 也不需要额外的 Scalar 指令
  + KV cache 追加等场景中, 行号是运行时值 (如 `seq_pos % 32`), 只能由 Scalar 提供.
]

== T_U: 初始化, 复制与转置

`op4 + funct5`; 立即数形式的 imm 占 `[27:12]` (16 bit, 见总则).

#manual-table(
  columns: (1fr, 1fr, 2.6fr, 2.6fr),
  caption: [T_U 操作码分配],
)[
  | op      | f5       | 汇编形式              | 含义                                    |
  | ------- | -------- | --------------------- | --------------------------------------- |
  | `0000`  | `00000`  | `{t,a,b,v}fill`       | 立即数填入有效区域 (imm 形式)           |
  | `0000`  | `00001`  | `{t,a,b,v}fillx`      | 用 Scalar 值填充 (xS 占 B 槽位)         |
  | `0001`  | `00000`  | `{t,a,b,v}copy D, S`  | 复制同域寄存器的有效数据 (S 占 A 槽位)  |
  | `0010`  | `00000`  | `ttranspose tD, tS`   | Tile 转置 (仅 8-bit Tile)               |
]

== T_RXM: 行搬运与 lane 操作

索引 (行号/lane 号) 可来自立即数或 Scalar: mode.src 选择来源, 为 0 时索引为 f5 槽位的 5-bit 立即数, 为 1 时索引取 f5 槽位的 Scalar 编号.

#manual-table(
  columns: (1fr, 1fr, 2.8fr, 2.4fr),
  caption: [行搬运与 lane 操作操作码分配],
)[
  | op      | f5    | 汇编形式                     | 含义                                      |
  | ------- | ----- | ---------------------------- | ----------------------------------------- |
  | `0011`  | rd    | `{t,a}insert.row tD[rd], S`  | 将向量写入矩阵指定行 (S 占 A 槽位)        |
  | `0100`  | rs    | `{t,a}extract.row D, S[rs]`  | 将矩阵指定行读入向量 (S 占 A 槽位)        |
  | `0101`  | lane  | `{b,v}extract xD, S[lane]`   | 将指定 lane 提取到 Scalar (xD 占 D 槽位)  |
  | `0110`  | lane  | `{b,v}insert D[lane], xS`    | 将 Scalar 值写入指定 lane                 |
  | `0111`  | lane  | `{b,v}broadcast D, S[lane]`  | 将源的一个 lane 广播到目的有效区域        |
]

= 10: 跨域计算与控制

== MMA 与 BDOT (T_R3)

`aD, tA, tB` 或 `vD, bA, tB`; f5 选择方向, mode 最低位选择写新或累加.

#manual-table(
  columns: (1fr, 1fr, 1.4fr, 3.4fr),
  caption: [MMA/BDOT 操作码分配],
)[
  | op      | f5       | mode  | 汇编形式              |
  | ------- | -------- | ----- | --------------------- |
  | `0000`  | `00000`  | nn    | `mma.nn.zero.i8.i32`  |
  | `0000`  | `00000`  | nn    | `mma.nn.acc.i8.i32`   |
  | `0000`  | `00001`  | nt    | `mma.nt.zero.i8.i32`  |
  | `0000`  | `00001`  | nt    | `mma.nt.acc.i8.i32`   |
  | `0001`  | `00000`  | nn    | `bdot.nn.i8.i32`      |
  | `0001`  | `00001`  | nt    | `bdot.nt.i8.i32`      |
]

f5: `00000` = nn, `00001` = nt (右 Tile 逻辑转置); `mode[0]`: 0 = zero (写新 Acc), 1 = acc (累加).

== RED (规约, T_U/T_U2)

#manual-table(
  columns: (1fr, 1fr, 2.6fr, 2.6fr),
  caption: [RED 操作码分配],
)[
  | op      | f5       | 汇编形式                  | 含义                                 |
  | ------- | -------- | ------------------------- | ------------------------------------ |
  | `0010`  | `00000`  | `areduce.rows.sum.f32`    | Acc 按行求和到 Vec32                 |
  | `0010`  | `00001`  | `areduce.rows.max.f32`    | Acc 按行取最大                       |
  | `0010`  | `00010`  | `areduce.rows.min.f32`    | Acc 按行取最小                       |
  | `0010`  | `00011`  | `areduce.rows.sumsq.f32`  | Acc 按行平方和                       |
  | `0011`  | `00000`  | `vreduce.sum.f32`         | Vec32 求和到 Scalar                  |
  | `0011`  | `00001`  | `vreduce.max.f32`         | Vec32 取最大到 Scalar                |
  | `0011`  | `00010`  | `vreduce.min.f32`         | Vec32 取最小到 Scalar                |
  | `0011`  | `00011`  | `vreduce.sumsq.f32`       | Vec32 平方和到 Scalar                |
  | `0011`  | `00100`  | `vreduce.argmax.f32`      | argmax, 输出索引与位模式两个 Scalar  |
]

`vreduce.argmax.f32 xIndex, xValue, vS` 使用 T_U2 变体: D 槽位写 xIndex (i32 语义, 符号扩展到 64 bit), A 槽位写 xValue (f32 位模式写低 32 bit, 高 32 bit 清零), B 槽位读 vS. 约束: `xIndex != xValue`.

== CVT (类型转换与扩大, T_U)

#manual-table(
  columns: (1fr, 1fr, 2.6fr, 2.6fr),
  caption: [CVT 操作码分配],
)[
  | op      | f5       | 汇编形式         | 含义                           |
  | ------- | -------- | ---------------- | ------------------------------ |
  | `0100`  | `00000`  | `acvt.i32.f32`   | Acc 中 i32 逐元素转 f32        |
  | `0100`  | `00001`  | `vcvt.i32.f32`   | Vec32 中 i32 逐 lane 转 f32    |
  | `0100`  | `00010`  | `twiden.i8.i32`  | Tile 的 i8 符号扩展到 Acc i32  |
]

== QNT (量化与反量化, T_R3 双目的变体)

bits 与 scale 是两个显式目的/源. 目的寄存器按助记符首字母写入 D 槽位, scale 寄存器写入 A 槽位; `vquant`/`bdequant` 的 scale lane 号写入 f5 槽位 (立即数).

#manual-table(
  columns: (1fr, 1fr, 3.2fr, 2.4fr),
  caption: [QNT 操作码分配],
)[
  | op      | f5       | 汇编形式                             | 含义                                 |
  | ------- | -------- | ------------------------------------ | ------------------------------------ |
  | `0101`  | `00000`  | `tquant.rows.q8s32 tD, vScale, aS`   | Acc 按行量化到 Tile + Vec32 scale    |
  | `0101`  | `00001`  | `vquant.q8s32 bD, vScale[lane], vS`  | Vec32 量化到 Vec8 + scale lane       |
  | `0101`  | `00010`  | `tdequant.rows.f32 aD, tS, vScale`   | 按行 scale 将 Tile 反量化到 f32 Acc  |
  | `0101`  | `00011`  | `bdequant.f32 vD, bS, vScale[lane]`  | 将 Vec8 反量化到 f32 Vec32           |
]

== T_C (配置)

`op4` 每指令一类 (seti/setx/copy/get 各占一个 op 类); `field` 为全局统一编号, 与配置类型解耦, 合法性按配置类型检查.

#manual-table(
  columns: (1fr, 3.8fr),
  caption: [T_C op 类分配],
)[
  | op      | 形式与布局                                                            |
  | ------- | --------------------------------------------------------------------- |
  | `0110`  | `cfg.seti C, field, imm`: imm 于 `[27:12]` (16 bit)                   |
  | `0111`  | `cfg.setx C, field, xS`: xS 于 `[27:23]`                              |
  | `1000`  | `cfg.copy C_D, C_S`: `C_D` 于 C 槽位, `C_S` 于 `[27:23]`              |
  | `1001`  | `cfg.get xD, C, field`: `xD` 于 C 槽位 (Scalar 目的), C 于 `[27:23]`  |
]

#manual-table(
  columns: (1fr, 2.4fr, 2.6fr),
  caption: [T_C field 全局编号],
)[
  | field    | 字段                | 合法配置类型  |
  | -------- | ------------------- | ------------- |
  | `0`      | `dtype`             | TC/AC/BC/VC   |
  | `1`      | `rows`              | TC/AC, TM     |
  | `2`      | `cols`              | TC/AC, TM     |
  | `3`      | `layout`            | TC/AC         |
  | `4`      | `len`               | BC/VC, VM     |
  | `5`      | `storage_dtype`     | TM, VM        |
  | `6`      | `transform`         | TM            |
  | `7`      | `flags`             | TM, VM        |
  | `8`      | `row_stride_bytes`  | TM            |
  | `9`      | `col_stride_bytes`  | TM            |
  | `10`     | `stride_bytes`      | VM            |
  | `11`     | `arith_mode`        | TC/BC         |
  | `12-15`  | reserved            | —             |
]

非法组合 (如 `cfg.seti tc0, stride_bytes, 4`, `cfg.seti vm0, rows, 32`, `cfg.seti tm0, dtype, f32`) 产生 `CFG_ERROR`. `cfg.seti` 用于小字段 (dtype, rows, cols, len, layout, transform, flags); stride 与超出立即数宽度的值使用 `cfg.setx`.

== T_S (同步与系统)

`op4 + funct5`; fence 与 `kernel.end` 不使用操作数字段, 标记为 reserved.

#manual-table(
  columns: (1fr, 1fr, 2.4fr, 2.8fr),
  caption: [T_S 操作码分配],
)[
  | op      | f5       | 汇编形式      | 含义                                                  |
  | ------- | -------- | ------------- | ----------------------------------------------------- |
  | `1111`  | `00000`  | `fence.mem`   | 等待此前访存完成并达到约定可见点                      |
  | `1111`  | `00001`  | `fence.sa`    | 等待此前 SA 操作完成                                  |
  | `1111`  | `00010`  | `fence.all`   | 等待此前全部后端工作完成                              |
  | `1111`  | `00011`  | `kernel.end`  | 报告 kernel 完成, 隐含 fence.all                      |
  | `1110`  | `00000`  | `getcap`      | 查询资源规格, 扩展和数值能力; 操作数与返回字段待定义  |
]
