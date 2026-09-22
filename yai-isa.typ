#import "yai-isa-style.typ": *
#import "yai-isa-rivet.typ": *

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
  | 记号                 | 含义                                               |
  | -------------------- | -------------------------------------------------- |
  | `D`                  | 目的寄存器, 对应汇编操作数 `tD`, `aD`, `bD`, `vD`  |
  | `A`, `B`             | 第一, 第二源寄存器, 对应 `tA`, `tB` 等             |
  | `S`                  | 单源或广播向量源                                   |
  | `M`                  | mask 寄存器, 值为全 0 或全 1 的 `u8`/`u32` 元素    |
  | `imm`                | 立即数                                             |
  | `xS`                 | 来自 Scalar 寄存器的操作数                         |
  | `xBounds`/`xRowCol`  | 打包 Scalar 寄存器                                 |
  | `tmJ`, `vmJ`         | 访存描述符 TM / VM 的编号                          |
  | `[i,j]`              | 矩阵元素索引                                       |
  | `[j]`                | 向量 lane 索引                                     |
  | `[p]`                | position, 元素坐标: 矩阵为 `[i,j]`, 向量为 `[j]`   |
  | `[rd,j]`             | 行操作中目的的指定行; `ra`, `rb` 为两个源的指定行  |
  | `sat`, `wrap`        | 饱和 / 回绕, 定义见 @elementwise                   |
]

Operation 列使用的函数记号:

#manual-table(
  columns: (1.6fr, 5fr),
  caption: [Operation 函数记号],
)[
  | 记号                      | 含义                                                             |
  | ------------------------- | ---------------------------------------------------------------- |
  | `min(A, B)`, `max(A, B)`  | 逐元素取小/取大; 浮点按 IEEE 754 minNum/maxNum 语义, NaN 不传播  |
  | `shl(A, B)`               | 逻辑左移; 移位量取 `B` 的低 $log_2 w$ 位 ($w$ 为元素位宽)        |
  | `shr(A, B)`               | 逻辑右移 (零填充); 移位量同上                                    |
  | `sra(A, B)`               | 算术右移 (符号填充); 移位量同上                                  |
  | `abs(A)`                  | 逐元素绝对值                                                     |
  | `not A`                   | 逐元素按位取反                                                   |
  | `and`, `or`, `xor`        | 逐元素按位与/或/异或                                             |
  | `quant_q8s32(...)` 等     | 量化与反量化函数, 定义见 @quantization                           |
  | `fma(A, B, C)`            | 融合乘加 `A × B + C`, 单次舍入; 仅 f32                           |
]

浮点 `+`, `-`, `×`, `/` 遵循 IEEE 754 binary32 规则, 舍入模式为 round-to-nearest-even.

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

#note[
  Vec8 (`b`) 是低精度存储与搬运域, 不定义逐元素计算指令 (加法, 位运算, 移位等); 量化数据需经 `bdequant` 反量化到 Vec32 后计算, 或经 `vquant` 从 Vec32 量化存入. Tile/Acc/Vec32 的计算指令分别在各域章节定义.
]

#important[
  32-bit 寄存器内无法存储两个半精度数(如`f16`/`bf16`), `f16`/`bf16`等半精度数加载后扩展到 f32 Acc/Vec.
]

=== 配置寄存器

配置寄存器分为计算配置寄存器和访存描述符.

#manual-table(
  columns: (1.05fr, 1fr, 1.2fr, 0.6fr, 2.2fr),
  caption: [计算配置寄存器与访存描述符],
)[
  | 寄存器类型          | 汇编名称     | 绑定或适用对象             | 容量    | 配置字段                                                                              |
  | :-----------------: | :----------: | -------------------------- | ------- | ------------------------------------------------------------------------------------- |
  | TC: Tile 计算配置   | `tc0..tc15`  | `tc[i]` ↔ `t[i]`           | 32bit   | `dtype`, `rows`, `cols`, `layout`, `arith_mode`                                       |
  | AC: Acc 计算配置    | `ac0..ac11`  | `ac[i]` ↔ `a[i]`           | 32bit   | `dtype`, `rows`, `cols`, `layout`                                                     |
  | BC: Vec8 计算配置   | `bc0..bc31`  | `bc[i]` ↔ `b[i]`           | 32bit   | `dtype`, `len`                                                                        |
  | VC: Vec32 计算配置  | `vc0..vc31`  | `vc[i]` ↔ `v[i]`           | 32bit   | `dtype`, `len`                                                                        |
  | TM: 矩阵访存描述符  | `tm0..tm15`  | Tile / Acc 访存显式选择    | 256bit  | `rows`, `cols`, `row_stride_bytes`, `col_stride_bytes`, `storage_dtype`, `transform`  |
  | VM: 向量访存描述符  | `vm0..vm31`  | Vec8 / Vec32 访存显式选择  | 128bit  | `length`, `stride_bytes`, `storage_dtype`                                             |
]

计算配置寄存器 TC/AC 与 BC/VC 均为 32-bit; 矩阵访存描述符 TM 为 256-bit (四个 64-bit word), 向量访存描述符 VM 为 128-bit (两个 64-bit word). 位段分配如下.

#rivet-c-figure(tc-schema, caption: [TC/AC 计算配置寄存器位段])

#rivet-c-figure(bc-schema, caption: [BC/VC 计算配置寄存器位段])

#rivet-tm-figure((tm-0-schema, tm-1-schema), caption: [TM 矩阵访存描述符位段])

#rivet-vm-figure(vm-schema, caption: [VM 向量访存描述符位段])

`flags.bit0` (EN) 为 0 时, 使用该描述符的访存指令被拒绝并产生 `CFG_ERROR`; flags 的其余位保留, 写零.

== 编程模型 <model>

待写

== 指令分类 <classification>

ISA 按五个数据域及其数据流划分功能. 下表列出正文定义的主要指令族.

#manual-table(
  columns: (1.4fr, 1.5fr, 2fr, 3fr),
  caption: [功能族总览],
)[
  | 功能族          | 主要数据流                                                                     | 架构职责                                   | 助记符入口                                                                                                                                      |
  | --------------- | ------------------------------------------------------------------------------ | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
  | 标量与控制      | Scalar ↔ Scalar #linebreak() Scalar ↔ 内存                                     | 地址, 索引, 标量计算, 控制流               | RV64IM (见 RISC-V 规范)                                                                                                                         |
  | 配置            | Scalar → TC, AC, BC, VC, TM, VM                                                | 建立数据域的类型, shape, 布局和访存描述    | `cfg.seti`, `cfg.setx`, `cfg.copy`, `cfg.get`                                                                                                   |
  | 地址与访存      | 内存 ↔ `t/a/b/v`                                                               | 按 TM/VM 描述符执行整块, 行和向量访问      | `{t,a}{load,store}` #linebreak() `{b,v}{load,store}`                                                                                            |
  | 初始化与搬运    | 域内 #linebreak() `t` ↔ `b` #linebreak() `a` ↔ `v` #linebreak() Scalar ↔ lane  | 填充, 复制, 行搬运, lane 搬运, 广播和转置  | `{t,a,b,v}{fill,fillx,copy}` #linebreak() `{t,a}{insert,extract}.row` #linebreak() `{b,v}{insert,extract,broadcast}` #linebreak() `ttranspose`  |
  | 矩阵乘与点积    | `t` × `t` → `a` #linebreak() `b` × `t` → `v`                                   | `i8` 乘法, `i32` 累加或点积                | `mma` #linebreak() `bdot`                                                                                                                       |
  | 逐元素与广播    | `t/a/v` 同域 #linebreak() 矩阵 ↔ 向量广播                                      | 算术, 位运算, 移位, 特殊函数, 比较和选择   | `{t,a,v}op` #linebreak() `.brow`, `.byrow`, `.bycol` #linebreak() `cmp`, `select`, `mask`                                                       |
  | 规约            | `a` → `v` #linebreak() `v` → Scalar                                            | 行规约, 向量规约, 平方和和 argmax          | `areduce` #linebreak() `vreduce`                                                                                                                |
  | 类型转换与扩大  | `a/v` 内部 #linebreak() `t` → `a`                                              | 数值类型转换和 `i8` → `i32` 扩大           | `acvt`, `vcvt` #linebreak() `twiden`                                                                                                            |
  | 量化与反量化    | `a` ↔ `t` #linebreak() `v` ↔ `b`                                               | 低精度存储与 `f32` 计算之间的显式转换      | `tquant`, `tdequant` #linebreak() `vquant`, `bdequant`                                                                                          |
  | 同步与结束      | 后端 → 完成边界 #linebreak() kernel → 完成                                     | 访存, SA, 全后端完成以及 kernel 生命周期   | `fence.mem`, `fence.sa`, `fence.all` #linebreak() `kernel.end`                                                                                  |
]

== 指令空间组织 <instruction-space>

指令空间按指令字最低两位划分. `[1:0] = 11` 的空间用于标量指令: 标量指令集采用 RV64IM (RISC-V 64-bit 基础整数指令集与乘除扩展). `[1:0]` 为 `00`, `01`, `10` 的原压缩指令空间全部用于非标量指令, `00` 的逐元素计算走向量计算通路, `01` 走访存与搬运通路, `10` 汇集跨域计算 (矩阵乘, 规约, 量化) 与控制类指令. 所有指令 (标量与非标量) 均为定长 32-bit, 最低两位作为类别标签.

非标量空间按功能域分为三部分:

#manual-table(
  columns: (1fr, 1.5fr, 3.6fr),
  caption: [非标量指令空间分配],
)[
  | 最低两位  | 功能域          | 内容                                                                                                 |
  | :-------: | --------------- | ---------------------------------------------------------------------------------------------------- |
  | `00`      | 通用逐元素计算  | 算术, 位运算, 比较, Scalar 变体 (`opx`, `cmpx`), 行广播与向量广播, 融合乘加, select, mask, 特殊函数  |
  | `01`      | 数据传输与重排  | 矩阵/向量访存, fill, copy, 行和 lane 搬运, 转置                                                      |
  | `10`      | 跨域计算与控制  | 矩阵乘与点积, 规约, 类型转换与扩大, 量化与反量化, 配置, 同步, `kernel.end`; 其余编码预留             |
]

#note[
  预留策略: `10` 空间除配置与系统指令外的空间作为预留. 未来的扩展 (新的数据类型, 更宽的 Tile, 多核同步, DMA 等) 优先使用预留空间.
  #link("https://opensecura.googlesource.com/hw/kelvin/")也使用了类似的策略, 即复用RV64im, 压缩指令的空间用于custom的向量指令.
]

== 指令格式 <encoding>

标量指令格式见 RISC-V 规范; 本章定义非标量指令格式.

所有非标量指令定长 32-bit. 指令字最低两位 `[1:0]` 为类别标签 (见 @instruction-space); `[31:28]` 为主操作码 `major4`, 按指令族划分; 中间的选择子与操作数字段按 `major4` 解释. 格式与功能域划分正交: 同一格式可以出现在不同功能域, 指令的归属按其功能决定.

=== 格式分类

非标量指令按操作数字段的数量与类型归为七种格式:

#manual-table(
  columns: (0.8fr, 3.6fr, 3.4fr),
  caption: [指令格式一览],
)[
  | 格式  | 字段布局                                        | 覆盖指令                                                                                                                   |
  | ----- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
  | R4    | `major4 + sel3 + funct3 + 4 × field5`           | 整块访存, 行与 lane 搬运, 矩阵乘与点积, `vreduce.argmax`, 量化与反量化, `cfg.setx/copy/get`, 比较, `select`/`fmadd`, mask  |
  | R3    | `major4 + sel3 + funct4 + 3 × field5`           | 普通二元操作 (`op`/`opx`), 向量广播 (`byrow`/`bycol`)                                                                      |
  | R2    | `major4 + sel3 + funct3 + S5 + D5`              | `fillx`/`copy`/`ttranspose`, 规约, 类型转换与扩大, 一元操作与特殊函数                                                      |
  | MR    | `major4 + sel3 + tmJ4 + R4 + 3 × field5`        | 行访存 (`.row` 族)                                                                                                         |
  | RB    | `major4 + sel3 + funct4 + index5 + 3 × field4`  | 矩阵源行广播 (`brow`)                                                                                                      |
  | I     | `major4 + sel2 + funct3 + imm16 + D5/C5`        | `fill`, `cfg.seti`                                                                                                         |
  | Z     | `major4 + funct3`                               | `fence.*`, `kernel.end`                                                                                                    |
]

=== 位段布局

#rivet-plate-figure(fmt-r4-schema, caption: [R4 格式: 四个 5-bit 字段])

#rivet-plate-figure(fmt-r3-schema, caption: [R3 格式: 三个 5-bit 字段])

#rivet-plate-figure(fmt-r2-schema, caption: [R2 格式: 两个 5-bit 字段])

#rivet-plate-figure(fmt-mr-schema, caption: [MR 格式: 行访存])

#rivet-plate-figure(fmt-rb-schema, caption: [RB 格式: 矩阵源行广播])

#rivet-plate-figure(fmt-i-schema, caption: [I 格式: 16-bit 立即数])

#rivet-plate-figure(fmt-z-schema, caption: [Z 格式: 无显式操作数])

=== 选择子与简写

`sel2`/`sel3` 为 2-bit/3-bit 选择子, 具体含义由 `major4` 解释; 承载数据域编码时语义值记为 `rf2`. `funct3`/`funct4` 为操作选择. 各选择子位的语义:

#manual-table(
  columns: (1fr, 5.6fr),
  caption: [选择子位语义],
)[
  | 简写      | 含义                                                                                  |
  | --------- | ------------------------------------------------------------------------------------- |
  | `rf2`     | 数据域选择: `00/01/10/11` 依次表示 Tile/Acc/Vec8/Vec32; 具体合法码点由各指令族规定    |
  | `S2`      | 第二源选择: `0` 选择同域寄存器 `B`, `1` 选择 Scalar 寄存器 `xS`                       |
  | `FS`      | fill 来源选择: `0` 选择立即数 `fill5`, `1` 选择 Scalar 寄存器 `xFill`                 |
  | `IS`      | 索引来源选择: `0` 选择 `index5` 中的立即数, `1` 选择由 `index5` 指定的 Scalar 寄存器  |
  | `EW`      | 元素位宽选择: `0` 选择 8-bit 寄存器组合, `1` 选择 32-bit 寄存器组合                   |
  | `TA`      | Tile/Acc 选择: `0` 选择 Tile, `1` 选择 Acc; `E_BCAST` 中同时选择对应的 Vec8/Vec32 源  |
  | `LS`      | load/store 选择: `0` 表示 load, `1` 表示 store                                        |
  | `DIR`     | 广播方向: `0` 表示按行, `1` 表示按列                                                  |
  | `MV`      | 矩阵/向量配置选择: `0` 选择矩阵配置, `1` 选择向量配置                                 |
  | `G`       | 操作组; 与 `op3` 共同组成 `funct4`, 选择逐元素操作                                    |
  | `xCoord`  | Scalar 坐标操作数: 按指令解释为 `xRowCol`, `xIndex`, `xLen` 或 `xDelta`               |
  | `index5`  | 5-bit 索引字段: 由 `IS` 选择立即数索引或 Scalar 寄存器索引                            |
]

字段名后的数字表示位宽, 如 `D5`, `rf2`, `funct3`; 同一字段作为汇编操作数时通常省略位宽后缀. `S2` 中的 `2` 表示第二源编号而非位宽.

=== `major4` 分配

`major4` 的具体编码值待定; 各功能域的指令族分配如下:

#manual-table(
  columns: (1fr, 3.2fr, 1.4fr),
  caption: [major4 指令族分配],
)[
  | 功能域  | 指令族 (`major4`)                                                                                 | 格式         |
  | ------- | ------------------------------------------------------------------------------------------------- | ------------ |
  | `00`    | `E_BIN`, `E_UNARY`, `E_CMP`, `E_R4`, `E_MASK`, `E_BCAST`, `E_BROW`                                | R3/R2/R4/RB  |
  | `01`    | `M_BLK`, `M_ROW`, `INIT_MOVE`, `ROW_MOVE`, `LANE_MOVE`                                            | R4/MR/R2     |
  | `10`    | `MMA_BDOT`, `AREDUCE`, `VREDUCE`, `CVT`, `QNT`, `CFG_MAT_SETI`, `CFG_VEC_SETI`, `CFG_REG`, `SYS`  | R4/R2/I/Z    |
]

编码原则:

+ 指令不包含 dtype 信息; 操作数的元素类型由绑定的配置寄存器 (TC/AC/BC/VC) 的 dtype 字段给出, 助记符中的 `.TYPE` 后缀是汇编层的可读性标注;
+ `reserved` 字段必须为 0, 非零组合为保留编码; 超出实际寄存器数量的编码为非法指令;
+ 各指令族内部的字段解释与合法码点见正文各章.

= 标量与同步 <scalar-sync>

标量指令集采用 RV64IM: 标量算术, 逻辑, 比较, 分支, 跳转和标量访存均按 RISC-V 规范执行, 不在本手册定义. 本章只定义 NPU 特有的同步指令.

#instruction-table(caption: [同步指令])[
  | Instruction   | Format  | Operation                          | Notes                        |
  | ------------- | ------- | ---------------------------------- | ---------------------------- |
  | `fence.mem`   | Z       | 等待此前访存完成并达到约定可见点.  | 后续访存不得越过此边界.      |
  | `fence.sa`    | Z       | 等待此前 SA 操作完成.              | 后续 SA 操作不得越过此边界.  |
  | `fence.all`   | Z       | 等待此前全部后端工作完成.          | 后续后端操作不得越过此边界.  |
  | `kernel.end`  | Z       | 报告 kernel 完成.                  | 隐含 `fence.all`.            |
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
  | `cfg.seti`   | I       | C[field] = extend(imm)    | 校验失败时产生 `CFG_ERROR`.                            |
  | `cfg.setx`   | R4      | C[field] = x[xS]          | 字段定义扩展, 截断与范围规则; 失败时产生 `CFG_ERROR`.  |
  | `cfg.copy`   | R4      | $C_D = C_S$               | 源和目的配置类型一致时执行复制.                        |
  | `cfg.get`    | R4      | x[xD] = extend(C[field])  | 结果为字段的整数或枚举值.                              |
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
  | Instruction       | Format  | Operation                    | Notes                                              |
  | ----------------- | ------- | ---------------------------- | -------------------------------------------------- |
  | `{t,a}load`       | R4      | D[i,j] = memory[addr(i,j)]   | 越界元素补零, 整块 load 清零目的其余位置.          |
  | `{t,a}store`      | R4      | memory[addr(i,j)] = S[i,j]   | 仅写有效交集; 越界位置不访问内存.                  |
  | `{t,a}load.row`   | MR      | D[rd,j] = memory[addr(0,j)]  | 仅处理目的行; 无效列补零, 其余行保持.              |
  | `{t,a}store.row`  | MR      | memory[addr(0,j)] = S[rs,j]  | 仅写有效交集; 越界位置不访问内存.                  |
  | `{b,v}load`       | R4      | D[j] = memory[addr(j)]       | 按寄存器有效长度与 VM 范围确定访问, 越界元素补零.  |
  | `{b,v}store`      | R4      | memory[addr(j)] = S[j]       | 仅写有效交集, 越界位置不访问内存.                  |
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
tload.row   tD[rd], tmJ, xBase, xRowCol
tstore.row  tS[rs], tmJ, xBase, xRowCol

aload.row   aD[rd], tmJ, xBase, xRowCol
astore.row  aS[rs], tmJ, xBase, xRowCol
```

内存行坐标 `row` 与列坐标 `col` 打包在一个 Scalar 寄存器 `xRowCol` 中 (`[31:0]` = `row`, `[63:32]` = `col`). `rd` 和 `rs` 是寄存器文件中的行号, 可以是立即数或 Scalar 寄存器提供的完整值; 它们不参与内存地址计算.

对于 row load:

```text
for 0 <= j < cols(CD):
    if 0 <= row < TM.rows
       and 0 <= col+j < TM.cols:
        CD[rd,j] ← memory[addr(0,j)]
    else:
        CD[rd,j] ← 0
```

row load 的效果是: 只清零或覆盖目的寄存器的第 rd 行; 目的寄存器的其他行保持原值; 目的寄存器第 rd 行的无效列写入零.

对于 row store:

```text
for 0 <= j < cols(CS):
    if 0 <= row < TM.rows
       and 0 <= col+j < TM.cols:
        memory[addr(0,j)] ← CS[rs,j]
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

`storage_dtype` 与目标配置 dtype 的合法组合如下:

#manual-table(
  columns: (1fr, 1.5fr, 1.4fr, 1.3fr, 1.7fr),
  caption: [访存存储格式与转换],
)[
  | 寄存器域  | 内存 storage_dtype  | 配置 dtype  | load 行为     | store 行为               |
  | --------- | ------------------- | ----------- | ------------- | ------------------------ |
  | `t`, `b`  | `i8`, `u8`          | 相同        | 原样搬运      | 原样写回                 |
  | `a`, `v`  | `i32`, `u32`        | 相同        | 原样搬运      | 原样写回                 |
  | `a`, `v`  | `f32`               | `f32`       | 原样搬运      | 原样写回                 |
  | `a`, `v`  | `f16`, `bf16`       | `f32`       | 扩展为 `f32`  | 从 `f32` 按规定舍入转换  |
]

#note[
  `i8` → `i32`, `i8` → `f32`, 子字节格式 (如 `q4`) 以及打包量化格式 (如 `q8` + scale) 到 `f32` 的直接反量化; 这些转换必须使用 `twiden`, `acvt`/`vcvt`, `tquant`/`vquant`, `tdequant`/`bdequant` 等显式指令完成 (见 @quantization).
]

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
  | Instruction         | Format  | Operation          | Notes                                                          |
  | ------------------- | ------- | ------------------ | -------------------------------------------------------------- |
  | `{t,a}fill.TYPE`    | I       | D[i,j] = imm       | TYPE: t 为 `i8/u8`, a 为 `i32/u32/f32`; 无效物理位置保持原值.  |
  | `{t,a}fillx.TYPE`   | R2      | D[i,j] = xS        | TYPE: t 为 `i8/u8`, a 为 `i32/u32/f32`.                        |
  | `{t,a}copy`         | R2      | D[i,j] = S[i,j]    | 源与目的 layout 一致.                                          |
  | `{b,v}fill.TYPE`    | I       | D[j] = imm         | TYPE: b 为 `i8/u8`, v 为 `i32/u32/f32`; 无效物理位置保持原值.  |
  | `{b,v}fillx.TYPE`   | R2      | D[j] = xS          | TYPE: b 为 `i8/u8`, v 为 `i32/u32/f32`.                        |
  | `{b,v}copy`         | R2      | D[j] = S[j]        | 源与目的 layout 一致.                                          |
  | `{t,a}insert.row`   | R4      | D[rd,j] = S[j]     | 向量长度等于列数; 其他行保持.                                  |
  | `{t,a}extract.row`  | R4      | D[j] = S[rs,j]     | 目的长度等于源列数.                                            |
  | `{b,v}extract`      | R4      | xD = S[lane]       | 按源 dtype 扩展或写入浮点位模式.                               |
  | `{b,v}insert`       | R4      | D[lane] = xS       | 按目的 dtype 解释数值.                                         |
  | `{b,v}broadcast`    | R4      | D[j] = S[lane]     | —                                                              |
  | `ttranspose`        | R2      | tD[i,j] = tS[j,i]  | 仅支持 8-bit Tile; 允许原地执行, 交换有效行列数.               |
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
  | Instruction           | Format  | Operation                                       | Notes                                              |
  | --------------------- | ------- | ----------------------------------------------- | -------------------------------------------------- |
  | `mma.nn.zero.i8.i32`  | R4      | $"aD"[m,n] = sum_k "tA"[m,k] times "tB"[k,n]$   | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `mma.nn.acc.i8.i32`   | R4      | $"aD"[m,n] += sum_k "tA"[m,k] times "tB"[k,n]$  | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `bdot.nn.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[k,n]$       | `i8` 输入, `i32` 输出; 跨块累加使用 `vadd.i32`.    |
  | `mma.nt.zero.i8.i32`  | R4      | $"aD"[m,n] = sum_k "tA"[m,k] times "tB"[n,k]$   | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `mma.nt.acc.i8.i32`   | R4      | $"aD"[m,n] += sum_k "tA"[m,k] times "tB"[n,k]$  | 输入为 `i8` Tile; 乘法前符号扩展, shape 必须匹配.  |
  | `bdot.nt.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[n,k]$       | `i8` 输入, `i32` 输出; 跨块累加使用 `vadd.i32`.    |
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

本节定义 Tile, Acc 和 Vec32 的逐元素运算, 按行/列广播, 比较, select 和 mask 操作.

本节中的基础运算只处理寄存器中的有效区域. 有效区域由目的寄存器对应的 `TC`, `AC` 或 `VC` 配置确定.

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

vop.TYPE       vD, vA, vB
vopx.TYPE      vD, vA, xS
```

例如:

```asm
tadd.sat.i8 t0, t1, t2

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

以下分 8-bit 域 (Tile) 与 32-bit 域 (Acc/Vec32) 两表列出基础操作. 二元操作展开为寄存器和 Scalar (`x`) 两种来源; 8-bit 域加法和减法的溢出模式由配置 `arith_mode` 决定. 一元操作仅列单源形式, 融合乘加, 特殊函数, 比较和 select 在各自小节列出. 每行的 `TYPE` 仅取该行给出的类型集合. `and`, `or`, `xor`, `not` 与 `select` 为按位操作, 不带类型后缀, 对域内任意 dtype 适用.

#instruction-table(caption: [Tile 基础逐元素指令])[
  | Instruction   | Format  | Operation                      | Notes                                             |
  | ------------- | ------- | ------------------------------ | ------------------------------------------------- |
  | `tadd.TYPE`   | R3      | tD[i,j] = A[i,j] + B[i,j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.  |
  | `taddx.TYPE`  | R3      | tD[i,j] = A[i,j] + xS          | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsub.TYPE`   | R3      | tD[i,j] = A[i,j] - B[i,j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsubx.TYPE`  | R3      | tD[i,j] = A[i,j] - xS          | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.  |
  | `tmin.TYPE`   | R3      | tD[i,j] = min(A[i,j], B[i,j])  | TYPE: `i8/u8`.                                    |
  | `tminx.TYPE`  | R3      | tD[i,j] = min(A[i,j], xS)      | TYPE: `i8/u8`.                                    |
  | `tmax.TYPE`   | R3      | tD[i,j] = max(A[i,j], B[i,j])  | TYPE: `i8/u8`.                                    |
  | `tmaxx.TYPE`  | R3      | tD[i,j] = max(A[i,j], xS)      | TYPE: `i8/u8`.                                    |
  | `tand`        | R3      | tD[i,j] = A[i,j] and B[i,j]    | 按位操作, 与元素 dtype 无关.                      |
  | `tandx`       | R3      | tD[i,j] = A[i,j] and xS        | 按位操作, 与元素 dtype 无关.                      |
  | `tor`         | R3      | tD[i,j] = A[i,j] or B[i,j]     | 按位操作, 与元素 dtype 无关.                      |
  | `torx`        | R3      | tD[i,j] = A[i,j] or xS         | 按位操作, 与元素 dtype 无关.                      |
  | `txor`        | R3      | tD[i,j] = A[i,j] xor B[i,j]    | 按位操作, 与元素 dtype 无关.                      |
  | `txorx`       | R3      | tD[i,j] = A[i,j] xor xS        | 按位操作, 与元素 dtype 无关.                      |
  | `tshl.TYPE`   | R3      | tD[i,j] = shl(A[i,j], B[i,j])  | TYPE: `i8/u8`.                                    |
  | `tshlx.TYPE`  | R3      | tD[i,j] = shl(A[i,j], xS)      | TYPE: `i8/u8`.                                    |
  | `tshr.TYPE`   | R3      | tD[i,j] = shr(A[i,j], B[i,j])  | TYPE: `i8/u8`.                                    |
  | `tshrx.TYPE`  | R3      | tD[i,j] = shr(A[i,j], xS)      | TYPE: `i8/u8`.                                    |
  | `tsra.TYPE`   | R3      | tD[i,j] = sra(A[i,j], B[i,j])  | TYPE: `i8/u8`.                                    |
  | `tsrax.TYPE`  | R3      | tD[i,j] = sra(A[i,j], xS)      | TYPE: `i8/u8`.                                    |
  | `tnot`        | R2      | tD[i,j] = not A[i,j]           | 按位操作, 与元素 dtype 无关; 仅有一个数据源.      |
]

#instruction-table(caption: [Acc/Vec32 基础逐元素指令])[
  | Instruction       | Format  | Operation               | Notes                                                   |
  | ----------------- | ------- | ----------------------- | ------------------------------------------------------- |
  | `{a,v}add.TYPE`   | R3      | D[p] = A[p] + B[p]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}addx.TYPE`  | R3      | D[p] = A[p] + xS        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}sub.TYPE`   | R3      | D[p] = A[p] - B[p]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}subx.TYPE`  | R3      | D[p] = A[p] - xS        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}mul.TYPE`   | R3      | D[p] = A[p] × B[p]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}mulx.TYPE`  | R3      | D[p] = A[p] × xS        | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `{a,v}div.TYPE`   | R3      | D[p] = A[p] / B[p]      | TYPE: `f32`.                                            |
  | `{a,v}divx.TYPE`  | R3      | D[p] = A[p] / xS        | TYPE: `f32`.                                            |
  | `{a,v}min.TYPE`   | R3      | D[p] = min(A[p], B[p])  | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}minx.TYPE`  | R3      | D[p] = min(A[p], xS)    | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}max.TYPE`   | R3      | D[p] = max(A[p], B[p])  | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}maxx.TYPE`  | R3      | D[p] = max(A[p], xS)    | TYPE: `i32/u32/f32`.                                    |
  | `{a,v}and`        | R3      | D[p] = A[p] and B[p]    | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}andx`       | R3      | D[p] = A[p] and xS      | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}or`         | R3      | D[p] = A[p] or B[p]     | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}orx`        | R3      | D[p] = A[p] or xS       | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}xor`        | R3      | D[p] = A[p] xor B[p]    | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}xorx`       | R3      | D[p] = A[p] xor xS      | 按位操作, 与元素 dtype 无关.                            |
  | `{a,v}shl.TYPE`   | R3      | D[p] = shl(A[p], B[p])  | TYPE: `i32/u32`.                                        |
  | `{a,v}shlx.TYPE`  | R3      | D[p] = shl(A[p], xS)    | TYPE: `i32/u32`.                                        |
  | `{a,v}shr.TYPE`   | R3      | D[p] = shr(A[p], B[p])  | TYPE: `i32/u32`.                                        |
  | `{a,v}shrx.TYPE`  | R3      | D[p] = shr(A[p], xS)    | TYPE: `i32/u32`.                                        |
  | `{a,v}sra.TYPE`   | R3      | D[p] = sra(A[p], B[p])  | TYPE: `i32/u32`.                                        |
  | `{a,v}srax.TYPE`  | R3      | D[p] = sra(A[p], xS)    | TYPE: `i32/u32`.                                        |
  | `{a,v}not`        | R2      | D[p] = not A[p]         | 按位操作, 与元素 dtype 无关; 仅有一个数据源.            |
  | `{a,v}abs.TYPE`   | R2      | D[p] = abs(A[p])        | 类型: `i32/f32`; 仅有一个数据源.                        |
  | `{a,v}neg.TYPE`   | R2      | D[p] = -A[p]            | 类型: `i32/f32`; 仅有一个数据源.                        |
]



== 整数算术规则

8-bit 域 (`i8/u8`) 的 `add` 和 `sub` 的溢出行为由绑定配置寄存器的 `arith_mode` 字段决定: 0 = wrap (回绕), 1 = sat (饱和), 2-3 预留. 汇编后缀 `.sat`/`.wrap` 是对配置状态的标注, 必须与实际配置一致; 不携带后缀时行为同样由配置决定. 32-bit 整数 `add`, `sub`, `mul` 默认使用 wrap32 回绕.

```asm
tadd.sat.i8  t0, t1, t2    # 要求 tc0.arith_mode = sat
tadd.wrap.i8 t0, t1, t2    # 要求 tc0.arith_mode = wrap
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


== 浮点逐元素规则

`fma` 运算使用 `fmadd` 助记符; 按 Acc/Vec32 的 f32 数据域列出. 这里只列三数据源形式, 其他操作数变体尚未定义.

#instruction-table(caption: [融合乘加指令])[
  | Instruction       | Format  | Operation                     | Notes                                                   |
  | ----------------- | ------- | ----------------------------- | ------------------------------------------------------- |
  | `{a,v}fmadd.f32`  | R4      | D[p] = fma(A[p], B[p], C[p])  | 一次融合乘加, 一次 f32 舍入; 不能任意替换独立 mul/add.  |
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
  | Instruction          | Format  | Operation                  | Notes                                        |
  | -------------------- | ------- | -------------------------- | -------------------------------------------- |
  | `{a,v}exp2.approx`   | R2      | D[p] = exp2_approx(A[p])   | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
  | `{a,v}rcp.approx`    | R2      | D[p] = rcp_approx(A[p])    | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
  | `{a,v}rsqrt.approx`  | R2      | D[p] = rsqrt_approx(A[p])  | 源和目的为 f32 Acc/Vec32; 采用近似函数规则.  |
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
  | Instruction       | Format  | Operation                         | Notes                                                   |
  | ----------------- | ------- | --------------------------------- | ------------------------------------------------------- |
  | `tadd.brow.TYPE`  | RB      | tD[i,j] = tA[i,j] + tB[rb,j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tsub.brow.TYPE`  | RB      | tD[i,j] = tA[i,j] - tB[rb,j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tmin.brow.TYPE`  | RB      | tD[i,j] = min(tA[i,j], tB[rb,j])  | TYPE: `i8/u8`.                                          |
  | `tmax.brow.TYPE`  | RB      | tD[i,j] = max(tA[i,j], tB[rb,j])  | TYPE: `i8/u8`.                                          |
  | `tand.brow`       | RB      | tD[i,j] = tA[i,j] and tB[rb,j]    | 按位操作, 与元素 dtype 无关.                            |
  | `tor.brow`        | RB      | tD[i,j] = tA[i,j] or tB[rb,j]     | 按位操作, 与元素 dtype 无关.                            |
  | `txor.brow`       | RB      | tD[i,j] = tA[i,j] xor tB[rb,j]    | 按位操作, 与元素 dtype 无关.                            |
  | `tshl.brow.TYPE`  | RB      | tD[i,j] = shl(tA[i,j], tB[rb,j])  | TYPE: `i8/u8`.                                          |
  | `tshr.brow.TYPE`  | RB      | tD[i,j] = shr(tA[i,j], tB[rb,j])  | TYPE: `i8/u8`.                                          |
  | `tsra.brow.TYPE`  | RB      | tD[i,j] = sra(tA[i,j], tB[rb,j])  | TYPE: `i8/u8`.                                          |
  | `aadd.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] + aB[rb,j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asub.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] - aB[rb,j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amul.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] × aB[rb,j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adiv.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] / aB[rb,j]      | TYPE: `f32`.                                            |
  | `amin.brow.TYPE`  | RB      | aD[i,j] = min(aA[i,j], aB[rb,j])  | TYPE: `i32/u32/f32`.                                    |
  | `amax.brow.TYPE`  | RB      | aD[i,j] = max(aA[i,j], aB[rb,j])  | TYPE: `i32/u32/f32`.                                    |
  | `aand.brow`       | RB      | aD[i,j] = aA[i,j] and aB[rb,j]    | 按位操作, 与元素 dtype 无关.                            |
  | `aor.brow`        | RB      | aD[i,j] = aA[i,j] or aB[rb,j]     | 按位操作, 与元素 dtype 无关.                            |
  | `axor.brow`       | RB      | aD[i,j] = aA[i,j] xor aB[rb,j]    | 按位操作, 与元素 dtype 无关.                            |
  | `ashl.brow.TYPE`  | RB      | aD[i,j] = shl(aA[i,j], aB[rb,j])  | TYPE: `i32/u32`.                                        |
  | `ashr.brow.TYPE`  | RB      | aD[i,j] = shr(aA[i,j], aB[rb,j])  | TYPE: `i32/u32`.                                        |
  | `asra.brow.TYPE`  | RB      | aD[i,j] = sra(aA[i,j], aB[rb,j])  | TYPE: `i32/u32`.                                        |
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
  | Instruction         | Format  | Operation                      | Notes                                                   |
  | ------------------- | ------- | ------------------------------ | ------------------------------------------------------- |
  | `taddb.byrow.TYPE`  | R3      | tD[i,j] = tA[i,j] + bS[i]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tsubb.byrow.TYPE`  | R3      | tD[i,j] = tA[i,j] - bS[i]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tminb.byrow.TYPE`  | R3      | tD[i,j] = min(tA[i,j], bS[i])  | TYPE: `i8/u8`.                                          |
  | `tmaxb.byrow.TYPE`  | R3      | tD[i,j] = max(tA[i,j], bS[i])  | TYPE: `i8/u8`.                                          |
  | `tandb.byrow`       | R3      | tD[i,j] = tA[i,j] and bS[i]    | 按位操作, 与元素 dtype 无关.                            |
  | `torb.byrow`        | R3      | tD[i,j] = tA[i,j] or bS[i]     | 按位操作, 与元素 dtype 无关.                            |
  | `txorb.byrow`       | R3      | tD[i,j] = tA[i,j] xor bS[i]    | 按位操作, 与元素 dtype 无关.                            |
  | `tshlb.byrow.TYPE`  | R3      | tD[i,j] = shl(tA[i,j], bS[i])  | TYPE: `i8/u8`.                                          |
  | `tshrb.byrow.TYPE`  | R3      | tD[i,j] = shr(tA[i,j], bS[i])  | TYPE: `i8/u8`.                                          |
  | `tsrab.byrow.TYPE`  | R3      | tD[i,j] = sra(tA[i,j], bS[i])  | TYPE: `i8/u8`.                                          |
  | `aaddv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] + vS[i]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asubv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] - vS[i]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amulv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] × vS[i]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adivv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] / vS[i]      | TYPE: `f32`.                                            |
  | `aminv.byrow.TYPE`  | R3      | aD[i,j] = min(aA[i,j], vS[i])  | TYPE: `i32/u32/f32`.                                    |
  | `amaxv.byrow.TYPE`  | R3      | aD[i,j] = max(aA[i,j], vS[i])  | TYPE: `i32/u32/f32`.                                    |
  | `aandv.byrow`       | R3      | aD[i,j] = aA[i,j] and vS[i]    | 按位操作, 与元素 dtype 无关.                            |
  | `aorv.byrow`        | R3      | aD[i,j] = aA[i,j] or vS[i]     | 按位操作, 与元素 dtype 无关.                            |
  | `axorv.byrow`       | R3      | aD[i,j] = aA[i,j] xor vS[i]    | 按位操作, 与元素 dtype 无关.                            |
  | `ashlv.byrow.TYPE`  | R3      | aD[i,j] = shl(aA[i,j], vS[i])  | TYPE: `i32/u32`.                                        |
  | `ashrv.byrow.TYPE`  | R3      | aD[i,j] = shr(aA[i,j], vS[i])  | TYPE: `i32/u32`.                                        |
  | `asrav.byrow.TYPE`  | R3      | aD[i,j] = sra(aA[i,j], vS[i])  | TYPE: `i32/u32`.                                        |
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
  | Instruction         | Format  | Operation                      | Notes                                                   |
  | ------------------- | ------- | ------------------------------ | ------------------------------------------------------- |
  | `taddb.bycol.TYPE`  | R3      | tD[i,j] = tA[i,j] + bS[j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tsubb.bycol.TYPE`  | R3      | tD[i,j] = tA[i,j] - bS[j]      | TYPE: `i8/u8`; 溢出模式由配置 `arith_mode` 决定.        |
  | `tminb.bycol.TYPE`  | R3      | tD[i,j] = min(tA[i,j], bS[j])  | TYPE: `i8/u8`.                                          |
  | `tmaxb.bycol.TYPE`  | R3      | tD[i,j] = max(tA[i,j], bS[j])  | TYPE: `i8/u8`.                                          |
  | `tandb.bycol`       | R3      | tD[i,j] = tA[i,j] and bS[j]    | 按位操作, 与元素 dtype 无关.                            |
  | `torb.bycol`        | R3      | tD[i,j] = tA[i,j] or bS[j]     | 按位操作, 与元素 dtype 无关.                            |
  | `txorb.bycol`       | R3      | tD[i,j] = tA[i,j] xor bS[j]    | 按位操作, 与元素 dtype 无关.                            |
  | `tshlb.bycol.TYPE`  | R3      | tD[i,j] = shl(tA[i,j], bS[j])  | TYPE: `i8/u8`.                                          |
  | `tshrb.bycol.TYPE`  | R3      | tD[i,j] = shr(tA[i,j], bS[j])  | TYPE: `i8/u8`.                                          |
  | `tsrab.bycol.TYPE`  | R3      | tD[i,j] = sra(tA[i,j], bS[j])  | TYPE: `i8/u8`.                                          |
  | `aaddv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] + vS[j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `asubv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] - vS[j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `amulv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] × vS[j]      | TYPE: `i32/u32/f32`; 整数使用 wrap32, 浮点按 f32 规则.  |
  | `adivv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] / vS[j]      | TYPE: `f32`.                                            |
  | `aminv.bycol.TYPE`  | R3      | aD[i,j] = min(aA[i,j], vS[j])  | TYPE: `i32/u32/f32`.                                    |
  | `amaxv.bycol.TYPE`  | R3      | aD[i,j] = max(aA[i,j], vS[j])  | TYPE: `i32/u32/f32`.                                    |
  | `aandv.bycol`       | R3      | aD[i,j] = aA[i,j] and vS[j]    | 按位操作, 与元素 dtype 无关.                            |
  | `aorv.bycol`        | R3      | aD[i,j] = aA[i,j] or vS[j]     | 按位操作, 与元素 dtype 无关.                            |
  | `axorv.bycol`       | R3      | aD[i,j] = aA[i,j] xor vS[j]    | 按位操作, 与元素 dtype 无关.                            |
  | `ashlv.bycol.TYPE`  | R3      | aD[i,j] = shl(aA[i,j], vS[j])  | TYPE: `i32/u32`.                                        |
  | `ashrv.bycol.TYPE`  | R3      | aD[i,j] = shr(aA[i,j], vS[j])  | TYPE: `i32/u32`.                                        |
  | `asrav.bycol.TYPE`  | R3      | aD[i,j] = sra(aA[i,j], vS[j])  | TYPE: `i32/u32`.                                        |
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
  | Instruction            | Format  | Operation                     | Notes                                                    |
  | ---------------------- | ------- | ----------------------------- | -------------------------------------------------------- |
  | `{a,v}cmp.eq.TYPE`     | R4      | D[p] = A[p] == B[p]           | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmp.ne.TYPE`     | R4      | D[p] = A[p] != B[p]           | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmp.lt.TYPE`     | R4      | D[p] = A[p] < B[p]            | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmp.ge.TYPE`     | R4      | D[p] = A[p] >= B[p]           | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmp.le.f32`      | R4      | D[p] = A[p] <= B[p]           | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmp.unord.f32`   | R4      | D[p] = unordered(A[p], B[p])  | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmpx.eq.TYPE`    | R4      | D[p] = A[p] == xS             | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmpx.ne.TYPE`    | R4      | D[p] = A[p] != xS             | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmpx.lt.TYPE`    | R4      | D[p] = A[p] < xS              | TYPE: `i32/u32/f32`; 生成 `u32` mask, 真为全一, 假为零.  |
  | `{a,v}cmpx.ge.TYPE`    | R4      | D[p] = A[p] >= xS             | TYPE: `i32/u32`; 生成 `u32` mask, 真为全一, 假为零.      |
  | `{a,v}cmpx.le.f32`     | R4      | D[p] = A[p] <= xS             | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
  | `{a,v}cmpx.unord.f32`  | R4      | D[p] = unordered(A[p], xS)    | 源为 f32, 目的为 `u32` mask; 真为全一, 假为零.           |
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
  | Instruction    | Format  | Operation                           | Notes                                                            |
  | -------------- | ------- | ----------------------------------- | ---------------------------------------------------------------- |
  | `tselect`      | R4      | tD[i,j] = M[i,j] ? A[i,j] : B[i,j]  | 按位选择, 与元素 dtype 无关; mask 为 `u8`, 两个数据源均被读取.   |
  | `{a,v}select`  | R4      | D[p] = M[p] ? A[p] : B[p]           | 按位选择, 与元素 dtype 无关; mask 为 `u32`, 两个数据源均被读取.  |
]

select 根据 mask 在两个已经计算好的值之间选择(t 数据使用 `u8`, a/v 数据使用 `u32`.):

```asm
tselect tD, tM, tA, tB
aselect aD, aM, aA, aB
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
  | Instruction        | Format  | Operation                                           | Notes                                                                             |
  | ------------------ | ------- | --------------------------------------------------- | --------------------------------------------------------------------------------- |
  | `{t,a}mask.tail`   | R4      | D[i,j] = (i < nRows and j < nCols) ? S[i,j] : fill  | 边界为打包 Scalar `xBounds` 的字段; 其余有效寄存器位置写 fill; 不缩短有效 shape.  |
  | `{t,a}mask.tril`   | R4      | D[i,j] = (j - i <= xDelta) ? S[i,j] : fill          | 有符号偏移; 包含边界, 其余位置写 fill.                                            |
  | `{t,a}mask.triu`   | R4      | D[i,j] = (j - i >= xDelta) ? S[i,j] : fill          | 有符号偏移; 包含边界, 其余位置写 fill.                                            |
  | `{b,v}mask.tail`   | R4      | D[j] = (j < xLen) ? S[j] : fill                     | 其余有效 lane 写 fill; 不缩短有效长度.                                            |
  | `{t,a}maskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                 | fill 可为任意值.                                                                  |
  | `{t,a}maskx.tril`  | R4      | 同 `mask.tril`, fill 由 Scalar 提供                 | fill 可为任意值.                                                                  |
  | `{t,a}maskx.triu`  | R4      | 同 `mask.triu`, fill 由 Scalar 提供                 | fill 可为任意值.                                                                  |
  | `{b,v}maskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                 | fill 可为任意值.                                                                  |
]

mask 指令将源数据的某些位置替换为指定 fill 值. `mask` 的 fill 为 6-bit 立即数编码 (按目的 dtype 解释); `maskx` 的 fill 由 Scalar 寄存器提供, 可为任意值.

矩阵 mask:

```asm
{t,a}mask.tail  D, S, xBounds, fill
{t,a}maskx.tail D, S, xBounds, xFill

{t,a}mask.tril  D, S, xDelta, fill
{t,a}maskx.tril D, S, xDelta, xFill
{t,a}mask.triu  D, S, xDelta, fill
{t,a}maskx.triu D, S, xDelta, xFill
```

`mask.tail` 的边界 `nRows` 和 `nCols` (有效行数, 列数) 打包在一个 Scalar 寄存器 `xBounds` 中 (`[31:0]` = `nRows`, `[63:32]` = `nCols`, 是寄存器内坐标, 并非内存 view); `tril`/`triu` 的 `xDelta` 为有符号 Scalar 值.

向量 mask:

```asm
{b,v}mask.tail  D, S, xLen, fill
{b,v}maskx.tail D, S, xLen, xFill
```

=== Tail mask

矩阵 tail mask 定义为 (`nRows`, `nCols` 取自打包寄存器 `xBounds` 的低, 高 32 bit):

```text
for 0 ≤ i < rows(D):
    for 0 ≤ j < cols(D):
        if i < nRows and j < nCols:
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
  | Instruction               | Format  | Operation                                                                     | Notes                                        |
  | ------------------------- | ------- | ----------------------------------------------------------------------------- | -------------------------------------------- |
  | `areduce.rows.sum.f32`    | R2      | $"vD"[i] = sum_j "aS"[i,j]$                                                   | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.max.f32`    | R2      | $"vD"[i] = max_j "aS"[i,j]$                                                   | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.min.f32`    | R2      | $"vD"[i] = min_j "aS"[i,j]$                                                   | 源与目的为 f32; 只规约源有效元素.            |
  | `areduce.rows.sumsq.f32`  | R2      | $"vD"[i] = sum_j "aS"[i,j]^2$                                                 | 源与目的为 f32; RMSNorm 示例中的行规约.      |
  | `vreduce.sum.f32`         | R2      | $"xD" = sum_j "vS"[j]$                                                        | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.max.f32`         | R2      | $"xD" = max_j "vS"[j]$                                                        | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.min.f32`         | R2      | $"xD" = min_j "vS"[j]$                                                        | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.sumsq.f32`       | R2      | $"xD" = sum_j "vS"[j]^2$                                                      | 按对应 fold 规则规约; 空结果使用规定单位元.  |
  | `vreduce.argmax.f32`      | R4      | $"xIndex" = op("argmax")_j "vS"[j]$ #linebreak() $"xValue" = "vS"["xIndex"]$  | 并列取较小索引; NaN 选择规则及空结果见正文.  |
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
  | `acvt.i32.f32`   | R2      | aD[i,j] = f32(aS[i,j])       | 允许原地执行; 成功接收时更新目的 dtype.  |
  | `vcvt.i32.f32`   | R2      | vD[j] = f32(vS[j])           | 允许原地执行; 成功接收时更新目的 dtype.  |
  | `twiden.i8.i32`  | R2      | aD[i,j] = sign_ext(tS[i,j])  | 跨数据域, 不能原地执行; 保持有效 shape.  |
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
  | Instruction          | Format  | Operation                                                                                | Notes                                          |
  | -------------------- | ------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------- |
  | `tquant.rows.q8s32`  | R4      | tD[i,:] = quant_q8s32(aS[i,:]).bits #linebreak() vScale[i] = quant_q8s32(aS[i,:]).scale  | Tile bits 与 Vec32 scale 是两个显式目的.       |
  | `vquant.q8s32`       | R4      | bD = quant_q8s32(vS).bits #linebreak() vScale[lane] = quant_q8s32(vS).scale              | Vec8 bits 与 Vec32 scale lane 是两个显式目的.  |
  | `tdequant.rows.f32`  | R4      | aD[i,j] = f32(tS[i,j]) × vScale[i]                                                       | Tile bits 和 Vec32 scale 都是显式源.           |
  | `bdequant.f32`       | R4      | vD[j] = f32(bS[j]) × vScale[lane]                                                        | Vec8 bits 和 Vec32 scale lane 都是显式源.      |
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

Scalar 指令集为 RV64IM, 其指令不在本清单. 各类尚未定义的变体均不作为已分配编码处理.

== 标量与同步

详细语义见 @scalar-sync.

#instruction-listing(caption: [同步指令清单])[
  | Instruction   | Format  | Function                           | Summary                            |
  | ------------- | ------- | ---------------------------------- | ---------------------------------- |
  | `fence.mem`   | Z       | 等待此前访存完成并达到约定可见点.  | 等待此前访存完成并达到约定可见点.  |
  | `fence.sa`    | Z       | 等待此前 SA 操作完成.              | 等待此前 SA 操作完成.              |
  | `fence.all`   | Z       | 等待此前全部后端工作完成.          | 等待此前全部后端工作完成.          |
  | `kernel.end`  | Z       | 报告 kernel 完成.                  | 报告 kernel 完成.                  |
]

== 配置指令

详细语义见 @configuration.

#instruction-listing(caption: [配置指令清单])[
  | Instruction  | Format  | Function                  | Summary                                    |
  | ------------ | ------- | ------------------------- | ------------------------------------------ |
  | `cfg.seti`   | I       | C[field] = extend(imm)    | 扩展立即数, 校验后写入指定配置字段.        |
  | `cfg.setx`   | R4      | C[field] = x[xS]          | 从 Scalar 读取完整值, 校验后写入配置字段.  |
  | `cfg.copy`   | R4      | $C_D = C_S$               | 复制同类型配置寄存器的全部字段.            |
  | `cfg.get`    | R4      | x[xD] = extend(C[field])  | 读取配置字段, 扩展后写入 Scalar.           |
]

== 地址与访存指令

详细语义见 @memory.

#instruction-listing(caption: [地址与访存指令清单])[
  | Instruction   | Format  | Function                      | Summary                                |
  | ------------- | ------- | ----------------------------- | -------------------------------------- |
  | `tload`       | R4      | tD[i,j] = memory[addr(i,j)]   | 从 TM 描述的内存读取到 Tile 有效区域.  |
  | `tstore`      | R4      | memory[addr(i,j)] = S[i,j]    | 将 Tile 有效区域写入 TM 描述的内存.    |
  | `tload.row`   | MR      | tD[rd,j] = memory[addr(0,j)]  | 从 TM 描述的内存读取到 Tile 指定行.    |
  | `tstore.row`  | MR      | memory[addr(0,j)] = S[rs,j]   | 将 Tile 指定行写入 TM 描述的内存.      |
  | `aload`       | R4      | aD[i,j] = memory[addr(i,j)]   | 从 TM 描述的内存读取到 Acc 有效区域.   |
  | `astore`      | R4      | memory[addr(i,j)] = S[i,j]    | 将 Acc 有效区域写入 TM 描述的内存.     |
  | `aload.row`   | MR      | aD[rd,j] = memory[addr(0,j)]  | 从 TM 描述的内存读取到 Acc 指定行.     |
  | `astore.row`  | MR      | memory[addr(0,j)] = S[rs,j]   | 将 Acc 指定行写入 TM 描述的内存.       |
  | `bload`       | R4      | bD[j] = memory[addr(j)]       | 从 VM 描述的内存读取 Vec8 向量.        |
  | `bstore`      | R4      | memory[addr(j)] = S[j]        | 将 Vec8 向量写入 VM 描述的内存.        |
  | `vload`       | R4      | vD[j] = memory[addr(j)]       | 从 VM 描述的内存读取 Vec32 向量.       |
  | `vstore`      | R4      | memory[addr(j)] = S[j]        | 将 Vec32 向量写入 VM 描述的内存.       |
]

== 初始化, 搬运与转置

详细语义见 @data-movement.

#instruction-listing(caption: [初始化, 搬运与转置指令清单])[
  | Instruction     | Format  | Function           | Summary                                     |
  | --------------- | ------- | ------------------ | ------------------------------------------- |
  | `tfill.TYPE`    | I       | tD[i,j] = imm      | 将立即数填入 Tile 的有效区域.               |
  | `tfillx.TYPE`   | R2      | tD[i,j] = xS       | 用 Scalar 值填充 Tile 的有效区域.           |
  | `tcopy`         | R2      | tD[i,j] = S[i,j]   | 复制同域 Tile 的有效数据.                   |
  | `afill.TYPE`    | I       | aD[i,j] = imm      | 将立即数填入 Acc 的有效区域.                |
  | `afillx.TYPE`   | R2      | aD[i,j] = xS       | 用 Scalar 值填充 Acc 的有效区域.            |
  | `acopy`         | R2      | aD[i,j] = S[i,j]   | 复制同域 Acc 的有效数据.                    |
  | `bfill.TYPE`    | I       | bD[j] = imm        | 将立即数填入 Vec8 的有效区域.               |
  | `bfillx.TYPE`   | R2      | bD[j] = xS         | 用 Scalar 值填充 Vec8 的有效区域.           |
  | `bcopy`         | R2      | bD[j] = S[j]       | 复制同域 Vec8 的有效数据.                   |
  | `vfill.TYPE`    | I       | vD[j] = imm        | 将立即数填入 Vec32 的有效区域.              |
  | `vfillx.TYPE`   | R2      | vD[j] = xS         | 用 Scalar 值填充 Vec32 的有效区域.          |
  | `vcopy`         | R2      | vD[j] = S[j]       | 复制同域 Vec32 的有效数据.                  |
  | `tinsert.row`   | R4      | tD[rd,j] = bS[j]   | 将 Vec8 写入 Tile 的指定行.                 |
  | `textract.row`  | R4      | bD[j] = tS[rs,j]   | 从 Tile 指定行提取到 Vec8.                  |
  | `ainsert.row`   | R4      | aD[rd,j] = vS[j]   | 将 Vec32 写入 Acc 的指定行.                 |
  | `aextract.row`  | R4      | vD[j] = aS[rs,j]   | 从 Acc 指定行提取到 Vec32.                  |
  | `bextract`      | R3      | xD = bS[lane]      | 将 Vec8 的指定 lane 提取到 Scalar.          |
  | `binsert`       | R3      | bD[lane] = xS      | 将 Scalar 值写入 Vec8 的指定 lane.          |
  | `bbroadcast`    | R3      | bD[j] = bS[lane]   | 将源 Vec8 的一个 lane 广播到目的有效区域.   |
  | `vextract`      | R3      | xD = vS[lane]      | 将 Vec32 的指定 lane 提取到 Scalar.         |
  | `vinsert`       | R3      | vD[lane] = xS      | 将 Scalar 值写入 Vec32 的指定 lane.         |
  | `vbroadcast`    | R3      | vD[j] = vS[lane]   | 将源 Vec32 的一个 lane 广播到目的有效区域.  |
  | `ttranspose`    | R2      | tD[i,j] = tS[j,i]  | 交换 Tile 的行列, 将元素转置写入目的 Tile.  |
]

== 矩阵乘与向量—矩阵乘

详细语义见 @matrix.

#instruction-listing(caption: [矩阵乘与点积指令清单])[
  | Instruction           | Format  | Function                                        | Summary                                              |
  | --------------------- | ------- | ----------------------------------------------- | ---------------------------------------------------- |
  | `mma.nn.zero.i8.i32`  | R4      | $"aD"[m,n] = sum_k "tA"[m,k] times "tB"[k,n]$   | 按普通右矩阵执行矩阵乘, 写入 `i32` Acc.              |
  | `mma.nn.acc.i8.i32`   | R4      | $"aD"[m,n] += sum_k "tA"[m,k] times "tB"[k,n]$  | 按普通右矩阵执行矩阵乘, 累加到旧 `i32` Acc.          |
  | `bdot.nn.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[k,n]$       | Vec8 与 Tile 各列执行点积, 结果写入 Vec32.           |
  | `mma.nt.zero.i8.i32`  | R4      | $"aD"[m,n] = sum_k "tA"[m,k] times "tB"[n,k]$   | 将右 Tile 逻辑转置后执行矩阵乘, 写入 `i32` Acc.      |
  | `mma.nt.acc.i8.i32`   | R4      | $"aD"[m,n] += sum_k "tA"[m,k] times "tB"[n,k]$  | 将右 Tile 逻辑转置后执行矩阵乘, 累加到旧 `i32` Acc.  |
  | `bdot.nt.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[n,k]$       | Vec8 与 Tile 各行执行点积, 结果写入 Vec32.           |
]

== 逐元素, 广播和 mask

详细语义见 @elementwise.

#instruction-listing(caption: [Tile 基础逐元素指令清单])[
  | Instruction   | Format  | Function                       | Summary                                                 |
  | ------------- | ------- | ------------------------------ | ------------------------------------------------------- |
  | `tadd.TYPE`   | R3      | tD[i,j] = A[i,j] + B[i,j]      | 同域逐元素加法; 溢出模式由配置 `arith_mode` 决定.       |
  | `taddx.TYPE`  | R3      | tD[i,j] = A[i,j] + xS          | Scalar 值逐元素加法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsub.TYPE`   | R3      | tD[i,j] = A[i,j] - B[i,j]      | 同域逐元素减法; 溢出模式由配置 `arith_mode` 决定.       |
  | `tsubx.TYPE`  | R3      | tD[i,j] = A[i,j] - xS          | Scalar 值逐元素减法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tmin.TYPE`   | R3      | tD[i,j] = min(A[i,j], B[i,j])  | 同域逐元素取小; `i8/u8`.                                |
  | `tminx.TYPE`  | R3      | tD[i,j] = min(A[i,j], xS)      | Scalar 值逐元素取小; `i8/u8`.                           |
  | `tmax.TYPE`   | R3      | tD[i,j] = max(A[i,j], B[i,j])  | 同域逐元素取大; `i8/u8`.                                |
  | `tmaxx.TYPE`  | R3      | tD[i,j] = max(A[i,j], xS)      | Scalar 值逐元素取大; `i8/u8`.                           |
  | `tand`        | R3      | tD[i,j] = A[i,j] and B[i,j]    | 同域逐元素按位与.                                       |
  | `tandx`       | R3      | tD[i,j] = A[i,j] and xS        | Scalar 值逐元素按位与.                                  |
  | `tor`         | R3      | tD[i,j] = A[i,j] or B[i,j]     | 同域逐元素按位或.                                       |
  | `torx`        | R3      | tD[i,j] = A[i,j] or xS         | Scalar 值逐元素按位或.                                  |
  | `txor`        | R3      | tD[i,j] = A[i,j] xor B[i,j]    | 同域逐元素按位异或.                                     |
  | `txorx`       | R3      | tD[i,j] = A[i,j] xor xS        | Scalar 值逐元素按位异或.                                |
  | `tshl.TYPE`   | R3      | tD[i,j] = shl(A[i,j], B[i,j])  | 同域逐元素左移; `i8/u8`.                                |
  | `tshlx.TYPE`  | R3      | tD[i,j] = shl(A[i,j], xS)      | Scalar 值逐元素左移; `i8/u8`.                           |
  | `tshr.TYPE`   | R3      | tD[i,j] = shr(A[i,j], B[i,j])  | 同域逐元素逻辑右移; `i8/u8`.                            |
  | `tshrx.TYPE`  | R3      | tD[i,j] = shr(A[i,j], xS)      | Scalar 值逐元素逻辑右移; `i8/u8`.                       |
  | `tsra.TYPE`   | R3      | tD[i,j] = sra(A[i,j], B[i,j])  | 同域逐元素算术右移; `i8/u8`.                            |
  | `tsrax.TYPE`  | R3      | tD[i,j] = sra(A[i,j], xS)      | Scalar 值逐元素算术右移; `i8/u8`.                       |
  | `tnot`        | R2      | tD[i,j] = not A[i,j]           | 逐元素按位取反.                                         |
]

#instruction-listing(caption: [Acc 基础逐元素指令清单])[
  | Instruction   | Format  | Function                       | Summary                              |
  | ------------- | ------- | ------------------------------ | ------------------------------------ |
  | `aadd.TYPE`   | R3      | aD[i,j] = A[i,j] + B[i,j]      | 同域逐元素加法; `i32/u32/f32`.       |
  | `aaddx.TYPE`  | R3      | aD[i,j] = A[i,j] + xS          | Scalar 值逐元素加法; `i32/u32/f32`.  |
  | `asub.TYPE`   | R3      | aD[i,j] = A[i,j] - B[i,j]      | 同域逐元素减法; `i32/u32/f32`.       |
  | `asubx.TYPE`  | R3      | aD[i,j] = A[i,j] - xS          | Scalar 值逐元素减法; `i32/u32/f32`.  |
  | `amul.TYPE`   | R3      | aD[i,j] = A[i,j] × B[i,j]      | 同域逐元素乘法; `i32/u32/f32`.       |
  | `amulx.TYPE`  | R3      | aD[i,j] = A[i,j] × xS          | Scalar 值逐元素乘法; `i32/u32/f32`.  |
  | `adiv.TYPE`   | R3      | aD[i,j] = A[i,j] / B[i,j]      | 同域逐元素除法; `f32`.               |
  | `adivx.TYPE`  | R3      | aD[i,j] = A[i,j] / xS          | Scalar 值逐元素除法; `f32`.          |
  | `amin.TYPE`   | R3      | aD[i,j] = min(A[i,j], B[i,j])  | 同域逐元素取小; `i32/u32/f32`.       |
  | `aminx.TYPE`  | R3      | aD[i,j] = min(A[i,j], xS)      | Scalar 值逐元素取小; `i32/u32/f32`.  |
  | `amax.TYPE`   | R3      | aD[i,j] = max(A[i,j], B[i,j])  | 同域逐元素取大; `i32/u32/f32`.       |
  | `amaxx.TYPE`  | R3      | aD[i,j] = max(A[i,j], xS)      | Scalar 值逐元素取大; `i32/u32/f32`.  |
  | `aand`        | R3      | aD[i,j] = A[i,j] and B[i,j]    | 同域逐元素按位与.                    |
  | `aandx`       | R3      | aD[i,j] = A[i,j] and xS        | Scalar 值逐元素按位与.               |
  | `aor`         | R3      | aD[i,j] = A[i,j] or B[i,j]     | 同域逐元素按位或.                    |
  | `aorx`        | R3      | aD[i,j] = A[i,j] or xS         | Scalar 值逐元素按位或.               |
  | `axor`        | R3      | aD[i,j] = A[i,j] xor B[i,j]    | 同域逐元素按位异或.                  |
  | `axorx`       | R3      | aD[i,j] = A[i,j] xor xS        | Scalar 值逐元素按位异或.             |
  | `ashl.TYPE`   | R3      | aD[i,j] = shl(A[i,j], B[i,j])  | 同域逐元素左移; `i32/u32`.           |
  | `ashlx.TYPE`  | R3      | aD[i,j] = shl(A[i,j], xS)      | Scalar 值逐元素左移; `i32/u32`.      |
  | `ashr.TYPE`   | R3      | aD[i,j] = shr(A[i,j], B[i,j])  | 同域逐元素逻辑右移; `i32/u32`.       |
  | `ashrx.TYPE`  | R3      | aD[i,j] = shr(A[i,j], xS)      | Scalar 值逐元素逻辑右移; `i32/u32`.  |
  | `asra.TYPE`   | R3      | aD[i,j] = sra(A[i,j], B[i,j])  | 同域逐元素算术右移; `i32/u32`.       |
  | `asrax.TYPE`  | R3      | aD[i,j] = sra(A[i,j], xS)      | Scalar 值逐元素算术右移; `i32/u32`.  |
  | `anot`        | R2      | aD[i,j] = not A[i,j]           | 逐元素按位取反.                      |
  | `aabs.TYPE`   | R2      | aD[i,j] = abs(A[i,j])          | 逐元素绝对值; `i32/f32`.             |
  | `aneg.TYPE`   | R2      | aD[i,j] = -A[i,j]              | 逐元素取负; `i32/f32`.               |
]

#instruction-listing(caption: [Vec32 基础逐元素指令清单])[
  | Instruction   | Format  | Function                 | Summary                              |
  | ------------- | ------- | ------------------------ | ------------------------------------ |
  | `vadd.TYPE`   | R3      | vD[j] = A[j] + B[j]      | 同域逐元素加法; `i32/u32/f32`.       |
  | `vaddx.TYPE`  | R3      | vD[j] = A[j] + xS        | Scalar 值逐元素加法; `i32/u32/f32`.  |
  | `vsub.TYPE`   | R3      | vD[j] = A[j] - B[j]      | 同域逐元素减法; `i32/u32/f32`.       |
  | `vsubx.TYPE`  | R3      | vD[j] = A[j] - xS        | Scalar 值逐元素减法; `i32/u32/f32`.  |
  | `vmul.TYPE`   | R3      | vD[j] = A[j] × B[j]      | 同域逐元素乘法; `i32/u32/f32`.       |
  | `vmulx.TYPE`  | R3      | vD[j] = A[j] × xS        | Scalar 值逐元素乘法; `i32/u32/f32`.  |
  | `vdiv.TYPE`   | R3      | vD[j] = A[j] / B[j]      | 同域逐元素除法; `f32`.               |
  | `vdivx.TYPE`  | R3      | vD[j] = A[j] / xS        | Scalar 值逐元素除法; `f32`.          |
  | `vmin.TYPE`   | R3      | vD[j] = min(A[j], B[j])  | 同域逐元素取小; `i32/u32/f32`.       |
  | `vminx.TYPE`  | R3      | vD[j] = min(A[j], xS)    | Scalar 值逐元素取小; `i32/u32/f32`.  |
  | `vmax.TYPE`   | R3      | vD[j] = max(A[j], B[j])  | 同域逐元素取大; `i32/u32/f32`.       |
  | `vmaxx.TYPE`  | R3      | vD[j] = max(A[j], xS)    | Scalar 值逐元素取大; `i32/u32/f32`.  |
  | `vand`        | R3      | vD[j] = A[j] and B[j]    | 同域逐元素按位与.                    |
  | `vandx`       | R3      | vD[j] = A[j] and xS      | Scalar 值逐元素按位与.               |
  | `vor`         | R3      | vD[j] = A[j] or B[j]     | 同域逐元素按位或.                    |
  | `vorx`        | R3      | vD[j] = A[j] or xS       | Scalar 值逐元素按位或.               |
  | `vxor`        | R3      | vD[j] = A[j] xor B[j]    | 同域逐元素按位异或.                  |
  | `vxorx`       | R3      | vD[j] = A[j] xor xS      | Scalar 值逐元素按位异或.             |
  | `vshl.TYPE`   | R3      | vD[j] = shl(A[j], B[j])  | 同域逐元素左移; `i32/u32`.           |
  | `vshlx.TYPE`  | R3      | vD[j] = shl(A[j], xS)    | Scalar 值逐元素左移; `i32/u32`.      |
  | `vshr.TYPE`   | R3      | vD[j] = shr(A[j], B[j])  | 同域逐元素逻辑右移; `i32/u32`.       |
  | `vshrx.TYPE`  | R3      | vD[j] = shr(A[j], xS)    | Scalar 值逐元素逻辑右移; `i32/u32`.  |
  | `vsra.TYPE`   | R3      | vD[j] = sra(A[j], B[j])  | 同域逐元素算术右移; `i32/u32`.       |
  | `vsrax.TYPE`  | R3      | vD[j] = sra(A[j], xS)    | Scalar 值逐元素算术右移; `i32/u32`.  |
  | `vnot`        | R2      | vD[j] = not A[j]         | 逐元素按位取反.                      |
  | `vabs.TYPE`   | R2      | vD[j] = abs(A[j])        | 逐元素绝对值; `i32/f32`.             |
  | `vneg.TYPE`   | R2      | vD[j] = -A[j]            | 逐元素取负; `i32/f32`.               |
]

#instruction-listing(caption: [融合乘加指令清单])[
  | Instruction   | Format  | Function                               | Summary                         |
  | ------------- | ------- | -------------------------------------- | ------------------------------- |
  | `afmadd.f32`  | R4      | aD[i,j] = fma(A[i,j], B[i,j], C[i,j])  | Acc 融合乘加, 单次 f32 舍入.    |
  | `vfmadd.f32`  | R4      | vD[j] = fma(A[j], B[j], C[j])          | Vec32 融合乘加, 单次 f32 舍入.  |
]

#instruction-listing(caption: [近似特殊函数指令清单])[
  | Instruction      | Format  | Function                        | Summary                  |
  | ---------------- | ------- | ------------------------------- | ------------------------ |
  | `aexp2.approx`   | R2      | aD[i,j] = exp2_approx(A[i,j])   | 逐元素计算 2 的幂.       |
  | `arcp.approx`    | R2      | aD[i,j] = rcp_approx(A[i,j])    | 逐元素计算倒数.          |
  | `arsqrt.approx`  | R2      | aD[i,j] = rsqrt_approx(A[i,j])  | 逐元素计算倒数平方根.    |
  | `vexp2.approx`   | R2      | vD[j] = exp2_approx(A[j])       | 逐 lane 计算 2 的幂.     |
  | `vrcp.approx`    | R2      | vD[j] = rcp_approx(A[j])        | 逐 lane 计算倒数.        |
  | `vrsqrt.approx`  | R2      | vD[j] = rsqrt_approx(A[j])      | 逐 lane 计算倒数平方根.  |
]



#instruction-listing(caption: [矩阵源行广播指令清单])[
  | Instruction       | Format  | Function                          | Summary                                              |
  | ----------------- | ------- | --------------------------------- | ---------------------------------------------------- |
  | `tadd.brow.TYPE`  | RB      | tD[i,j] = tA[i,j] + tB[rb,j]      | 矩阵源行广播加法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsub.brow.TYPE`  | RB      | tD[i,j] = tA[i,j] - tB[rb,j]      | 矩阵源行广播减法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tmin.brow.TYPE`  | RB      | tD[i,j] = min(tA[i,j], tB[rb,j])  | 矩阵源行广播取小; `i8/u8`.                           |
  | `tmax.brow.TYPE`  | RB      | tD[i,j] = max(tA[i,j], tB[rb,j])  | 矩阵源行广播取大; `i8/u8`.                           |
  | `tand.brow`       | RB      | tD[i,j] = tA[i,j] and tB[rb,j]    | 矩阵源行广播按位与.                                  |
  | `tor.brow`        | RB      | tD[i,j] = tA[i,j] or tB[rb,j]     | 矩阵源行广播按位或.                                  |
  | `txor.brow`       | RB      | tD[i,j] = tA[i,j] xor tB[rb,j]    | 矩阵源行广播按位异或.                                |
  | `tshl.brow.TYPE`  | RB      | tD[i,j] = shl(tA[i,j], tB[rb,j])  | 矩阵源行广播左移; `i8/u8`.                           |
  | `tshr.brow.TYPE`  | RB      | tD[i,j] = shr(tA[i,j], tB[rb,j])  | 矩阵源行广播逻辑右移; `i8/u8`.                       |
  | `tsra.brow.TYPE`  | RB      | tD[i,j] = sra(tA[i,j], tB[rb,j])  | 矩阵源行广播算术右移; `i8/u8`.                       |
  | `aadd.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] + aB[rb,j]      | 矩阵源行广播加法; `i32/u32/f32`.                     |
  | `asub.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] - aB[rb,j]      | 矩阵源行广播减法; `i32/u32/f32`.                     |
  | `amul.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] × aB[rb,j]      | 矩阵源行广播乘法; `i32/u32/f32`.                     |
  | `adiv.brow.TYPE`  | RB      | aD[i,j] = aA[i,j] / aB[rb,j]      | 矩阵源行广播除法; `f32`.                             |
  | `amin.brow.TYPE`  | RB      | aD[i,j] = min(aA[i,j], aB[rb,j])  | 矩阵源行广播取小; `i32/u32/f32`.                     |
  | `amax.brow.TYPE`  | RB      | aD[i,j] = max(aA[i,j], aB[rb,j])  | 矩阵源行广播取大; `i32/u32/f32`.                     |
  | `aand.brow`       | RB      | aD[i,j] = aA[i,j] and aB[rb,j]    | 矩阵源行广播按位与.                                  |
  | `aor.brow`        | RB      | aD[i,j] = aA[i,j] or aB[rb,j]     | 矩阵源行广播按位或.                                  |
  | `axor.brow`       | RB      | aD[i,j] = aA[i,j] xor aB[rb,j]    | 矩阵源行广播按位异或.                                |
  | `ashl.brow.TYPE`  | RB      | aD[i,j] = shl(aA[i,j], aB[rb,j])  | 矩阵源行广播左移; `i32/u32`.                         |
  | `ashr.brow.TYPE`  | RB      | aD[i,j] = shr(aA[i,j], aB[rb,j])  | 矩阵源行广播逻辑右移; `i32/u32`.                     |
  | `asra.brow.TYPE`  | RB      | aD[i,j] = sra(aA[i,j], aB[rb,j])  | 矩阵源行广播算术右移; `i32/u32`.                     |
]

#instruction-listing(caption: [向量按行广播指令清单])[
  | Instruction         | Format  | Function                       | Summary                                              |
  | ------------------- | ------- | ------------------------------ | ---------------------------------------------------- |
  | `taddb.byrow.TYPE`  | R3      | tD[i,j] = tA[i,j] + bS[i]      | 向量按行广播加法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsubb.byrow.TYPE`  | R3      | tD[i,j] = tA[i,j] - bS[i]      | 向量按行广播减法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tminb.byrow.TYPE`  | R3      | tD[i,j] = min(tA[i,j], bS[i])  | 向量按行广播取小; `i8/u8`.                           |
  | `tmaxb.byrow.TYPE`  | R3      | tD[i,j] = max(tA[i,j], bS[i])  | 向量按行广播取大; `i8/u8`.                           |
  | `tandb.byrow`       | R3      | tD[i,j] = tA[i,j] and bS[i]    | 向量按行广播按位与.                                  |
  | `torb.byrow`        | R3      | tD[i,j] = tA[i,j] or bS[i]     | 向量按行广播按位或.                                  |
  | `txorb.byrow`       | R3      | tD[i,j] = tA[i,j] xor bS[i]    | 向量按行广播按位异或.                                |
  | `tshlb.byrow.TYPE`  | R3      | tD[i,j] = shl(tA[i,j], bS[i])  | 向量按行广播左移; `i8/u8`.                           |
  | `tshrb.byrow.TYPE`  | R3      | tD[i,j] = shr(tA[i,j], bS[i])  | 向量按行广播逻辑右移; `i8/u8`.                       |
  | `tsrab.byrow.TYPE`  | R3      | tD[i,j] = sra(tA[i,j], bS[i])  | 向量按行广播算术右移; `i8/u8`.                       |
  | `aaddv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] + vS[i]      | 向量按行广播加法; `i32/u32/f32`.                     |
  | `asubv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] - vS[i]      | 向量按行广播减法; `i32/u32/f32`.                     |
  | `amulv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] × vS[i]      | 向量按行广播乘法; `i32/u32/f32`.                     |
  | `adivv.byrow.TYPE`  | R3      | aD[i,j] = aA[i,j] / vS[i]      | 向量按行广播除法; `f32`.                             |
  | `aminv.byrow.TYPE`  | R3      | aD[i,j] = min(aA[i,j], vS[i])  | 向量按行广播取小; `i32/u32/f32`.                     |
  | `amaxv.byrow.TYPE`  | R3      | aD[i,j] = max(aA[i,j], vS[i])  | 向量按行广播取大; `i32/u32/f32`.                     |
  | `aandv.byrow`       | R3      | aD[i,j] = aA[i,j] and vS[i]    | 向量按行广播按位与.                                  |
  | `aorv.byrow`        | R3      | aD[i,j] = aA[i,j] or vS[i]     | 向量按行广播按位或.                                  |
  | `axorv.byrow`       | R3      | aD[i,j] = aA[i,j] xor vS[i]    | 向量按行广播按位异或.                                |
  | `ashlv.byrow.TYPE`  | R3      | aD[i,j] = shl(aA[i,j], vS[i])  | 向量按行广播左移; `i32/u32`.                         |
  | `ashrv.byrow.TYPE`  | R3      | aD[i,j] = shr(aA[i,j], vS[i])  | 向量按行广播逻辑右移; `i32/u32`.                     |
  | `asrav.byrow.TYPE`  | R3      | aD[i,j] = sra(aA[i,j], vS[i])  | 向量按行广播算术右移; `i32/u32`.                     |
]

#instruction-listing(caption: [向量按列广播指令清单])[
  | Instruction         | Format  | Function                       | Summary                                              |
  | ------------------- | ------- | ------------------------------ | ---------------------------------------------------- |
  | `taddb.bycol.TYPE`  | R3      | tD[i,j] = tA[i,j] + bS[j]      | 向量按列广播加法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tsubb.bycol.TYPE`  | R3      | tD[i,j] = tA[i,j] - bS[j]      | 向量按列广播减法; 溢出模式由配置 `arith_mode` 决定.  |
  | `tminb.bycol.TYPE`  | R3      | tD[i,j] = min(tA[i,j], bS[j])  | 向量按列广播取小; `i8/u8`.                           |
  | `tmaxb.bycol.TYPE`  | R3      | tD[i,j] = max(tA[i,j], bS[j])  | 向量按列广播取大; `i8/u8`.                           |
  | `tandb.bycol`       | R3      | tD[i,j] = tA[i,j] and bS[j]    | 向量按列广播按位与.                                  |
  | `torb.bycol`        | R3      | tD[i,j] = tA[i,j] or bS[j]     | 向量按列广播按位或.                                  |
  | `txorb.bycol`       | R3      | tD[i,j] = tA[i,j] xor bS[j]    | 向量按列广播按位异或.                                |
  | `tshlb.bycol.TYPE`  | R3      | tD[i,j] = shl(tA[i,j], bS[j])  | 向量按列广播左移; `i8/u8`.                           |
  | `tshrb.bycol.TYPE`  | R3      | tD[i,j] = shr(tA[i,j], bS[j])  | 向量按列广播逻辑右移; `i8/u8`.                       |
  | `tsrab.bycol.TYPE`  | R3      | tD[i,j] = sra(tA[i,j], bS[j])  | 向量按列广播算术右移; `i8/u8`.                       |
  | `aaddv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] + vS[j]      | 向量按列广播加法; `i32/u32/f32`.                     |
  | `asubv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] - vS[j]      | 向量按列广播减法; `i32/u32/f32`.                     |
  | `amulv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] × vS[j]      | 向量按列广播乘法; `i32/u32/f32`.                     |
  | `adivv.bycol.TYPE`  | R3      | aD[i,j] = aA[i,j] / vS[j]      | 向量按列广播除法; `f32`.                             |
  | `aminv.bycol.TYPE`  | R3      | aD[i,j] = min(aA[i,j], vS[j])  | 向量按列广播取小; `i32/u32/f32`.                     |
  | `amaxv.bycol.TYPE`  | R3      | aD[i,j] = max(aA[i,j], vS[j])  | 向量按列广播取大; `i32/u32/f32`.                     |
  | `aandv.bycol`       | R3      | aD[i,j] = aA[i,j] and vS[j]    | 向量按列广播按位与.                                  |
  | `aorv.bycol`        | R3      | aD[i,j] = aA[i,j] or vS[j]     | 向量按列广播按位或.                                  |
  | `axorv.bycol`       | R3      | aD[i,j] = aA[i,j] xor vS[j]    | 向量按列广播按位异或.                                |
  | `ashlv.bycol.TYPE`  | R3      | aD[i,j] = shl(aA[i,j], vS[j])  | 向量按列广播左移; `i32/u32`.                         |
  | `ashrv.bycol.TYPE`  | R3      | aD[i,j] = shr(aA[i,j], vS[j])  | 向量按列广播逻辑右移; `i32/u32`.                     |
  | `asrav.bycol.TYPE`  | R3      | aD[i,j] = sra(aA[i,j], vS[j])  | 向量按列广播算术右移; `i32/u32`.                     |
]

#instruction-listing(caption: [比较指令清单])[
  | Instruction        | Format  | Function                             | Summary                            |
  | ------------------ | ------- | ------------------------------------ | ---------------------------------- |
  | `acmp.eq.TYPE`     | R4      | aD[i,j] = A[i,j] == B[i,j]           | 同域右源相等比较; `i32/u32/f32`.   |
  | `acmp.ne.TYPE`     | R4      | aD[i,j] = A[i,j] != B[i,j]           | 同域右源不等比较; `i32/u32`.       |
  | `acmp.lt.TYPE`     | R4      | aD[i,j] = A[i,j] < B[i,j]            | 同域右源小于比较; `i32/u32/f32`.   |
  | `acmp.ge.TYPE`     | R4      | aD[i,j] = A[i,j] >= B[i,j]           | 同域右源大于等于比较; `i32/u32`.   |
  | `acmp.le.f32`      | R4      | aD[i,j] = A[i,j] <= B[i,j]           | 同域右源小于等于比较; `f32`.       |
  | `acmp.unord.f32`   | R4      | aD[i,j] = unordered(A[i,j], B[i,j])  | 同域右源浮点无序比较.              |
  | `acmpx.eq.TYPE`    | R4      | aD[i,j] = A[i,j] == xS               | Scalar 值相等比较; `i32/u32/f32`.  |
  | `acmpx.ne.TYPE`    | R4      | aD[i,j] = A[i,j] != xS               | Scalar 值不等比较; `i32/u32`.      |
  | `acmpx.lt.TYPE`    | R4      | aD[i,j] = A[i,j] < xS                | Scalar 值小于比较; `i32/u32/f32`.  |
  | `acmpx.ge.TYPE`    | R4      | aD[i,j] = A[i,j] >= xS               | Scalar 值大于等于比较; `i32/u32`.  |
  | `acmpx.le.f32`     | R4      | aD[i,j] = A[i,j] <= xS               | Scalar 值小于等于比较; `f32`.      |
  | `acmpx.unord.f32`  | R4      | aD[i,j] = unordered(A[i,j], xS)      | Scalar 值浮点无序比较.             |
  | `vcmp.eq.TYPE`     | R4      | vD[j] = A[j] == B[j]                 | 同域右源相等比较; `i32/u32/f32`.   |
  | `vcmp.ne.TYPE`     | R4      | vD[j] = A[j] != B[j]                 | 同域右源不等比较; `i32/u32`.       |
  | `vcmp.lt.TYPE`     | R4      | vD[j] = A[j] < B[j]                  | 同域右源小于比较; `i32/u32/f32`.   |
  | `vcmp.ge.TYPE`     | R4      | vD[j] = A[j] >= B[j]                 | 同域右源大于等于比较; `i32/u32`.   |
  | `vcmp.le.f32`      | R4      | vD[j] = A[j] <= B[j]                 | 同域右源小于等于比较; `f32`.       |
  | `vcmp.unord.f32`   | R4      | vD[j] = unordered(A[j], B[j])        | 同域右源浮点无序比较.              |
  | `vcmpx.eq.TYPE`    | R4      | vD[j] = A[j] == xS                   | Scalar 值相等比较; `i32/u32/f32`.  |
  | `vcmpx.ne.TYPE`    | R4      | vD[j] = A[j] != xS                   | Scalar 值不等比较; `i32/u32`.      |
  | `vcmpx.lt.TYPE`    | R4      | vD[j] = A[j] < xS                    | Scalar 值小于比较; `i32/u32/f32`.  |
  | `vcmpx.ge.TYPE`    | R4      | vD[j] = A[j] >= xS                   | Scalar 值大于等于比较; `i32/u32`.  |
  | `vcmpx.le.f32`     | R4      | vD[j] = A[j] <= xS                   | Scalar 值小于等于比较; `f32`.      |
  | `vcmpx.unord.f32`  | R4      | vD[j] = unordered(A[j], xS)          | Scalar 值浮点无序比较.             |
]

#instruction-listing(caption: [选择指令清单])[
  | Instruction  | Format  | Function                            | Summary                         |
  | ------------ | ------- | ----------------------------------- | ------------------------------- |
  | `tselect`    | R4      | tD[i,j] = M[i,j] ? A[i,j] : B[i,j]  | mask 非零时选择 A, 否则选择 B.  |
  | `aselect`    | R4      | aD[i,j] = M[i,j] ? A[i,j] : B[i,j]  | mask 非零时选择 A, 否则选择 B.  |
  | `vselect`    | R4      | vD[j] = M[j] ? A[j] : B[j]          | mask 非零时选择 A, 否则选择 B.  |
]

#instruction-listing(caption: [Mask 指令清单])[
  | Instruction    | Format  | Function                                             | Summary                                                   |
  | -------------- | ------- | ---------------------------------------------------- | --------------------------------------------------------- |
  | `tmask.tail`   | R4      | tD[i,j] = (i < nRows and j < nCols) ? S[i,j] : fill  | 保留行列坐标小于 `xBounds` 中 `nRows`, `nCols` 的源元素.  |
  | `tmask.tril`   | R4      | tD[i,j] = (j - i <= xDelta) ? S[i,j] : fill          | 保留满足 $j-i <= "xDelta"$ 的源元素.                      |
  | `tmask.triu`   | R4      | tD[i,j] = (j - i >= xDelta) ? S[i,j] : fill          | 保留满足 $j-i >= "xDelta"$ 的源元素.                      |
  | `amask.tail`   | R4      | aD[i,j] = (i < nRows and j < nCols) ? S[i,j] : fill  | 保留行列坐标小于 `xBounds` 中 `nRows`, `nCols` 的源元素.  |
  | `amask.tril`   | R4      | aD[i,j] = (j - i <= xDelta) ? S[i,j] : fill          | 保留满足 $j-i <= "xDelta"$ 的源元素.                      |
  | `amask.triu`   | R4      | aD[i,j] = (j - i >= xDelta) ? S[i,j] : fill          | 保留满足 $j-i >= "xDelta"$ 的源元素.                      |
  | `bmask.tail`   | R4      | bD[j] = (j < xLen) ? S[j] : fill                     | 保留 lane 索引小于 xLen 的源元素.                         |
  | `vmask.tail`   | R4      | vD[j] = (j < xLen) ? S[j] : fill                     | 保留 lane 索引小于 xLen 的源元素.                         |
  | `tmaskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                  | 同 `tmask.tail`, fill 由 Scalar 提供.                     |
  | `tmaskx.tril`  | R4      | 同 `mask.tril`, fill 由 Scalar 提供                  | 同 `tmask.tril`, fill 由 Scalar 提供.                     |
  | `tmaskx.triu`  | R4      | 同 `mask.triu`, fill 由 Scalar 提供                  | 同 `tmask.triu`, fill 由 Scalar 提供.                     |
  | `amaskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                  | 同 `amask.tail`, fill 由 Scalar 提供.                     |
  | `amaskx.tril`  | R4      | 同 `mask.tril`, fill 由 Scalar 提供                  | 同 `amask.tril`, fill 由 Scalar 提供.                     |
  | `amaskx.triu`  | R4      | 同 `mask.triu`, fill 由 Scalar 提供                  | 同 `amask.triu`, fill 由 Scalar 提供.                     |
  | `bmaskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                  | 同 `bmask.tail`, fill 由 Scalar 提供.                     |
  | `vmaskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                  | 同 `vmask.tail`, fill 由 Scalar 提供.                     |
]

== 规约与类型转换

详细语义见 @reduction-conversion.

#instruction-listing(caption: [规约指令清单])[
  | Instruction               | Format  | Function                                                                      | Summary                                         |
  | ------------------------- | ------- | ----------------------------------------------------------------------------- | ----------------------------------------------- |
  | `areduce.rows.sum.f32`    | R2      | $"vD"[i] = sum_j "aS"[i,j]$                                                   | 将 Acc 按行求和到 Vec32.                        |
  | `areduce.rows.max.f32`    | R2      | $"vD"[i] = max_j "aS"[i,j]$                                                   | 将 Acc 按行取最大到 Vec32.                      |
  | `areduce.rows.min.f32`    | R2      | $"vD"[i] = min_j "aS"[i,j]$                                                   | 将 Acc 按行取最小到 Vec32.                      |
  | `areduce.rows.sumsq.f32`  | R2      | $"vD"[i] = sum_j "aS"[i,j]^2$                                                 | 将 Acc 每行有效元素的平方和写入 Vec32.          |
  | `vreduce.sum.f32`         | R2      | $"xD" = sum_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 求和到 Scalar.         |
  | `vreduce.max.f32`         | R2      | $"xD" = max_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 取最大到 Scalar.       |
  | `vreduce.min.f32`         | R2      | $"xD" = min_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 取最小到 Scalar.       |
  | `vreduce.sumsq.f32`       | R2      | $"xD" = sum_j "vS"[j]^2$                                                      | 将 f32 Vec32 的有效 lane 平方和到 Scalar.       |
  | `vreduce.argmax.f32`      | R4      | $"xIndex" = op("argmax")_j "vS"[j]$ #linebreak() $"xValue" = "vS"["xIndex"]$  | 输出最大值的逻辑索引与浮点位模式到两个 Scalar.  |
]

#instruction-listing(caption: [类型转换与扩大指令清单])[
  | Instruction      | Format  | Function                     | Summary                                   |
  | ---------------- | ------- | ---------------------------- | ----------------------------------------- |
  | `acvt.i32.f32`   | R2      | aD[i,j] = f32(aS[i,j])       | 将 Acc 中的 `i32` 逐元素转为 `f32`.       |
  | `vcvt.i32.f32`   | R2      | vD[j] = f32(vS[j])           | 将 Vec32 中的 `i32` 逐 lane 转为 `f32`.   |
  | `twiden.i8.i32`  | R2      | aD[i,j] = sign_ext(tS[i,j])  | 将 Tile 的 `i8` 符号扩展到 Acc 的 `i32`.  |
]

== 量化与反量化

详细语义见 @quantization.

#instruction-listing(caption: [量化与反量化指令清单])[
  | Instruction          | Format  | Function                                                                                 | Summary                                            |
  | -------------------- | ------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
  | `tquant.rows.q8s32`  | R4      | tD[i,:] = quant_q8s32(aS[i,:]).bits #linebreak() vScale[i] = quant_q8s32(aS[i,:]).scale  | 将 Acc 按行量化到 Tile, 每行产生一个 Vec32 scale.  |
  | `vquant.q8s32`       | R4      | bD = quant_q8s32(vS).bits #linebreak() vScale[lane] = quant_q8s32(vS).scale              | 将 Vec32 量化到 Vec8, 产生一个指定 lane 的 scale.  |
  | `tdequant.rows.f32`  | R4      | aD[i,j] = f32(tS[i,j]) × vScale[i]                                                       | 用每行的 Vec32 scale 将 Tile 反量化到 f32 Acc.     |
  | `bdequant.f32`       | R4      | vD[j] = f32(bS[j]) × vScale[lane]                                                        | 用指定 scale lane 将 Vec8 反量化到 f32 Vec32.      |
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
  | `b` / `v`           | Vec8 / Vec32 向量数据域     | `bload` / `vload` 使用 `VM`; `bdequant` / `vquant` 在 Vec8 与 Vec32 之间转换.   |
  | `cfg`               | `TC/AC/BC/VC/TM/VM`         | `cfg.seti` 写立即数字段; `cfg.setx` 从 Scalar 写字段.                           |
  | `mma`               | Tile × Tile → Acc           | `mma.nt.acc.i8.i32` 以 `i8` 输入执行逻辑转置矩阵乘, 并累加到 `i32` Acc.         |
  | `bdot`              | Vec8 × Tile → Vec32         | `bdot.nn.i8.i32` 产生 `i32` 向量; 跨块累加使用 `vadd.i32`.                      |
  | 跨域转换            | 指令显式规定输入与输出域    | `twiden`: Tile → Acc; `tquant`: Acc → Tile; `vquant`: Vec32 → Vec8.             |
  | `fence` / `kernel`  | 后端完成与 kernel 生命周期  | `fence.mem` / `fence.sa` / `fence.all` 建立完成边界; `kernel.end` 结束 kernel.  |
]

前缀表示指令所属的数据域或功能族, 跨域指令须结合操作数阅读. 例如 `treduce` 的目的为 Vec32, `vreduce` 的目的为 Scalar, 不能仅根据前缀推断目的寄存器.
