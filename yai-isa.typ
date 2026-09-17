#import "yai-isa-style.typ": *

#show: setup

#align(center)[
  #v(18mm)
  #text(size: 25pt, weight: "bold")[Tile NPU 指令集手册]
  #v(5mm)
  #text(size: 14pt)[Tile-oriented ISA]
  #v(12mm)
  #line(length: 55%, stroke: 1.2pt + rgb("446e9b"))
  #v(8mm)
  *版本 1.0*
  #v(5mm)
  规范性草案
  #v(18mm)
  本手册描述 Tile NPU 的物理指令集.
]
#outline()

= 前言

本手册定义 Tile NPU 的物理指令集 (Tile-oriented ISA). 手册规定架构状态 (数据寄存器与配置寄存器), 指令的操作语义, 访存与同步规则, 并汇总全部已命名指令.

手册按功能组织: @overview 描述架构状态并给出指令分类; @scalar-sync 至 @quantization 按指令族定义语义; @instructions 汇总全部已命名指令; 附录提供助记符速查与编码图版.

记法约定:
+ 指令助记符, 寄存器名与字段名使用等宽字体 (如 `vadd.f32`, `a0`, `rows`)
+ 数学公式与伪代码共同定义指令语义
+ `i8`, `u8`, `i32`, `u32`, `f32` 表示元素数据类型; 整数元素用作 mask 时取全 0 (假) 或全 1 (真)
+ 尚未定义的内容在文中统一标注为 "待定".
+ `{t,a}` 形式的展开记号依次表示 t 形式和 a 形式两条指令, 多处出现时按顺序配对 (如 `{t,a}insert.row` 中 `{b,v}` 与 `{t,a}` 配对).
+ 指令表 Operation 列中, 目的 `D` 按助记符的展开域标注 (如 `{t,a}D`); 源操作数 `A`, `B`, `S` 不再重复标注, 未标注时与目的同域, 跨域时显式写出 (如 `{t,a}insert.row` 的 `{b,v}S`).
+ Operation 列省略索引时表示对目的有效区域逐元素执行; 行或广播变体以 `[rd,j]`, `S[i]` 等显式索引表示.

指令表与伪代码中的通用操作数记号:

#manual-table(
  columns: (1.2fr, 5fr),
  caption: [通用操作数记号],
)[
  | 记号           | 含义                                               |
  | -------------- | -------------------------------------------------- |
  | `D`            | 目的寄存器, 对应汇编操作数 `tD`, `aD`, `bD`, `vD`  |
  | `A`, `B`       | 第一, 第二源寄存器, 对应 `tA`, `tB` 等             |
  | `S`            | 单源或广播向量源                                   |
  | `M`            | mask 寄存器, 值为全 0 或全 1 的 `u8`/`u32` 元素    |
  | `imm`          | 立即数                                             |
  | `xS`           | 来自 Scalar 寄存器的操作数                         |
  | `tmJ`, `vmJ`   | 访存描述符 TM / VM 的编号                          |
  | `[i,j]`        | 矩阵元素索引                                       |
  | `[j]`          | 向量 lane 索引                                     |
  | `[rd,j]`       | 行操作中目的的指定行; `ra`, `rb` 为两个源的指定行  |
  | `sat`, `wrap`  | 饱和 / 回绕, 定义见 @elementwise                   |
]

= 指令集概览 <overview>

== 架构状态

=== 数据寄存器

#manual-table(
  columns: (1fr, 1fr, 1.3fr, 2fr, 2fr),
  caption: [数据寄存器与数据域],
)[
  | 寄存器类型  | 汇编名称   | 单寄存器容量                                       | 基础数据解释                           | 主要用途                                |
  | :---------: | :--------: | -------------------------------------------------- | -------------------------------------- | --------------------------------------- |
  | Tile        | `t0..t15`  | $32 times 32 times 8$ bit #linebreak() $= 1$ KiB   | `i8`, `u8`                             | 矩阵输入, 低精度中间结果                |
  | Acc         | `a0..a11`  | $32 times 32 times 32$ bit #linebreak() $= 4$ KiB  | `i32`, `u32`, `f32`                    | 矩阵宽累加结果, Attention score/output  |
  | Vec8        | `b0..b31`  | $32 times 8$ bit #linebreak() $= 32$ B             | `i8`, `u8`                             | 低精度向量, decode 阶段单 batch query   |
  | Vec32       | `v0..v31`  | $32 times 32$ bit #linebreak() $= 128$ B           | `i32`, `u32`, `f32`                    | 行状态, 规约结果, 向量计算输入输出      |
  | Scalar      | `x0..x31`  | $64$ bit $= 8$ B                                   | 地址, 整数, 低 32 bit 的 `f32` 位模式  | 地址, 循环, 索引和控制值                |
]

以上构成五个不同的*数据域*. 标量域的指令集为 RV64IM (见 @scalar-sync); 其余数据域的指令由本手册定义.

#important[
  32-bit 寄存器内无法存储两个半精度数(如`f16`/`bf16`), `f16`/`bf16`等半精度数加载后扩展到 f32 Acc/Vec.
]

=== 配置寄存器

配置寄存器分为计算配置寄存器和访存描述符.

#manual-table(
  columns: (1.05fr, 1fr, 1.2fr, 0.6fr, 2.2fr),
  caption: [计算配置寄存器与访存描述符],
)[
  | 寄存器类型          | 汇编名称     | 绑定或适用对象             | 容量  | 配置字段                                                                              |
  | :-----------------: | :----------: | -------------------------- | ----- | ------------------------------------------------------------------------------------- |
  | TC: Tile 计算配置   | `tc0..tc15`  | `tc[i]` ↔ `t[i]`           | 待定  | `dtype`, `rows`, `cols`, `layout`                                                     |
  | AC: Acc 计算配置    | `ac0..ac11`  | `ac[i]` ↔ `a[i]`           | 待定  | `dtype`, `rows`, `cols`, `layout`                                                     |
  | BC: Vec8 计算配置   | `bc0..bc31`  | `bc[i]` ↔ `b[i]`           | 待定  | `dtype`, `len`                                                                        |
  | VC: Vec32 计算配置  | `vc0..vc31`  | `vc[i]` ↔ `v[i]`           | 待定  | `dtype`, `len`                                                                        |
  | TM: 矩阵访存描述符  | `tm0..tm15`  | Tile / Acc 访存显式选择    | 待定  | `rows`, `cols`, `row_stride_bytes`, `col_stride_bytes`, `storage_dtype`, `transform`  |
  | VM: 向量访存描述符  | `vm0..vm31`  | Vec8 / Vec32 访存显式选择  | 待定  | `length`, `stride_bytes`, `storage_dtype`                                             |
]

== 编程模型 <model>

待写

== 指令格式 <formats>

待写

== 指令分类 <classification>

ISA 按五个数据域及其数据流划分功能. 下表列出正文定义的主要指令族.

#manual-table(
  columns: (1.25fr, 1.45fr, 1.7fr, 2.4fr),
  caption: [功能族总览],
)[
  | 功能族          | 主要数据流                                                                     | 架构职责                                   | 助记符入口                                                                                                                                      |
  | --------------- | ------------------------------------------------------------------------------ | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
  | 标量与控制      | Scalar ↔ Scalar #linebreak() Scalar ↔ 内存                                     | 地址, 索引, 标量计算, 控制流, 能力查询     | RV64IM (见 RISC-V 规范) #linebreak() `getcap`                                                                                                   |
  | 配置            | Scalar → TC, AC, BC, VC, TM, VM                                                | 建立数据域的类型, shape, 布局和访存描述    | `cfg.seti`, `cfg.setx`, `cfg.copy`, `cfg.get`                                                                                                   |
  | 地址与访存      | 内存 ↔ `t/a/b/v`                                                               | 按 TM/VM 描述符执行整块, 行和向量访问      | `{t,a}{load,store}` #linebreak() `{b,v}{load,store}`                                                                                            |
  | 初始化与搬运    | 域内 #linebreak() `t` ↔ `b` #linebreak() `a` ↔ `v` #linebreak() Scalar ↔ lane  | 填充, 复制, 行搬运, lane 搬运, 广播和转置  | `{t,a,b,v}{fill,fillx,copy}` #linebreak() `{t,a}{insert,extract}.row` #linebreak() `{b,v}{insert,extract,broadcast}` #linebreak() `ttranspose`  |
  | 矩阵乘与点积    | `t` × `t` → `a` #linebreak() `b` × `t` → `v`                                   | `i8` 乘法, `i32` 累加或点积                | `mma` #linebreak() `bdot`                                                                                                                       |
  | 逐元素与广播    | `t/a/b/v` 同域 #linebreak() 矩阵 ↔ 向量广播                                    | 算术, 位运算, 移位, 特殊函数, 比较和选择   | `{t,a,b,v}op` #linebreak() `.brow`, `.byrow`, `.bycol` #linebreak() `cmp`, `select`, `mask`                                                     |
  | 规约            | `a` → `v` #linebreak() `v` → Scalar                                            | 行规约, 向量规约, 平方和和 argmax          | `areduce` #linebreak() `vreduce`                                                                                                                |
  | 类型转换与扩大  | `a/v` 内部 #linebreak() `t` → `a`                                              | 数值类型转换和 `i8` → `i32` 扩大           | `acvt`, `vcvt` #linebreak() `twiden`                                                                                                            |
  | 量化与反量化    | `a` ↔ `t` #linebreak() `v` ↔ `b`                                               | 低精度存储与 `f32` 计算之间的显式转换      | `tquant`, `tdequant` #linebreak() `vquant`, `bdequant`                                                                                          |
  | 同步与结束      | 后端 → 完成边界 #linebreak() kernel → 完成                                     | 访存, SA, 全后端完成以及 kernel 生命周期   | `fence.mem`, `fence.sa`, `fence.all` #linebreak() `kernel.end`                                                                                  |
]

== 指令空间组织 <instruction-space>

指令空间按指令字最低两位划分. `[1:0] = 11` 的空间用于标量指令: 标量指令集采用 RV64IM (RISC-V 64-bit 基础整数指令集与乘除扩展), 译码按 RISC-V 规范执行. `[1:0]` 为 `00`, `01`, `10` 的原压缩指令空间全部用于非标量指令, 共 $3 times 2^30$ 个 32-bit 编码槽; 其内部组织待定.

= 指令格式 <encoding>

待定

= 标量与同步 <scalar-sync>

标量指令集采用 RV64IM: 标量算术, 逻辑, 比较, 分支, 跳转和标量访存均按 RISC-V 规范执行, 不在本手册定义. 本章只定义 NPU 特有的能力查询与同步指令.

#instruction-table(caption: [能力查询与同步指令])[
  | Instruction   | Format  | Operation                          | Notes                        |
  | ------------- | ------- | ---------------------------------- | ---------------------------- |
  | `getcap`      | 待定    | 查询资源规格, 扩展和数值能力.      | 操作数与返回字段待定义.      |
  | `fence.mem`   | 待定    | 等待此前访存完成并达到约定可见点.  | 后续访存不得越过此边界.      |
  | `fence.sa`    | 待定    | 等待此前 SA 操作完成.              | 后续 SA 操作不得越过此边界.  |
  | `fence.all`   | 待定    | 等待此前全部后端工作完成.          | 后续后端操作不得越过此边界.  |
  | `kernel.end`  | 待定    | 报告 kernel 完成.                  | 隐含 `fence.all`.            |
]

```asm
fence.mem       # 此前访存完成并达到约定可见点, 后续访存不得越过
fence.sa        # 此前 SA 操作完成, 后续 SA 操作不得越过
fence.all       # 此前全部后端工作完成, 后续后端工作不得越过
kernel.end      # 隐含 fence.all, 报告 kernel 完成
```

= 配置指令 <configuration>

下表列出配置指令的语义摘要; `Format` 为尚待定义的二进制编码格式.

#instruction-table(caption: [配置指令])[
  | Instruction  | Format  | Operation                 | Notes                                                  |
  | ------------ | ------- | ------------------------- | ------------------------------------------------------ |
  | `cfg.seti`   | 待定    | C[field] = extend(imm)    | 校验失败时产生 `CFG_ERROR`.                            |
  | `cfg.setx`   | 待定    | C[field] = x[xS]          | 字段定义扩展, 截断与范围规则; 失败时产生 `CFG_ERROR`.  |
  | `cfg.copy`   | 待定    | $C_D = C_S$               | 源和目的配置类型一致时执行复制.                        |
  | `cfg.get`    | 待定    | x[xD] = extend(C[field])  | 结果为字段的整数或枚举值.                              |
]

== `cfg.seti` — 写立即数配置字段

```asm
cfg.seti C, field, imm
```

将立即数写入指定配置字段.

操作:

```
    v ← extend(imm, type(field))
    if !valid(C, field, v):
        raise CFG_ERROR
    C[field] ← v
```

示例:

```asm
cfg.seti tc0, rows, 32
```

对于`cfg.seti tc0, rows, 32`, 执行后的架构状态是`tc0.rows = 32`, 由于`tc0 <-> t0`, 它表示 `t0` 的有效行数为 32.

== `cfg.setx` — 写 Scalar 值到配置字段

```asm
cfg.setx C, field, xS
```

将 Scalar 寄存器中的完整值写入指定配置字段. 字段的符号扩展, 截断和范围规则由字段定义决定.

操作:

```
    v ← x[xS]
    if !valid(C, field, v):
        raise CFG_ERROR
    C[field] ← v
```

示例:

```asm
cfg.setx tm0, row_stride_bytes, x4
```

将 Scalar 寄存器 `x4` 的 64-bit 值解释为有符号字节步长, 检查其是否满足 `TM.row_stride_bytes` 的约束, 并写入 `tm0.row_stride_bytes`.

如果`x4 = 128`, 则`tm0.row_stride_bytes = 128`,后续矩阵访存使用:

$
  op("addr")(i,j) & = "xBase" \
                  & quad + ("xRow" + i) dot "tm0.row_stride_bytes" \
                  & quad + ("xCol" + j) dot "tm0.col_stride_bytes"
$

== `cfg.copy` — 复制配置寄存器

```asm
cfg.copy C_D, C_S
```

复制源配置在执行时的全部字段.

操作:

```
    if(typeof(C_D) == typeof(C_S)){
        C_D ← C_S
    }
```

== `cfg.get` — 读配置字段到 Scalar

```asm
cfg.get xD, C, field
```

将配置字段的整数或枚举值写入 Scalar 寄存器.

操作:

```
    v ← C[field]
    x[xD] ← extend(v, 64)
```

= 地址与访存指令 <memory>

本章定义按描述符寻址的访存指令. 矩阵访存 (`tload`, `tstore`, `aload`, `astore` 及行形式) 由 TM 描述, 向量访存 (`bload`, `vload`, `bstore`, `vstore`) 由 VM 描述; Scalar 访存由 RV64IM load/store 指令承担. 所有 x/t/a/b/v 访存保持统一的程序可见顺序.

#instruction-table(caption: [地址与访存指令])[
  | Instruction       | Format  | Operation                        | Notes                                              |
  | ----------------- | ------- | -------------------------------- | -------------------------------------------------- |
  | `{t,a}load`       | 待定    | {t,a}D[i,j] = memory[addr(i,j)]  | 越界元素补零, 整块 load 清零目的其余位置.          |
  | `{t,a}store`      | 待定    | memory[addr(i,j)] = S[i,j]       | 仅写有效交集; 越界位置不访问内存.                  |
  | `{t,a}load.row`   | 待定    | {t,a}D[r,j] = memory[addr(r,j)]  | 仅处理目的行; 无效列补零, 其余行保持.              |
  | `{t,a}store.row`  | 待定    | memory[addr(r,j)] = S[r,j]       | 仅写有效交集; 越界位置不访问内存.                  |
  | `{b,v}load`       | 待定    | {b,v}D[j] = memory[addr(j)]      | 按寄存器有效长度与 VM 范围确定访问, 越界元素补零.  |
  | `{b,v}store`      | 待定    | memory[addr(j)] = S[j]           | 仅写有效交集, 越界位置不访问内存.                  |
]

== 访存描述符和地址操作数

矩阵访存使用 `TM` 描述符, 向量访存使用 `VM` 描述符.

`TM` 字段有`rows`, `cols`, `row_stride_bytes`, `col_stride_bytes`, `storage_dtype`, `transform`

`VM` 字段有`length`, `stride_bytes`, `storage_dtype`:

基地址和访问坐标由 64-bit Scalar 操作数提供.
对一维 VM, 内存元素地址定义为:

$
  op("addr")(j) = "xBase" + ("xIndex" + j) dot "VM.stride_bytes"
$

对二维 TM, 内存元素地址定义为:

$
  op("addr")(i,j) & = "xBase" \
                  & quad + ("xRow" + i) dot "TM.row_stride_bytes" \
                  & quad + ("xCol" + j) dot "TM.col_stride_bytes"
$

#manual-table(columns: (2fr, 5fr), caption: [地址计算符号])[
  | 符号      | 含义                                 |
  | --------- | ------------------------------------ |
  | `xBase`   | view 逻辑坐标 $[0, 0]$ 对应的基地址  |
  | `xIndex`  | 一维 view 的起始元素坐标             |
  | `xRow`    | 二维 view 的起始行坐标               |
  | `xCol`    | 二维 view 的起始列坐标               |
  | $i$, $j$  | 当前 Tile 或 Vector 内的局部坐标     |
]

坐标以元素计, stride 以字节计; RF 行号 $r$ 与内存 `xRow` 独立.

编译器将逻辑 Tile 编号乘以固定边长 $L = 32$ 后, 形成对应的元素坐标.

== 基础访存指令

=== 矩阵整块访存

```asm
tload   tD, tmJ, xBase, xRow, xCol
tstore  tS, tmJ, xBase, xRow, xCol

aload   aD, tmJ, xBase, xRow, xCol
astore  aS, tmJ, xBase, xRow, xCol
```

`tload` 使用 `tD` 对应的 `TC` 配置, `aload` 使用 `aD` 对应的 `AC` 配置. `tstore` 和 `astore` 使用源寄存器对应的配置.

对于矩阵整块 load, 令 $R & = op("rows")("CD"), C & = op("cols")("CD")$

其中 `CD` 是目的 Tile 或 Acc. 对每个有效寄存器元素执行:

```text
for 0 <= i < R:
    for 0 <= j < C:
        if 0 <= xRow+i < TM.rows
           and 0 <= xCol+j < TM.cols:
            CD[i,j] ← memory[addr(i,j)]
        else:
            CD[i,j] ← 0
```

对于矩阵整块 store:

```text
for 0 <= i < R:
    for 0 <= j < C:
        if 0 <= xRow+i < TM.rows
           and 0 <= xCol+j < TM.cols:
            memory[addr(i,j)] ← CS[i,j]
        else:
            no memory access
```

其中 `CS` 是源 Tile 或 Acc.

=== 矩阵行访存

```asm
tload.row   tD[rd], tmJ, xBase, xRow, xCol
tstore.row  tS[rs], tmJ, xBase, xRow, xCol

aload.row   aD[rd], tmJ, xBase, xRow, xCol
astore.row  aS[rs], tmJ, xBase, xRow, xCol
```

`rd` 和 `rs` 是寄存器文件中的行号, 可以是立即数或 Scalar 寄存器提供的完整值.

对于 row load:

```text
for 0 <= j < cols(CD):
    if 0 <= xRow < TM.rows
       and 0 <= xCol+j < TM.cols:
        CD[r,j] ← memory[addr(r,j)]
    else:
        CD[r,j] ← 0
```

row load 的效果是: 只清零或覆盖目的寄存器的第 r 行; 目的寄存器的其他行保持原值; 目的寄存器第 r 行的无效列写入零.

对于 row store:

```text
for 0 <= j < cols(CS):
    if 0 <= xRow < TM.rows
       and 0 <= xCol+j < TM.cols:
        memory[addr(r,j)] ← CS[r,j]
    else:
        no memory access
```

=== 向量访存

```asm
bload   bD, vmJ, xBase, xIndex
bstore  bS, vmJ, xBase, xIndex

vload   vD, vmJ, xBase, xIndex
vstore  vS, vmJ, xBase, xIndex
```

`bload` 和 `bstore` 使用对应 `BC` 配置中的 `len`. `vload` 和 `vstore` 使用对应 `VC` 配置中的 `len`.

对于向量 load:

```text
for 0 <= j < len(CD):
    if 0 <= xIndex+j < VM.length:
        CD[j] ← memory[addr(j)]
    else:
        CD[j] ← 0
```

对于向量 store:

```text
for 0 <= j < len(CS):
    if 0 <= xIndex+j < VM.length:
        memory[addr(j)] ← CS[j]
    else:
        no memory access
```

`VM.length` 描述内存 view 的有效长度; `BC.len` 或 `VC.len` 描述当前向量寄存器的有效长度. 两者共同决定最终的有效访问范围.

== 存储数据类型和转换

`t/a/b/v` 的存储类型由访存描述符的 `storage_dtype` 字段决定; Scalar 访存由 RV64IM 指令承担. 转置加载通过 `TM.transform` 选择, 仍使用 `tload` (见 @transpose-load).

#manual-table(
  columns: (1.1fr, 1.6fr, 1.1fr, 1.9fr),
  caption: [访存存储格式与转换],
)[
  | 寄存器域    | 允许的存储格式  | load 行为     | store 行为               |
  | ----------- | --------------- | ------------- | ------------------------ |
  | `t/b`       | `i8`, `u8`      | 原样搬运      | 原样写回                 |
  | `a/v` 整数  | `i32`, `u32`    | 原样搬运      | 原样写回                 |
  | `a/v` 浮点  | `f32`           | 原样搬运      | 原样写回                 |
  | `a/v` 浮点  | `f16`, `bf16`   | 扩展为 `f32`  | 从 `f32` 按规定舍入转换  |
]

格式转换必须使用明确的转换, 量化或反量化指令. 因此:

1. `aload a0, tm0, xBase, xRow, xCol` 且 `tm0.storage_dtype = bf16`: 其结果是将 `bf16` 元素扩展为 `f32` 后写入 `a0`.
2. `astore a0, tm0, xBase, xRow, xCol` 且`tm0.storage_dtype = bf16`: 每个 `f32` 元素必须按照数值规则舍入为 `bf16` 后写入内存.

== 受限动态行读取

Embedding 可以使用 Scalar 先读取 token ID (RV64IM 指令):

```asm
add xAddr, xTokenBase, xTokenOffset
lw xToken, 0(xAddr)
```

Scalar 代码先检查:

$ 0 <= "xToken" < "vocab_size" $

然后将 `xToken` 作为内存行坐标执行:

```asm
aload.row a0[rd], tm_embedding, xEmbeddingBase, xToken, 0
```

或:

```asm
vload v0, vm_embedding, xEmbeddingBase, xToken
```

== KV Cache 追加示例

Decode 的 KV 追加可直接用 `bstore` 写 `i8` 行片段, 用 `vstore` 写 `f16` scale, 无需先把向量插入 Tile. bits 和 scale 分别使用 Vec8 和 Vec32 访存:

```asm
bstore bK, vm_k_bits,   xKVBase, xPosition
vstore vS, vm_k_scale,  xScaleBase, xPosition
```

这些指令分别写入:

```text
i8 KV bits
f16/bf16 KV scale
```

= 初始化, 搬运与转置 <data-movement>

本节定义数据寄存器之间的初始化, 复制, 行搬运, lane 搬运, 广播和 Tile 转置操作.

`TYPE` 在 Tile/Vec8 中为 `i8/u8`, 在 Acc/Vec32 中为 `i32/u32/f32`. 不带类型后缀的搬运使用寄存器配置中的 dtype. 行号和 lane 号可以来自立即数或 Scalar.

#instruction-table(caption: [初始化, 搬运与转置指令])[
  | Instruction         | Format  | Operation                 | Notes                                                          |
  | ------------------- | ------- | ------------------------- | -------------------------------------------------------------- |
  | `{t,a}fill.TYPE`    | 待定    | {t,a}D[i,j] = imm         | TYPE: t 为 `i8/u8`, a 为 `i32/u32/f32`; 无效物理位置保持原值.  |
  | `{t,a}fillx.TYPE`   | 待定    | {t,a}D[i,j] = xS          | TYPE: t 为 `i8/u8`, a 为 `i32/u32/f32`.                        |
  | `{t,a}copy`         | 待定    | {t,a}D[i,j] = S[i,j]      | 源与目的 dtype, shape, layout 必须一致.                        |
  | `{b,v}fill.TYPE`    | 待定    | {b,v}D[j] = imm           | TYPE: b 为 `i8/u8`, v 为 `i32/u32/f32`; 无效物理位置保持原值.  |
  | `{b,v}fillx.TYPE`   | 待定    | {b,v}D[j] = xS            | TYPE: b 为 `i8/u8`, v 为 `i32/u32/f32`.                        |
  | `{b,v}copy`         | 待定    | {b,v}D[j] = S[j]          | 源与目的 dtype, shape, layout 必须一致.                        |
  | `{t,a}insert.row`   | 待定    | {t,a}D[rd,j] = {b,v}S[j]  | 行号有效, 向量长度等于列数, dtype 相同; 其他行保持.            |
  | `{t,a}extract.row`  | 待定    | {b,v}D[j] = {t,a}S[rs,j]  | 行号有效, 目的长度等于源列数, dtype 相同.                      |
  | `{b,v}extract`      | 待定    | xD = S[lane]              | lane 有效; 按源 dtype 扩展或写入浮点位模式.                    |
  | `{b,v}insert`       | 待定    | {b,v}D[lane] = xS         | lane 有效; 按目的 dtype 解释数值.                              |
  | `{b,v}broadcast`    | 待定    | {b,v}D[j] = S[lane]       | 源与目的同域且 dtype 相同.                                     |
  | `ttranspose`        | 待定    | tD[i,j] = tS[j,i]         | 仅支持 8-bit Tile; 允许原地执行, 交换有效行列数.               |
]

== Fill 指令

```asm
{t,a,b,v}fill.TYPE   D, imm
{t,a,b,v}fillx.TYPE  D, xS
```

`fill` 将立即数填入目标有效区域; `fillx` 用 Scalar 值填充. 目标数据域由指令前缀确定:

```text
tfill: 目标为 Tile
afill: 目标为 Acc
bfill: 目标为 Vec8
vfill: 目标为 Vec32
```

`fill` 操作: 对于矩阵目标, 令$R & = op("rows")(D), C & = op("cols")(D)$

执行:

```text
for 0 <= i < R:
    for 0 <= j < C:
        D[i,j] ← value
```

对于向量目标, 令$N & = op("len")(D)$:

执行:

```text
for 0 <= j < N:
    D[j] ← value
```

`fill` 只修改目标数据寄存器的当前有效区域. 有效区域之外的物理位置保持原值: 矩阵中满足 $i >= op("rows")(D)$ 或 $j >= op("cols")(D)$ 的位置保持不变; 向量中满足 $j >= op("len")(D)$ 的 lane 保持不变.

`fillx` 操作: 从 Scalar 寄存器中读取填充值 `value ← x[xS]`, 然后按照 `TYPE` 写入目标有效区域.

示例:

```asm
tfill.i8    t0, 0
afill.f32   a0, 0.0
bfill.i8    b0, 0
vfill.f32   v0, 0.0

tfillx.i8   t0, x4
vfillx.f32  v0, x5
```

== Copy 指令

```asm
{t,a,b,v}copy D, S
```

复制同域寄存器的有效数据.

约束: 源和目的必须属于同一数据域, 且 dtype, shape 和 layout 相同. Tile/Acc 的 shape 为 rows 和 cols; Vec8/Vec32 的 shape 为 len.

操作: 矩阵 copy 定义为:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← S[i,j]
```

向量 copy 定义为:

```text
for 0 <= j < len(D):
    D[j] ← S[j]
```

copy 只写目标的有效区域, 目标有效区域之外的物理位置保持不变.

示例:

```asm
cfg.copy tc1, tc0
tcopy t1, t0
```

前一条复制的是计算配置值, 后一条复制的是 Tile 数据. 两条指令都不会让 `t1` 永久引用 `t0`.

== Tile 和 Vec8 的行搬运

```asm
tinsert.row  tD[rd], bS
textract.row bD,     tS[rs]
```

在 Vec8 与 Tile 的指定行之间搬运数据.

约束: 只执行同精度 bit 搬运, 即 `i8` Tile ↔ `i8` Vec8, `u8` ↔ `u8`. 如果需要扩大或量化, 必须先使用 `twiden`, `tquant` 或 `vquant` 完成转换, 再执行行搬运.

`tinsert.row` 操作: 将一个 Vec8 写入 Tile 的指定行:

```text
if 0 <= rd < rows(tD)
    && len(bS) = cols(tD)
    && dtype(bS) = dtype(tD):
    for 0 <= j < cols(tD):
        tD[rd,j] ← bS[j]
```

只有目标 Tile 的第 `rd` 行被修改, 其他行保持原值.

`textract.row` 操作: 将 Tile 的指定行读入 Vec8:

```text
if 0 <= rs < rows(tS)
    && len(bD) = cols(tS)
    && dtype(bD) = dtype(tS):
    for 0 <= j < cols(tS):
        bD[j] ← tS[rs,j]
```

只有 `bD` 的有效 lane 被写入, 其他 lane 保持原值.

== Acc 和 Vec32 的行搬运

```asm
ainsert.row  aD[rd], vS
aextract.row vD,     aS[rs]
```

在 Vec32 与 Acc 的指定行之间搬运数据.

约束: 只允许同精度搬运, 即 `i32` Acc ↔ `i32` Vec32, `u32` ↔ `u32`, `f32` ↔ `f32`.

`ainsert.row` 操作: 将一个 Vec32 写入 Acc 的指定行:

```text
if 0 <= rd < rows(aD)
    && len(vS) = cols(aD)
    && dtype(vS) = dtype(aD):
    for 0 <= j < cols(aD):
        aD[rd,j] ← vS[j]
```

只有目标 Acc 的第 `rd` 行被修改, 其他行保持原值.

`aextract.row` 操作: 将 Acc 的指定行读入 Vec32:

```text
if 0 <= rs < rows(aS)
    && len(vD) = cols(aS)
    && dtype(vD) = dtype(aS):
    for 0 <= j < cols(aS):
        vD[j] ← aS[rs,j]
```

只有 `vD` 的有效 lane 被写入, 其他 lane 保持原值.

== Scalar 与 Vector lane 操作

```asm
{b,v}extract xD, S[lane]
{b,v}insert  D[lane], xS
{b,v}broadcast D, S[lane]
```

在 Scalar 与 Vector 的单个 lane 之间读写数据, 或将一个 lane 广播到整个向量. `lane` 可以是立即数, 也可以由 Scalar 寄存器提供.

`extract` 操作:

```text
if 0 <= lane < len(S):
    x[xD] ← S[lane]
```

Scalar 结果的扩展规则由源 dtype 决定:

```text
i8/i32: 符号扩展到 64 bit;
u8/u32: 零扩展到 64 bit;
f32: 低 32 bit 写入浮点位模式, 高 32 bit 清零.
```

`insert` 操作:

```text
if 0 <= lane < len(D):
    value ← x[xS]
    D[lane] ← value
```

`broadcast` 操作:

```text
if 0 <= lane < len(S)
    value ← S[lane]

    for 0 <= j < len(D):
        D[j] ← value
```

`broadcast` 的源和目的必须属于同一 Vector 数据域, 且 dtype 相同 (`bS` → `bD` 或 `vS` → `vD`).

== Tile 转置

```asm
ttranspose tD, tS
```

交换源 Tile 的行列, 将元素转置写入目的 Tile. 该指令只对 Tile 执行转置, 基础版本的转置单元只支持 8-bit 数据.

操作: 设源 Tile 的有效 shape 为$R & = op("rows")("tS"), C & = op("cols")("tS")$

执行:

```text
for 0 <= i < C:
    for 0 <= j < R:
        tD[i,j] ← tS[j,i]
```

转置完成后, 目的 Tile 的有效 shape 为:

$
    op("rows")("tD") & = C \
    op("cols")("tD") & = R \
   op("dtype")("tD") & = op("dtype")("tS") \
  op("layout")("tD") & = "canonical"
$

允许原地转置, 即:

```asm
ttranspose t0, t0
```

== Full load 的转置形式 <transpose-load>

`TM.transform=transpose` 可以作为 full `tload` 的访存变换:

```asm
tload tD, tmTranspose, xBase, xRow, xCol
```

其结果等价于:

$ "tD"_(i,j) <- "memory"["xRow" + j, "xCol" + i] $

该形式和:

```asm
tload tTmp, tmNormal, xBase, xRow, xCol
ttranspose tD, tTmp
```

具有相同的架构结果, 但实现路径不同:

```text
transpose-on-load:
    在访存路径或转置 SRAM 中完成转置;

显式 ttranspose:
    先产生普通 Tile, 再调用 Tile 转置指令.
```

== KV Cache 中的行搬运

KV cache 追加可以采用如下指令序列:

```asm
# 从计算结果中取得一个低精度行
textract.row b0, tK[rowK]

# 写入 KV cache 的 bits
bstore b0, vm_k_bits, xKVBitsBase, xPosition

# 写入对应的 f16/bf16 scale
vstore v0, vm_k_scale, xKVScaleBase, xPosition
```

如果需要把 Vec8 的一行写入驻留 Tile, 则使用:

```asm
tinsert.row tK[rowK], b0
```

= 矩阵乘与向量—矩阵乘 <matrix>

本节定义基础 `i8` 矩阵乘和 Vec8—Tile 点积指令. 基础指令使用*`i8` 输入, `i32` 输出或累加*.

#instruction-table(caption: [矩阵乘与点积指令])[
  | Instruction           | Format  | Operation            | Notes                                              |
  | --------------------- | ------- | -------------------- | -------------------------------------------------- |
  | `mma.nn.zero.i8.i32`  | 待定    | aD = tA tB           | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `mma.nn.acc.i8.i32`   | 待定    | aD = aD + tA tB      | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `bdot.nn.i8.i32`      | 待定    | vD = bA tB           | `i8` 输入, `i32` 输出; 跨块累加使用 `vadd.i32`.    |
  | `mma.nt.zero.i8.i32`  | 待定    | aD = tA (tB)^T       | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `mma.nt.acc.i8.i32`   | 待定    | aD = aD + tA (tB)^T  | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `bdot.nt.i8.i32`      | 待定    | vD = bA (tB)^T       | `i8` 输入, `i32` 输出; 跨块累加使用 `vadd.i32`.    |
]

== 指令格式

```asm
mma.nn.zero.i8.i32 aD, tA, tB
mma.nn.acc.i8.i32  aD, tA, tB

mma.nt.zero.i8.i32 aD, tA, tB
mma.nt.acc.i8.i32  aD, tA, tB

bdot.nn.i8.i32     vD, bA, tB
bdot.nt.i8.i32     vD, bA, tB
```

操作数含义:

#manual-table(
  columns: (0.9fr, 0.9fr, 3.5fr),
  caption: [矩阵乘与点积操作数],
)[
  | 操作数  | 数据域  | 作用                           |
  | ------- | ------- | ------------------------------ |
  | `tA`    | Tile    | MMA 或 row-dot 的左操作数      |
  | `tB`    | Tile    | MMA 或 row-dot 的右操作数      |
  | `aD`    | Acc     | MMA 的 `i32` 目的和累加寄存器  |
  | `bA`    | Vec8    | bdot 的 `i8` 向量输入          |
  | `vD`    | Vec32   | bdot 的 `i32` 向量输出         |
]

数学形式:

#manual-table(
  columns: (1fr, 4fr),
  caption: [矩阵乘与点积的数学形式],
)[
  | 形式       | 运算                                                      |
  | ---------- | --------------------------------------------------------- |
  | `mma.nn`   | $A_(M times K) B_(K times N) -> D_(M times N)$            |
  | `mma.nt`   | $A_(M times K) (B_(N times K))^sans(T) -> D_(M times N)$  |
  | `bdot.nn`  | $"out"_j = sum_(k=0)^(K-1) b_k B_(k,j)$                   |
  | `bdot.nt`  | $"out"_j = sum_(k=0)^(K-1) b_k B_(j,k)$                   |
]

== `nn` 和 `nt` 的矩阵布局

`nn` 和 `nt` 表示右操作数的逻辑方向.

=== `nn`

`mma.nn` 的数学形式为:

$ A_(M times K) B_(K times N) -> D_(M times N) $

其中:

$ A_(i,k) = "tA"_(i,k), quad B_(k,j) = "tB"_(k,j) $

因此:

$ D_(i,j) = sum_(k=0)^(K-1) A_(i,k) B_(k,j) $

=== `nt`

`nt` 的含义是矩阵运算的逻辑布局, `mma.nt` 的数学形式为:

$ A_(M times K) (B_(N times K))^sans(T) -> D_(M times N) $

Tile `tB` 的物理有效 shape 是:

$ op("shape")("tB") = N times K $

逻辑转置后的 shape 为:

$ op("shape")(("tB")^sans(T)) = K times N $

因此:

$ D_(i,j) = sum_(k=0)^(K-1) A_(i,k) "tB"_(j,k) $

== `mma.nn.zero.i8.i32`

```asm
mma.nn.zero.i8.i32 aD, tA, tB
```

按普通右矩阵执行矩阵乘, 结果写入 `i32` Acc. 每个 `i8` 操作数先符号扩展到 `i32`, 再进行乘法; 乘积和累加使用 `i32` 算术.

约束:

$
  op("dtype")("tA") & = "i8" and op("dtype")("tB") = "i8" \
  op("dtype")("aD") & = "i32" \
   op("rows")("tA") & = M, op("cols")("tA") = K \
   op("rows")("tB") & = K, op("cols")("tB") = N \
   op("rows")("aD") & = M, op("cols")("aD") = N
$

操作:

```text
for i = 0 ... M-1:
    for j = 0 ... N-1:
        sum = 0
        for k = 0 ... K-1:
            lhs = sign_extend_i8(tA[i,k])
            rhs = sign_extend_i8(tB[k,j])
            sum = sum + lhs * rhs
        aD[i,j] = sum
```

== `mma.nn.acc.i8.i32`

```asm
mma.nn.acc.i8.i32 aD, tA, tB
```

按普通右矩阵执行矩阵乘, 并累加到目的 Acc 的旧值.

约束: 与 `mma.nn.zero.i8.i32` 相同.

操作: `acc` 形式与 `zero` 使用相同的乘法定义, 但将结果加到目的 Acc 的旧值上:

```text
for i = 0 ... M-1:
    for j = 0 ... N-1:
        partial = 0
        for k = 0 ... K-1:
            lhs = sign_extend_i8(tA[i,k])
            rhs = sign_extend_i8(tB[k,j])
            partial = partial + lhs * rhs

        aD[i,j] = wrap32(aD[i,j] + partial)
```

示例: 沿 K 维分块累加:

```asm
mma.nn.zero.i8.i32 a0, tA0, tB0
mma.nn.acc.i8.i32  a0, tA1, tB1
mma.nn.acc.i8.i32  a0, tA2, tB2
mma.nn.acc.i8.i32  a0, tA3, tB3
```

每条 `mma.nn.acc` 都读取上一次得到的 `a0`, 并产生新的 `a0`, 结果为:

$ "a0" = A_0 B_0 + A_1 B_1 + A_2 B_2 + A_3 B_3 $

== `mma.nt.zero.i8.i32` 和 `mma.nt.acc.i8.i32`

```asm
mma.nt.zero.i8.i32 aD, tA, tB
mma.nt.acc.i8.i32  aD, tA, tB
```

将右 Tile 逻辑转置后执行矩阵乘; `zero` 形式写入目的 Acc, `acc` 形式累加到目的 Acc 的旧值.

约束: 与 `mma.nn` 形式相同, 但右操作数 `tB` 按逻辑转置解释, 其物理有效 shape 为 $N times K$.

`zero` 操作:

```text
for i = 0 ... M-1:
    for j = 0 ... N-1:
        sum = 0
        for k = 0 ... K-1:
            lhs = sign_extend_i8(tA[i,k])
            rhs = sign_extend_i8(tB[j,k])
            sum = sum + lhs * rhs
        aD[i,j] = sum
```

`acc` 操作:

```text
for i = 0 ... M-1:
    for j = 0 ... N-1:
        partial = 0
        for k = 0 ... K-1:
            lhs = sign_extend_i8(tA[i,k])
            rhs = sign_extend_i8(tB[j,k])
            partial = partial + lhs * rhs

        aD[i,j] = wrap32(aD[i,j] + partial)
```

== `bdot.nn.i8.i32`

```asm
bdot.nn.i8.i32 vD, bA, tB
```

Vec8 与 Tile 各列执行点积, 结果写入 `i32` Vec32.

约束:

$
  op("dtype")("bA") & = "i8" \
  op("dtype")("tB") & = "i8" \
  op("dtype")("vD") & = "i32" \
    op("len")("bA") & = K \
   op("rows")("tB") & = K \
   op("cols")("tB") & = N \
    op("len")("vD") & = N
$

操作:

```text
for j = 0 ... N-1:
    sum = 0
    for k = 0 ... K-1:
        lhs = sign_extend_i8(bA[k])
        rhs = sign_extend_i8(tB[k,j])
        sum = sum + lhs * rhs
    vD[j] = sum
```

数学形式为:

$ "bA"_(1 times K) "tB"_(K times N) -> "vD"_(1 times N) $

== `bdot.nt.i8.i32`

```asm
bdot.nt.i8.i32 vD, bA, tB
```

Vec8 与 Tile 各行执行点积, 结果写入 `i32` Vec32.

约束:

$
  op("dtype")("bA") & = "i8" and op("dtype")("tB") = "i8" and op("dtype")("vD") = "i32" \
  op("len")("bA") & = K and op("len")("vD") = N \
  op("cols")("tB") & = K and op("rows")("tB") = N \
$

操作:

```text
for j = 0 ... N-1:
    sum = 0
    for k = 0 ... K-1:
        lhs = sign_extend_i8(bA[k])
        rhs = sign_extend_i8(tB[j,k])
        sum = sum + lhs * rhs
    vD[j] = sum
```

数学形式为:

$ "bA"_(1 times K) ("tB"_(N times K))^sans(T) -> "vD"_(1 times N) $

`bdot.nt` 使用 Tile 的每一行作为一个待匹配的向量:

$ "tB"[j, 0:K] $

== Decode 中的 $Q K^sans(T)$

以`head_dim = 128`为例, head dimension 可以分为四个 32-element 子块:

$ Q = [Q_0, Q_1, Q_2, Q_3], quad op("shape")(Q_d) = 1 times 32 $

每个 Query 子块可放入一个 Vec8:

$ Q_0 -> "b0", quad Q_1 -> "b1", quad Q_2 -> "b2", quad Q_3 -> "b3" $

对于一个包含 `N` 个 key 的 Tile:

$ op("shape")(K_0) = N times 32 $

其中每一行是一个 key 的 32 维子块.

在该子块上:

```asm
bdot.nt.i8.i32 vScore0, b0, tK0
```

产生:

$ "vScore0"_j = op("dot")(Q_0, K_0[j,:]) $

依次处理四个 head-dimension 子块:

```asm
bdot.nt.i8.i32 vScore0, b0, tK0
bdot.nt.i8.i32 vScore1, b1, tK1
vadd.i32       vScore0, vScore0, vScore1

bdot.nt.i8.i32 vScore1, b2, tK2
vadd.i32       vScore0, vScore0, vScore1

bdot.nt.i8.i32 vScore1, b3, tK3
vadd.i32       vScore0, vScore0, vScore1
```

得到:

$ "vScore0"_j = sum_(d=0)^3 op("dot")(Q_d, K_d[j,:]) $

这等价于:

$ Q K^sans(T) $

但具体的 scale, 反量化和 softmax 前缩放须由指令序列显式完成.

== Decode 中的 $P V$

假设一个 key block 有 `K` 个 token, V 的维度块宽度为 32:

$ op("shape")(P) = 1 times K, quad op("shape")(V) = K times 32 $

将 P 的 `i8` 量化值放入 Vec8, 将 V 的 `i8` block 放入 Tile:

$ "Pbits" -> "bP", "Vbits" -> "tV" $

然后执行:

```asm
bdot.nn.i8.i32 vOutRaw, bP, tV
```

产生:

$ "vOutRaw"_j = sum_(k=0)^(K-1) "Pbits"_k "Vbits"_(k,j) $

如果 V 的 scale 或 P 的 scale 不同, 须显式执行 scale 重建:

```text
vOutF32 = convert_i32_to_f32(vOutRaw)
vOutF32 = apply_scale(vOutF32, p_scale, v_scale)
```

随后可以使用 Vec32 累加:

```asm
vadd.f32 vOut, vOut, vOutF32
```

= 逐元素, 广播和 mask <elementwise>

本节定义 Tile, Acc, Vec8 和 Vec32 的逐元素运算, 按行/列广播, 比较, select 和 mask 操作.

本节中的基础运算只处理寄存器中的有效区域. 有效区域由目的寄存器对应的 `TC`, `AC`, `BC` 或 `VC` 配置确定.

普通逐元素操作必须满足:

1. 源和目的属于同一数据域;
2. 源和目的 dtype 相同;
3. 源和目的有效 shape 相同;
4. 所有动态行号和 lane 号均在有效范围内.

== 基础逐元素指令形式

以 `op` 表示某个合法的逐元素操作, 基础形式包括:

```asm
top.TYPE       tD, tA, tB
topx.TYPE      tD, tA, xS

aop.TYPE       aD, aA, aB
aopx.TYPE      aD, aA, xS

bop.TYPE       bD, bA, bB
bopx.TYPE      bD, bA, xS

vop.TYPE       vD, vA, vB
vopx.TYPE      vD, vA, xS
```

例如:

```asm
tadd.sat.i8 t0, t1, t2
badd.sat.i8 b0, b1, b2

aadd.f32   a0, a1, a2
vadd.f32   v0, v1, v2

vaddx.f32  v0, v1, x4
```

`x` 表示右操作数来自 Scalar 寄存器.

整块二元操作的语义为:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← op(A[i,j], B[i,j])
```

向量二元操作的语义为:

```text
for 0 <= j < len(D):
    D[j] ← op(A[j], B[j])
```

Scalar 形式的语义为:

```text
value ← decode_scalar(xS, TYPE)
D[element] ← op(A[element], value)
```

== 基础操作集合

基础逐元素操作按数据类型划分.

#manual-table(
  columns: (1.2fr, 4.5fr),
  caption: [逐元素操作与数据类型],
)[
  | dtype           | 基础操作                                                                              |
  | --------------- | ------------------------------------------------------------------------------------- |
  | `i8/u8`         | `add`, `sub`, `min`, `max`, `and`, `or`, `xor`, `not`, `shl`, `shr`, `sra`, `select`  |
  | `i32/u32`       | `add`, `sub`, `mul`, `min`, `max`, bitwise, shift, `cmp`, `select`                    |
  | `i32`           | 另外支持 `abs`, `neg`                                                                 |
  | `f32`           | `add`, `sub`, `mul`, `div`, `min`, `max`, `abs`, `neg`, `fma`, `cmp`, `select`        |
  | `f32` 近似函数  | `exp2.approx`, `rcp.approx`, `rsqrt.approx`                                           |
]

以下分 8-bit 域 (Tile/Vec8) 与 32-bit 域 (Acc/Vec32) 两表列出基础操作. 二元操作展开为寄存器和 Scalar (`x`) 两种来源; 低精度整数的 `sat`, `wrap` 分别列出. 一元操作仅列单源形式, 融合乘加, 特殊函数, 比较和 select 在各自小节列出. 每行的 `TYPE` 仅取该行给出的类型集合. `and`, `or`, `xor`, `not` 与 `select` 为按位操作, 不带类型后缀, 对域内任意 dtype 适用.

#instruction-table(caption: [Tile/Vec8 基础逐元素指令])[
  | Instruction            | Format  | Operation              | Notes                                         |
  | ---------------------- | ------- | ---------------------- | --------------------------------------------- |
  | `{t,b}add.sat.TYPE`    | 待定    | {t,b}D = sat(A + B)    | TYPE: `i8/u8`; 使用饱和结果.                  |
  | `{t,b}add.wrap.TYPE`   | 待定    | {t,b}D = wrap(A + B)   | TYPE: `i8/u8`; 保留低 8 bit.                  |
  | `{t,b}addx.sat.TYPE`   | 待定    | {t,b}D = sat(A + xS)   | TYPE: `i8/u8`; 使用饱和结果.                  |
  | `{t,b}addx.wrap.TYPE`  | 待定    | {t,b}D = wrap(A + xS)  | TYPE: `i8/u8`; 保留低 8 bit.                  |
  | `{t,b}sub.sat.TYPE`    | 待定    | {t,b}D = sat(A - B)    | TYPE: `i8/u8`; 使用饱和结果.                  |
  | `{t,b}sub.wrap.TYPE`   | 待定    | {t,b}D = wrap(A - B)   | TYPE: `i8/u8`; 保留低 8 bit.                  |
  | `{t,b}subx.sat.TYPE`   | 待定    | {t,b}D = sat(A - xS)   | TYPE: `i8/u8`; 使用饱和结果.                  |
  | `{t,b}subx.wrap.TYPE`  | 待定    | {t,b}D = wrap(A - xS)  | TYPE: `i8/u8`; 保留低 8 bit.                  |
  | `{t,b}min.TYPE`        | 待定    | {t,b}D = min(A, B)     | TYPE: `i8/u8`.                                |
  | `{t,b}minx.TYPE`       | 待定    | {t,b}D = min(A, xS)    | TYPE: `i8/u8`.                                |
  | `{t,b}max.TYPE`        | 待定    | {t,b}D = max(A, B)     | TYPE: `i8/u8`.                                |
  | `{t,b}maxx.TYPE`       | 待定    | {t,b}D = max(A, xS)    | TYPE: `i8/u8`.                                |
  | `{t,b}and`             | 待定    | {t,b}D = A and B       | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}andx`            | 待定    | {t,b}D = A and xS      | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}or`              | 待定    | {t,b}D = A or B        | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}orx`             | 待定    | {t,b}D = A or xS       | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}xor`             | 待定    | {t,b}D = A xor B       | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}xorx`            | 待定    | {t,b}D = A xor xS      | 按位操作, 与元素 dtype 无关.                  |
  | `{t,b}shl.TYPE`        | 待定    | {t,b}D = shl(A, B)     | TYPE: `i8/u8`.                                |
  | `{t,b}shlx.TYPE`       | 待定    | {t,b}D = shl(A, xS)    | TYPE: `i8/u8`.                                |
  | `{t,b}shr.TYPE`        | 待定    | {t,b}D = shr(A, B)     | TYPE: `i8/u8`.                                |
  | `{t,b}shrx.TYPE`       | 待定    | {t,b}D = shr(A, xS)    | TYPE: `i8/u8`.                                |
  | `{t,b}sra.TYPE`        | 待定    | {t,b}D = sra(A, B)     | TYPE: `i8/u8`.                                |
  | `{t,b}srax.TYPE`       | 待定    | {t,b}D = sra(A, xS)    | TYPE: `i8/u8`.                                |
  | `{t,b}not`             | 待定    | {t,b}D = not A         | 按位操作, 与元素 dtype 无关; 仅有一个数据源.  |
]

#instruction-table(caption: [Acc/Vec32 基础逐元素指令])[
  | Instruction       | Format  | Operation            | Notes                                                   |
  | ----------------- | ------- | -------------------- | ------------------------------------------------------- |
  | `{a,v}add.TYPE`   | 待定    | {a,v}D = A + B       | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}addx.TYPE`  | 待定    | {a,v}D = A + xS      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}sub.TYPE`   | 待定    | {a,v}D = A - B       | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}subx.TYPE`  | 待定    | {a,v}D = A - xS      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}mul.TYPE`   | 待定    | {a,v}D = A × B       | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}mulx.TYPE`  | 待定    | {a,v}D = A × xS      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}div.TYPE`   | 待定    | {a,v}D = A / B       | TYPE: `f32`.                                            |
  | `{a,v}divx.TYPE`  | 待定    | {a,v}D = A / xS      | TYPE: `f32`.                                            |
  | `{a,v}min.TYPE`   | 待定    | {a,v}D = min(A, B)   | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}minx.TYPE`  | 待定    | {a,v}D = min(A, xS)  | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}max.TYPE`   | 待定    | {a,v}D = max(A, B)   | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}maxx.TYPE`  | 待定    | {a,v}D = max(A, xS)  | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}and`        | 待定    | {a,v}D = A and B     | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}andx`       | 待定    | {a,v}D = A and xS    | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}or`         | 待定    | {a,v}D = A or B      | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}orx`        | 待定    | {a,v}D = A or xS     | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}xor`        | 待定    | {a,v}D = A xor B     | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}xorx`       | 待定    | {a,v}D = A xor xS    | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}shl.TYPE`   | 待定    | {a,v}D = shl(A, B)   | TYPE: `i32/u32`.                                        |
  | `{a,v}shlx.TYPE`  | 待定    | {a,v}D = shl(A, xS)  | TYPE: `i32/u32`.                                        |
  | `{a,v}shr.TYPE`   | 待定    | {a,v}D = shr(A, B)   | TYPE: `i32/u32`.                                        |
  | `{a,v}shrx.TYPE`  | 待定    | {a,v}D = shr(A, xS)  | TYPE: `i32/u32`.                                        |
  | `{a,v}sra.TYPE`   | 待定    | {a,v}D = sra(A, B)   | TYPE: `i32/u32`.                                        |
  | `{a,v}srax.TYPE`  | 待定    | {a,v}D = sra(A, xS)  | TYPE: `i32/u32`.                                        |
  | `{a,v}not`        | 待定    | {a,v}D = not A       | 按位操作, 与元素 dtype 无关; 仅有一个数据源.            |
  | `{a,v}abs.TYPE`   | 待定    | {a,v}D = abs(A)      | 类型: `i32/f32`; 仅有一个数据源.                        |
  | `{a,v}neg.TYPE`   | 待定    | {a,v}D = -A          | 类型: `i32/f32`; 仅有一个数据源.                        |
]



== 整数算术规则

对于 `i8/u8` 的 `add` 和 `sub`, 必须明确指定 `.sat` 或 `.wrap`:

```asm
tadd.sat.i8  t0, t1, t2
tadd.wrap.i8 t0, t1, t2

bsub.sat.u8  b0, b1, b2
```

=== Wrap 形式

对于宽度为 `w` 的整数类型:

$ op("wrap")_w(x) = x mod 2^w $

结果保留低 `w` bit, 并按目标 dtype 解释. 例如:

1. i8 wrap: 结果按 8 bit 保留;
2. u8 wrap: 结果按无符号 8 bit 保留.

=== Saturate 形式

对于 `i8`:

$ op("sat")_("i8")(x) = min(max(x, -128), 127) $

对于 `u8`:

$ op("sat")_("u8")(x) = min(max(x, 0), 255) $

对于 `i32/u32` 的 `add`, `sub` 和 `mul`, 默认使用 wrap32 回绕.

== 浮点逐元素规则

`fma` 运算使用 `fmadd` 助记符; 按 Acc/Vec32 的 f32 数据域列出. 这里只列三数据源形式, 其他操作数变体尚未定义.

#instruction-table(caption: [融合乘加指令])[
  | Instruction       | Format  | Operation              | Notes                                                   |
  | ----------------- | ------- | ---------------------- | ------------------------------------------------------- |
  | `{a,v}fmadd.f32`  | 待定    | {a,v}D = fma(A, B, C)  | 一次融合乘加, 一次 f32 舍入; 不能任意替换独立 mul/add.  |
]

f32 逐元素运算包括:

```asm
vadd.f32   vD, vA, vB
vsub.f32   vD, vA, vB
vmul.f32   vD, vA, vB
vdiv.f32   vD, vA, vB
vmin.f32   vD, vA, vB
vmax.f32   vD, vA, vB
vabs.f32   vD, vA
vneg.f32   vD, vA
vfmadd.f32 vD, vA, vB, vC
```

`fma` 定义为一次融合乘加:

$ D_i = op("round")_("f32")(A_i B_i + C_i) $

#warning[
  `fma(A, B, C)` 与先 `mul(A, B)` 再 `add(..., C)` 不保证数值等价, 因此编译器不能自动把 `mul` 与 `add` 合并成 `fma`.
]

== 近似特殊函数

近似特殊函数对 Acc 或 Vec32 的 f32 有效区域逐元素求值.

#instruction-table(caption: [近似特殊函数指令])[
  | Instruction          | Format  | Operation                 | Notes                                        |
  | -------------------- | ------- | ------------------------- | -------------------------------------------- |
  | `{a,v}exp2.approx`   | 待定    | {a,v}D = exp2_approx(A)   | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
  | `{a,v}rcp.approx`    | 待定    | {a,v}D = rcp_approx(A)    | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
  | `{a,v}rsqrt.approx`  | 待定    | {a,v}D = rsqrt_approx(A)  | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
]

基础 f32 近似函数为:

```asm
aexp2.approx  aD, aS
arcp.approx   aD, aS
arsqrt.approx aD, aS

vexp2.approx  vD, vS
vrcp.approx   vD, vS
vrsqrt.approx vD, vS
```

这些指令对有效区域逐元素执行. 向量形式为:

```text
for 0 ≤ j < len(D):
    D[j] = f(S[j])
```

矩阵形式为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        D[i,j] = f(S[i,j])
```

== 行广播

=== Tile/Acc 行广播

右矩阵指定行的各列元素广播到每个目的行.

#instruction-table(caption: [矩阵源行广播指令])[
  | Instruction            | Format  | Operation                        | Notes                                                   |
  | ---------------------- | ------- | -------------------------------- | ------------------------------------------------------- |
  | `tadd.brow.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] + B[rb,j])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `tadd.brow.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] + B[rb,j])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tsub.brow.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] - B[rb,j])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `tsub.brow.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] - B[rb,j])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tmin.brow.TYPE`       | 待定    | D[i,j] = min(A[i,j], B[rb,j])    | TYPE: `i8/u8`.                                          |
  | `tmax.brow.TYPE`       | 待定    | D[i,j] = max(A[i,j], B[rb,j])    | TYPE: `i8/u8`.                                          |
  | `tand.brow`            | 待定    | D[i,j] = A[i,j] and B[rb,j]      | 按位操作, 与元素 dtype 无关.                            |
  | `tor.brow`             | 待定    | D[i,j] = A[i,j] or B[rb,j]       | 按位操作, 与元素 dtype 无关.                            |
  | `txor.brow`            | 待定    | D[i,j] = A[i,j] xor B[rb,j]      | 按位操作, 与元素 dtype 无关.                            |
  | `tshl.brow.TYPE`       | 待定    | D[i,j] = shl(A[i,j], B[rb,j])    | TYPE: `i8/u8`.                                          |
  | `tshr.brow.TYPE`       | 待定    | D[i,j] = shr(A[i,j], B[rb,j])    | TYPE: `i8/u8`.                                          |
  | `tsra.brow.TYPE`       | 待定    | D[i,j] = sra(A[i,j], B[rb,j])    | TYPE: `i8/u8`.                                          |
  | `aadd.brow.TYPE`       | 待定    | D[i,j] = A[i,j] + B[rb,j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asub.brow.TYPE`       | 待定    | D[i,j] = A[i,j] - B[rb,j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amul.brow.TYPE`       | 待定    | D[i,j] = A[i,j] × B[rb,j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adiv.brow.TYPE`       | 待定    | D[i,j] = A[i,j] / B[rb,j]        | TYPE: `f32`.                                            |
  | `amin.brow.TYPE`       | 待定    | D[i,j] = min(A[i,j], B[rb,j])    | TYPE: `i32/u32/f32`.                                    |
  | `amax.brow.TYPE`       | 待定    | D[i,j] = max(A[i,j], B[rb,j])    | TYPE: `i32/u32/f32`.                                    |
  | `aand.brow`            | 待定    | D[i,j] = A[i,j] and B[rb,j]      | 按位操作, 与元素 dtype 无关.                            |
  | `aor.brow`             | 待定    | D[i,j] = A[i,j] or B[rb,j]       | 按位操作, 与元素 dtype 无关.                            |
  | `axor.brow`            | 待定    | D[i,j] = A[i,j] xor B[rb,j]      | 按位操作, 与元素 dtype 无关.                            |
  | `ashl.brow.TYPE`       | 待定    | D[i,j] = shl(A[i,j], B[rb,j])    | TYPE: `i32/u32`.                                        |
  | `ashr.brow.TYPE`       | 待定    | D[i,j] = shr(A[i,j], B[rb,j])    | TYPE: `i32/u32`.                                        |
  | `asra.brow.TYPE`       | 待定    | D[i,j] = sra(A[i,j], B[rb,j])    | TYPE: `i32/u32`.                                        |
]

Tile 或 Acc 可以将右操作数的一行广播到目的对象的每一行:

```asm
top.brow.TYPE tD, tA, tB[rb]

aop.brow.TYPE aD, aA, aB[rb]
```

执行语义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        D[i,j] ← op(A[i,j], B[rb,j])
```

例如, 选择饱和减法:

```asm
tsub.brow.sat.i8 t0, t1, t2[0]
```

表示:

$ "t0"_(i,j) = op("sat")_("i8")("t1"_(i,j) - "t2"_(0,j)) $

=== 按行广播

Tile 使用 Vec8, Acc 使用 Vec32; 向量的第 i 个元素广播到矩阵第 i 行.

#instruction-table(caption: [向量按行广播指令])[
  | Instruction              | Format  | Operation                     | Notes                                                   |
  | ------------------------ | ------- | ----------------------------- | ------------------------------------------------------- |
  | `taddb.byrow.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] + S[i])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `taddb.byrow.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] + S[i])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tsubb.byrow.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] - S[i])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `tsubb.byrow.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] - S[i])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tminb.byrow.TYPE`       | 待定    | D[i,j] = min(A[i,j], S[i])    | TYPE: `i8/u8`.                                          |
  | `tmaxb.byrow.TYPE`       | 待定    | D[i,j] = max(A[i,j], S[i])    | TYPE: `i8/u8`.                                          |
  | `tandb.byrow`            | 待定    | D[i,j] = A[i,j] and S[i]      | 按位操作, 与元素 dtype 无关.                            |
  | `torb.byrow`             | 待定    | D[i,j] = A[i,j] or S[i]       | 按位操作, 与元素 dtype 无关.                            |
  | `txorb.byrow`            | 待定    | D[i,j] = A[i,j] xor S[i]      | 按位操作, 与元素 dtype 无关.                            |
  | `tshlb.byrow.TYPE`       | 待定    | D[i,j] = shl(A[i,j], S[i])    | TYPE: `i8/u8`.                                          |
  | `tshrb.byrow.TYPE`       | 待定    | D[i,j] = shr(A[i,j], S[i])    | TYPE: `i8/u8`.                                          |
  | `tsrab.byrow.TYPE`       | 待定    | D[i,j] = sra(A[i,j], S[i])    | TYPE: `i8/u8`.                                          |
  | `aaddv.byrow.TYPE`       | 待定    | D[i,j] = A[i,j] + S[i]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asubv.byrow.TYPE`       | 待定    | D[i,j] = A[i,j] - S[i]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amulv.byrow.TYPE`       | 待定    | D[i,j] = A[i,j] × S[i]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adivv.byrow.TYPE`       | 待定    | D[i,j] = A[i,j] / S[i]        | TYPE: `f32`.                                            |
  | `aminv.byrow.TYPE`       | 待定    | D[i,j] = min(A[i,j], S[i])    | TYPE: `i32/u32/f32`.                                    |
  | `amaxv.byrow.TYPE`       | 待定    | D[i,j] = max(A[i,j], S[i])    | TYPE: `i32/u32/f32`.                                    |
  | `aandv.byrow`            | 待定    | D[i,j] = A[i,j] and S[i]      | 按位操作, 与元素 dtype 无关.                            |
  | `aorv.byrow`             | 待定    | D[i,j] = A[i,j] or S[i]       | 按位操作, 与元素 dtype 无关.                            |
  | `axorv.byrow`            | 待定    | D[i,j] = A[i,j] xor S[i]      | 按位操作, 与元素 dtype 无关.                            |
  | `ashlv.byrow.TYPE`       | 待定    | D[i,j] = shl(A[i,j], S[i])    | TYPE: `i32/u32`.                                        |
  | `ashrv.byrow.TYPE`       | 待定    | D[i,j] = shr(A[i,j], S[i])    | TYPE: `i32/u32`.                                        |
  | `asrav.byrow.TYPE`       | 待定    | D[i,j] = sra(A[i,j], S[i])    | TYPE: `i32/u32`.                                        |
]

Tile 使用 Vec8 作为每一行的标量源:

```asm
topb.byrow.TYPE tD, tA, bS
```

Acc/Vec32 使用 Vec32 作为每一行的标量源:

```asm
aopv.byrow.TYPE aD, aA, vS
```

执行语义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        D[i,j] ← op(A[i,j], S[i])
```

例如:

```asm
amulv.byrow.f32 a0, a1, v0
```

表示:

$ "a0"_(i,j) = "a1"_(i,j) "v0"_i $

=== 按列广播

Tile 使用 Vec8, Acc 使用 Vec32; 向量的第 j 个元素广播到矩阵第 j 列.

#instruction-table(caption: [向量按列广播指令])[
  | Instruction              | Format  | Operation                     | Notes                                                   |
  | ------------------------ | ------- | ----------------------------- | ------------------------------------------------------- |
  | `taddb.bycol.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] + S[j])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `taddb.bycol.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] + S[j])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tsubb.bycol.sat.TYPE`   | 待定    | D[i,j] = sat(A[i,j] - S[j])   | TYPE: `i8/u8`; 使用饱和结果.                            |
  | `tsubb.bycol.wrap.TYPE`  | 待定    | D[i,j] = wrap(A[i,j] - S[j])  | TYPE: `i8/u8`; 保留低 8 bit.                            |
  | `tminb.bycol.TYPE`       | 待定    | D[i,j] = min(A[i,j], S[j])    | TYPE: `i8/u8`.                                          |
  | `tmaxb.bycol.TYPE`       | 待定    | D[i,j] = max(A[i,j], S[j])    | TYPE: `i8/u8`.                                          |
  | `tandb.bycol`            | 待定    | D[i,j] = A[i,j] and S[j]      | 按位操作, 与元素 dtype 无关.                            |
  | `torb.bycol`             | 待定    | D[i,j] = A[i,j] or S[j]       | 按位操作, 与元素 dtype 无关.                            |
  | `txorb.bycol`            | 待定    | D[i,j] = A[i,j] xor S[j]      | 按位操作, 与元素 dtype 无关.                            |
  | `tshlb.bycol.TYPE`       | 待定    | D[i,j] = shl(A[i,j], S[j])    | TYPE: `i8/u8`.                                          |
  | `tshrb.bycol.TYPE`       | 待定    | D[i,j] = shr(A[i,j], S[j])    | TYPE: `i8/u8`.                                          |
  | `tsrab.bycol.TYPE`       | 待定    | D[i,j] = sra(A[i,j], S[j])    | TYPE: `i8/u8`.                                          |
  | `aaddv.bycol.TYPE`       | 待定    | D[i,j] = A[i,j] + S[j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asubv.bycol.TYPE`       | 待定    | D[i,j] = A[i,j] - S[j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amulv.bycol.TYPE`       | 待定    | D[i,j] = A[i,j] × S[j]        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adivv.bycol.TYPE`       | 待定    | D[i,j] = A[i,j] / S[j]        | TYPE: `f32`.                                            |
  | `aminv.bycol.TYPE`       | 待定    | D[i,j] = min(A[i,j], S[j])    | TYPE: `i32/u32/f32`.                                    |
  | `amaxv.bycol.TYPE`       | 待定    | D[i,j] = max(A[i,j], S[j])    | TYPE: `i32/u32/f32`.                                    |
  | `aandv.bycol`            | 待定    | D[i,j] = A[i,j] and S[j]      | 按位操作, 与元素 dtype 无关.                            |
  | `aorv.bycol`             | 待定    | D[i,j] = A[i,j] or S[j]       | 按位操作, 与元素 dtype 无关.                            |
  | `axorv.bycol`            | 待定    | D[i,j] = A[i,j] xor S[j]      | 按位操作, 与元素 dtype 无关.                            |
  | `ashlv.bycol.TYPE`       | 待定    | D[i,j] = shl(A[i,j], S[j])    | TYPE: `i32/u32`.                                        |
  | `ashrv.bycol.TYPE`       | 待定    | D[i,j] = shr(A[i,j], S[j])    | TYPE: `i32/u32`.                                        |
  | `asrav.bycol.TYPE`       | 待定    | D[i,j] = sra(A[i,j], S[j])    | TYPE: `i32/u32`.                                        |
]

Tile 使用 Vec8 作为每一列的标量源:

```asm
topb.bycol.TYPE tD, tA, bS
```

Acc/Vec32 使用 Vec32 作为每一列的标量源:

```asm
aopv.bycol.TYPE aD, aA, vS
```

执行语义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        D[i,j] ← op(A[i,j], S[j])
```

例如:

```asm
amulv.bycol.f32 a0, a1, v0
```

表示:

$ "a0"_(i,j) = "a1"_(i,j) "v0"_j $

`bycol` 是逻辑列广播. 硬件可以按行读取矩阵, 然后在每个 lane 上选择 `S[j]`.

== 比较指令

条件取独立子集: 整数为 `eq/ne/lt/ge`, `gt` 与 `le` 由交换两个源操作数获得; f32 为 `eq/lt/le/unord`, `ord` 由 `unord` 结果取反获得, `ne` 由 `eq` 结果取反获得. 比较只在 Acc 与 Vec32 上定义, 分寄存器和 Scalar 两种形式. `TYPE` 为源数值类型, 目的为同宽 mask.

#instruction-table(caption: [比较指令])[
  | Instruction            | Format  | Operation                  | Notes                                                    |
  | ---------------------- | ------- | -------------------------- | -------------------------------------------------------- |
  | `{a,v}cmp.eq.TYPE`     | 待定    | {a,v}D = A == B            | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmp.ne.TYPE`     | 待定    | {a,v}D = A != B            | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmp.lt.TYPE`     | 待定    | {a,v}D = A < B             | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmp.ge.TYPE`     | 待定    | {a,v}D = A >= B            | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmp.le.f32`      | 待定    | {a,v}D = A <= B            | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmp.unord.f32`   | 待定    | {a,v}D = unordered(A, B)   | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmpx.eq.TYPE`    | 待定    | {a,v}D = A == xS           | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmpx.ne.TYPE`    | 待定    | {a,v}D = A != xS           | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmpx.lt.TYPE`    | 待定    | {a,v}D = A < xS            | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmpx.ge.TYPE`    | 待定    | {a,v}D = A >= xS           | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmpx.le.f32`     | 待定    | {a,v}D = A <= xS           | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmpx.unord.f32`  | 待定    | {a,v}D = unordered(A, xS)  | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
]

比较指令产生 mask 数据:

```asm
acmp.COND.TYPE   aM, aA, aB
vcmp.COND.TYPE   vM, vA, vB
```

Scalar 形式为:

```asm
acmpx.COND.TYPE  aM, aA, xS
vcmpx.COND.TYPE  vM, vA, xS
```

整数条件为 `eq/ne/lt/ge`; f32 条件为 `eq/lt/le/unord`; 其余条件由交换操作数或对 mask 取反获得.

比较结果定义为:

```text
true  → u8 lane 为 0xff, u32 lane 为 0xffffffff
false → 0
```

对于矩阵比较:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        D[i,j] = predicate(A[i,j], B[i,j])
```

对于向量比较:

```text
for 0 ≤ j < len(D):
    D[j] = predicate(A[j], B[j])
```

比较目的寄存器的 dtype 应是 `u8`/`u32`. 作为 mask 使用的整数元素应取全 0 (假) 或全 1 (真); 非规范值参与位运算组合时, 不保证等价于逻辑运算.

== Select 指令

#instruction-table(caption: [选择指令])[
  | Instruction    | Format  | Operation           | Notes                                                            |
  | -------------- | ------- | ------------------- | ---------------------------------------------------------------- |
  | `{t,b}select`  | 待定    | {t,b}D = M ? A : B  | 按位选择, 与元素 dtype 无关; mask 为 `u8`, 两个数据源均被读取.   |
  | `{a,v}select`  | 待定    | {a,v}D = M ? A : B  | 按位选择, 与元素 dtype 无关; mask 为 `u32`, 两个数据源均被读取.  |
]

select 根据 mask 在两个已经计算好的值之间选择(t/b 数据使用 `u8`, a/v 数据使用 `u32`.):

```asm
tselect tD, tM, tA, tB
aselect aD, aM, aA, aB
bselect bD, bM, bA, bB
vselect vD, vM, vA, vB
```

执行语义为:

```text
if M[element] != 0:
    D[element] ← A[element]
else:
    D[element] ← B[element]
```

select 必须读取两个数据源: M 为 true 时选择 A; M 为 false 时选择 B; A 和 B 都是已经计算好的架构数据.

== Mask 指令

mask 使用寄存器配置中的 dtype; 它改写数据值, 保留区域之外写入显式 fill 值.

#instruction-table(caption: [Mask 指令])[
  | Instruction       | Format  | Operation                                                | Notes                                         |
  | ----------------- | ------- | -------------------------------------------------------- | --------------------------------------------- |
  | `{t,a}mask.tail`  | 待定    | {t,a}D[i,j] = (i < xRows and j < xCols) ? S[i,j] : fill  | 其余有效寄存器位置写 fill; 不缩短有效 shape.  |
  | `{t,a}mask.tril`  | 待定    | {t,a}D[i,j] = (j - i <= xDelta) ? S[i,j] : fill          | 有符号偏移; 包含边界, 其余位置写 fill.        |
  | `{t,a}mask.triu`  | 待定    | {t,a}D[i,j] = (j - i >= xDelta) ? S[i,j] : fill          | 有符号偏移; 包含边界, 其余位置写 fill.        |
  | `{b,v}mask.tail`  | 待定    | {b,v}D[j] = (j < xLen) ? S[j] : fill                     | 其余有效 lane 写 fill; 不缩短有效长度.        |
]

mask 指令将源数据的某些位置替换为指定 fill 值.

矩阵 mask:

```asm
{t,a}mask.tail D, S, xRows, xCols, fill
{t,a}mask.tril D, S, xDelta, fill
{t,a}mask.triu D, S, xDelta, fill
```

向量 mask:

```asm
{b,v}mask.tail D, S, xLen, fill
```

=== Tail mask

矩阵 tail mask 定义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        if i < xRows and j < xCols:
            D[i,j] ← S[i,j]
        else:
            D[i,j] ← fill
```

向量 tail mask 定义为:

```text
for 0 ≤ j < len(D):
    if j < xLen:
        D[j] ← S[j]
    else:
        D[j] ← fill
```

=== 下三角 mask

下三角 mask 使用有符号 `xDelta`:

```asm
amask.tril aD, aS, xDelta, fill
tmask.tril tD, tS, xDelta, fill
```

局部坐标语义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        if j - i ≤ xDelta:
            D[i,j] ← S[i,j]
        else:
            D[i,j] ← fill
```

边界相等时保留元素.

例如`xDelta = 0`表示保留主对角线及其下方元素; `xDelta = 1`表示额外保留主对角线上方一条对角线.

=== 上三角 mask

上三角 mask 定义为:

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        if j - i ≥ xDelta:
            D[i,j] ← S[i,j]
        else:
            D[i,j] ← fill
```

例如 `xDelta = 0`表示保留主对角线及其上方元素.

== 示例

=== Attention score 的 causal mask

```asm
amask.tril aScore, aScore, xDelta, neg_inf
```

其逻辑含义是:

$
  "aScore"_(i,j) = cases(
    "old_score"_(i,j) & "if" j - i <= "xDelta",
    -infinity & "else",
  )
$

其中 `xDelta` 已经由全局 query/key 起点计算得到.

=== Vec32 的逐元素 softmax 后处理

```asm
vsub.f32       v0, vScore, vMax
vmul.f32       v1, v0, vLog2e
vexp2.approx   v2, v1
vdiv.f32       vOut, v2, vSum
```

= 规约与类型转换 <reduction-conversion>

本节定义矩阵规约, 向量规约, Scalar 规约, 数据类型转换和低精度扩大转换. 规约指令将多个元素合并为一个或多个结果.

== 规约指令格式

行规约每行产生一个 Vec32 元素. 除基础 `sum/max/min` 外, 正文示例还定义了 `areduce.rows.sumsq.f32`; 向量规约另含 f32 `sumsq` 与 `argmax`.

#instruction-table(caption: [规约指令])[
  | Instruction               | Format  | Operation                      | Notes                                        |
  | ------------------------- | ------- | ------------------------------ | -------------------------------------------- |
  | `areduce.rows.sum.f32`    | 待定    | vD[i] = sum_j aS[i,j]          | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.max.f32`    | 待定    | vD[i] = max_j aS[i,j]          | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.min.f32`    | 待定    | vD[i] = min_j aS[i,j]          | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.sumsq.f32`  | 待定    | vD[i] = sum_j aS[i,j]^2        | 源与目的为 f32; RMSNorm 示例中的行规约.      |
  | `vreduce.sum.f32`         | 待定    | xD = sum_j vS[j]               | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.max.f32`         | 待定    | xD = max_j vS[j]               | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.min.f32`         | 待定    | xD = min_j vS[j]               | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.sumsq.f32`       | 待定    | xD = sum_j vS[j]^2             | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.argmax.f32`      | 待定    | (xIndex, xValue) = argmax(vS)  | 并列取较小索引; NaN 选择规则及空结果见正文.  |
]

基础矩阵规约形式为:

```asm
areduce.rows.OP.f32   vD, aS
```

其中$"OP" in {"sum", "max", "min"}$

基础形式包括:

```asm
areduce.rows.sum.f32    vD, aS
areduce.rows.max.f32    vD, aS
areduce.rows.min.f32    vD, aS
```

向量到 Scalar 的规约形式为:

```asm
vreduce.sum.f32       xD, vS
vreduce.max.f32       xD, vS
vreduce.min.f32       xD, vS
vreduce.sumsq.f32     xD, vS
vreduce.argmax.f32    xIndex, xValue, vS
```

== 矩阵按行规约

=== `areduce.rows.*.f32`

源 Acc 的有效 shape 为:

$
  R & = op("rows")("aS") \
  C & = op("cols")("aS")
$

目的 Vec32 须满足:

$
  op("dtype")("vD") & = "f32" \
    op("len")("vD") & = R
$

`areduce.rows.sum.f32` 的操作为:

```text
for i = 0 ... R-1:
    sum = +0.0
    for j = 0 ... C-1:
        sum = fold_add(sum, aS[i,j])
    vD[i] = sum
```

`areduce.rows.max.f32` 的操作为:

```text
for i = 0 ... R-1:
    value = -inf
    for j = 0 ... C-1:
        value = fold_max(value, aS[i,j])
    vD[i] = value
```

`areduce.rows.min.f32` 的操作为:

```text
for i = 0 ... R-1:
    value = +inf
    for j = 0 ... C-1:
        value = fold_min(value, aS[i,j])
    vD[i] = value
```

== 向量到 Scalar 的规约

=== Vec32 浮点规约

对于:

```asm
vreduce.sum.f32   xD, vS
vreduce.max.f32   xD, vS
vreduce.min.f32   xD, vS
vreduce.sumsq.f32 xD, vS
```

设$N = op("len")("vS")$

源 `vS` 必须$op("dtype")("vS") = "f32"$

sum:

```text
value = +0.0
for j = 0 ... N-1:
    value = fold_add(value, vS[j])
```

max:

```text
value = -inf
for j = 0 ... N-1:
    value = fold_max(value, vS[j])
```

min:

```text
value = +inf
for j = 0 ... N-1:
    value = fold_min(value, vS[j])
```

sumsq:

```text
value = +0.0
for j = 0 ... N-1:
    product = round_f32(vS[j] × vS[j])
    value = fold_add(value, product)
```

== Argmax

```asm
vreduce.argmax.f32 xIndex, xValue, vS
```

将 `f32` Vec32 的有效 lane 取最大值, 输出其逻辑索引与浮点位模式到两个 Scalar.

约束: 源 `vS` 的 dtype 须为 `f32`. 两个输出的解释为:

```text
xIndex: 最大值的逻辑索引, i32 语义, 符号扩展到 64 bit
xValue: 最大值的 f32 位模式, 写入低 32 bit, 高 32 bit 清零
```

操作:

```text
if len(vS) == 0:
    xIndex = -1
    xValue = -inf
else:
    best_index = 0
    best_value = vS[0]

    for j = 1 ... len(vS)-1:
        candidate = vS[j]

        if candidate is NaN:
            if best_value is not NaN:
                choose candidate
            else if j < best_index:
                choose candidate
        else if best_value is NaN:
            keep best_value
        else if candidate > best_value:
            choose candidate
        else if candidate == best_value and j < best_index:
            choose candidate
```

如果算子需要忽略显式 mask 的位置, 不能只依赖 `-inf` 填充. 因为真实输入也可能是 `-inf`, 而且填充位置仍属于当前有效 Vector shape.

正确做法是缩短 `vS.len`; 或保留显式候选有效性; 或使用带有效性输入的专用 argmax 展开.

== 空规约和单位元

空规约的结果由规约类型决定.

#manual-table(
  columns: (1.1fr, 3.5fr),
  caption: [空规约结果与单位元],
)[
  | 规约        | 空结果                                 |
  | ----------- | -------------------------------------- |
  | f32 sum     | $+0.0$                                 |
  | f32 sumsq   | $+0.0$                                 |
  | f32 max     | $-infinity$                            |
  | f32 min     | $+infinity$                            |
  | f32 argmax  | $"index" = -1$, $"value" = -infinity$  |
]

空规约可能由以下情况产生: 源的 $"rows" = 0$, $"cols" = 0$ 或 $"len" = 0$; 逻辑 view 与有效 shape 的交集为空.

== 类型转换指令

#instruction-table(caption: [类型转换与扩大指令])[
  | Instruction      | Format  | Operation                    | Notes                                    |
  | ---------------- | ------- | ---------------------------- | ---------------------------------------- |
  | `acvt.i32.f32`   | 待定    | aD[i,j] = f32(aS[i,j])       | 允许原地执行; 成功接收时更新目的 dtype.  |
  | `vcvt.i32.f32`   | 待定    | vD[j] = f32(vS[j])           | 允许原地执行; 成功接收时更新目的 dtype.  |
  | `twiden.i8.i32`  | 待定    | aD[i,j] = sign_ext(tS[i,j])  | 跨数据域, 不能原地执行; 保持有效 shape.  |
]

本节的转换助记符采用源类型在前, 目的类型在后:

```text
<source type>.<destination type>
```

将 `i32` 数据逐元素转换为 `f32`:

```asm
acvt.i32.f32 aD, aS
vcvt.i32.f32 vD, vS
```

`acvt` 操作:

```text
for 0 ≤ i < rows(aD):
    for 0 ≤ j < cols(aD):
        aD[i,j] = convert_f32(aS[i,j])
```

`vcvt` 操作:

```text
for 0 ≤ j < len(vD):
    vD[j] = convert_f32(vS[j])
```

`acvt` 和 `vcvt` 都允许原地使用:

```asm
acvt.i32.f32 a0, a0
vcvt.i32.f32 v0, v0
```

原地转换必须先读取源元素, 再写回目的元素. 目的 dtype 在该转换操作被成功接收时更新; 后续消费者按照新的 dtype 等待结果, 已经被接收的旧消费者仍按照转换前的源 dtype 执行.

== Tile 到 Acc 的扩大转换

```asm
twiden.i8.i32 aD, tS
```

将 Tile 的 `i8` 符号扩展到 Acc 的 `i32`. 跨数据域, 不能原地执行; 目的 Acc 的有效 shape 与源 Tile 相同.

操作:

```text
for 0 ≤ i < rows(tS):
    for 0 ≤ j < cols(tS):
        aD[i,j] = sign_extend_i8_to_i32(tS[i,j])
```

== 示例

=== RMSNorm 行规约

```asm
areduce.rows.sumsq.f32 vSumSq, aX
vrsqrt.approx         vInv, vSumSq
amulv.byrow.f32       aY, aX, vInv
```

其逻辑含义为:

$
  "vSumSq"_i & = sum_(j=0)^(op("cols")("aX")-1) ("aX"_(i,j))^2 \
    "vInv"_i & = op("rsqrt.approx")("vSumSq"_i) \
  "aY"_(i,j) & = "aX"_(i,j) "vInv"_i
$

如果需要加 epsilon, 应先执行显式的 Vec32 操作:

```asm
vadd.f32 vSumSq, vSumSq, vEpsilon
vrsqrt.approx vInv, vSumSq
```

=== `i8` Tile 扩大到 Acc

```asm
twiden.i8.i32 aRaw, tInput
```

其逻辑含义为:

$ "aRaw"_(i,j) = op("sign_extend_i8")("tInput"_(i,j)) $

如果后续需要 `f32`:

```asm
acvt.i32.f32 aFloat, aRaw
```

如果需要反量化:

```asm
amulv.bycol.f32 aFloat, aFloat, vScale
```

或使用明确的 scale 乘法指令.

=== Vec8 dot 结果转 `f32`

```asm
bdot.nt.i8.i32 vRaw, bQ, tK
vcvt.i32.f32   vScore, vRaw
vmul.f32       vScore, vScore, vScale
```

这三条指令分别表示:

```text
vRaw   = i8 dot product
vScore = i32 转 f32
vScore = vScore × scale
```

= 量化与反量化 <quantization>

bits 和 scale 都是显式操作数. Q8 MMA, decode scale 重建与 P×V 量化流程是基础指令序列, 不另外分配复合指令助记符.

#instruction-table(caption: [量化与反量化指令])[
  | Instruction          | Format  | Operation                                    | Notes                                          |
  | -------------------- | ------- | -------------------------------------------- | ---------------------------------------------- |
  | `tquant.rows.q8s32`  | 待定    | (tD[i,:], vScale[i]) = quant_q8s32(aS[i,:])  | Tile bits 与 Vec32 scale 是两个显式目的.       |
  | `vquant.q8s32`       | 待定    | (bD, vScale[lane]) = quant_q8s32(vS)         | Vec8 bits 与 Vec32 scale lane 是两个显式目的.  |
  | `tdequant.rows.f32`  | 待定    | aD[i,j] = tS[i,j] vScale[i]                  | Tile bits 和 Vec32 scale 都是显式源.           |
  | `bdequant.f32`       | 待定    | vD[j] = bS[j] vScale[lane]                   | Vec8 bits 和 Vec32 scale lane 都是显式源.      |
]

```asm
tquant.rows.q8s32 tD, vScale, aS
vquant.q8s32      bD, vScale[lane], vS
tdequant.rows.f32 aD, tS, vScale
bdequant.f32      vD, bS, vScale[lane]
```

矩阵行量化每行产生一个 scale; 向量量化产生一个 scale. bits 和 scale 是两个显式目的/源, 依赖与生命周期必须一起跟踪. 内部动态量化使用具名格式 q8s32, 外部权重保留原始 bits/scale; 舍入与特殊值规则待定义.

Q8 MMA 是以下基础指令的复合操作, 不隐藏临时 Acc:

```asm
mma.nn.zero.i8.i32 aTmp, tA, tB
acvt.i32.f32       aTmp, aTmp
amulv.byrow.f32    aTmp, aTmp, vAs
amulv.bycol.f32    aTmp, aTmp, vBs
aadd.f32          aOut, aOut, aTmp
```

aOut 预先初始化, aTmp 与 aOut 分开. 每个 K 块分别 scale 后再累加. Decode 对应 `bdot → vcvt → scale → vadd`, raw 临时使用 v.

在 $P V$ 中, 当 `Vscale` 位于规约轴时, 先在 Vec32 中计算:

$ "Pscaled" = P "Vscale" $

再 vquant 到 b, 随后 bdot; 每个 V 维度块从原始 P 重建, 结果只乘 Pscale. 这是需要明确允许量化误差的算法选择, 不是 `f32` $P V$ 的无损替代.

= 指令集清单 <instructions>

本章按正文的章节顺序列出已命名的指令, 并展开通用二元操作中的数据域, 操作名, 操作数来源, 行/广播模式和低精度整数的饱和/回绕变体. 每行是一个指令形式; 类型参数的多种取值不在这里重复展开.

== 清单说明

`Format`, `Opcode` 和 `Function` 为尚待定义的二进制编码字段, 统一标为待定. `TYPE` 的合法取值以对应章节的每行说明为准; 带固定类型后缀的指令直接按该类型解释. 比较条件取独立子集: 整数为 `eq/ne/lt/ge`, f32 为 `eq/lt/le/unord`; `gt`/`le` 由交换操作数获得, `ord` 由 `unord` 取反获得.

Scalar 指令集为 RV64IM, 其指令不在本清单. `getcap` 的操作数与返回字段仍待定义. 各类尚未定义的变体均不作为已分配编码处理.

== 标量与同步

详细语义见 @scalar-sync.

#instruction-listing(caption: [能力查询与同步指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                            |
  | ------------- | ------- | ------- | --------- | ---------------------------------- |
  | `getcap`      | 待定    | 待定    | 待定      | 查询资源规格, 扩展和数值能力.      |
  | `fence.mem`   | 待定    | 待定    | 待定      | 等待此前访存完成并达到约定可见点.  |
  | `fence.sa`    | 待定    | 待定    | 待定      | 等待此前 SA 操作完成.              |
  | `fence.all`   | 待定    | 待定    | 待定      | 等待此前全部后端工作完成.          |
  | `kernel.end`  | 待定    | 待定    | 待定      | 报告 kernel 完成.                  |
]

== 配置指令

详细语义见 @configuration.

#instruction-listing(caption: [配置指令清单])[
  | Instruction  | Format  | Opcode  | Function  | Summary                                    |
  | ------------ | ------- | ------- | --------- | ------------------------------------------ |
  | `cfg.seti`   | 待定    | 待定    | 待定      | 扩展立即数, 校验后写入指定配置字段.        |
  | `cfg.setx`   | 待定    | 待定    | 待定      | 从 Scalar 读取完整值, 校验后写入配置字段.  |
  | `cfg.copy`   | 待定    | 待定    | 待定      | 复制同类型配置寄存器的全部字段.            |
  | `cfg.get`    | 待定    | 待定    | 待定      | 读取配置字段, 扩展后写入 Scalar.           |
]

== 地址与访存指令

详细语义见 @memory.

#instruction-listing(caption: [地址与访存指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                                |
  | ------------- | ------- | ------- | --------- | -------------------------------------- |
  | `tload`       | 待定    | 待定    | 待定      | 从 TM 描述的内存读取到 Tile 有效区域.  |
  | `tstore`      | 待定    | 待定    | 待定      | 将 Tile 有效区域写入 TM 描述的内存.    |
  | `tload.row`   | 待定    | 待定    | 待定      | 从 TM 描述的内存读取到 Tile 指定行.    |
  | `tstore.row`  | 待定    | 待定    | 待定      | 将 Tile 指定行写入 TM 描述的内存.      |
  | `aload`       | 待定    | 待定    | 待定      | 从 TM 描述的内存读取到 Acc 有效区域.   |
  | `astore`      | 待定    | 待定    | 待定      | 将 Acc 有效区域写入 TM 描述的内存.     |
  | `aload.row`   | 待定    | 待定    | 待定      | 从 TM 描述的内存读取到 Acc 指定行.     |
  | `astore.row`  | 待定    | 待定    | 待定      | 将 Acc 指定行写入 TM 描述的内存.       |
  | `bload`       | 待定    | 待定    | 待定      | 从 VM 描述的内存读取 Vec8 向量.        |
  | `bstore`      | 待定    | 待定    | 待定      | 将 Vec8 向量写入 VM 描述的内存.        |
  | `vload`       | 待定    | 待定    | 待定      | 从 VM 描述的内存读取 Vec32 向量.       |
  | `vstore`      | 待定    | 待定    | 待定      | 将 Vec32 向量写入 VM 描述的内存.       |
]

== 初始化, 搬运与转置

详细语义见 @data-movement.

#instruction-listing(caption: [初始化, 搬运与转置指令清单])[
  | Instruction     | Format  | Opcode  | Function  | Summary                                     |
  | --------------- | ------- | ------- | --------- | ------------------------------------------- |
  | `tfill.TYPE`    | 待定    | 待定    | 待定      | 将立即数填入 Tile 的有效区域.               |
  | `tfillx.TYPE`   | 待定    | 待定    | 待定      | 用 Scalar 值填充 Tile 的有效区域.           |
  | `tcopy`         | 待定    | 待定    | 待定      | 复制同域 Tile 的有效数据.                   |
  | `afill.TYPE`    | 待定    | 待定    | 待定      | 将立即数填入 Acc 的有效区域.                |
  | `afillx.TYPE`   | 待定    | 待定    | 待定      | 用 Scalar 值填充 Acc 的有效区域.            |
  | `acopy`         | 待定    | 待定    | 待定      | 复制同域 Acc 的有效数据.                    |
  | `bfill.TYPE`    | 待定    | 待定    | 待定      | 将立即数填入 Vec8 的有效区域.               |
  | `bfillx.TYPE`   | 待定    | 待定    | 待定      | 用 Scalar 值填充 Vec8 的有效区域.           |
  | `bcopy`         | 待定    | 待定    | 待定      | 复制同域 Vec8 的有效数据.                   |
  | `vfill.TYPE`    | 待定    | 待定    | 待定      | 将立即数填入 Vec32 的有效区域.              |
  | `vfillx.TYPE`   | 待定    | 待定    | 待定      | 用 Scalar 值填充 Vec32 的有效区域.          |
  | `vcopy`         | 待定    | 待定    | 待定      | 复制同域 Vec32 的有效数据.                  |
  | `tinsert.row`   | 待定    | 待定    | 待定      | 将 Vec8 写入 Tile 的指定行.                 |
  | `textract.row`  | 待定    | 待定    | 待定      | 从 Tile 指定行提取到 Vec8.                  |
  | `ainsert.row`   | 待定    | 待定    | 待定      | 将 Vec32 写入 Acc 的指定行.                 |
  | `aextract.row`  | 待定    | 待定    | 待定      | 从 Acc 指定行提取到 Vec32.                  |
  | `bextract`      | 待定    | 待定    | 待定      | 将 Vec8 的指定 lane 提取到 Scalar.          |
  | `binsert`       | 待定    | 待定    | 待定      | 将 Scalar 值写入 Vec8 的指定 lane.          |
  | `bbroadcast`    | 待定    | 待定    | 待定      | 将源 Vec8 的一个 lane 广播到目的有效区域.   |
  | `vextract`      | 待定    | 待定    | 待定      | 将 Vec32 的指定 lane 提取到 Scalar.         |
  | `vinsert`       | 待定    | 待定    | 待定      | 将 Scalar 值写入 Vec32 的指定 lane.         |
  | `vbroadcast`    | 待定    | 待定    | 待定      | 将源 Vec32 的一个 lane 广播到目的有效区域.  |
  | `ttranspose`    | 待定    | 待定    | 待定      | 交换 Tile 的行列, 将元素转置写入目的 Tile.  |
]

== 矩阵乘与向量—矩阵乘

详细语义见 @matrix.

#instruction-listing(caption: [矩阵乘与点积指令清单])[
  | Instruction           | Format  | Opcode  | Function  | Summary                                              |
  | --------------------- | ------- | ------- | --------- | ---------------------------------------------------- |
  | `mma.nn.zero.i8.i32`  | 待定    | 待定    | 待定      | 按普通右矩阵执行矩阵乘, 写入 `i32` Acc.              |
  | `mma.nn.acc.i8.i32`   | 待定    | 待定    | 待定      | 按普通右矩阵执行矩阵乘, 累加到旧 `i32` Acc.          |
  | `bdot.nn.i8.i32`      | 待定    | 待定    | 待定      | Vec8 与 Tile 各列执行点积, 结果写入 Vec32.           |
  | `mma.nt.zero.i8.i32`  | 待定    | 待定    | 待定      | 将右 Tile 逻辑转置后执行矩阵乘, 写入 `i32` Acc.      |
  | `mma.nt.acc.i8.i32`   | 待定    | 待定    | 待定      | 将右 Tile 逻辑转置后执行矩阵乘, 累加到旧 `i32` Acc.  |
  | `bdot.nt.i8.i32`      | 待定    | 待定    | 待定      | Vec8 与 Tile 各行执行点积, 结果写入 Vec32.           |
]

== 逐元素, 广播和 mask

详细语义见 @elementwise.

#instruction-listing(caption: [Tile 基础逐元素指令清单])[
  | Instruction        | Format  | Opcode  | Function  | Summary                              |
  | ------------------ | ------- | ------- | --------- | ------------------------------------ |
  | `tadd.sat.TYPE`    | 待定    | 待定    | 待定      | 同域逐元素加法, 饱和; `i8/u8`.       |
  | `tadd.wrap.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素加法, 回绕; `i8/u8`.       |
  | `taddx.sat.TYPE`   | 待定    | 待定    | 待定      | Scalar 值逐元素加法, 饱和; `i8/u8`.  |
  | `taddx.wrap.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素加法, 回绕; `i8/u8`.  |
  | `tsub.sat.TYPE`    | 待定    | 待定    | 待定      | 同域逐元素减法, 饱和; `i8/u8`.       |
  | `tsub.wrap.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素减法, 回绕; `i8/u8`.       |
  | `tsubx.sat.TYPE`   | 待定    | 待定    | 待定      | Scalar 值逐元素减法, 饱和; `i8/u8`.  |
  | `tsubx.wrap.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素减法, 回绕; `i8/u8`.  |
  | `tmin.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素取小; `i8/u8`.             |
  | `tminx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素取小; `i8/u8`.        |
  | `tmax.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素取大; `i8/u8`.             |
  | `tmaxx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素取大; `i8/u8`.        |
  | `tand`             | 待定    | 待定    | 待定      | 同域逐元素按位与.                    |
  | `tandx`            | 待定    | 待定    | 待定      | Scalar 值逐元素按位与.               |
  | `tor`              | 待定    | 待定    | 待定      | 同域逐元素按位或.                    |
  | `torx`             | 待定    | 待定    | 待定      | Scalar 值逐元素按位或.               |
  | `txor`             | 待定    | 待定    | 待定      | 同域逐元素按位异或.                  |
  | `txorx`            | 待定    | 待定    | 待定      | Scalar 值逐元素按位异或.             |
  | `tshl.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素左移; `i8/u8`.             |
  | `tshlx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素左移; `i8/u8`.        |
  | `tshr.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素逻辑右移; `i8/u8`.         |
  | `tshrx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素逻辑右移; `i8/u8`.    |
  | `tsra.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素算术右移; `i8/u8`.         |
  | `tsrax.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素算术右移; `i8/u8`.    |
  | `tnot`             | 待定    | 待定    | 待定      | 逐元素按位取反.                      |
]

#instruction-listing(caption: [Acc 基础逐元素指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                              |
  | ------------- | ------- | ------- | --------- | ------------------------------------ |
  | `aadd.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素加法; `i32/u32/f32`.       |
  | `aaddx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素加法; `i32/u32/f32`.  |
  | `asub.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素减法; `i32/u32/f32`.       |
  | `asubx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素减法; `i32/u32/f32`.  |
  | `amul.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素乘法; `i32/u32/f32`.       |
  | `amulx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素乘法; `i32/u32/f32`.  |
  | `adiv.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素除法; `f32`.               |
  | `adivx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素除法; `f32`.          |
  | `amin.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素取小; `i32/u32/f32`.       |
  | `aminx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素取小; `i32/u32/f32`.  |
  | `amax.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素取大; `i32/u32/f32`.       |
  | `amaxx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素取大; `i32/u32/f32`.  |
  | `aand`        | 待定    | 待定    | 待定      | 同域逐元素按位与.                    |
  | `aandx`       | 待定    | 待定    | 待定      | Scalar 值逐元素按位与.               |
  | `aor`         | 待定    | 待定    | 待定      | 同域逐元素按位或.                    |
  | `aorx`        | 待定    | 待定    | 待定      | Scalar 值逐元素按位或.               |
  | `axor`        | 待定    | 待定    | 待定      | 同域逐元素按位异或.                  |
  | `axorx`       | 待定    | 待定    | 待定      | Scalar 值逐元素按位异或.             |
  | `ashl.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素左移; `i32/u32`.           |
  | `ashlx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素左移; `i32/u32`.      |
  | `ashr.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素逻辑右移; `i32/u32`.       |
  | `ashrx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素逻辑右移; `i32/u32`.  |
  | `asra.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素算术右移; `i32/u32`.       |
  | `asrax.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素算术右移; `i32/u32`.  |
  | `anot`        | 待定    | 待定    | 待定      | 逐元素按位取反.                      |
  | `aabs.TYPE`   | 待定    | 待定    | 待定      | 逐元素绝对值; `i32/f32`.             |
  | `aneg.TYPE`   | 待定    | 待定    | 待定      | 逐元素取负; `i32/f32`.               |
]

#instruction-listing(caption: [Vec8 基础逐元素指令清单])[
  | Instruction        | Format  | Opcode  | Function  | Summary                              |
  | ------------------ | ------- | ------- | --------- | ------------------------------------ |
  | `badd.sat.TYPE`    | 待定    | 待定    | 待定      | 同域逐元素加法, 饱和; `i8/u8`.       |
  | `badd.wrap.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素加法, 回绕; `i8/u8`.       |
  | `baddx.sat.TYPE`   | 待定    | 待定    | 待定      | Scalar 值逐元素加法, 饱和; `i8/u8`.  |
  | `baddx.wrap.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素加法, 回绕; `i8/u8`.  |
  | `bsub.sat.TYPE`    | 待定    | 待定    | 待定      | 同域逐元素减法, 饱和; `i8/u8`.       |
  | `bsub.wrap.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素减法, 回绕; `i8/u8`.       |
  | `bsubx.sat.TYPE`   | 待定    | 待定    | 待定      | Scalar 值逐元素减法, 饱和; `i8/u8`.  |
  | `bsubx.wrap.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素减法, 回绕; `i8/u8`.  |
  | `bmin.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素取小; `i8/u8`.             |
  | `bminx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素取小; `i8/u8`.        |
  | `bmax.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素取大; `i8/u8`.             |
  | `bmaxx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素取大; `i8/u8`.        |
  | `band`             | 待定    | 待定    | 待定      | 同域逐元素按位与.                    |
  | `bandx`            | 待定    | 待定    | 待定      | Scalar 值逐元素按位与.               |
  | `bor`              | 待定    | 待定    | 待定      | 同域逐元素按位或.                    |
  | `borx`             | 待定    | 待定    | 待定      | Scalar 值逐元素按位或.               |
  | `bxor`             | 待定    | 待定    | 待定      | 同域逐元素按位异或.                  |
  | `bxorx`            | 待定    | 待定    | 待定      | Scalar 值逐元素按位异或.             |
  | `bshl.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素左移; `i8/u8`.             |
  | `bshlx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素左移; `i8/u8`.        |
  | `bshr.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素逻辑右移; `i8/u8`.         |
  | `bshrx.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素逻辑右移; `i8/u8`.    |
  | `bsra.TYPE`        | 待定    | 待定    | 待定      | 同域逐元素算术右移; `i8/u8`.         |
  | `bsrax.TYPE`       | 待定    | 待定    | 待定      | Scalar 值逐元素算术右移; `i8/u8`.    |
  | `bnot`             | 待定    | 待定    | 待定      | 逐元素按位取反.                      |
]

#instruction-listing(caption: [Vec32 基础逐元素指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                              |
  | ------------- | ------- | ------- | --------- | ------------------------------------ |
  | `vadd.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素加法; `i32/u32/f32`.       |
  | `vaddx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素加法; `i32/u32/f32`.  |
  | `vsub.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素减法; `i32/u32/f32`.       |
  | `vsubx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素减法; `i32/u32/f32`.  |
  | `vmul.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素乘法; `i32/u32/f32`.       |
  | `vmulx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素乘法; `i32/u32/f32`.  |
  | `vdiv.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素除法; `f32`.               |
  | `vdivx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素除法; `f32`.          |
  | `vmin.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素取小; `i32/u32/f32`.       |
  | `vminx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素取小; `i32/u32/f32`.  |
  | `vmax.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素取大; `i32/u32/f32`.       |
  | `vmaxx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素取大; `i32/u32/f32`.  |
  | `vand`        | 待定    | 待定    | 待定      | 同域逐元素按位与.                    |
  | `vandx`       | 待定    | 待定    | 待定      | Scalar 值逐元素按位与.               |
  | `vor`         | 待定    | 待定    | 待定      | 同域逐元素按位或.                    |
  | `vorx`        | 待定    | 待定    | 待定      | Scalar 值逐元素按位或.               |
  | `vxor`        | 待定    | 待定    | 待定      | 同域逐元素按位异或.                  |
  | `vxorx`       | 待定    | 待定    | 待定      | Scalar 值逐元素按位异或.             |
  | `vshl.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素左移; `i32/u32`.           |
  | `vshlx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素左移; `i32/u32`.      |
  | `vshr.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素逻辑右移; `i32/u32`.       |
  | `vshrx.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素逻辑右移; `i32/u32`.  |
  | `vsra.TYPE`   | 待定    | 待定    | 待定      | 同域逐元素算术右移; `i32/u32`.       |
  | `vsrax.TYPE`  | 待定    | 待定    | 待定      | Scalar 值逐元素算术右移; `i32/u32`.  |
  | `vnot`        | 待定    | 待定    | 待定      | 逐元素按位取反.                      |
  | `vabs.TYPE`   | 待定    | 待定    | 待定      | 逐元素绝对值; `i32/f32`.             |
  | `vneg.TYPE`   | 待定    | 待定    | 待定      | 逐元素取负; `i32/f32`.               |
]

#instruction-listing(caption: [融合乘加指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                         |
  | ------------- | ------- | ------- | --------- | ------------------------------- |
  | `afmadd.f32`  | 待定    | 待定    | 待定      | Acc 融合乘加, 单次 f32 舍入.    |
  | `vfmadd.f32`  | 待定    | 待定    | 待定      | Vec32 融合乘加, 单次 f32 舍入.  |
]

#instruction-listing(caption: [近似特殊函数指令清单])[
  | Instruction      | Format  | Opcode  | Function  | Summary                  |
  | ---------------- | ------- | ------- | --------- | ------------------------ |
  | `aexp2.approx`   | 待定    | 待定    | 待定      | 逐元素计算 2 的幂.       |
  | `arcp.approx`    | 待定    | 待定    | 待定      | 逐元素计算倒数.          |
  | `arsqrt.approx`  | 待定    | 待定    | 待定      | 逐元素计算倒数平方根.    |
  | `vexp2.approx`   | 待定    | 待定    | 待定      | 逐 lane 计算 2 的幂.     |
  | `vrcp.approx`    | 待定    | 待定    | 待定      | 逐 lane 计算倒数.        |
  | `vrsqrt.approx`  | 待定    | 待定    | 待定      | 逐 lane 计算倒数平方根.  |
]



#instruction-listing(caption: [矩阵源行广播指令清单])[
  | Instruction            | Format  | Opcode  | Function  | Summary                           |
  | ---------------------- | ------- | ------- | --------- | --------------------------------- |
  | `tadd.brow.sat.TYPE`   | 待定    | 待定    | 待定      | 矩阵源行广播加法, 饱和; `i8/u8`.  |
  | `tadd.brow.wrap.TYPE`  | 待定    | 待定    | 待定      | 矩阵源行广播加法, 回绕; `i8/u8`.  |
  | `tsub.brow.sat.TYPE`   | 待定    | 待定    | 待定      | 矩阵源行广播减法, 饱和; `i8/u8`.  |
  | `tsub.brow.wrap.TYPE`  | 待定    | 待定    | 待定      | 矩阵源行广播减法, 回绕; `i8/u8`.  |
  | `tmin.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播取小; `i8/u8`.        |
  | `tmax.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播取大; `i8/u8`.        |
  | `tand.brow`            | 待定    | 待定    | 待定      | 矩阵源行广播按位与.               |
  | `tor.brow`             | 待定    | 待定    | 待定      | 矩阵源行广播按位或.               |
  | `txor.brow`            | 待定    | 待定    | 待定      | 矩阵源行广播按位异或.             |
  | `tshl.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播左移; `i8/u8`.        |
  | `tshr.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播逻辑右移; `i8/u8`.    |
  | `tsra.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播算术右移; `i8/u8`.    |
  | `aadd.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播加法; `i32/u32/f32`.  |
  | `asub.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播减法; `i32/u32/f32`.  |
  | `amul.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播乘法; `i32/u32/f32`.  |
  | `adiv.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播除法; `f32`.          |
  | `amin.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播取小; `i32/u32/f32`.  |
  | `amax.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播取大; `i32/u32/f32`.  |
  | `aand.brow`            | 待定    | 待定    | 待定      | 矩阵源行广播按位与.               |
  | `aor.brow`             | 待定    | 待定    | 待定      | 矩阵源行广播按位或.               |
  | `axor.brow`            | 待定    | 待定    | 待定      | 矩阵源行广播按位异或.             |
  | `ashl.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播左移; `i32/u32`.      |
  | `ashr.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播逻辑右移; `i32/u32`.  |
  | `asra.brow.TYPE`       | 待定    | 待定    | 待定      | 矩阵源行广播算术右移; `i32/u32`.  |
]

#instruction-listing(caption: [向量按行广播指令清单])[
  | Instruction              | Format  | Opcode  | Function  | Summary                           |
  | ------------------------ | ------- | ------- | --------- | --------------------------------- |
  | `taddb.byrow.sat.TYPE`   | 待定    | 待定    | 待定      | 向量按行广播加法, 饱和; `i8/u8`.  |
  | `taddb.byrow.wrap.TYPE`  | 待定    | 待定    | 待定      | 向量按行广播加法, 回绕; `i8/u8`.  |
  | `tsubb.byrow.sat.TYPE`   | 待定    | 待定    | 待定      | 向量按行广播减法, 饱和; `i8/u8`.  |
  | `tsubb.byrow.wrap.TYPE`  | 待定    | 待定    | 待定      | 向量按行广播减法, 回绕; `i8/u8`.  |
  | `tminb.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播取小; `i8/u8`.        |
  | `tmaxb.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播取大; `i8/u8`.        |
  | `tandb.byrow`            | 待定    | 待定    | 待定      | 向量按行广播按位与.               |
  | `torb.byrow`             | 待定    | 待定    | 待定      | 向量按行广播按位或.               |
  | `txorb.byrow`            | 待定    | 待定    | 待定      | 向量按行广播按位异或.             |
  | `tshlb.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播左移; `i8/u8`.        |
  | `tshrb.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播逻辑右移; `i8/u8`.    |
  | `tsrab.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播算术右移; `i8/u8`.    |
  | `aaddv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播加法; `i32/u32/f32`.  |
  | `asubv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播减法; `i32/u32/f32`.  |
  | `amulv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播乘法; `i32/u32/f32`.  |
  | `adivv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播除法; `f32`.          |
  | `aminv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播取小; `i32/u32/f32`.  |
  | `amaxv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播取大; `i32/u32/f32`.  |
  | `aandv.byrow`            | 待定    | 待定    | 待定      | 向量按行广播按位与.               |
  | `aorv.byrow`             | 待定    | 待定    | 待定      | 向量按行广播按位或.               |
  | `axorv.byrow`            | 待定    | 待定    | 待定      | 向量按行广播按位异或.             |
  | `ashlv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播左移; `i32/u32`.      |
  | `ashrv.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播逻辑右移; `i32/u32`.  |
  | `asrav.byrow.TYPE`       | 待定    | 待定    | 待定      | 向量按行广播算术右移; `i32/u32`.  |
]

#instruction-listing(caption: [向量按列广播指令清单])[
  | Instruction              | Format  | Opcode  | Function  | Summary                           |
  | ------------------------ | ------- | ------- | --------- | --------------------------------- |
  | `taddb.bycol.sat.TYPE`   | 待定    | 待定    | 待定      | 向量按列广播加法, 饱和; `i8/u8`.  |
  | `taddb.bycol.wrap.TYPE`  | 待定    | 待定    | 待定      | 向量按列广播加法, 回绕; `i8/u8`.  |
  | `tsubb.bycol.sat.TYPE`   | 待定    | 待定    | 待定      | 向量按列广播减法, 饱和; `i8/u8`.  |
  | `tsubb.bycol.wrap.TYPE`  | 待定    | 待定    | 待定      | 向量按列广播减法, 回绕; `i8/u8`.  |
  | `tminb.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播取小; `i8/u8`.        |
  | `tmaxb.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播取大; `i8/u8`.        |
  | `tandb.bycol`            | 待定    | 待定    | 待定      | 向量按列广播按位与.               |
  | `torb.bycol`             | 待定    | 待定    | 待定      | 向量按列广播按位或.               |
  | `txorb.bycol`            | 待定    | 待定    | 待定      | 向量按列广播按位异或.             |
  | `tshlb.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播左移; `i8/u8`.        |
  | `tshrb.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播逻辑右移; `i8/u8`.    |
  | `tsrab.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播算术右移; `i8/u8`.    |
  | `aaddv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播加法; `i32/u32/f32`.  |
  | `asubv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播减法; `i32/u32/f32`.  |
  | `amulv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播乘法; `i32/u32/f32`.  |
  | `adivv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播除法; `f32`.          |
  | `aminv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播取小; `i32/u32/f32`.  |
  | `amaxv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播取大; `i32/u32/f32`.  |
  | `aandv.bycol`            | 待定    | 待定    | 待定      | 向量按列广播按位与.               |
  | `aorv.bycol`             | 待定    | 待定    | 待定      | 向量按列广播按位或.               |
  | `axorv.bycol`            | 待定    | 待定    | 待定      | 向量按列广播按位异或.             |
  | `ashlv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播左移; `i32/u32`.      |
  | `ashrv.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播逻辑右移; `i32/u32`.  |
  | `asrav.bycol.TYPE`       | 待定    | 待定    | 待定      | 向量按列广播算术右移; `i32/u32`.  |
]

#instruction-listing(caption: [比较指令清单])[
  | Instruction        | Format  | Opcode  | Function  | Summary                            |
  | ------------------ | ------- | ------- | --------- | ---------------------------------- |
  | `acmp.eq.TYPE`     | 待定    | 待定    | 待定      | 同域右源相等比较; `i32/u32/f32`.   |
  | `acmp.ne.TYPE`     | 待定    | 待定    | 待定      | 同域右源不等比较; `i32/u32`.       |
  | `acmp.lt.TYPE`     | 待定    | 待定    | 待定      | 同域右源小于比较; `i32/u32/f32`.   |
  | `acmp.ge.TYPE`     | 待定    | 待定    | 待定      | 同域右源大于等于比较; `i32/u32`.   |
  | `acmp.le.f32`      | 待定    | 待定    | 待定      | 同域右源小于等于比较; `f32`.       |
  | `acmp.unord.f32`   | 待定    | 待定    | 待定      | 同域右源浮点无序比较.              |
  | `acmpx.eq.TYPE`    | 待定    | 待定    | 待定      | Scalar 值相等比较; `i32/u32/f32`.  |
  | `acmpx.ne.TYPE`    | 待定    | 待定    | 待定      | Scalar 值不等比较; `i32/u32`.      |
  | `acmpx.lt.TYPE`    | 待定    | 待定    | 待定      | Scalar 值小于比较; `i32/u32/f32`.  |
  | `acmpx.ge.TYPE`    | 待定    | 待定    | 待定      | Scalar 值大于等于比较; `i32/u32`.  |
  | `acmpx.le.f32`     | 待定    | 待定    | 待定      | Scalar 值小于等于比较; `f32`.      |
  | `acmpx.unord.f32`  | 待定    | 待定    | 待定      | Scalar 值浮点无序比较.             |
  | `vcmp.eq.TYPE`     | 待定    | 待定    | 待定      | 同域右源相等比较; `i32/u32/f32`.   |
  | `vcmp.ne.TYPE`     | 待定    | 待定    | 待定      | 同域右源不等比较; `i32/u32`.       |
  | `vcmp.lt.TYPE`     | 待定    | 待定    | 待定      | 同域右源小于比较; `i32/u32/f32`.   |
  | `vcmp.ge.TYPE`     | 待定    | 待定    | 待定      | 同域右源大于等于比较; `i32/u32`.   |
  | `vcmp.le.f32`      | 待定    | 待定    | 待定      | 同域右源小于等于比较; `f32`.       |
  | `vcmp.unord.f32`   | 待定    | 待定    | 待定      | 同域右源浮点无序比较.              |
  | `vcmpx.eq.TYPE`    | 待定    | 待定    | 待定      | Scalar 值相等比较; `i32/u32/f32`.  |
  | `vcmpx.ne.TYPE`    | 待定    | 待定    | 待定      | Scalar 值不等比较; `i32/u32`.      |
  | `vcmpx.lt.TYPE`    | 待定    | 待定    | 待定      | Scalar 值小于比较; `i32/u32/f32`.  |
  | `vcmpx.ge.TYPE`    | 待定    | 待定    | 待定      | Scalar 值大于等于比较; `i32/u32`.  |
  | `vcmpx.le.f32`     | 待定    | 待定    | 待定      | Scalar 值小于等于比较; `f32`.      |
  | `vcmpx.unord.f32`  | 待定    | 待定    | 待定      | Scalar 值浮点无序比较.             |
]

#instruction-listing(caption: [选择指令清单])[
  | Instruction  | Format  | Opcode  | Function  | Summary                         |
  | ------------ | ------- | ------- | --------- | ------------------------------- |
  | `tselect`    | 待定    | 待定    | 待定      | mask 非零时选择 A, 否则选择 B.  |
  | `aselect`    | 待定    | 待定    | 待定      | mask 非零时选择 A, 否则选择 B.  |
  | `bselect`    | 待定    | 待定    | 待定      | mask 非零时选择 A, 否则选择 B.  |
  | `vselect`    | 待定    | 待定    | 待定      | mask 非零时选择 A, 否则选择 B.  |
]

#instruction-listing(caption: [Mask 指令清单])[
  | Instruction   | Format  | Opcode  | Function  | Summary                                  |
  | ------------- | ------- | ------- | --------- | ---------------------------------------- |
  | `tmask.tail`  | 待定    | 待定    | 待定      | 保留行列坐标小于 xRows, xCols 的源元素.  |
  | `tmask.tril`  | 待定    | 待定    | 待定      | 保留满足 $j-i <= "xDelta"$ 的源元素.     |
  | `tmask.triu`  | 待定    | 待定    | 待定      | 保留满足 $j-i >= "xDelta"$ 的源元素.     |
  | `amask.tail`  | 待定    | 待定    | 待定      | 保留行列坐标小于 xRows, xCols 的源元素.  |
  | `amask.tril`  | 待定    | 待定    | 待定      | 保留满足 $j-i <= "xDelta"$ 的源元素.     |
  | `amask.triu`  | 待定    | 待定    | 待定      | 保留满足 $j-i >= "xDelta"$ 的源元素.     |
  | `bmask.tail`  | 待定    | 待定    | 待定      | 保留 lane 索引小于 xLen 的源元素.        |
  | `vmask.tail`  | 待定    | 待定    | 待定      | 保留 lane 索引小于 xLen 的源元素.        |
]

== 规约与类型转换

详细语义见 @reduction-conversion.

#instruction-listing(caption: [规约指令清单])[
  | Instruction               | Format  | Opcode  | Function  | Summary                                         |
  | ------------------------- | ------- | ------- | --------- | ----------------------------------------------- |
  | `areduce.rows.sum.f32`    | 待定    | 待定    | 待定      | 将 Acc 按行求和到 Vec32.                        |
  | `areduce.rows.max.f32`    | 待定    | 待定    | 待定      | 将 Acc 按行取最大到 Vec32.                      |
  | `areduce.rows.min.f32`    | 待定    | 待定    | 待定      | 将 Acc 按行取最小到 Vec32.                      |
  | `areduce.rows.sumsq.f32`  | 待定    | 待定    | 待定      | 将 Acc 每行有效元素的平方和写入 Vec32.          |
  | `vreduce.sum.f32`         | 待定    | 待定    | 待定      | 将 f32 Vec32 的有效 lane 求和到 Scalar.         |
  | `vreduce.max.f32`         | 待定    | 待定    | 待定      | 将 f32 Vec32 的有效 lane 取最大到 Scalar.       |
  | `vreduce.min.f32`         | 待定    | 待定    | 待定      | 将 f32 Vec32 的有效 lane 取最小到 Scalar.       |
  | `vreduce.sumsq.f32`       | 待定    | 待定    | 待定      | 将 f32 Vec32 的有效 lane 平方和到 Scalar.       |
  | `vreduce.argmax.f32`      | 待定    | 待定    | 待定      | 输出最大值的逻辑索引与浮点位模式到两个 Scalar.  |
]

#instruction-listing(caption: [类型转换与扩大指令清单])[
  | Instruction      | Format  | Opcode  | Function  | Summary                                   |
  | ---------------- | ------- | ------- | --------- | ----------------------------------------- |
  | `acvt.i32.f32`   | 待定    | 待定    | 待定      | 将 Acc 中的 `i32` 逐元素转为 `f32`.       |
  | `vcvt.i32.f32`   | 待定    | 待定    | 待定      | 将 Vec32 中的 `i32` 逐 lane 转为 `f32`.   |
  | `twiden.i8.i32`  | 待定    | 待定    | 待定      | 将 Tile 的 `i8` 符号扩展到 Acc 的 `i32`.  |
]

== 量化与反量化

详细语义见 @quantization.

#instruction-listing(caption: [量化与反量化指令清单])[
  | Instruction          | Format  | Opcode  | Function  | Summary                                            |
  | -------------------- | ------- | ------- | --------- | -------------------------------------------------- |
  | `tquant.rows.q8s32`  | 待定    | 待定    | 待定      | 将 Acc 按行量化到 Tile, 每行产生一个 Vec32 scale.  |
  | `vquant.q8s32`       | 待定    | 待定    | 待定      | 将 Vec32 量化到 Vec8, 产生一个指定 lane 的 scale.  |
  | `tdequant.rows.f32`  | 待定    | 待定    | 待定      | 用每行的 Vec32 scale 将 Tile 反量化到 f32 Acc.     |
  | `bdequant.f32`       | 待定    | 待定    | 待定      | 用指定 scale lane 将 Vec8 反量化到 f32 Vec32.      |
]

= 附录: 助记符速查 <quickref>

#manual-table(
  columns: (1.1fr, 2fr, 2.9fr),
  caption: [ISA 助记符速查],
)[
  | 前缀或功能族        | 主要对象                    | 读法示例                                                                        |
  | ------------------- | --------------------------- | ------------------------------------------------------------------------------- |
  | 标量                | Scalar `x` 与内存, 控制流   | 标量指令集为 RV64IM, 按 RISC-V 规范执行, 本手册不展开.                          |
  | `t` / `a`           | Tile / Acc 矩阵数据域       | `tload` / `aload` 使用 `TM`; `tcopy` / `acopy` 执行同域复制.                    |
  | `b` / `v`           | Vec8 / Vec32 向量数据域     | `bload` / `vload` 使用 `VM`; `badd` / `vadd` 执行同域向量加法.                  |
  | `cfg`               | `TC/AC/BC/VC/TM/VM`         | `cfg.seti` 写立即数字段; `cfg.setx` 从 Scalar 写字段.                           |
  | `mma`               | Tile × Tile → Acc           | `mma.nt.acc.i8.i32` 以 `i8` 输入执行逻辑转置矩阵乘, 并累加到 `i32` Acc.         |
  | `bdot`              | Vec8 × Tile → Vec32         | `bdot.nn.i8.i32` 产生 `i32` 向量; 跨块累加使用 `vadd.i32`.                      |
  | 跨域转换            | 指令显式规定输入与输出域    | `twiden`: Tile → Acc; `tquant`: Acc → Tile; `vquant`: Vec32 → Vec8.             |
  | `fence` / `kernel`  | 后端完成与 kernel 生命周期  | `fence.mem` / `fence.sa` / `fence.all` 建立完成边界; `kernel.end` 结束 kernel.  |
]

前缀表示指令所属的数据域或功能族, 跨域指令须结合操作数阅读. 例如 `treduce` 的目的为 Vec32, `vreduce` 的目的为 Scalar, 不能仅根据前缀推断目的寄存器.

= 附录: 编码图版 <plates>

本附录预留二进制编码图. 指令字宽及字段位段确定后, 再补充与 @encoding 对应的图版.

// = 附录 C：整页编码图版 <plates>
//
// 本附录使用 Rivet 的 blueprint 配置生成各格式的完整字段图。每张图版单独使用 A4 横向页面，以便完整显示字段名称和位宽；图版与正文中的分片图使用相同的 schema，不增加编码语义。
//
// #captioned-table(
//   table(
//     columns: (1fr, 3.8fr),
//     inset: 5pt,
//     stroke: 0.35pt + luma(195),
//     fill: (_, y) => if y == 0 { rgb("e9f0f7") } else { none },
//     table.header(table-header[图版], table-header[完整结构]),
//     [C.1], [`S_R` 标量寄存器格式],
//     [C.2], [`S_I` 标量立即数格式],
//     [C.3], [`S_B` 分支和循环格式],
//     [C.4], [`T_R3` 三源 Tile 计算格式],
//     [C.5], [`T_R4` 四源 Tile 计算格式],
//     [C.6], [`T_M` Tile memory 格式],
//     [C.7], [`T_MP` paged Tile memory 格式],
//     [C.8], [`T_D` descriptor/lifetime 格式],
//     [C.9], [`T_S` event/wait/fence/system 格式],
//   ),
//   caption: [编码图版索引],
// )
//
// #set page(flipped: true)
// #pagebreak()
// #align(center)[*C.1　`S_R` 标量寄存器格式*]
// #rivet-plate(sr-format-schema)
//
// #pagebreak()
// #align(center)[*C.2　`S_I` 标量立即数格式*]
// #rivet-plate(si-schema)
//
// #pagebreak()
// #align(center)[*C.3　`S_B` 分支和循环格式*]
// #rivet-plate(sb-schema)
//
// #pagebreak()
// #align(center)[*C.4　`T_R3` 三源 Tile 计算格式*]
// #rivet-plate(tr3-schema)
//
// #pagebreak()
// #align(center)[*C.5　`T_R4` 四源 Tile 计算格式*]
// #rivet-plate(tr4-schema)
//
// #pagebreak()
// #align(center)[*C.6　`T_M` Tile memory 格式*]
// #rivet-plate(tm-schema)
//
// #pagebreak()
// #align(center)[*C.7　`T_MP` paged Tile memory 格式*]
// #rivet-plate(tmp-schema)
//
// #pagebreak()
// #align(center)[*C.8　`T_D` descriptor/lifetime 格式*]
// #rivet-plate(td-schema)
//
// #pagebreak()
// #align(center)[*C.9　`T_S` event/wait/fence/system 格式*]
// #rivet-plate(ts-schema)
// #set page(flipped: false)
