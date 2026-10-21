#import "style.typ": *
#import "rivet/rivet.typ": *

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

本手册定义 Tile NPU 的物理指令集 (Tile-oriented ISA).

手册按功能组织: @overview 描述架构状态并给出指令分类; @scalar-sync 至 @quantization 按指令族定义语义; @instructions 汇总全部已命名指令.

记法约定:
+ 指令助记符, 寄存器名与字段名使用等宽字体 (如 `vadd`, `a0`, `rows`)
+ 花括号表示该位置可取的一组文本, 并展开为所有对应的助记符. 例如 `{t,a}insert.row` 表示 `tinsert.row` 和 `ainsert.row`; `{t,a}{load,store}` 表示 `tload`, `tstore`, `aload` 和 `astore`.
+ 指令表的 Operation 列用赋值式描述每条指令的效果. 式子里的下标默认取遍目的寄存器的整个有效区域, 如 `D[i,j] = A[i,j] + B[i,j]` 表示对所有 `i`, `j` 逐元素相加. 矩阵使用 `[i,j]`, 向量使用 `[j]`; 同一表达式兼写矩阵与向量形式时使用 `[p]`. `D` 为目的操作数, `A`, `B`, `S` 为源操作数. 例如 `{t,a}insert.row` 的 `D[rd,j] = S[j]` 实际对应两条指令: `tD[rd,j] = bS[j]` 和 `aD[rd,j] = vS[j]`.

指令表与伪代码中的通用操作数记号:

#manual-table(
  columns: (1.2fr, 5fr),
  caption: [通用操作数记号],
)[
  | 记号                         | 含义                                                                                    |
  | ---------------------------- | --------------------------------------------------------------------------------------- |
  | `D`                          | 目的寄存器, 对应汇编操作数 `tD`, `aD`, `bD`, `vD`                                       |
  | `A`, `B`                     | 第一, 第二源寄存器, 对应 `tA`, `tB`                                                     |
  | `S`                          | 单源或广播向量源                                                                        |
  | `M`                          | mask 操作数：以 mask 方式使用的数据寄存器                                               |
  | `C`                          | 配置寄存器 (计算配置或访存描述符); `C[field]` 表示其字段                                |
  | `imm`                        | 立即数                                                                                  |
  | `xS`                         | Scalar 源操作数 (寄存器编号); 其值记为 `x[xS]`                                          |
  | `x[r]`                       | Scalar 寄存器 `r` 的值                                                                  |
  | `xBounds`, `xLen`, `xDelta`  | mask 边界操作数 (Scalar): 打包行列数 / 长度 / 有符号偏移, 见 @elementwise 的 mask 小节  |
  | `[i,j]`                      | 矩阵元素索引                                                                            |
  | `[j]`                        | 向量 lane 索引                                                                          |
  | `[p]`                        | position, 矩阵与向量共用表达式的元素坐标: 矩阵为 `[i,j]`, 向量为 `[j]`                  |
  | `[rd,j]`, `[rs,j]`           | 行操作选中的目的 / 源行号                                                               |
]

Operation 列使用的函数记号:

#manual-table(
  columns: (1.6fr, 5fr),
  caption: [Operation 函数记号],
)[
  | 记号                       | 含义                                                          |
  | -------------------------- | ------------------------------------------------------------- |
  | `min(A, B)`, `max(A, B)`   | 逐元素取小/取大; 浮点按 IEEE 754 minNum/maxNum 语义           |
  | `shl(A, B)`, `shr(A, B)`   | 逻辑左/右移; 移位量取 $B$ 的低 $log_2 w$ 位 ($w$ 为元素位宽)  |
  | `sra(A, B)`                | 算术右移 (符号填充); 移位量同上                               |
  | `abs(A)`                   | 逐元素绝对值                                                  |
  | `not`,`and`, `or`, `xor`   | 逐元素按位取反/与/或/异或                                     |
  | `quant_q8s32(...)` 等      | 量化与反量化函数, 定义见 @quantization                        |
  | `fma(A, B, C)`             | 融合乘加 $A × B + C$, 单次舍入; 仅 f32                        |
  | $sum_j$, $min_j$, $max_j$  | 对下标 $j$ 归约: 求和/取小/取大                               |
  | $"sumsq"_j$                | 对下标 $j$ 求平方和                                           |
  | $max_j abs(...)$           | 对下标 $j$ 取绝对值最大                                       |
  | $op("argmax")_j$           | 对下标 $j$ 取最大值索引                                       |
  | `unordered(A, B)`          | IEEE unordered 比较: 任一操作数为 NaN 时为真                  |
  | `f32(A)`                   | 转换为 f32                                                    |
  | `sign_ext(A)`              | 符号扩展                                                      |
  | `extend(v, w)`             | 整数值扩展到位宽 `w`; 省略 `w` 时按目标字段位宽               |
  | `exp2_approx(A)`           | f32 近似 $2^x$; 规则见 "近似特殊函数" 小节                    |
  | `rcp_approx(A)`            | f32 近似 $1 / x$; 同上                                        |
  | `rsqrt_approx(A)`          | f32 近似 $1 / sqrt(x)$; 同上                                  |
  | `decode_scalar(xS)`        | 将 Scalar 寄存器 `xS` 的值截取元素位宽, 按目的 dtype 解释     |
  | `tree_reduce(...)`         | 相邻两两归约树, 定义见 @reduce-areduce                        |
  | `add_f32_rne(a, b)`        | f32 加法, 单次 RNE 舍入, 定义见 @reduce-areduce               |
  | `pair_max`/`pair_min`      | 规约取大/取小, 定义见 @reduce-areduce                         |
  | `absmax_leaf(x)`           | NaN 视为 +0, 否则取绝对值, 定义见 @reduce-areduce             |
]

= 指令集概览 <overview>

== 架构状态

=== 数据寄存器

#manual-table(
  columns: (1fr, 1fr, 1.3fr, 2fr, 2fr),
  caption: [数据寄存器与数据域],
)[
  | 寄存器类型  | 汇编名称   | 单寄存器容量                                       | 基础数据解释                         | 主要用途                                |
  | :---------: | :--------: | -------------------------------------------------- | ------------------------------------ | --------------------------------------- |
  | Tile        | `t0..t15`  | $32 times 32 times 8$ bit #linebreak() $= 1$ KiB   | `i8`, `u8`                           | 矩阵输入, 低精度中间结果                |
  | Acc         | `a0..a11`  | $32 times 32 times 32$ bit #linebreak() $= 4$ KiB  | `i32`, `u32`, `f32`                  | 矩阵宽累加结果, Attention score/output  |
  | Vec8        | `b0..b31`  | $32 times 8$ bit #linebreak() $= 32$ B             | `i8`, `u8`                           | 低精度向量, decode 阶段单 batch query   |
  | Vec32       | `v0..v31`  | $32 times 32$ bit #linebreak() $= 128$ B           | `i32`, `u32`, `f32`                  | 行状态, 规约结果, 向量计算输入输出      |
  | Scalar      | `x0..x31`  | $64$ bit $= 8$ B                                   | `i64`, `u64`; f32 位模式取低 32 bit  | 地址, 循环, 索引和控制值                |
]

以上构成五个不同的*数据域*. 标量域的指令集为 RV64IM (见 @scalar-sync); 其余数据域的指令由本手册定义.

矩阵寄存器的物理尺寸为 32 行 $times$ 32 列, 向量寄存器为 32 lane; 配置寄存器中的 `rows`, `cols`, `len` 的合法取值为 $[1, 32]$.

#note[
  配置寄存器复位后全 0 表示未配置。通过 `cfg.seti`/`cfg.setx` 写入 $0$ 时，校验失败并产生 `CFG_ERROR`；若指令使用了全 0 配置（即复位后未配置），则按非法配置处理。
]

=== 配置寄存器

配置寄存器分为计算配置寄存器和访存描述符.

#manual-table(
  columns: (1fr, 0.6fr, 1fr, 0.4fr, 2fr),
  caption: [计算配置寄存器],
)[
  | 寄存器类型          | 汇编名称     | 绑定或适用对象    | 容量   | 配置字段                                         |
  | :-----------------: | :----------: | :---------------: | ------ | ------------------------------------------------ |
  | TC: Tile 计算配置   | `tc0..tc15`  | `tc[i]` ↔ `t[i]`  | 32bit  | `dtype`, `rows`, `cols`, `layout`, `arith_mode`  |
  | AC: Acc 计算配置    | `ac0..ac11`  | `ac[i]` ↔ `a[i]`  | 32bit  | `dtype`, `rows`, `cols`, `layout`                |
  | BC: Vec8 计算配置   | `bc0..bc31`  | `bc[i]` ↔ `b[i]`  | 32bit  | `dtype`, `len`                                   |
  | VC: Vec32 计算配置  | `vc0..vc31`  | `vc[i]` ↔ `v[i]`  | 32bit  | `dtype`, `len`                                   |
]

计算配置寄存器属于*寄存器侧*配置, 主要配置数据寄存器的逻辑形状、元素类型、内部布局和相关运算行为:
- `dtype`：数据寄存器中元素的逻辑数据类型. `TC/BC` 支持 `i8/u8`, `AC/VC` 支持 `i32/u32/f32`; 具体合法组合由对应指令规定.
- `rows`、`cols`：矩阵寄存器的有效逻辑行数和列数, 适用于 `TC` 和 `AC`.
- `len`：向量寄存器的有效 lane 数, 适用于 `BC` 和 `VC`. 它决定向量指令实际处理的有效元素范围.
- `layout`：矩阵寄存器内部的逻辑布局, 适用于 `TC` 和 `AC`. 具体布局编码及其适用指令由对应章节规定.
- `arith_mode`：Tile 8-bit 整数 `add` 和 `sub` 的溢出模式, 适用于 `TC`; `wrap` 表示回绕, `sat` 表示饱和.

#figure(
  manual-table(
    columns: (1fr, 0.6fr, 1fr, 0.4fr, 2fr),
    caption: [访存描述符],
  )[
    | 寄存器类型            | 汇编名称     | 绑定或适用对象    | 容量    | 配置字段                                                                   |
    | :-------------------: | :----------: | :---------------: | ------- | -------------------------------------------------------------------------- |
    | TM: Tile 访存描述符   | `tm0..tm15`  | `tm[i]` ↔ `t[i]`  | 192bit  | `base_addr`, `row_stride_bytes`, `col_stride_bytes`, `transform`, `flags`  |
    | AM: Acc 访存描述符    | `am0..am11`  | `am[i]` ↔ `a[i]`  | 192bit  | `base_addr`, `row_stride_bytes`, `col_stride_bytes`, `transform`, `flags`  |
    | BM: Vec8 访存描述符   | `bm0..bm31`  | `bm[i]` ↔ `b[i]`  | 128bit  | `base_addr`, `stride_bytes`, `flags`                                       |
    | VM: Vec32 访存描述符  | `vm0..vm31`  | `vm[i]` ↔ `v[i]`  | 128bit  | `base_addr`, `stride_bytes`, `flags`                                       |
  ],
)<mem-desc>

访存描述符属于*内存侧*配置. 矩阵访存使用 `TM`/`AM` 描述符, 向量访存使用 `BM`/`VM` 描述符.

访存的有效范围由绑定的计算配置寄存器决定: `TM`/`AM` 的有效行, 列数取自 `TC`/`AC` 的 `rows`/`cols`, `BM`/`VM` 的有效长度取自 `BC`/`VC` 的 `len`. 内存中的元素类型同样按绑定配置寄存器的 `dtype` 解释. 基地址由描述符的 `base_addr` 字段给出.

`BM`/`VM` 主要提供：
- `base_addr`：一维内存 view 原点的字节地址, 即逻辑元素 0 的地址.
- `stride_bytes`：相邻逻辑元素之间的字节步长, 该步长可以描述连续或带间隔的一维内存布局.
- `flags`：位标志. 位 `[0]` 为 `inc`: 置位时访存完成后 `base_addr` 增加 `len` × `stride_bytes`, 其余位保留; 自增语义见 @memory.

对一维 BM/VM, 内存元素地址定义为:

$ op("addr")(j) = "base_addr" + j dot "stride_bytes" $

`TM`/`AM` 主要提供：
- `base_addr`：二维内存 view 原点的字节地址, 即逻辑坐标 $[0, 0]$ 处元素的地址；
- `row_stride_bytes`：沿内存行方向移动一个元素行的字节步长；
- `col_stride_bytes`：沿内存列方向移动一个元素列的字节步长；
- `transform`：是否使用转置等访存变换。
- `flags`：位标志. 位 `[1:0]` 为 `inc_mode`: `00` 不递增, `01` 访存完成后 `base_addr` 沿行方向递增, `10` 沿列方向递增, `11` 保留; 其余位保留. 递增量与自增语义见 @memory.

对二维 TM/AM, 内存元素地址定义为:

$
  op("addr")(i,j) = "base_addr" + i dot "row_stride_bytes" + j dot "col_stride_bytes"
$

其中 $i$, $j$ 为当前 Tile 或 Acc 内的局部坐标.

计算配置寄存器 TC/AC 与 BC/VC 均为 32-bit; 矩阵访存描述符 TM/AM 为 192-bit (三个 64-bit word), 向量访存描述符 BM/VM 为 128-bit (两个 64-bit word). 位段分配如下.

#rivet-c-figure(tc-schema, caption: [TC 计算配置寄存器位段])

#rivet-c-figure(ac-schema, caption: [AC 计算配置寄存器位段])

#rivet-c-figure(bc-schema, caption: [BC/VC 计算配置寄存器位段])

#rivet-tm-figure(
  (tm-0-schema, tm-1-schema, tm-2-schema),
  caption: [TM/AM 矩阵访存描述符位段],
)

#rivet-vm-figure(vm-schema, caption: [BM/VM 向量访存描述符位段])

== 编程模型 <model>

待写

== 指令分类 <classification>

ISA 按五个数据域及其数据流划分功能. 下表列出正文定义的主要指令族.

#manual-table(
  columns: (1.4fr, 1.5fr, 2fr, 3fr),
  caption: [功能族总览],
)[
  | 功能族          | 主要数据流                                                                     | 架构职责                                           | 助记符入口                                                                                                                                      |
  | --------------- | ------------------------------------------------------------------------------ | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
  | 标量与控制      | Scalar ↔ Scalar #linebreak() Scalar ↔ 内存                                     | 地址, 索引, 标量计算, 控制流                       | RV64IM (见 RISC-V 规范)                                                                                                                         |
  | 配置            | Scalar → TC, AC, BC, VC, TM, AM, BM, VM                                        | 建立数据域的类型, shape, 布局和访存描述            | `cfg.seti`, `cfg.setx`, `cfg.copy`, `cfg.get` #linebreak() `cfg.setw`, `cfg.getw`                                                               |
  | 地址与访存      | 内存 ↔ `t/a/b/v`                                                               | 按绑定的 TM/AM/BM/VM 描述符执行整块, 行和向量访问  | `{t,a}{load,store}` #linebreak() `{t,a}{load,store}.row` #linebreak() `{b,v}{load,store}` #linebreak() `{t,b,v}load.gather`                     |
  | 初始化与搬运    | 域内 #linebreak() `t` ↔ `b` #linebreak() `a` ↔ `v` #linebreak() Scalar ↔ lane  | 填充, 复制, 行搬运, lane 搬运, 广播和转置          | `{t,a,b,v}{fill,fillx,copy}` #linebreak() `{t,a}{insert,extract}.row` #linebreak() `{b,v}{insert,extract,broadcast}` #linebreak() `ttranspose`  |
  | 矩阵乘与点积    | `t` × `t` → `a` #linebreak() `b` × `t` → `v`                                   | `i8` 乘法, `i32` 累加或点积                        | `mma` #linebreak() `bdot`                                                                                                                       |
  | 逐元素与广播    | `t/a/v` 同域 #linebreak() 矩阵 ↔ 向量广播                                      | 算术, 位运算, 移位, 特殊函数, 比较和选择           | `{t,a,v}op` #linebreak() `.byrow`, `.bycol` #linebreak() `cmp`, `select`, `mask`                                                                |
  | 规约            | `a` → `v` #linebreak() `v` → Scalar                                            | 行规约, 向量规约, 平方和和 argmax                  | `areduce` #linebreak() `vreduce`                                                                                                                |
  | 类型转换与扩大  | `a/v` 内部 #linebreak() `t` → `a`                                              | 数值类型转换和 `i8` → `i32` 扩大                   | `acvt`, `vcvt` #linebreak() `twiden`                                                                                                            |
  | 量化与反量化    | `a` ↔ `t` #linebreak() `v` ↔ `b`                                               | 低精度存储与 `f32` 计算之间的显式转换              | `tquant`, `tdequant` #linebreak() `vquant`, `bdequant`                                                                                          |
  | 同步与结束      | 后端 → 完成边界 #linebreak() kernel → 完成                                     | 访存, 脉动阵列, 全后端完成以及 kernel 生命周期     | `fence.mem`, `fence.sa`, `fence.all` #linebreak() `kernel.end`                                                                                  |
]

== 指令空间组织 <instruction-space>

所有指令 (标量与非标量) 均为定长 32-bit. 指令空间按指令字最低两位划分:

`[1:0] = 11` 的空间用于标量指令: 标量指令集采用 RV64IM (RISC-V 64-bit 基础整数指令集与乘除扩展).`[1:0]` 为 `00`, `01`, `10` 的原压缩指令空间全部用于非标量指令, `00` 的逐元素计算走向量计算通路, `01` 走访存与搬运通路, `10` 汇集跨域计算 (矩阵乘, 规约, 量化) 与控制类指令. 最低两位记为 `q` (沿用 RISC-V 的 quadrant 缩写). 如下表所示

#manual-table(
  columns: (0.5fr, 1fr, 3fr),
  caption: [非标量指令空间分配],
)[
  | `[1:0]`  | 功能域          | 内容                                                                                         |
  | :------: | --------------- | -------------------------------------------------------------------------------------------- |
  | `00`     | 通用逐元素计算  | 算术, 位运算, 比较, Scalar 变体 (`opx`, `cmpx`), 向量广播, 融合乘加, select, mask, 特殊函数  |
  | `01`     | 数据传输与重排  | 矩阵/向量访存, fill, copy, 行和 lane 搬运, 转置                                              |
  | `10`     | 跨域计算与控制  | 矩阵乘与点积, 规约, 类型转换与扩大, 量化与反量化, 配置, 同步, `kernel.end`; 其余编码预留     |
]

#note[
  预留策略: `10` 空间除配置与系统指令外的空间作为预留. 未来的扩展 (新的数据类型, 更宽的 Tile, 多核同步, DMA 等) 优先使用预留空间.
]

#note[
  #link("https://opensecura.googlesource.com/hw/kelvin/")也使用了类似的策略: 复用RV64im, 压缩指令的空间用于custom的向量指令.
]

== 指令格式 <encoding>

标量指令格式见 RISC-V 规范; 本章定义非标量指令格式.

所有非标量指令定长 32-bit. 指令字最低两位 `[1:0]` 为类别标签 (见 @instruction-space); `[31:28]` 为主操作码 `major4`, 中间的选择子与操作数字段按 `major4` 解释.

=== 格式分类

所有格式均以 `major4[31:28]` 开头, 以 `q[1:0]` 结尾. 下表仅列出中间字段 `[27:2]` 及其主要用途; 各指令族的完整分配见后文的 `major4` 分配表.

#manual-table(
  columns: (0.6fr, 3fr, 3.2fr),
  caption: [非标量指令格式],
)[
  | 格式  | 中间字段 `[27:2]`                                        | 主要用途                                    |
  | :---: | -------------------------------------------------------- | ------------------------------------------- |
  | R4    | `sel3 + funct3 + 4 × field5`                             | 多源或跨域计算; 配置访问                    |
  | R3    | `sel3 + funct4 + reserved4 + 3 × field5`                 | 二元逐元素计算; 矩阵与向量广播              |
  | R2    | `sel3 + funct3 + reserved10 + S5 + D5`                   | 访存; 单源单目的搬运; 规约、转换与一元计算  |
  | MR    | `sel3 + funct3 + reserved5 + index5 + reserved5 + reg5`  | 矩阵行访存 (`M_BLK` 的 row 形式)            |
  | I     | `sel2 + funct3 + imm16 + D5/C5`                          | 立即数填充与配置                            |
  | Z     | `funct3 + reserved23`                                    | 同步与 kernel 结束                          |
]

=== 位段布局

#rivet-format-figure(fmt-r4-schema, caption: [R4 格式: 四个 5-bit 字段])

#rivet-format-figure(fmt-r3-schema, caption: [R3 格式: 三个 5-bit 字段])

#rivet-format-figure(fmt-r2-schema, caption: [R2 格式: 两个 5-bit 字段])

#rivet-format-figure(fmt-mr-schema, caption: [MR 格式: 行访存])

#rivet-format-figure(fmt-i-schema, caption: [I 格式: 16-bit 立即数])

#rivet-format-figure(fmt-z-schema, caption: [Z 格式: 无显式操作数])

=== 选择子与简写

`sel2`/`sel3` 为 2-bit/3-bit 选择子, 具体含义由 `major4` 解释; 承载数据域编码时语义值记为 `dom2`. `funct3`/`funct4` 为操作选择. 各选择子位的语义:

#manual-table(
  columns: (1fr, 5.6fr),
  caption: [选择子位语义],
)[
  | 简写      | 含义                                                                                           |
  | --------- | ---------------------------------------------------------------------------------------------- |
  | `dom2`    | 架构数据域选择: `dom[0]`代表位宽,`dom[1]`代表类型, `00/01/10/11` 依次表示 Tile/Acc/Vec8/Vec32  |
  | `BX`      | 第二源选择 (`B`/`xS` 二选一): `0` 选择同域寄存器 `B`, `1` 选择 Scalar 寄存器 `xS`              |
  | `FS`      | fill 来源选择: `0` 选择立即数 `fill5`, `1` 选择 Scalar 寄存器 `xFill`                          |
  | `IS`      | 索引来源选择: `0` 选择 `index5` 中的立即数, `1` 选择由 `index5` 指定的 Scalar 寄存器           |
  | `EW`      | 元素位宽选择: `0` 选择 8-bit 寄存器组合 (Tile/Vec8), `1` 选择 32-bit 寄存器组合 (Acc/Vec32)    |
  | `LS`      | load/store 选择: `0` 表示 load, `1` 表示 store; 在 `M_BLK` 中占 `funct3` 最低位                |
  | `DIR`     | 广播方向: `0` 表示按行, `1` 表示按列                                                           |
  | `MV`      | 矩阵/向量配置选择: `0` 选择矩阵配置, `1` 选择向量配置                                          |
  | `G`       | 操作组; 与 `op3` 共同组成 `funct4`, 选择逐元素操作                                             |
  | `xBound`  | Scalar 边界操作数: 按指令解释为 `xBounds`, `xLen` 或 `xDelta`                                  |
  | `index5`  | 5-bit 索引字段: 由 `IS` 选择立即数索引或 Scalar 寄存器索引                                     |
  | `xVal5`   | `xValue` 目的寄存器字段, 仅 `vreduce.argmax` 使用                                              |
]

字段名后的数字表示位宽, 如 `D5`, `dom2`, `funct3`.

=== `major4` 分配

各功能域的指令族编码分配如下; 未列出的码点均为预留:

#manual-table(
  columns: (1fr, 1fr, 2.2fr, 1.2fr),
  caption: [major4 指令族分配],
)[
  | 功能域  | `major4`  | 指令族          | 格式   |
  | ------- | --------- | --------------- | ------ |
  | `00`    | `0000`    | `E_BIN`         | R3     |
  | `00`    | `0001`    | `E_UNARY`       | R2     |
  | `00`    | `0010`    | `E_CMP`         | R4     |
  | `00`    | `0011`    | `E_R4`          | R4     |
  | `00`    | `0100`    | `E_MASK`        | R4     |
  | `00`    | `0101`    | `E_BCAST`       | R3     |
  | `01`    | `0000`    | `M_BLK`         | R2/MR  |
  | `01`    | `0001`    | `FILL_IMM`      | I      |
  | `01`    | `0010`    | `REG_MOVE`      | R2     |
  | `01`    | `0011`    | `ROW_MOVE`      | R4     |
  | `01`    | `0100`    | `LANE_MOVE`     | R4     |
  | `10`    | `0000`    | `MMA_BDOT`      | R4     |
  | `10`    | `0001`    | `AREDUCE`       | R2     |
  | `10`    | `0010`    | `VREDUCE`       | R2/R4  |
  | `10`    | `0011`    | `CVT`           | R2     |
  | `10`    | `0100`    | `QNT`           | R4     |
  | `10`    | `0101`    | `CFG_MAT_SETI`  | I      |
  | `10`    | `0110`    | `CFG_VEC_SETI`  | I      |
  | `10`    | `0111`    | `CFG_REG`       | R4     |
  | `10`    | `1000`    | `SYS`           | Z      |
]

编码原则:

+ `reserved` 字段必须为 0, 非零组合为保留编码;
+ 寄存器编号字段的合法范围由操作数所属的数据域决定; 编码值未对应到该数据域中已定义的架构寄存器时, 该指令编码为保留编码, 执行时按非法指令处理 (例如 Tile 仅允许 `t0..t15`, Acc 仅允许 `a0..a11`);
+ 译码按 `q` → `major4` → `funct3` → `sel3` 分层: 选择子位的含义总在其指令族语境下解释; 操作数字段位置全局固定 (`D5` 在 `[6:2]`, 第一源在 `[11:7]`, 第二源或索引在 `[16:12]`), 寄存器读取可在译码完成前开始;
+ `sel3` 内高位优先放域选择 (`dom2`, `EW`), 变体位 (`BX`, `FS`, `IS`, `DIR`, `MV`) 固定占 `sel3` 最低位 `[25]`; 选择操作数来源的变体位 (`BX`, `FS`, `IS`) 只改变 `[16:12]` 的解释;
  + 元素位宽`EW`由 `[26]` 表示: `dom2` 的低位与 `EW` 同位, `0` 为 8-bit, `1` 为 32-bit; 使用 `EW` 的指令族要求 `[27] = 0`, 因此 `sel3[2:1] = {0, EW}` 与对应矩阵域的 `dom2` 编码一致;

= 标量与同步 <scalar-sync>

标量指令集采用 RV64IM: 标量算术, 逻辑, 比较, 分支, 跳转和标量访存均按 RISC-V 规范执行, 不在本手册定义. 本章只定义 NPU 特有的同步指令.

#instruction-table(caption: [同步指令])[
  | Instruction   | Format  | Operation                          | Summary                          |
  | :-----------: | :-----: | ---------------------------------- | -------------------------------- |
  | `fence.mem`   | Z       | 等待此前访存完成并达到约定可见点.  | 后续访存不得越过此边界.          |
  | `fence.sa`    | Z       | 等待此前脉动阵列操作完成.          | 后续脉动阵列操作不得越过此边界.  |
  | `fence.all`   | Z       | 等待此前全部后端工作完成.          | 后续后端操作不得越过此边界.      |
  | `kernel.end`  | Z       | 报告 kernel 完成.                  | 隐含 `fence.all`.                |
]

同步与 kernel 结束指令使用 Z 格式, 无显式操作数:

#rivet-encoding-figure(sys-schema, caption: [同步与结束格式 (SYS)])

= 配置指令 <configuration>

下表列出配置指令的语义摘要.

#instruction-table(
  columns: (1fr, 0.5fr, 2fr, 2fr),
  caption: [配置指令],
)[
  | Instruction  | Format  | Operation                                | Summary                                                   |
  | :----------: | :-----: | ---------------------------------------- | --------------------------------------------------------- |
  | `cfg.seti`   | I       | C[field] = extend(imm)                   | 扩展立即数, 校验后写入指定配置字段.                       |
  | `cfg.setx`   | R4      | $C_(D+k)$[field] = x[xS], $0 <= k <= N$  | 从 Scalar 读取完整值, 校验后写入配置字段; $0 <= k <= N$.  |
  | `cfg.copy`   | R4      | $C_(D+k) = C_S$, $0 <= k <= N$           | 将同类型配置的全部字段广播到目的; $0 <= k <= N$.          |
  | `cfg.get`    | R4      | x[xD] = extend(C[field])                 | 读取配置字段, 扩展后写入 Scalar.                          |
  | `cfg.setw`   | R4      | $C_(D+k) =$ x[xS][31:0], $0 <= k <= N$   | 整字写入计算配置的全部字段; $0 <= k <= N$.                |
  | `cfg.getw`   | R4      | x[xD] = zext(C)                          | 整字读出计算配置到 Scalar.                                |
]

`cfg.seti` 使用 I 格式. `sel2` 选择配置寄存器对 (`00` = TC/BC, `01` = AC/VC, `10` = TM/BM, `11` = AM/VM), `major4` 选择矩阵侧 (`0101` = CFG_MAT_SETI) 或向量侧 (`0110` = CFG_VEC_SETI), `field3` 直接编号字段:

#rivet-encoding-figure(cfg-seti-schema, caption: [cfg.seti 格式 (I)])

`cfg.setx`, `cfg.copy`, `cfg.get`, `cfg.setw`, `cfg.getw` 共用 R4 格式, `sel3 = {sel2, MV}` 选择配置类型与矩阵/向量侧, `funct3` 选择操作:

#rivet-encoding-rows-figure(
  (cfg-setx-schema, cfg-get-schema),
  caption: [配置字段访问格式 (R4): cfg.setx / cfg.get],
)

#rivet-encoding-rows-figure(
  (cfg-copy-setw-schema, cfg-getw-schema),
  caption: [整配置访问格式 (R4): cfg.copy、cfg.setw / cfg.getw],
)

`cfg.setx` 和 `cfg.get` 的 `field3[19:17]` 选择字段, `[21:20]` 为保留位. `cfg.copy` 和 `cfg.setw` 的 `[21:17]`、`cfg.get` 的 `[16:12]`、`cfg.getw` 的 `[21:12]` 均为保留位, 必须为 0.

写配置的 `cfg.setx`, `cfg.copy`, `cfg.setw` 使用 `D5` 指定起始目的配置寄存器, `N5[16:12]` 指定最后一个目的配置寄存器相对于起始寄存器的偏移. 汇编操作数 `N` 直接编码到 `N5` ($0 <= N <= 31$), 写入范围为 `C[D5]` 至 `C[D5 + N]`, 包含两端: 相对编号 0 是起始寄存器, 1 是其下一个寄存器. 省略 `N` 时取 0, 只写入起始寄存器. `D5 + N` 超出该配置类型的最后一个寄存器编号时为保留编码, 按非法指令处理. 多目的写入要么全部完成, 要么在 `CFG_ERROR` 时全部保持原值.

下文伪代码用 `D` 表示 `D5`, 用 `C[D..D + N]` 表示按上述范围选中的全部目的配置寄存器.

`field3` 字段编号按配置类型解释. 表中 `-` 表示该配置类型下未定义的字段编号; `cfg.seti`、`cfg.setx`、`cfg.get` 使用这些编号时按非法指令处理. 对已定义字段写入非法值时, `cfg.seti`/`cfg.setx` 产生 `CFG_ERROR`.

#manual-table(
  columns: (1fr, 1.4fr, 1.4fr, 1.8fr, 1.2fr, 1.2fr, 1.6fr),
  caption: [配置字段编号 (field3)],
)[
  | `field3`  | TC          | AC      | TM/AM             | BC     | VC     | BM/VM         |
  | --------- | ----------- | ------- | ----------------- | ------ | ------ | ------------- |
  | `000`     | dtype       | dtype   | base_addr         | dtype  | dtype  | base_addr     |
  | `001`     | rows        | rows    | row_stride_bytes  | len    | len    | stride_bytes  |
  | `010`     | cols        | cols    | col_stride_bytes  | -      | -      | flags         |
  | `011`     | layout      | layout  | transform         | -      | -      | -             |
  | `100`     | arith_mode  | -       | flags             | -      | -      | -             |
  | `101`     | -           | -       | -                 | -      | -      | -             |
  | `110`     | -           | -       | -                 | -      | -      | -             |
  | `111`     | -           | -       | -                 | -      | -      | -             |
]

`base_addr` 为 64-bit 字段, 完整地址由 `cfg.setx` 写入; `cfg.seti` 写入时将 `imm16` 符号扩展到 64 bit.

== `cfg.seti` — 写立即数配置字段 <cfg-seti>

```asm
cfg.seti C, field, imm
```

`imm16` 按 16-bit 二进制补码解释, 取值范围为 $[-32768, 32767]$. 将其符号扩展到 64 bit, 再按与 `cfg.setx` 相同的字段值规则校验并写入指定配置字段:

```
    v ← sign_ext(imm16)
    C[field] ← v
```

其中 `v` 为 64-bit 位模式. `row_stride_bytes`、`col_stride_bytes`、`stride_bytes` 按有符号 32-bit 值保存; `base_addr` 保存完整的 64-bit 位模式; 其他字段按各自的合法取值或枚举编码校验. 校验针对扩展后的完整值进行, 通过后按字段位宽写入; 失败时产生 `CFG_ERROR`, 目标字段保持原值.

例如 `imm16 = 0xfffc` 表示 $-4$, 扩展后为 `0xfffffffffffffffc`: 写入步长字段时得到 $-4$, 写入 `base_addr` 时得到地址 `0xfffffffffffffffc`; 写入 `rows` 时因不满足 $[1, 32]$ 的范围要求而产生 `CFG_ERROR`.

示例:

```asm
cfg.seti tc0, rows, 32
```

对于`cfg.seti tc0, rows, 32`, 执行后的架构状态是`tc0.rows = 32`, 由于`tc0 ↔ t0`, 它表示 `t0` 的有效行数为 32.

== `cfg.setx` — 写 Scalar 值到配置字段 <cfg-setx>

```asm
cfg.setx C, field, xS[, N]
```

将 Scalar 寄存器中的完整值写入从 `C` 开始、相对编号 0 至 `N` 的同类型配置寄存器的指定字段:

```
    v ← x[xS]
    check(field, v)
    C[D..D + N][field] ← v
```

示例:

```asm
cfg.setx tm0, row_stride_bytes, x4
```

将 Scalar 寄存器 `x4` 的 64-bit 值解释为有符号字节步长, 检查其是否满足 `TM.row_stride_bytes` 的约束, 并写入 `tm0.row_stride_bytes`.

如果`x4 = 128`, 则`tm0.row_stride_bytes = 128`,后续矩阵访存使用:

$
  op("addr")(i,j) = "tm0.base_addr" + i dot "tm0.row_stride_bytes" + j dot "tm0.col_stride_bytes"
$

== `cfg.copy` — 复制配置寄存器 <cfg-copy>

```asm
cfg.copy C_D, C_S[, N]
```

将源配置在执行前的全部字段广播到从 `C_D` 开始、相对编号 0 至 `N` 的同类型配置寄存器:

```
    v ← C_S
    C[D..D + N] ← v
```

两个配置操作数共享 `sel3`, 因此 `cfg.copy` 只能同类型复制, 并复制该类型的全部字段. 源值在任何写入之前读取, 因此源落在目的区间内时 (例如 `cfg.copy tm0, tm0, 2`) 所有目的都得到源的原值.

典型用法是先完整配置一个访存描述符, 再广播给相邻描述符, 最后分别写入各自的 `base_addr`:

```asm
cfg.copy tm1, tm0, 2             # tm1..tm3 = tm0
cfg.setx tm1, base_addr, x5
```

== `cfg.get` — 读配置字段到 Scalar <cfg-get>

```asm
cfg.get xD, C, field
```

将配置字段的整数或枚举值写入 Scalar 寄存器:

```
    v ← C[field]
    x[xD] ← extend(v, 64)
```

== `cfg.setw` — 整字写入计算配置 <cfg-setw>

```asm
cfg.setw C, xS[, N]
```

将 Scalar 寄存器 `xS` 的低 32 bit 按计算配置寄存器的整字位段 (见 @overview 的 TC/AC 与 BC/VC 位段图) 写入从 `C` 开始、相对编号 0 至 `N` 的同类型计算配置寄存器, 一次设置这些寄存器的全部字段. `xS[63:32]` 被忽略.

- `sel2` 只能为 `00` (TC/BC) 或 `01` (AC/VC); 访存描述符 (`sel2 = 1x`) 不是 32-bit 整字, 对应编码保留.
- `D5[6:2]` 为首个目的配置寄存器编号, `S5[11:7]` 为 `xS`, `N5[16:12]` 为末个目的相对于首个目的的偏移 `N`, `[21:17]` 为保留位.

执行:

```
    w ← x[xS][31:0]
    check(w)
    C[D..D + N] ← w
```

`w` 中任一字段取值非法 (例如 `rows`/`cols`/`len` 为 0 或大于 32, `dtype` 不属于该配置类型, `layout` 或 `arith_mode` 为保留编码) 或保留位非零时产生 `CFG_ERROR`, 所有目的配置寄存器保持原值. AC 的 `[24:23]` (`arith_mode` 位置) 为保留位.

示例:

```asm
li       t0, 0x2020          # rows = 32, cols = 32, dtype = i8, row_major, wrap
cfg.setw tc2, t0, 2          # tc2..tc4
li       t0, 0x0420          # len = 32, dtype = f32
cfg.setw vc0, t0, 31         # vc0..vc31
```

#note[
  配置字的保留位必须写 0. 以后在保留位中新增的字段, 取值 0 表示新增前的行为; 因此按当前位段写入的配置字在新增字段后语义不变, `cfg.setw` 的编码也无需变化.
]

== `cfg.getw` — 整字读出计算配置 <cfg-getw>

```asm
cfg.getw xD, C
```

将计算配置寄存器 `C` (TC/AC/BC/VC) 的 32-bit 整字零扩展后写入 Scalar 寄存器 `xD`; 保留位读出为 0. 指令的 `[21:12]` 为保留位. 与 `cfg.setw` 配合可用于保存和恢复配置:

```
    x[xD] ← zext(C, 64)
```

= 地址与访存指令 <memory>

本章定义按描述符寻址的访存指令. 访存描述符与数据寄存器一一绑定 (见 @overview): 矩阵访存 (`tload`, `tstore`, `aload`, `astore` 及行形式) 使用绑定的 `TM`/`AM`, 向量访存 (`bload`, `vload`, `bstore`, `vstore`) 使用绑定的 `BM`/`VM`; 描述符编号由数据寄存器操作数隐含, 基地址与访问坐标都在描述符的 `base_addr` 字段中. Scalar 访存由 RV64IM load/store 指令承担. 所有 x/t/a/b/v 访存保持统一的程序可见顺序.

#instruction-table(
  columns: (1.5fr, 0.5fr, 2.5fr, 2.1fr),
  caption: [地址与访存指令],
)[
  | Instruction         | Format  | Operation                    | Summary                                            |
  | :------------------ | :-----: | ---------------------------- | -------------------------------------------------- |
  | `{t,a}load`         | R2      | D[i,j] = memory[addr(i,j)]   | 按绑定的 TM/AM 读取内存到 Tile/Acc 有效区域.       |
  | `{t,a}store`        | R2      | memory[addr(i,j)] = S[i,j]   | 将 Tile/Acc 有效区域按绑定的 TM/AM 写入内存.       |
  | `{t,a}load.row`     | MR      | D[rd,j] = memory[addr(0,j)]  | 按绑定的 TM/AM 读取内存到 Tile/Acc 指定行.         |
  | `{t,a}store.row`    | MR      | memory[addr(0,j)] = S[rs,j]  | 将 Tile/Acc 指定行按绑定的 TM/AM 写入内存.         |
  | `tload.gather`      | R2      | D[i,j] = memory[gaddr(i,j)]  | 以 Vec32 各 lane 为索引 gather 加载到 Tile 行.     |
  | `{b,v}load.gather`  | R2      | D[j] = memory[gaddr(j)]      | 以 Vec32 各 lane 为索引 gather 加载到 Vec8/Vec32.  |
  | `{b,v}load`         | R2      | D[j] = memory[addr(j)]       | 按绑定的 BM/VM 读取内存到 Vec8/Vec32 向量.         |
  | `{b,v}store`        | R2      | memory[addr(j)] = S[j]       | 将 Vec8/Vec32 向量按绑定的 BM/VM 写入内存.         |
]

`M_BLK` 的 `funct3 = {form2, LS}` 区分整块访问, gather 与 row 形式, 其最低位 `LS` 选择 load (`0`) 或 store (`1`).

普通整块与向量访存使用 R2 格式, `sel3 = {dom2, 0}` 选择数据域. load/store 的 `funct3` 分别为 `000`/`001`, `[11:7]` 为保留位, 必须为 0:

#rivet-encoding-figure(m-blk-schema, caption: [整块与向量访存格式 (M_BLK)])

gather 同样使用 R2 格式和 `sel3 = {dom2, 0}`, 但 `S5[11:7]` 为 Vec32 索引向量寄存器编号. 目的域只允许 Tile、Vec8、Vec32. gather 只定义 load 形式 (`funct3 = 010`), `funct3 = 011` 保留:

#rivet-encoding-figure(
  m-gather-schema,
  caption: [Gather 访存格式 (M_BLK gather 形式)],
)

行访存是 `M_BLK` 的 row 形式 (`funct3 = 10x`), 使用 MR 格式; 目标行号 `rd`/`rs` 为独立的 `index5` 字段, 与行搬运和 lane 操作的索引字段位置对齐:

#rivet-encoding-figure(m-row-schema, caption: [行访存格式 (M_BLK row 形式)])

== 基础访存指令

=== 矩阵整块访存 <mem-block>

```asm
tload   tD
tstore  tS

aload   aD
astore  aS
```

`tload` 使用 `tD` 绑定的 `TC` 配置与 `TM` 描述符, `aload` 使用 `aD` 绑定的 `AC` 配置与 `AM` 描述符. `tstore` 和 `astore` 使用源寄存器绑定的配置与描述符.

对于矩阵整块 load, 令 $R = op("rows")("CD"), C & = op("cols")("CD")$

其中 $C D$ 是目的 Tile 或 Acc. 对每个有效寄存器元素执行:

```text
for 0 <= i < R:
    for 0 <= j < C:
        CD[i,j] ← memory[addr(i,j)]
```

对于矩阵整块 store:

```text
for 0 <= i < R:
    for 0 <= j < C:
        memory[addr(i,j)] ← CS[i,j]
```

其中 `CS` 是源 Tile 或 Acc. 内存 view 的有效范围等于寄存器的有效区域, 访存恰好覆盖 $R times C$ 个元素, 不存在越界元素.

=== 矩阵行访存 <mem-row>

```asm
tload.row   tD[rd]
tstore.row  tS[rs]

aload.row   aD[rd]
astore.row  aS[rs]
```

`rd` 和 `rs` 是寄存器文件中的行号, 可以是立即数或 Scalar 寄存器提供的完整值. 行号必须小于绑定配置的有效行数 (`rows(CD)` / `rows(CS)`), 否则为非法配置. 目标内存行的坐标在建立描述符时已折算进 `base_addr`, 即行访存访问描述符 `base_addr` 处的一行.

对于 row load:

```text
for 0 <= j < cols(CD):
    CD[rd,j] ← memory[addr(0,j)]
```

对于 row store:

```text
for 0 <= j < cols(CS):
    memory[addr(0,j)] ← CS[rs,j]
```

=== Gather 加载 <mem-gather>

```asm
tload.gather   tD, vS

bload.gather   bD, vS
vload.gather   vD, vS
```

gather 的索引向量为 `vS` (Vec32), `vS` 对应的 `VC.dtype` 须为 `i32`.

`tload.gather` 使用 `tD` 绑定的 `TC` 配置与 `TM` 描述符, 访存地址定义为:

$
  op("gaddr")(i,j) = "base_addr" + "vS"[i] dot "row_stride_bytes" + j dot "col_stride_bytes"
$

目的第 `i` 行以 `vS[i]` 为内存行索引, 按 `row_stride_bytes` 定位该行 (如 embedding 表中 token `vS[i]` 对应的行), 再按 `col_stride_bytes` 逐列加载元素. 两个 stride 的含义与矩阵整块访存一致, 同一内存 view 可共用描述符:

```text
for 0 <= i < rows(CD):
    if i < len(vS):
        for 0 <= j < cols(CD):
            CD[i,j] ← memory[gaddr(i,j)]
    else:
        CD[i,:] ← 0
```

`bload.gather` 和 `vload.gather` 使用目的绑定的 `BC`/`VC` 配置与 `BM`/`VM` 描述符, 访存地址定义为:

$ op("gaddr")(j) = "base_addr" + "vS"[j] dot "stride_bytes" $

```text
for 0 <= j < len(CD):
    if j < len(vS):
        CD[j] ← memory[gaddr(j)]
    else:
        CD[j] ← 0
```

=== 向量访存 <mem-vector>

```asm
bload   bD
bstore  bS

vload   vD
vstore  vS
```

`bload` 和 `bstore` 使用绑定的 `BC.len` 与 `BM` 描述符. `vload` 和 `vstore` 使用绑定的 `VC.len` 与 `VM` 描述符.

对于向量 load:

```text
for 0 <= j < len(CD):
    CD[j] ← memory[addr(j)]
```

对于向量 store:

```text
for 0 <= j < len(CS):
    memory[addr(j)] ← CS[j]
```

内存 view 的有效长度即绑定的 `BC.len` 或 `VC.len`, 访存恰好覆盖有效长度的元素.

== 访存后地址自增

描述符 `flags` 中的自增位 (`TM`/`AM` 的 `inc_mode`, `BM`/`VM` 的 `inc`) 置位时, 访存指令完成后按本次访问的跨度更新 `base_addr`, 对后续使用该描述符的指令生效. 递增量为:

#manual-table(
  columns: (1.2fr, 1fr, 2fr),
  caption: [访存后 base_addr 递增量],
)[
  | 访问形式             | 自增模式     | 递增量                              |
  | -------------------- | ------------ | ----------------------------------- |
  | 矩阵整块 load/store  | 沿行 (`01`)  | `rows(CD/CS)` × `row_stride_bytes`  |
  | 矩阵整块 load/store  | 沿列 (`10`)  | `cols(CD/CS)` × `col_stride_bytes`  |
  | 矩阵行 load/store    | 沿行 (`01`)  | `row_stride_bytes`                  |
  | 矩阵行 load/store    | 沿列 (`10`)  | `cols(CD/CS)` × `col_stride_bytes`  |
  | 向量 load/store      | `inc` = 1    | `len(CD/CS)` × `stride_bytes`       |
]

gather 不触发递增. load 的递增量按目的 `CD` 的有效范围计算, store 按源 `CS` 计算. 自增将连续的 tile 流 (权重块扫描, KV 追加等) 表达为对同一描述符的连续访存, 无需在循环中重写 `base_addr`.

== 存储数据类型

内存中的元素类型由绑定配置寄存器的 `dtype` 决定; load/store 均为原样搬运, 访存路径不执行类型转换. 转置加载通过 `TM`/`AM` 的 `transform` 字段选择, 仍使用 `tload` (见 @transpose-load).

#note[
  类型与精度转换 (`i8` → `i32`, `i8` → `f32`, 子字节格式如 `q4` 的展开, 以及打包量化格式如 `q8` + scale 到 `f32` 的反量化) 由 `twiden`, `acvt`/`vcvt`, `tquant`/`vquant`, `tdequant`/`bdequant` 等显式指令完成 (见 @quantization).
]

== Embedding 的行 Gather

Embedding 查表使用 gather 加载: token ID 先作为 `i32` 向量由 `vload` 载入 Vec32, 再由 `tload.gather` 索引出 embedding 行, 由 `vload.gather` 索引出对应的 scale:

```asm
vload        v1            # vm1 指向 ids 块
tload.gather t0, v1        # tm0 指向 embedding 表
vload.gather v2, v1        # vm2 指向 table_scale
```

`tm0` 的 `base_addr` 指向表原点, `row_stride_bytes` 为相邻 token 之间的字节跨步, `col_stride_bytes` 为 embedding 维方向的字节跨步; `vm2` 的 `stride_bytes` 为相邻 token scale 之间的字节跨步. token ID 的合法性 ($0 <= "id" < "vocab_size"$) 由软件保证, 索引越界行为见 gather 加载的定义.

== KV Cache 追加示例

Decode 的 KV 追加可直接用 `bstore` 写 `i8` 行片段, 用 `vstore` 写 scale; bits 和 scale 分别使用 Vec8 和 Vec32 访存. 起始追加位置的地址由 Scalar 代码计算后写入绑定描述符的 `base_addr`, 并置位自增标志; 此后每次写入自动前进到下一追加位置:

```asm
cfg.setx bm0, base_addr, xAppendBitsAddr
cfg.seti bm0, flags, 1
cfg.setx vm0, base_addr, xAppendScaleAddr
cfg.seti vm0, flags, 1
bstore  b0     # 写入 token t 的 bits, 完成后 bm0.base_addr += len × stride_bytes
vstore  v0     # 写入 token t 的 scale, 同理
```

下一个 token 追加时重复同样的 `bstore`/`vstore` 即可, 无需重写描述符.

= 填充, 搬运与转置 <data-movement>

本节定义数据寄存器的填充, 复制, 行搬运, lane 搬运, 广播和 Tile 转置操作.

元素类型使用寄存器配置中的 dtype: Tile/Vec8 为 `i8/u8`, Acc/Vec32 为 `i32/u32/f32`.

#instruction-table(caption: [填充, 搬运与转置指令])[
  | Instruction         | Format  | Operation          | Summary                                           |
  | :-----------------: | :-----: | ------------------ | ------------------------------------------------- |
  | `{t,a,b,v}fill`     | I       | D[p] = imm         | 将立即数填入 Tile/Acc/Vec8/Vec32 的有效区域.      |
  | `{t,a,b,v}fillx`    | R2      | D[p] = xS          | 用 Scalar 值填充 Tile/Acc/Vec8/Vec32 的有效区域.  |
  | `{t,a,b,v}copy`     | R2      | D[p] = S[p]        | 复制同域 Tile/Acc/Vec8/Vec32 的有效数据.          |
  | `{t,a}insert.row`   | R4      | D[rd,j] = S[j]     | 将 Vec8/Vec32 写入 Tile/Acc 的指定行.             |
  | `{t,a}extract.row`  | R4      | D[j] = S[rs,j]     | 从 Tile/Acc 指定行提取到 Vec8/Vec32.              |
  | `{b,v}extract`      | R4      | xD = S[lane]       | 将 Vec8/Vec32 的指定 lane 提取到 Scalar.          |
  | `{b,v}insert`       | R4      | D[lane] = xS       | 将 Scalar 值写入 Vec8/Vec32 的指定 lane.          |
  | `{b,v}broadcast`    | R4      | D[j] = S[lane]     | 将源 Vec8/Vec32 的一个 lane 广播到目的有效区域.   |
  | `ttranspose`        | R2      | tD[i,j] = tS[j,i]  | 交换 Tile 的行列, 将元素转置写入目的 Tile.        |
]

`fill` 单独占用 `major4 = FILL_IMM`, 使用 I 格式, 立即数 `imm16` 按目的 dtype 解释:

#rivet-encoding-figure(fill-imm-schema, caption: [fill 格式 (FILL_IMM, I)])

`fillx`/`copy`/`ttranspose` 占用 `major4 = REG_MOVE`, 使用 R2 格式:

#rivet-encoding-figure(
  reg-move-schema,
  caption: [fillx/copy/ttranspose 格式 (REG_MOVE, R2)],
)

行搬运与 lane 操作共用 R4 格式; `EW` 选择 8-bit/32-bit 寄存器组合, `IS` 选择索引来源:

#rivet-encoding-figure(
  row-move-schema,
  caption: [行搬运格式 (ROW_MOVE)],
)

#rivet-encoding-figure(
  lane-move-schema,
  caption: [lane 操作格式 (LANE_MOVE)],
)

== Fill 指令 <fill-instr>

```asm
{t,a,b,v}fill   D, imm
{t,a,b,v}fillx  D, xS
```

`fill` 将立即数填入目标有效区域; `fillx` 用 Scalar 值填充. 目标数据域由指令前缀确定.

立即数 `imm16` 按目的 `dtype` 解释. 整数目的 (`i8/u8/i32/u32`): `imm16` 先符号扩展到 64 bit, 然后与 `fillx` 的填充值一样截取元素位宽写入, `i8/u8` 取低 8 bit, `i32/u32` 取低 32 bit. `f32` 目的: `imm16` 按 BF16 位模式解释, 零扩展后置于 f32 位模式的高 16 位, 低 16 位置零, 即 `f32_bits = zext(imm16) << 16`; 常用浮点常数 (±0, ±1, ±0.5, ±inf 等) 均可由 BF16 精确表示.

`fill` 与 `fillx` 使用不同的 `major4`, 因此 `imm16` 的全部 65536 个取值均可用于 `fill`.

对于矩阵目标, 令$R & = op("rows")(D), C & = op("cols")(D)$, `fill`执行:

```text
for 0 <= i < R:
    for 0 <= j < C:
        D[i,j] ← value
```

对于向量目标, 令$N & = op("len")(D)$, 执行:

```text
for 0 <= j < N:
    D[j] ← value
```

`fillx` 操作: 从 Scalar 寄存器中读取填充值 `value ← x[xS]`, 然后按目的 dtype 截取元素位宽, 写入目标有效区域.

== Copy 指令 <copy-instr>

```asm
{t,a,b,v}copy D, S
```

复制同域寄存器的有效数据. 源和目的的有效 shape 必须相同; 有效 shape 的定义: Tile/Acc 的 shape 为 `rows` 和 `cols`; Vec8/Vec32 的 shape 为 `len`.

矩阵 copy 定义为:

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

前一条复制的是计算配置值, 后一条复制的是 Tile 数据; 两条指令均为值复制, 执行后目的与源相互独立.

== Tile 和 Vec8 的行搬运 <row-move-tile>

```asm
tinsert.row  tD[rd], bS
textract.row bD,     tS[rs]
```

在 Vec8 与 Tile 的指定行之间搬运数据. 如果需要扩大或量化, 必须先使用 `twiden`, `tquant` 或 `vquant` 完成转换, 再执行行搬运.

`tinsert.row` 操作: 将一个 Vec8 写入 Tile 的指定行:

```text
for 0 <= j < cols(tD):
    tD[rd,j] ← bS[j]
```

只有目标 Tile 的第 `rd` 行被修改, 其他行保持原值.

`textract.row` 操作: 将 Tile 的指定行读入 Vec8:

```text
for 0 <= j < cols(tS):
    bD[j] ← tS[rs,j]
```

只有 `bD` 的有效 lane 被写入, 其他 lane 保持原值.

== Acc 和 Vec32 的行搬运 <row-move-acc>

```asm
ainsert.row  aD[rd], vS
aextract.row vD,     aS[rs]
```

在 Vec32 与 Acc 的指定行之间搬运数据.

`ainsert.row` 操作: 将一个 Vec32 写入 Acc 的指定行:

```text
for 0 <= j < cols(aD):
    aD[rd,j] ← vS[j]
```

只有目标 Acc 的第 `rd` 行被修改, 其他行保持原值.

`aextract.row` 操作: 将 Acc 的指定行读入 Vec32:

```text
for 0 <= j < cols(aS):
    vD[j] ← aS[rs,j]
```

只有 `vD` 的有效 lane 被写入, 其他 lane 保持原值.

== Scalar 与 Vector lane 操作 <lane-move>

```asm
{b,v}extract xD, S[lane]
{b,v}insert  D[lane], xS
{b,v}broadcast D, S[lane]
```

在 Scalar 与 Vector 的单个 lane 之间读写数据, 或将一个 lane 广播到整个向量. `lane` 可以是立即数, 也可以由 Scalar 寄存器提供.

`extract` 操作:

```text
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
D[lane] ← x[xS]
```

`broadcast` 操作:

```text
for 0 <= j < len(D):
    D[j] ← S[lane]
```

== Tile 转置 <ttranspose>

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
  op("layout")("tD") & = "row_major"
$

即 `ttranspose` 将目的绑定配置更新为 `tc[tD].rows ← C`, `tc[tD].cols ← R`; 源和目的的 `dtype` 必须相同, 二者的 `layout` 均须为 `row_major`, 否则为非法配置. 转置后的有效区域之外的物理位置保持原值.

允许原地转置, 即:

```asm
ttranspose t0, t0
```

== Full load 的转置形式 <transpose-load>

绑定描述符的 `transform=transpose` 可以作为 full `tload` 的访存变换:

```asm
tload tD    # tm[tD].transform = transpose
```

其结果等价于:

$ "tD"_(i,j) <- "memory"[op("addr")(j, i)] $

该形式和:

```asm
tload tTmp       # tm[tTmp].transform = normal
ttranspose tD, tTmp
```

具有相同的架构结果, 但实现路径不同:

```text
transpose-on-load:
    在访存路径或转置 SRAM 中完成转置;

显式 ttranspose:
    先产生普通 Tile, 再调用 Tile 转置指令.
```

转置访存变换只对 full `tload` 定义; 其余访存指令 (store, 行形式, `aload`/`astore` 与向量访存) 执行时绑定描述符的 `transform` 必须为 `normal`, 否则为非法配置.

== KV Cache 中的行搬运

KV cache 追加可以采用如下指令序列:

```asm
# 从计算结果中取得一个低精度行
textract.row b0, tK[rowK]

# 写入 KV cache 的 bits (bm0.base_addr 已指向追加位置)
bstore b0

# 写入对应的 scale (vm0.base_addr 已指向追加位置)
vstore v0
```

如果需要把 Vec8 的一行写入驻留 Tile, 则使用:

```asm
tinsert.row tK[rowK], b0
```

= 矩阵乘与向量—矩阵乘 <matrix>

本节定义基础 `i8` 矩阵乘和 Vec8—Tile 点积指令. 基础指令使用*`i8` 输入, `i32` 输出或累加*.

#instruction-table(caption: [矩阵乘与点积指令])[
  | Instruction           | Format  | Operation                                       | Summary                                           |
  | :-------------------: | :-----: | ----------------------------------------------- | ------------------------------------------------- |
  | `mma.nn.zero.i8.i32`  | R4      | $"aD"[m,n] = sum_k "tA"[m,k] times "tB"[k,n]$   | 按普通右矩阵执行矩阵乘, 写入 `i32` Acc.           |
  | `mma.nn.acc.i8.i32`   | R4      | $"aD"[m,n] += sum_k "tA"[m,k] times "tB"[k,n]$  | 按普通右矩阵执行矩阵乘, 累加到旧 `i32` Acc.       |
  | `bdot.nn.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[k,n]$       | Vec8 与 Tile 各列执行点积, 结果写入 Vec32.        |
  | `bdot.nn.acc.i8.i32`  | R4      | $"vD"[n] += sum_k "bA"[k] times "tB"[k,n]$      | Vec8 与 Tile 各列执行点积, 累加到旧 `i32` Vec32.  |
  | `bdot.nt.i8.i32`      | R4      | $"vD"[n] = sum_k "bA"[k] times "tB"[n,k]$       | Vec8 与 Tile 各行执行点积, 结果写入 Vec32.        |
  | `bdot.nt.acc.i8.i32`  | R4      | $"vD"[n] += sum_k "bA"[k] times "tB"[n,k]$      | Vec8 与 Tile 各行执行点积, 累加到旧 `i32` Vec32.  |
]

矩阵乘与点积使用 R4 格式; `funct3` 的三个 bit 依次区分 MMA/BDOT, nn/nt 和 zero/acc. `nt` 只对 `bdot` 定义, `funct3 = 010/011` 保留:

#rivet-encoding-figure(mma-bdot-schema, caption: [矩阵乘与点积格式 (MMA_BDOT)])

== 指令格式

```asm
mma.nn.zero.i8.i32 aD, tA, tB
mma.nn.acc.i8.i32  aD, tA, tB

bdot.nn.i8.i32     vD, bA, tB
bdot.nn.acc.i8.i32 vD, bA, tB

bdot.nt.i8.i32     vD, bA, tB
bdot.nt.acc.i8.i32 vD, bA, tB
```

操作数含义:

#manual-table(
  columns: (0.9fr, 0.9fr, 3.5fr),
  caption: [矩阵乘与点积操作数],
)[
  | 操作数  | 数据域  | 作用                                |
  | ------- | ------- | ----------------------------------- |
  | `tA`    | Tile    | MMA 或 row-dot 的左操作数           |
  | `tB`    | Tile    | MMA 或 row-dot 的右操作数           |
  | `aD`    | Acc     | MMA 的 `i32` 目的和累加寄存器       |
  | `bA`    | Vec8    | bdot 的 `i8` 向量输入               |
  | `vD`    | Vec32   | bdot 的 `i32` 向量输出和累加寄存器  |
]

数学形式:

#manual-table(
  columns: (1fr, 4fr),
  caption: [矩阵乘与点积的数学形式],
)[
  | 形式       | 运算                                            |
  | ---------- | ----------------------------------------------- |
  | `mma.nn`   | $A_(M times K) B_(K times N) -> D_(M times N)$  |
  | `bdot.nn`  | $"out"_j = sum_(k=0)^(K-1) b_k B_(k,j)$         |
  | `bdot.nt`  | $"out"_j = sum_(k=0)^(K-1) b_k B_(j,k)$         |
]

== `nn` 和 `nt` 的矩阵布局

`nn` 和 `nt` 表示右操作数的逻辑方向. `mma` 只有 `nn` 形式: 右操作数 `tB` 总是按 $K times N$ 存放, `tB` 的第 $k$ 行对应矩阵乘阵列的第 $k$ 行, 阵列只需一个方向的右操作数装载路径. 需要 $B^sans(T)$ 时, 由数据准备阶段把转置形式存入 Tile, 例如使用 `transform = transpose` 的 `tload` (见 @transpose-load) 或 `ttranspose`.

`bdot` 的两种形式都只按行读取 Tile, 区别在运算结构: `bdot.nn` 逐行读取 `tB[k, :]`, 将 `bA[k]` 广播到整行后逐 lane 乘加, 跨行保留 $N$ 个 `i32` 部分和; `bdot.nt` 逐行读取 `tB[j, :]`, 与 `bA` 做一次完整点积, 得到 `vD[j]`.

=== `nn`

`mma.nn` 的数学形式为:

$ A_(M times K) B_(K times N) -> D_(M times N) $

其中:

$ A_(i,k) = "tA"_(i,k), quad B_(k,j) = "tB"_(k,j) $

因此:

$ D_(i,j) = sum_(k=0)^(K-1) A_(i,k) B_(k,j) $

=== `nt`

`bdot.nt` 把 Tile 的每一行当作一个与 `bA` 做点积的向量, Tile `tB` 的物理有效 shape 为 $N times K$:

$ "vD"_j = sum_(k=0)^(K-1) "bA"_k "tB"_(j,k) $

== `mma.nn.zero.i8.i32` 和 `mma.nn.acc.i8.i32` <matrix-mma>

```asm
mma.nn.zero.i8.i32 aD, tA, tB
mma.nn.acc.i8.i32  aD, tA, tB
```

两种形式都按普通右矩阵执行矩阵乘. 每个 `i8` 操作数先符号扩展到 `i32`, 再进行乘法; 乘积和累加使用 `i32` 算术. `zero` 将结果写入目的 Acc; `acc` 将结果加上目的 Acc 的旧值.

约束:

$
  op("rows")("tA") & = M, op("cols")("tA") = K \
  op("rows")("tB") & = K, op("cols")("tB") = N \
  op("rows")("aD") & = M, op("cols")("aD") = N
$

操作:

```text
for 0 <= i < M:
    for 0 <= j < N:
        partial ← 0
        for 0 <= k < K:
            lhs ← sign_ext(tA[i,k])
            rhs ← sign_ext(tB[k,j])
            partial ← partial + lhs × rhs
        if zero:
            aD[i,j] ← partial
        else:  # acc
            aD[i,j] ← wrap32(aD[i,j] + partial)
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

== `bdot.nn.i8.i32` 和 `bdot.nn.acc.i8.i32` <matrix-bdot-nn>

```asm
bdot.nn.i8.i32     vD, bA, tB
bdot.nn.acc.i8.i32 vD, bA, tB
```

Vec8 与 Tile 各列执行点积. `zero` 形式将结果写入 `i32` Vec32; `acc` 形式将结果累加到旧值.

约束:

$
   op("len")("bA") & = K \
  op("rows")("tB") & = K \
  op("cols")("tB") & = N \
   op("len")("vD") & = N
$

操作:

```text
for 0 <= j < N:
    vD[j] ← 0
for 0 <= k < K:
    lhs ← sign_ext(bA[k])
    for 0 <= j < N:
        rhs ← sign_ext(tB[k,j])
        vD[j] ← wrap32(vD[j] + lhs × rhs)
```

该形式逐行读取 `tB`, 与逐列做点积的写法结果相同: `i32` 回绕加法满足结合律, 累加顺序不影响结果.

数学形式为:

$ "bA"_(1 times K) "tB"_(K times N) -> "vD"_(1 times N) $

`bdot.nn.acc.i8.i32` 使用相同的列点积定义, 但部分和从 `vD` 的旧值开始:

```text
for 0 <= k < K:
    lhs ← sign_ext(bA[k])
    for 0 <= j < N:
        rhs ← sign_ext(tB[k,j])
        vD[j] ← wrap32(vD[j] + lhs × rhs)
```

== `bdot.nt.i8.i32` 和 `bdot.nt.acc.i8.i32` <matrix-bdot-nt>

```asm
bdot.nt.i8.i32     vD, bA, tB
bdot.nt.acc.i8.i32 vD, bA, tB
```

Vec8 与 Tile 各行执行点积. Tile 的每一行是一个待匹配的向量:

$ "tB"[j, 0:K] $

`zero` 形式将结果写入 `i32` Vec32; `acc` 形式将结果累加到旧值.

约束:

$
   op("len")("bA") & = K and op("len")("vD") = N \
  op("cols")("tB") & = K and op("rows")("tB") = N \
$

操作:

```text
for 0 <= j < N:
    sum ← 0
    for 0 <= k < K:
        lhs ← sign_ext(bA[k])
        rhs ← sign_ext(tB[j,k])
        sum ← sum + lhs × rhs
    vD[j] ← sum
```

数学形式为:

$ "bA"_(1 times K) ("tB"_(N times K))^sans(T) -> "vD"_(1 times N) $

`bdot.nt.acc.i8.i32` 使用相同的行点积定义, 再将结果加到旧值:

```text
for 0 <= j < N:
    partial ← 0
    for 0 <= k < K:
        lhs ← sign_ext(bA[k])
        rhs ← sign_ext(tB[j,k])
        partial ← partial + lhs × rhs
    vD[j] ← wrap32(vD[j] + partial)
```

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
bdot.nt.i8.i32     vScore0, b0, tK0
bdot.nt.acc.i8.i32 vScore0, b1, tK1
bdot.nt.acc.i8.i32 vScore0, b2, tK2
bdot.nt.acc.i8.i32 vScore0, b3, tK3
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
vadd vOut, vOut, vOutF32
```

= 逐元素, 广播和 mask <elementwise>

本节定义 Tile, Acc 和 Vec32 的逐元素运算, 按行/列广播, 比较, select 和 mask 操作.

本节中的基础运算只处理寄存器中的有效区域. 有效区域由目的寄存器对应的 `TC`, `AC` 或 `VC` 配置确定.

普通逐元素操作必须满足:

1. 源和目的属于同一数据域;
2. 源和目的 dtype 相同;
3. 源和目的有效 shape 相同;
4. 所有动态行号和 lane 号均在有效范围内.

fill, copy 以及行搬运和 lane 操作遵循同样的 dtype 一致与索引有效性约束; 比较, select, mask 指令的 mask 操作数与比较目的的 dtype 按各指令定义; 跨域指令的域配对和 shape 对应关系按各指令定义 (如行搬运中向量长度等于矩阵列数). 广播, 矩阵乘, 规约, 量化与访存指令的操作数约束在对应章节单独规定.

== 基础逐元素指令形式

以 `op` 表示某个合法的逐元素操作, 基础形式包括:

```asm
top       tD, tA, tB
topx      tD, tA, xS

aop       aD, aA, aB
aopx      aD, aA, xS

vop       vD, vA, vB
vopx      vD, vA, xS
```

例如:

```asm
tadd t0, t1, t2

aadd   a0, a1, a2
vadd   v0, v1, v2

vaddx  v0, v1, x4
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
value ← decode_scalar(xS)
D[p] ← op(A[p], value)
```

普通二元操作使用 R3 格式; `BX` 选择第二源为同域寄存器或 Scalar:

#rivet-encoding-figure(e-bin-schema, caption: [普通二元操作格式 (E_BIN)])

== 基础操作集合 <elementwise-ops>

`E_BIN` 与 `E_BCAST` 共用逐元素操作编码 `funct4 = {G, op3}`:

#manual-table(
  columns: (0.8fr, 1fr, 1.2fr, 3.4fr),
  caption: [逐元素公共操作编码 ({G, op3})],
)[
  | `G`  | `op3`  | 操作   | 备注              |
  | ---- | ------ | ------ | ----------------- |
  | `0`  | `000`  | `add`  |                   |
  | `0`  | `001`  | `sub`  |                   |
  | `0`  | `010`  | `mul`  | 仅 Acc/Vec32      |
  | `0`  | `011`  | `div`  | 仅 f32 Acc/Vec32  |
  | `0`  | `100`  | `min`  |                   |
  | `0`  | `101`  | `max`  |                   |
  | `1`  | `000`  | `and`  | 按位操作          |
  | `1`  | `001`  | `or`   | 按位操作          |
  | `1`  | `010`  | `xor`  | 按位操作          |
  | `1`  | `011`  | `shl`  | 整数逐元素移位    |
  | `1`  | `100`  | `shr`  | 逻辑右移          |
  | `1`  | `101`  | `sra`  | 算术右移          |
]

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

以下分 8-bit 域 (Tile) 与 32-bit 域 (Acc/Vec32) 两表列出基础操作. 8-bit 域的元素类型为 `i8/u8`, 32-bit 域为 `i32/u32/f32`, 由目的寄存器配置决定; 标注 "仅 f32" 或 "仅整数" 的行为例外. 二元操作展开为寄存器和 Scalar (`x`) 两种来源; 8-bit 域加法和减法的溢出模式由配置 `arith_mode` 决定 (见 @integer-arithmetic). 一元操作仅列单源形式, 融合乘加, 特殊函数, 比较和 select 在各自小节列出.

#instruction-table(caption: [Tile 基础逐元素指令])[
  | Instruction  | Format  | Operation                     | Summary                   |
  | :----------: | :-----: | ----------------------------- | ------------------------- |
  | `tadd`       | R3      | D[i,j] = A[i,j] + B[i,j]      | 同域逐元素加法.           |
  | `taddx`      | R3      | D[i,j] = A[i,j] + xS          | Scalar 值逐元素加法.      |
  | `tsub`       | R3      | D[i,j] = A[i,j] - B[i,j]      | 同域逐元素减法.           |
  | `tsubx`      | R3      | D[i,j] = A[i,j] - xS          | Scalar 值逐元素减法.      |
  | `tmin`       | R3      | D[i,j] = min(A[i,j], B[i,j])  | 同域逐元素取小.           |
  | `tminx`      | R3      | D[i,j] = min(A[i,j], xS)      | Scalar 值逐元素取小.      |
  | `tmax`       | R3      | D[i,j] = max(A[i,j], B[i,j])  | 同域逐元素取大.           |
  | `tmaxx`      | R3      | D[i,j] = max(A[i,j], xS)      | Scalar 值逐元素取大.      |
  | `tand`       | R3      | D[i,j] = A[i,j] and B[i,j]    | 同域逐元素按位与.         |
  | `tandx`      | R3      | D[i,j] = A[i,j] and xS        | Scalar 值逐元素按位与.    |
  | `tor`        | R3      | D[i,j] = A[i,j] or B[i,j]     | 同域逐元素按位或.         |
  | `torx`       | R3      | D[i,j] = A[i,j] or xS         | Scalar 值逐元素按位或.    |
  | `txor`       | R3      | D[i,j] = A[i,j] xor B[i,j]    | 同域逐元素按位异或.       |
  | `txorx`      | R3      | D[i,j] = A[i,j] xor xS        | Scalar 值逐元素按位异或.  |
  | `tshl`       | R3      | D[i,j] = shl(A[i,j], B[i,j])  | 同域逐元素左移.           |
  | `tshlx`      | R3      | D[i,j] = shl(A[i,j], xS)      | Scalar 值逐元素左移.      |
  | `tshr`       | R3      | D[i,j] = shr(A[i,j], B[i,j])  | 同域逐元素逻辑右移.       |
  | `tshrx`      | R3      | D[i,j] = shr(A[i,j], xS)      | Scalar 值逐元素逻辑右移.  |
  | `tsra`       | R3      | D[i,j] = sra(A[i,j], B[i,j])  | 同域逐元素算术右移.       |
  | `tsrax`      | R3      | D[i,j] = sra(A[i,j], xS)      | Scalar 值逐元素算术右移.  |
  | `tnot`       | R2      | D[i,j] = not A[i,j]           | 逐元素按位取反.           |
]

#instruction-table(caption: [Acc/Vec32 基础逐元素指令])[
  | Instruction  | Format  | Operation               | Summary                           |
  | :----------: | :-----: | ----------------------- | --------------------------------- |
  | `{a,v}add`   | R3      | D[p] = A[p] + B[p]      | 同域逐元素加法.                   |
  | `{a,v}addx`  | R3      | D[p] = A[p] + xS        | Scalar 值逐元素加法.              |
  | `{a,v}sub`   | R3      | D[p] = A[p] - B[p]      | 同域逐元素减法.                   |
  | `{a,v}subx`  | R3      | D[p] = A[p] - xS        | Scalar 值逐元素减法.              |
  | `{a,v}mul`   | R3      | D[p] = A[p] × B[p]      | 同域逐元素乘法.                   |
  | `{a,v}mulx`  | R3      | D[p] = A[p] × xS        | Scalar 值逐元素乘法.              |
  | `{a,v}div`   | R3      | D[p] = A[p] / B[p]      | 同域逐元素除法; 仅 f32.           |
  | `{a,v}divx`  | R3      | D[p] = A[p] / xS        | Scalar 值逐元素除法; 仅 f32.      |
  | `{a,v}min`   | R3      | D[p] = min(A[p], B[p])  | 同域逐元素取小.                   |
  | `{a,v}minx`  | R3      | D[p] = min(A[p], xS)    | Scalar 值逐元素取小.              |
  | `{a,v}max`   | R3      | D[p] = max(A[p], B[p])  | 同域逐元素取大.                   |
  | `{a,v}maxx`  | R3      | D[p] = max(A[p], xS)    | Scalar 值逐元素取大.              |
  | `{a,v}and`   | R3      | D[p] = A[p] and B[p]    | 同域逐元素按位与.                 |
  | `{a,v}andx`  | R3      | D[p] = A[p] and xS      | Scalar 值逐元素按位与.            |
  | `{a,v}or`    | R3      | D[p] = A[p] or B[p]     | 同域逐元素按位或.                 |
  | `{a,v}orx`   | R3      | D[p] = A[p] or xS       | Scalar 值逐元素按位或.            |
  | `{a,v}xor`   | R3      | D[p] = A[p] xor B[p]    | 同域逐元素按位异或.               |
  | `{a,v}xorx`  | R3      | D[p] = A[p] xor xS      | Scalar 值逐元素按位异或.          |
  | `{a,v}shl`   | R3      | D[p] = shl(A[p], B[p])  | 同域逐元素左移; 仅整数.           |
  | `{a,v}shlx`  | R3      | D[p] = shl(A[p], xS)    | Scalar 值逐元素左移; 仅整数.      |
  | `{a,v}shr`   | R3      | D[p] = shr(A[p], B[p])  | 同域逐元素逻辑右移; 仅整数.       |
  | `{a,v}shrx`  | R3      | D[p] = shr(A[p], xS)    | Scalar 值逐元素逻辑右移; 仅整数.  |
  | `{a,v}sra`   | R3      | D[p] = sra(A[p], B[p])  | 同域逐元素算术右移; 仅整数.       |
  | `{a,v}srax`  | R3      | D[p] = sra(A[p], xS)    | Scalar 值逐元素算术右移; 仅整数.  |
  | `{a,v}not`   | R2      | D[p] = not A[p]         | 逐元素按位取反.                   |
  | `{a,v}abs`   | R2      | D[p] = abs(A[p])        | 逐元素绝对值; 仅 `i32/f32`.       |
  | `{a,v}neg`   | R2      | D[p] = -A[p]            | 逐元素取负; 仅 `i32/f32`.         |
]

== 整数算术规则 <integer-arithmetic>

8-bit 域 (`i8/u8`) 的 `add` 和 `sub` 的溢出行为由绑定配置寄存器的 `arith_mode` 字段决定: 0 = wrap (回绕), 1 = sat (饱和), 2-3 预留. 32-bit 整数 `add`, `sub`, `mul` 默认使用 wrap32 回绕.

```asm
tadd  t0, t1, t2    # 溢出行为由 tc0.arith_mode 决定
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


== 浮点逐元素规则 <elementwise-fma>

`fma` 运算使用 `fmadd` 助记符; 按 Acc/Vec32 的 f32 数据域列出. 这里只列三数据源形式, 其他操作数变体尚未定义.

#instruction-table(
  columns: (1fr, 0.5fr, 2fr, 2fr),
  caption: [融合乘加指令],
)[
  | Instruction   | Format  | Operation                     | Summary                             |
  | :-----------: | :-----: | ----------------------------- | ----------------------------------- |
  | `{a,v}fmadd`  | R4      | D[p] = fma(A[p], B[p], C[p])  | Acc/Vec32 融合乘加, 单次 f32 舍入.  |
]

`fmadd` 与 `select` 共用 R4 四寄存器格式, `M5/C5` 为第四操作数 (`select` 的 mask `M`, `fmadd` 的加数 `C`):

#rivet-encoding-figure(e-r4-schema, caption: [select/fmadd 格式 (E_R4)])

f32 逐元素运算包括:

```asm
vadd   vD, vA, vB
vsub   vD, vA, vB
vmul   vD, vA, vB
vdiv   vD, vA, vB
vmin   vD, vA, vB
vmax   vD, vA, vB
vabs   vD, vA
vneg   vD, vA
vfmadd vD, vA, vB, vC
```

`fma` 定义为一次融合乘加:

$ D_i = op("round")_("f32")(A_i B_i + C_i) $

#warning[
  `fma(A, B, C)` 与先 `mul(A, B)` 再 `add(..., C)` 不保证数值等价, 因此编译器不能自动把 `mul` 与 `add` 合并成 `fma`.
]

== 近似特殊函数 <elementwise-approx>

近似特殊函数对 Acc 或 Vec32 的 f32 有效区域逐元素求值.

`not`/`abs`/`neg` 与近似特殊函数同属一元操作族 (E_UNARY), 使用 R2 格式:

#rivet-encoding-figure(
  e-unary-schema,
  caption: [一元操作与特殊函数格式 (E_UNARY)],
)

#instruction-table(
  columns: (1.2fr, 0.5fr, 2fr, 2fr),
  caption: [近似特殊函数指令],
)[
  | Instruction          | Format  | Operation                  | Summary                |
  | :------------------: | :-----: | -------------------------- | ---------------------- |
  | `{a,v}exp2.approx`   | R2      | D[p] = exp2_approx(A[p])   | 逐元素计算 2 的幂.     |
  | `{a,v}rcp.approx`    | R2      | D[p] = rcp_approx(A[p])    | 逐元素计算倒数.        |
  | `{a,v}rsqrt.approx`  | R2      | D[p] = rsqrt_approx(A[p])  | 逐元素计算倒数平方根.  |
]

E_UNARY 的 funct3 = 110/111 编码保留.

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
for 0 <= j < len(D):
    D[j] ← f(S[j])
```

矩阵形式为:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← f(S[i,j])
```

近似函数规则如下. 数学定义为:

$ "exp2_approx"(x) = 2^x $
$ "rcp_approx"(x) = 1 / x $
$ "rsqrt_approx"(x) = 1 / sqrt(x) $

- 精度: 数学结果为有限非零值时, 结果的相对误差不超过 $2^(-10)$; 不要求正确舍入, 也不要求与其他实现逐位一致.
- 确定性: 同一实现上, 相同输入产生相同结果.
- 非正规数: 实现可将非正规输入冲刷为零后求值, 或将非正规结果冲刷为零 (FTZ), 冲刷保留符号; 数学结果为零或落入非正规范围时结果可为 $plus.minus 0$, 相对误差界不适用.
- 上溢: `exp2_approx` 结果上溢时返回 $+infinity$.
- 特殊值: 按下表求值; 其他有限输入按数学定义求值.

#manual-table(
  columns: (0.9fr, 1fr, 1fr, 1fr),
  caption: [近似函数特殊值规则],
)[
  | 输入 `x`      | `exp2_approx`  | `rcp_approx`  | `rsqrt_approx`  |
  | :-----------: | :------------: | :-----------: | :-------------: |
  | NaN           | NaN            | NaN           | NaN             |
  | $+infinity$   | $+infinity$    | $+0$          | $+0$            |
  | $-infinity$   | $+0$           | $-0$          | NaN             |
  | $+0$          | $1$            | $+infinity$   | $+infinity$     |
  | $-0$          | $1$            | $-infinity$   | $-infinity$     |
  | 有限 $x < 0$  | 按定义         | 按定义        | NaN             |
]

== 向量广播 <elementwise-bcast>

矩阵目的 D 与矩阵源 A 遵循逐元素公共约束 (同域, 同 dtype, 同有效 shape); 向量源 S 的 dtype 与矩阵相同, 按行广播时 `len(S)` 等于 `rows(D)`, 按列广播时等于 `cols(D)`.

=== 按行广播

Tile 使用 Vec8, Acc 使用 Vec32; 向量的第 i 个元素广播到矩阵第 i 行.

向量广播使用 R3 格式; `EW` 选择 8-bit/32-bit 寄存器组合, `DIR` 选择按行/按列:

#rivet-encoding-figure(e-bcast-schema, caption: [向量广播格式 (E_BCAST)])

#instruction-table(
  columns: (1.2fr, 0.5fr, 2fr, 2fr),
  caption: [向量按行广播指令],
)[
  | Instruction    | Format  | Operation                   | Summary                        |
  | :------------: | :-----: | --------------------------- | ------------------------------ |
  | `taddb.byrow`  | R3      | D[i,j] = A[i,j] + S[i]      | 向量按行广播加法.              |
  | `tsubb.byrow`  | R3      | D[i,j] = A[i,j] - S[i]      | 向量按行广播减法.              |
  | `tminb.byrow`  | R3      | D[i,j] = min(A[i,j], S[i])  | 向量按行广播取小.              |
  | `tmaxb.byrow`  | R3      | D[i,j] = max(A[i,j], S[i])  | 向量按行广播取大.              |
  | `tandb.byrow`  | R3      | D[i,j] = A[i,j] and S[i]    | 向量按行广播按位与.            |
  | `torb.byrow`   | R3      | D[i,j] = A[i,j] or S[i]     | 向量按行广播按位或.            |
  | `txorb.byrow`  | R3      | D[i,j] = A[i,j] xor S[i]    | 向量按行广播按位异或.          |
  | `tshlb.byrow`  | R3      | D[i,j] = shl(A[i,j], S[i])  | 向量按行广播左移.              |
  | `tshrb.byrow`  | R3      | D[i,j] = shr(A[i,j], S[i])  | 向量按行广播逻辑右移.          |
  | `tsrab.byrow`  | R3      | D[i,j] = sra(A[i,j], S[i])  | 向量按行广播算术右移.          |
  | `aaddv.byrow`  | R3      | D[i,j] = A[i,j] + S[i]      | 向量按行广播加法.              |
  | `asubv.byrow`  | R3      | D[i,j] = A[i,j] - S[i]      | 向量按行广播减法.              |
  | `amulv.byrow`  | R3      | D[i,j] = A[i,j] × S[i]      | 向量按行广播乘法.              |
  | `adivv.byrow`  | R3      | D[i,j] = A[i,j] / S[i]      | 向量按行广播除法; 仅 f32.      |
  | `aminv.byrow`  | R3      | D[i,j] = min(A[i,j], S[i])  | 向量按行广播取小.              |
  | `amaxv.byrow`  | R3      | D[i,j] = max(A[i,j], S[i])  | 向量按行广播取大.              |
  | `aandv.byrow`  | R3      | D[i,j] = A[i,j] and S[i]    | 向量按行广播按位与.            |
  | `aorv.byrow`   | R3      | D[i,j] = A[i,j] or S[i]     | 向量按行广播按位或.            |
  | `axorv.byrow`  | R3      | D[i,j] = A[i,j] xor S[i]    | 向量按行广播按位异或.          |
  | `ashlv.byrow`  | R3      | D[i,j] = shl(A[i,j], S[i])  | 向量按行广播左移; 仅整数.      |
  | `ashrv.byrow`  | R3      | D[i,j] = shr(A[i,j], S[i])  | 向量按行广播逻辑右移; 仅整数.  |
  | `asrav.byrow`  | R3      | D[i,j] = sra(A[i,j], S[i])  | 向量按行广播算术右移; 仅整数.  |
]

Tile 使用 Vec8 作为每一行的标量源:

```asm
topb.byrow tD, tA, bS
```

Acc/Vec32 使用 Vec32 作为每一行的标量源:

```asm
aopv.byrow aD, aA, vS
```

执行语义为:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← op(A[i,j], S[i])
```

例如:

```asm
amulv.byrow a0, a1, v0
```

表示:

$ "a0"_(i,j) = "a1"_(i,j) "v0"_i $

=== 按列广播

Tile 使用 Vec8, Acc 使用 Vec32; 向量的第 j 个元素广播到矩阵第 j 列.

#instruction-table(
  columns: (1.2fr, 0.5fr, 2fr, 2fr),
  caption: [向量按列广播指令],
)[
  | Instruction    | Format  | Operation                   | Summary                        |
  | :------------: | :-----: | --------------------------- | ------------------------------ |
  | `taddb.bycol`  | R3      | D[i,j] = A[i,j] + S[j]      | 向量按列广播加法.              |
  | `tsubb.bycol`  | R3      | D[i,j] = A[i,j] - S[j]      | 向量按列广播减法.              |
  | `tminb.bycol`  | R3      | D[i,j] = min(A[i,j], S[j])  | 向量按列广播取小.              |
  | `tmaxb.bycol`  | R3      | D[i,j] = max(A[i,j], S[j])  | 向量按列广播取大.              |
  | `tandb.bycol`  | R3      | D[i,j] = A[i,j] and S[j]    | 向量按列广播按位与.            |
  | `torb.bycol`   | R3      | D[i,j] = A[i,j] or S[j]     | 向量按列广播按位或.            |
  | `txorb.bycol`  | R3      | D[i,j] = A[i,j] xor S[j]    | 向量按列广播按位异或.          |
  | `tshlb.bycol`  | R3      | D[i,j] = shl(A[i,j], S[j])  | 向量按列广播左移.              |
  | `tshrb.bycol`  | R3      | D[i,j] = shr(A[i,j], S[j])  | 向量按列广播逻辑右移.          |
  | `tsrab.bycol`  | R3      | D[i,j] = sra(A[i,j], S[j])  | 向量按列广播算术右移.          |
  | `aaddv.bycol`  | R3      | D[i,j] = A[i,j] + S[j]      | 向量按列广播加法.              |
  | `asubv.bycol`  | R3      | D[i,j] = A[i,j] - S[j]      | 向量按列广播减法.              |
  | `amulv.bycol`  | R3      | D[i,j] = A[i,j] × S[j]      | 向量按列广播乘法.              |
  | `adivv.bycol`  | R3      | D[i,j] = A[i,j] / S[j]      | 向量按列广播除法; 仅 f32.      |
  | `aminv.bycol`  | R3      | D[i,j] = min(A[i,j], S[j])  | 向量按列广播取小.              |
  | `amaxv.bycol`  | R3      | D[i,j] = max(A[i,j], S[j])  | 向量按列广播取大.              |
  | `aandv.bycol`  | R3      | D[i,j] = A[i,j] and S[j]    | 向量按列广播按位与.            |
  | `aorv.bycol`   | R3      | D[i,j] = A[i,j] or S[j]     | 向量按列广播按位或.            |
  | `axorv.bycol`  | R3      | D[i,j] = A[i,j] xor S[j]    | 向量按列广播按位异或.          |
  | `ashlv.bycol`  | R3      | D[i,j] = shl(A[i,j], S[j])  | 向量按列广播左移; 仅整数.      |
  | `ashrv.bycol`  | R3      | D[i,j] = shr(A[i,j], S[j])  | 向量按列广播逻辑右移; 仅整数.  |
  | `asrav.bycol`  | R3      | D[i,j] = sra(A[i,j], S[j])  | 向量按列广播算术右移; 仅整数.  |
]

Tile 使用 Vec8 作为每一列的标量源:

```asm
topb.bycol tD, tA, bS
```

Acc/Vec32 使用 Vec32 作为每一列的标量源:

```asm
aopv.bycol aD, aA, vS
```

执行语义为:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← op(A[i,j], S[j])
```

例如:

```asm
amulv.bycol a0, a1, v0
```

表示:

$ "a0"_(i,j) = "a1"_(i,j) "v0"_j $

`bycol` 是逻辑列广播. 硬件可以按行读取矩阵, 然后在每个 lane 上选择 `S[j]`.

== 比较指令 <elementwise-cmp>

条件取独立子集: 整数为 `eq/ne/lt/ge`, `gt` 与 `le` 由交换两个源操作数获得; f32 为 `eq/lt/le/unord`, `ord` 由 `unord` 结果取反获得, `ne` 由 `eq` 结果取反获得. 比较只在 Acc 与 Vec32 上定义, 分寄存器和 Scalar 两种形式; 目的为同宽 mask, 真为全一, 假为零 (见前言 `M` 记号).

比较使用 R4 格式, `BX` 选择第二源为同域寄存器或 Scalar; mask 目的为 `M5` 槽位:

#rivet-encoding-figure(e-cmp-schema, caption: [比较格式 (E_CMP)])

#instruction-table(
  columns: (1.3fr, 0.5fr, 2fr, 2fr),
  caption: [比较指令],
)[
  | Instruction        | Format  | Operation                     | Summary                         |
  | :----------------: | :-----: | ----------------------------- | ------------------------------- |
  | `{a,v}cmp.eq`      | R4      | D[p] = A[p] == B[p]           | 同域右源相等比较.               |
  | `{a,v}cmp.ne`      | R4      | D[p] = A[p] != B[p]           | 同域右源不等比较; 仅整数.       |
  | `{a,v}cmp.lt`      | R4      | D[p] = A[p] < B[p]            | 同域右源小于比较.               |
  | `{a,v}cmp.ge`      | R4      | D[p] = A[p] >= B[p]           | 同域右源大于等于比较; 仅整数.   |
  | `{a,v}cmp.le`      | R4      | D[p] = A[p] <= B[p]           | 同域右源小于等于比较; 仅 f32.   |
  | `{a,v}cmp.unord`   | R4      | D[p] = unordered(A[p], B[p])  | 同域右源浮点无序比较.           |
  | `{a,v}cmpx.eq`     | R4      | D[p] = A[p] == xS             | Scalar 值相等比较.              |
  | `{a,v}cmpx.ne`     | R4      | D[p] = A[p] != xS             | Scalar 值不等比较; 仅整数.      |
  | `{a,v}cmpx.lt`     | R4      | D[p] = A[p] < xS              | Scalar 值小于比较.              |
  | `{a,v}cmpx.ge`     | R4      | D[p] = A[p] >= xS             | Scalar 值大于等于比较; 仅整数.  |
  | `{a,v}cmpx.le`     | R4      | D[p] = A[p] <= xS             | Scalar 值小于等于比较; 仅 f32.  |
  | `{a,v}cmpx.unord`  | R4      | D[p] = unordered(A[p], xS)    | Scalar 值浮点无序比较.          |
]

比较指令产生 mask 数据:

```asm
acmp.COND   aM, aA, aB
vcmp.COND   vM, vA, vB
```

Scalar 形式为:

```asm
acmpx.COND  aM, aA, xS
vcmpx.COND  vM, vA, xS
```

整数条件为 `eq/ne/lt/ge`; f32 条件为 `eq/lt/le/unord`; 其余条件由交换操作数或对 mask 取反获得.

比较结果定义为:

```text
true  → u32 lane 为 0xffffffff
false → 0
```

对于矩阵比较:

```text
for 0 <= i < rows(D):
    for 0 <= j < cols(D):
        D[i,j] ← predicate(A[i,j], B[i,j])
```

对于向量比较:

```text
for 0 <= j < len(D):
    D[j] ← predicate(A[j], B[j])
```

比较目的寄存器的 dtype 应是 `u32`.

== Select 指令 <elementwise-select>

#instruction-table(
  columns: (1fr, 0.5fr, 2fr, 2.1fr),
  caption: [选择指令],
)[
  | Instruction    | Format  | Operation                          | Summary                         |
  | :------------: | :-----: | ---------------------------------- | ------------------------------- |
  | `tselect`      | R4      | D[i,j] = M[i,j] ? A[i,j] : B[i,j]  | mask 非零时选择 A, 否则选择 B.  |
  | `{a,v}select`  | R4      | D[p] = M[p] ? A[p] : B[p]          | mask 非零时选择 A, 否则选择 B.  |
]

select 按位选择, 与元素 dtype 无关: 根据 mask 在两个已经计算好的值之间选择 (t 数据使用 `u8` mask, a/v 数据使用 `u32` mask). mask 通常由 `cmp` 产生; Tile 域没有比较指令, 位置型 mask 可由 `tmask.*` 合成 (以零 Tile 为源, fill 取 $-1$ 即全一).

```asm
tselect tD, tM, tA, tB
aselect aD, aM, aA, aB
vselect vD, vM, vA, vB
```

执行语义为:

```text
if M[p] != 0:
    D[p] ← A[p]
else:
    D[p] ← B[p]
```

select 必须读取两个数据源: M 为 true 时选择 A; M 为 false 时选择 B; A 和 B 都是已经计算好的架构数据.

== Mask 指令 <elementwise-mask>

mask 使用寄存器配置中的 dtype; 它在目的有效区域内改写数据值, 保留区域之外写入显式 fill 值; 有效区域之外的物理位置保持原值.

mask 使用 R4 格式; `[16:12]` 为 fill, `FS` 选择其来源 (立即数 `fill5` 或 Scalar `xFill`); `[21:17]` 为 Scalar 边界 `xBound`, 按操作解释为 `xBounds`, `xLen` 或 `xDelta`:

#rivet-encoding-figure(e-mask-schema, caption: [mask 格式 (E_MASK)])

#instruction-table(
  columns: (1fr, 0.5fr, 2fr, 2fr),
  caption: [Mask 指令],
)[
  | Instruction        | Format  | Operation                                          | Summary                                                   |
  | :----------------: | :-----: | -------------------------------------------------- | --------------------------------------------------------- |
  | `{t,a}mask.tail`   | R4      | D[i,j] = (i < nRows && j < nCols) ? S[i,j] : fill  | 保留行列坐标小于 `xBounds` 中 `nRows`, `nCols` 的源元素.  |
  | `{t,a}mask.tril`   | R4      | D[i,j] = (j - i <= xDelta) ? S[i,j] : fill         | 保留满足 $j-i <= "xDelta"$ 的源元素.                      |
  | `{t,a}mask.triu`   | R4      | D[i,j] = (j - i >= xDelta) ? S[i,j] : fill         | 保留满足 $j-i >= "xDelta"$ 的源元素.                      |
  | `{b,v}mask.tail`   | R4      | D[j] = (j < xLen) ? S[j] : fill                    | 保留 lane 索引小于 xLen 的源元素.                         |
  | `{t,a}maskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                | fill 由 Scalar `xFill` 提供, 可为任意值.                  |
  | `{t,a}maskx.tril`  | R4      | 同 `mask.tril`, fill 由 Scalar 提供                | fill 由 Scalar `xFill` 提供, 可为任意值.                  |
  | `{t,a}maskx.triu`  | R4      | 同 `mask.triu`, fill 由 Scalar 提供                | fill 由 Scalar `xFill` 提供, 可为任意值.                  |
  | `{b,v}maskx.tail`  | R4      | 同 `mask.tail`, fill 由 Scalar 提供                | fill 由 Scalar `xFill` 提供, 可为任意值.                  |
]

mask 指令将源数据的某些位置替换为指定 fill 值. `mask` 的 fill 为 5-bit 立即数编码 `fill5`, 按下表解码后转换为目的 dtype; `maskx` 的 fill 由 Scalar 寄存器提供, 可为任意值.

#manual-table(
  columns: (1fr, 1fr, 3fr),
  caption: [fill5 常量码表],
)[
  | `fill5`  | 常量         | 说明         |
  | -------- | ------------ | ------------ |
  | `00000`  | $+0$         |              |
  | `00001`  | $+1$         |              |
  | `00010`  | $-1$         |              |
  | `00011`  | $+2$         |              |
  | `00100`  | $-2$         |              |
  | `00101`  | $+0.5$       | 仅 f32 目的  |
  | `00110`  | $-0.5$       | 仅 f32 目的  |
  | `00111`  | $+infinity$  | 仅 f32 目的  |
  | `01000`  | $-infinity$  | 仅 f32 目的  |
  | 其余     | —            | 保留         |
]

整数目的只使用 `00000..00100`; $plus.minus 0.5$ 与 $plus.minus infinity$ 仅在目的 dtype 为 `f32` 时有效.

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

=== 公共语义

所有 mask 指令在目的有效区域内按同一规则执行:

```text
D[p] ← keep(p) ? S[p] : fill
```

矩阵形式遍历 `rows(D) × cols(D)`, 向量形式遍历 `len(D)`. `keep` 由指令决定:

#manual-table(
  columns: (1.4fr, 3fr),
  inset: 3.5pt,
  caption: [Mask 保留条件],
)[
  | 指令              | `keep`                    |
  | ----------------- | ------------------------- |
  | `{t,a}mask.tail`  | `i < nRows && j < nCols`  |
  | `{t,a}mask.tril`  | `j - i <= xDelta`         |
  | `{t,a}mask.triu`  | `j - i >= xDelta`         |
  | `{b,v}mask.tail`  | `j < xLen`                |
]

`mask` 的 fill 来自 `fill5`, `maskx` 的 fill 来自 Scalar `xFill`; 两者的 `keep` 条件相同. 矩阵 tail 的 `nRows`, `nCols` 取自打包寄存器 `xBounds` 的低, 高 32 bit; 向量 tail 的 `xLen` 和三角 mask 的 `xDelta` 为 Scalar 值.

三角 mask 的边界相等时保留元素. 例如 `xDelta = 0` 对 `tril` 保留主对角线及其下方元素, 对 `triu` 保留主对角线及其上方元素; `xDelta = 1` 对 `tril` 额外保留主对角线上方一条对角线.

== 示例

=== Attention score 的 causal mask

```asm
amask.tril aScore, aScore, xDelta, -inf
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
vsub       v0, vScore, vMax
vmul       v1, v0, vLog2e
vexp2.approx   v2, v1
vdiv       vOut, v2, vSum
```

= 规约与类型转换 <reduction-conversion>

本节定义矩阵规约, 向量规约, Scalar 规约, 数据类型转换和低精度扩大转换. 规约指令将多个元素合并为一个或多个结果.

== 规约指令格式

行规约每行产生一个 Vec32 元素. 除基础 `sum/max/min` 外, 行规约还定义了 `sumsq`, `absmax` 与 `argmax`; 向量规约另含 f32 `sumsq` 与 `argmax`.

#instruction-table(caption: [规约指令])[
  | Instruction            | Format  | Operation                                                                     | Summary                                         |
  | :--------------------: | :-----: | ----------------------------------------------------------------------------- | ----------------------------------------------- |
  | `areduce.rows.sum`     | R2      | $"vD"[i] = sum_j "aS"[i,j]$                                                   | 将 Acc 按行求和到 Vec32.                        |
  | `areduce.rows.max`     | R2      | $"vD"[i] = max_j "aS"[i,j]$                                                   | 将 Acc 按行取最大到 Vec32.                      |
  | `areduce.rows.min`     | R2      | $"vD"[i] = min_j "aS"[i,j]$                                                   | 将 Acc 按行取最小到 Vec32.                      |
  | `areduce.rows.sumsq`   | R2      | $"vD"[i] = sum_j "aS"[i,j]^2$                                                 | 将 Acc 每行有效元素的平方和写入 Vec32.          |
  | `areduce.rows.absmax`  | R2      | $"vD"[i] = max_j abs("aS"[i,j])$                                              | 将 Acc 每行有效元素的绝对值最大写入 Vec32.      |
  | `areduce.rows.argmax`  | R2      | $"vD"[i] = op("argmax")_j "aS"[i,j]$                                          | 将 Acc 每行最大值的局部列号写入 Vec32.          |
  | `vreduce.sum`          | R2      | $"xD" = sum_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 求和到 Scalar.         |
  | `vreduce.max`          | R2      | $"xD" = max_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 取最大到 Scalar.       |
  | `vreduce.min`          | R2      | $"xD" = min_j "vS"[j]$                                                        | 将 f32 Vec32 的有效 lane 取最小到 Scalar.       |
  | `vreduce.sumsq`        | R2      | $"xD" = sum_j "vS"[j]^2$                                                      | 将 f32 Vec32 的有效 lane 平方和到 Scalar.       |
  | `vreduce.argmax`       | R4      | $"xIndex" = op("argmax")_j "vS"[j]$ #linebreak() $"xValue" = "vS"["xIndex"]$  | 输出最大值的逻辑索引与浮点位模式到两个 Scalar.  |
]

普通单目的规约使用 R2 格式:

#rivet-encoding-figure(red-schema, caption: [规约格式 (AREDUCE/VREDUCE)])

`vreduce.argmax` 使用 R4 双目的变体, 写两个 Scalar 目的寄存器:

#rivet-encoding-figure(
  vreduce-argmax-schema,
  caption: [argmax 格式 (VREDUCE, R4 双目的变体)],
)

基础矩阵规约形式为:

```asm
areduce.rows.OP   vD, aS
```

其中$"OP" in {"sum", "max", "min", "sumsq", "absmax", "argmax"}$

```asm
areduce.rows.sum    vD, aS
areduce.rows.max    vD, aS
areduce.rows.min    vD, aS
areduce.rows.sumsq  vD, aS
areduce.rows.absmax vD, aS
areduce.rows.argmax vD, aS
```

向量到 Scalar 的规约形式为:

```asm
vreduce.sum       xD, vS
vreduce.max       xD, vS
vreduce.min       xD, vS
vreduce.sumsq     xD, vS
vreduce.argmax    xIndex, xValue, vS
```

== 矩阵按行规约 <reduce-areduce>

=== `areduce.rows.*`

源 Acc 的有效 shape 为:

$
  R & = op("rows")("aS") \
  C & = op("cols")("aS")
$

目的 Vec32 须满足:

$
  op("len")("vD") & = R
$

除 `argmax` 外, 行规约对每一行的有效元素执行固定的相邻二叉树规约. `sum` 与 `sumsq` 的每个加法节点都执行一次 binary32 round-to-nearest, ties-to-even (RNE) 舍入. 树的定义如下:

```text
tree_reduce(nodes, pair_op):
    level ← nodes
    while length(level) > 1:
        next ← []
        for 0 <= k and 2*k+1 < length(level):
            next.append(pair_op(level[2*k], level[2*k+1]))
        if length(level) is odd:
            next.append(level[length(level)-1])
        level ← next
    return level[0]
```

每一层从左到右合并相邻节点; 奇数个节点时, 最右节点不参与本层运算, 原样直通到下一层. 有效 shape 非空, 因此 `tree_reduce` 总能返回一个元素.

`sum`, `max`, `min` 和 `sumsq` 对应的规约表达式如下表所示.

#manual-table(
  columns: (1.2fr, 3fr),
  inset: 3.5pt,
  caption: [行规约操作],
)[
  | 指令                   | 规约表达式                                        |
  | ---------------------- | ------------------------------------------------- |
  | `areduce.rows.sum`     | `tree_reduce(row, add_f32_rne)`                   |
  | `areduce.rows.max`     | `tree_reduce(row, pair_max)`                      |
  | `areduce.rows.min`     | `tree_reduce(row, pair_min)`                      |
  | `areduce.rows.sumsq`   | `tree_reduce([round_f32(x_j^2)]_j, add_f32_rne)`  |
  | `areduce.rows.absmax`  | `tree_reduce([absmax_leaf(x_j)]_j, pair_max)`     |
]

`pair_max` 和 `pair_min` 的比较规则为: 一方为 NaN 时返回另一方, 两方均为 NaN 时返回左操作数; 两方均为数值且比较结果相等时, `max` 在 `+0` 与 `-0` 中返回 `+0`, `min` 返回 `-0`, 其他相等值返回左操作数.

`absmax` 的每个叶先经过 `absmax_leaf(x)` 映射: NaN 视为 `+0`, 其他值取绝对值; 然后对有效叶执行 `pair_max`. 因此单元素、`-0` 和全 NaN 的 `absmax` 都得到非负结果.

`areduce.rows.argmax` 每行取最大值, 目的 `vD` 的 dtype 为 `i32`, 值为该行最大值的有效局部列号; 并列取较小索引, NaN 选择规则与 `vreduce.argmax` 一致:

```text
for 0 <= i < R:
    (best_index, best_value) ← argmax_tree((j, aS[i,j]) for 0 <= j < C)
    vD[i] ← best_index
```

`argmax_tree` 使用与上文相同的相邻二叉树和奇数节点直通规则. 两个候选比较时, NaN 胜过非 NaN, 两个 NaN 取左操作数; 两个数值中较大者胜出, 数值相等时取较小的逻辑索引.

== 向量到 Scalar 的规约 <reduce-vreduce>

=== Vec32 浮点规约

对于:

```asm
vreduce.sum   xD, vS
vreduce.max   xD, vS
vreduce.min   xD, vS
vreduce.sumsq xD, vS
```

设$N = op("len")("vS")$

源 `vS` 必须$op("dtype")("vS") = "f32"$. 结果的 f32 位模式写入 `xD` 的低 32 bit, 高 32 bit 清零.

`vreduce` 对 `vS[0..N-1]` 使用上文定义的相邻二叉树. `sum`, `max`, `min` 和 `sumsq` 对应的规约表达式如下表所示.

#manual-table(
  columns: (1fr, 3fr),
  inset: 3.5pt,
  caption: [向量规约操作],
)[
  | 指令             | 规约表达式                                        |
  | ---------------- | ------------------------------------------------- |
  | `vreduce.sum`    | `tree_reduce(vS, add_f32_rne)`                    |
  | `vreduce.max`    | `tree_reduce(vS, pair_max)`                       |
  | `vreduce.min`    | `tree_reduce(vS, pair_min)`                       |
  | `vreduce.sumsq`  | `tree_reduce([round_f32(vS[j]^2)], add_f32_rne)`  |
]

== Argmax <reduce-argmax>

```asm
vreduce.argmax xIndex, xValue, vS
```

将 `f32` Vec32 的有效 lane 取最大值, 输出其逻辑索引与浮点位模式到两个 Scalar.

约束: 源 `vS` 的 dtype 须为 `f32`. 两个输出的解释为:

```text
xIndex: 最大值的逻辑索引, i32 语义, 符号扩展到 64 bit
xValue: 最大值的 f32 位模式, 写入低 32 bit, 高 32 bit 清零
```

操作:

```text
(xIndex, xValue) ← argmax_tree((j, vS[j]) for 0 <= j < len(vS))
```

`argmax_tree` 的 NaN, 相等值, `+0`/`-0`, 奇数节点直通和树拓扑规则与行规约中的定义完全相同. 因而 NaN 候选胜过非 NaN, 两个 NaN 取较小逻辑索引, 数值相等时也取较小逻辑索引.

如果算子需要忽略显式 mask 的位置, 不能只依赖 `-inf` 填充. 因为真实输入也可能是 `-inf`, 而且填充位置仍属于当前有效 Vector shape.

正确做法是缩短 `vS.len`; 或保留显式候选有效性; 或使用带有效性输入的专用 argmax 展开.

== 类型转换指令 <reduce-cvt>

#instruction-table(
  columns: (1fr, 0.5fr, 2fr, 2fr),
  caption: [类型转换与扩大指令],
)[
  | Instruction      | Format  | Operation                    | Summary                                   |
  | :--------------: | :-----: | ---------------------------- | ----------------------------------------- |
  | `acvt.i32.f32`   | R2      | aD[i,j] = f32(aS[i,j])       | 将 Acc 中的 `i32` 逐元素转为 `f32`.       |
  | `vcvt.i32.f32`   | R2      | vD[j] = f32(vS[j])           | 将 Vec32 中的 `i32` 逐 lane 转为 `f32`.   |
  | `twiden.i8.i32`  | R2      | aD[i,j] = sign_ext(tS[i,j])  | 将 Tile 的 `i8` 符号扩展到 Acc 的 `i32`.  |
]

类型转换与扩大使用 R2 格式; `dom2` 选择目的数据域:

#rivet-encoding-figure(cvt-schema, caption: [类型转换与扩大格式 (CVT)])

源与目的的寄存器配置必须合法且有效 shape 相同; `acvt`/`vcvt` 要求源与目的 dtype 均为 `i32`, 成功接收后目的 dtype 更新为 `f32`; `twiden` 要求源 Tile dtype 为 `i8`, 目的 Acc dtype 为 `i32`.

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
for 0 <= i < rows(aD):
    for 0 <= j < cols(aD):
        aD[i,j] ← f32(aS[i,j])
```

`vcvt` 操作:

```text
for 0 <= j < len(vD):
    vD[j] ← f32(vS[j])
```

`acvt` 和 `vcvt` 都允许原地使用:

```asm
acvt.i32.f32 a0, a0
vcvt.i32.f32 v0, v0
```

原地转换必须先读取源元素, 再写回目的元素. 目的 dtype 在该转换操作被成功接收时更新; 后续消费者按照新的 dtype 等待结果, 已经被接收的旧消费者仍按照转换前的源 dtype 执行.

== Tile 到 Acc 的扩大转换 <reduce-widen>

```asm
twiden.i8.i32 aD, tS
```

将 Tile 的 `i8` 符号扩展到 Acc 的 `i32`. 跨数据域, 不能原地执行; 目的 Acc 的有效 shape 与源 Tile 相同.

操作:

```text
for 0 <= i < rows(tS):
    for 0 <= j < cols(tS):
        aD[i,j] ← sign_ext(tS[i,j])
```

== 示例

=== RMSNorm 行规约

```asm
areduce.rows.sumsq vSumSq, aX
vrsqrt.approx         vInv, vSumSq
amulv.byrow       aY, aX, vInv
```

其逻辑含义为:

$
  "vSumSq"_i & = sum_(j=0)^(op("cols")("aX")-1) ("aX"_(i,j))^2 \
    "vInv"_i & = op("rsqrt.approx")("vSumSq"_i) \
  "aY"_(i,j) & = "aX"_(i,j) "vInv"_i
$

如果需要加 epsilon, 应先执行显式的 Vec32 操作:

```asm
vadd vSumSq, vSumSq, vEpsilon
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
amulv.bycol aFloat, aFloat, vScale
```

或使用明确的 scale 乘法指令.

=== Vec8 dot 结果转 `f32`

```asm
bdot.nt.i8.i32 vRaw, bQ, tK
vcvt.i32.f32   vScore, vRaw
vmul       vScore, vScore, vScale
```

这三条指令分别表示:

```text
vRaw   = i8 dot product
vScore = i32 转 f32
vScore = vScore × scale
```

= 量化与反量化 <quantization>

#instruction-table(
  columns: (1.5fr, 0.5fr, 2.5fr, 1.8fr),
  caption: [量化与反量化指令],
)[
  | Instruction                | Format  | Operation                                                                                | Summary                                            |
  | :------------------------: | :-----: | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
  | `tquant.rows.q8s32`        | R4      | tD[i,:] = quant_q8s32(aS[i,:]).bits #linebreak() vScale[i] = quant_q8s32(aS[i,:]).scale  | 将 Acc 按行量化到 Tile, 每行产生一个 Vec32 scale.  |
  | `tquant.rows.scale.q8s32`  | R4      | tD[i,:] = quant_q8s32(aS[i,:], vScale[i]).bits                                           | 用外部 Vec32 scale 将 Acc 按行量化到 Tile.         |
  | `vquant.q8s32`             | R4      | bD = quant_q8s32(vS).bits #linebreak() vScale[lane] = quant_q8s32(vS).scale              | 将 Vec32 量化到 Vec8, 产生一个指定 lane 的 scale.  |
  | `tdequant.rows.f32`        | R4      | aD[i,j] = f32(tS[i,j]) × vScale[i]                                                       | 用每行的 Vec32 scale 将 Tile 反量化到 f32 Acc.     |
  | `bdequant.f32`             | R4      | vD[j] = f32(bS[j]) × vScale[lane]                                                        | 用指定 scale lane 将 Vec8 反量化到 f32 Vec32.      |
]

量化与反量化使用 R4 双目的/双源格式; `vScale` 始终是 Vec32 scale 寄存器, `dom2` 选择主目的数据域, 量化方向随之确定.

矩阵形式的 `[25]` 与 `[16:12]` 为保留位, 必须为 0. `funct3 = 000` 选择动态量化或反量化, `001` 选择外部提供 scale 的行量化 (`tquant.rows.scale.q8s32`, 仅 Tile 目的):

#rivet-encoding-figure(qnt-mat-schema, caption: [矩阵量化与反量化格式 (QNT)])

向量形式使用 `IS[25]` 和 `index5[16:12]` 指定 scale lane, `funct3 = 000`:

#rivet-encoding-figure(qnt-vec-schema, caption: [向量量化与反量化格式 (QNT)])

汇编操作数先列目的, 再列源. 动态量化的 `vScale` 是第二目的; 外部 scale 量化与反量化的 `vScale` 是源, 位于数据源之后.

```asm
tquant.rows.q8s32       tD, vScale, aS
tquant.rows.scale.q8s32 tD, aS, vScale
vquant.q8s32            bD, vScale[lane], vS
tdequant.rows.f32       aD, tS, vScale
bdequant.f32            vD, bS, vScale[lane]
```

矩阵行量化每行产生一个 scale; 向量量化产生一个 scale. bits 和 scale 是两个显式目的/源, 依赖与生命周期必须一起跟踪. `tquant.rows.scale.q8s32` 不重新计算 scale: 每行的 scale 由显式 Vec32 源 `vScale` 提供 (记作 `quant_q8s32(x, s)`), 适用于 scale 已由前序计算 (如运行最大值, 外部校准) 给出的场景, 此时只有 Tile bits 一个目的. 内部动态量化使用具名格式 q8s32, 外部权重保留原始 bits/scale.

约束:

1. 矩阵形式 (`tquant`/`tdequant`): Acc 与 Tile 有效 shape 相同, Tile 操作数 dtype 为 `i8`, Acc 操作数 dtype 为 `f32`; `vScale` dtype 为 `f32` 且 `len` 等于行数.
2. 向量形式 (`vquant`/`bdequant`): 两个数据向量 `len` 相同, Vec8 操作数 dtype 为 `i8`, Vec32 数据操作数 dtype 为 `f32`; `vScale` dtype 为 `f32`, scale lane 号 (`IS` = 0 时为 `index5` 立即数, `IS` = 1 时为由 `index5` 指定的 Scalar 寄存器的值) 必须在 `vScale` 的有效范围内.

`quant_q8s32(x)` 的动态量化定义如下 (`x` 为一行或一个向量的有效元素, 共 $N$ 个):

```text
amax   ← max_j |x_j|               # 与 areduce.rows.absmax 相同的 absmax 树规则
scale  ← amax / 127                # f32 除法
bits_j ← sat_rne(x_j / scale)      # RNE 舍入到整数, 饱和到 [-127, 127];
                                   # x_j / scale 为 NaN 时 bits_j ← 0
```

外部 scale 形式 `quant_q8s32(x, s)` 以给定的 `s` 替换上式中的 `scale`, 不重新计算. `vquant` 的单一 scale 写入 `vScale[index]` 一个 lane; 反量化逐元素计算 `f32(bits_j) × scale` (f32 乘法).

Q8 MMA 是以下基础指令的复合操作, 不隐藏临时 Acc:

```asm
mma.nn.zero.i8.i32 aTmp, tA, tB
acvt.i32.f32       aTmp, aTmp
amulv.byrow    aTmp, aTmp, vAs
amulv.bycol    aTmp, aTmp, vBs
aadd          aOut, aOut, aTmp
```

aOut 预先初始化, aTmp 与 aOut 分开. 每个 K 块分别 scale 后再累加. Decode 对应 `bdot → vcvt → scale → vadd`, raw 临时使用 v.

在 $P V$ 中, 当 `Vscale` 位于规约轴时, 先在 Vec32 中计算:

$ "Pscaled" = P "Vscale" $

再 vquant 到 b, 随后 bdot; 每个 V 维度块从原始 P 重建, 结果只乘 Pscale. 这是需要明确允许量化误差的算法选择, 不是 `f32` $P V$ 的无损替代.

= 指令集清单 <instructions>

本章是全书的指令索引, 按 `Instruction`, `Format` 和章节组织; 每条指令的 Operation 与 Summary 见对应章节. 每行是一个指令形式; 类型参数的多种取值不在这里重复展开.

== 清单说明

元素类型的合法取值以对应章节的每行说明为准; 带固定类型后缀的指令 (如 `acvt.i32.f32`) 直接按该类型解释. 比较条件取独立子集: 整数为 `eq/ne/lt/ge`, f32 为 `eq/lt/le/unord`; 整数的 `gt`/`le` 由交换操作数获得, `ord` 由 `unord` 取反获得.

Scalar 指令集为 RV64IM, 其指令不在本清单. 各类尚未定义的变体均不作为已分配编码处理.

== 标量与同步

详细语义见 @scalar-sync.

#instruction-index(caption: [同步指令清单])[
  | Instruction   | Format  | Section       |
  | :-----------: | :-----: | :------------ |
  | `fence.mem`   | Z       | @scalar-sync  |
  | `fence.sa`    | Z       | @scalar-sync  |
  | `fence.all`   | Z       | @scalar-sync  |
  | `kernel.end`  | Z       | @scalar-sync  |
]

== 配置指令

详细语义见 @configuration.

#instruction-index(caption: [配置指令清单])[
  | Instruction  | Format  | Section    |
  | :----------: | :-----: | :--------- |
  | `cfg.seti`   | I       | @cfg-seti  |
  | `cfg.setx`   | R4      | @cfg-setx  |
  | `cfg.copy`   | R4      | @cfg-copy  |
  | `cfg.get`    | R4      | @cfg-get   |
  | `cfg.setw`   | R4      | @cfg-setw  |
  | `cfg.getw`   | R4      | @cfg-getw  |
]

== 地址与访存指令

详细语义见 @memory.

#instruction-index(caption: [地址与访存指令清单])[
  | Instruction     | Format  | Section      |
  | :-------------: | :-----: | :----------- |
  | `tload`         | R2      | @mem-block   |
  | `tstore`        | R2      | @mem-block   |
  | `tload.row`     | MR      | @mem-row     |
  | `tstore.row`    | MR      | @mem-row     |
  | `tload.gather`  | R2      | @mem-gather  |
  | `bload.gather`  | R2      | @mem-gather  |
  | `vload.gather`  | R2      | @mem-gather  |
  | `aload`         | R2      | @mem-block   |
  | `astore`        | R2      | @mem-block   |
  | `aload.row`     | MR      | @mem-row     |
  | `astore.row`    | MR      | @mem-row     |
  | `bload`         | R2      | @mem-vector  |
  | `bstore`        | R2      | @mem-vector  |
  | `vload`         | R2      | @mem-vector  |
  | `vstore`        | R2      | @mem-vector  |
]

== 填充, 搬运与转置

详细语义见 @data-movement.

#instruction-index(caption: [填充, 搬运与转置指令清单])[
  | Instruction     | Format  | Section         |
  | :-------------: | :-----: | :-------------- |
  | `tfill`         | I       | @fill-instr     |
  | `tfillx`        | R2      | @fill-instr     |
  | `tcopy`         | R2      | @copy-instr     |
  | `afill`         | I       | @fill-instr     |
  | `afillx`        | R2      | @fill-instr     |
  | `acopy`         | R2      | @copy-instr     |
  | `bfill`         | I       | @fill-instr     |
  | `bfillx`        | R2      | @fill-instr     |
  | `bcopy`         | R2      | @copy-instr     |
  | `vfill`         | I       | @fill-instr     |
  | `vfillx`        | R2      | @fill-instr     |
  | `vcopy`         | R2      | @copy-instr     |
  | `tinsert.row`   | R4      | @row-move-tile  |
  | `textract.row`  | R4      | @row-move-tile  |
  | `ainsert.row`   | R4      | @row-move-acc   |
  | `aextract.row`  | R4      | @row-move-acc   |
  | `bextract`      | R4      | @lane-move      |
  | `binsert`       | R4      | @lane-move      |
  | `bbroadcast`    | R4      | @lane-move      |
  | `vextract`      | R4      | @lane-move      |
  | `vinsert`       | R4      | @lane-move      |
  | `vbroadcast`    | R4      | @lane-move      |
  | `ttranspose`    | R2      | @ttranspose     |
]

== 矩阵乘与向量—矩阵乘

详细语义见 @matrix.

#instruction-index(caption: [矩阵乘与点积指令清单])[
  | Instruction           | Format  | Section          |
  | :-------------------: | :-----: | :--------------- |
  | `mma.nn.zero.i8.i32`  | R4      | @matrix-mma      |
  | `mma.nn.acc.i8.i32`   | R4      | @matrix-mma      |
  | `bdot.nn.i8.i32`      | R4      | @matrix-bdot-nn  |
  | `bdot.nn.acc.i8.i32`  | R4      | @matrix-bdot-nn  |
  | `bdot.nt.i8.i32`      | R4      | @matrix-bdot-nt  |
  | `bdot.nt.acc.i8.i32`  | R4      | @matrix-bdot-nt  |
]

== 逐元素, 广播和 mask

详细语义见 @elementwise.

#instruction-index(caption: [Tile 基础逐元素指令清单])[
  | Instruction  | Format  | Section           |
  | :----------: | :-----: | :---------------- |
  | `tadd`       | R3      | @elementwise-ops  |
  | `taddx`      | R3      | @elementwise-ops  |
  | `tsub`       | R3      | @elementwise-ops  |
  | `tsubx`      | R3      | @elementwise-ops  |
  | `tmin`       | R3      | @elementwise-ops  |
  | `tminx`      | R3      | @elementwise-ops  |
  | `tmax`       | R3      | @elementwise-ops  |
  | `tmaxx`      | R3      | @elementwise-ops  |
  | `tand`       | R3      | @elementwise-ops  |
  | `tandx`      | R3      | @elementwise-ops  |
  | `tor`        | R3      | @elementwise-ops  |
  | `torx`       | R3      | @elementwise-ops  |
  | `txor`       | R3      | @elementwise-ops  |
  | `txorx`      | R3      | @elementwise-ops  |
  | `tshl`       | R3      | @elementwise-ops  |
  | `tshlx`      | R3      | @elementwise-ops  |
  | `tshr`       | R3      | @elementwise-ops  |
  | `tshrx`      | R3      | @elementwise-ops  |
  | `tsra`       | R3      | @elementwise-ops  |
  | `tsrax`      | R3      | @elementwise-ops  |
  | `tnot`       | R2      | @elementwise-ops  |
]

#instruction-index(caption: [Acc 基础逐元素指令清单])[
  | Instruction  | Format  | Section           |
  | :----------: | :-----: | :---------------- |
  | `aadd`       | R3      | @elementwise-ops  |
  | `aaddx`      | R3      | @elementwise-ops  |
  | `asub`       | R3      | @elementwise-ops  |
  | `asubx`      | R3      | @elementwise-ops  |
  | `amul`       | R3      | @elementwise-ops  |
  | `amulx`      | R3      | @elementwise-ops  |
  | `adiv`       | R3      | @elementwise-ops  |
  | `adivx`      | R3      | @elementwise-ops  |
  | `amin`       | R3      | @elementwise-ops  |
  | `aminx`      | R3      | @elementwise-ops  |
  | `amax`       | R3      | @elementwise-ops  |
  | `amaxx`      | R3      | @elementwise-ops  |
  | `aand`       | R3      | @elementwise-ops  |
  | `aandx`      | R3      | @elementwise-ops  |
  | `aor`        | R3      | @elementwise-ops  |
  | `aorx`       | R3      | @elementwise-ops  |
  | `axor`       | R3      | @elementwise-ops  |
  | `axorx`      | R3      | @elementwise-ops  |
  | `ashl`       | R3      | @elementwise-ops  |
  | `ashlx`      | R3      | @elementwise-ops  |
  | `ashr`       | R3      | @elementwise-ops  |
  | `ashrx`      | R3      | @elementwise-ops  |
  | `asra`       | R3      | @elementwise-ops  |
  | `asrax`      | R3      | @elementwise-ops  |
  | `anot`       | R2      | @elementwise-ops  |
  | `aabs`       | R2      | @elementwise-ops  |
  | `aneg`       | R2      | @elementwise-ops  |
]

#instruction-index(caption: [Vec32 基础逐元素指令清单])[
  | Instruction  | Format  | Section           |
  | :----------: | :-----: | :---------------- |
  | `vadd`       | R3      | @elementwise-ops  |
  | `vaddx`      | R3      | @elementwise-ops  |
  | `vsub`       | R3      | @elementwise-ops  |
  | `vsubx`      | R3      | @elementwise-ops  |
  | `vmul`       | R3      | @elementwise-ops  |
  | `vmulx`      | R3      | @elementwise-ops  |
  | `vdiv`       | R3      | @elementwise-ops  |
  | `vdivx`      | R3      | @elementwise-ops  |
  | `vmin`       | R3      | @elementwise-ops  |
  | `vminx`      | R3      | @elementwise-ops  |
  | `vmax`       | R3      | @elementwise-ops  |
  | `vmaxx`      | R3      | @elementwise-ops  |
  | `vand`       | R3      | @elementwise-ops  |
  | `vandx`      | R3      | @elementwise-ops  |
  | `vor`        | R3      | @elementwise-ops  |
  | `vorx`       | R3      | @elementwise-ops  |
  | `vxor`       | R3      | @elementwise-ops  |
  | `vxorx`      | R3      | @elementwise-ops  |
  | `vshl`       | R3      | @elementwise-ops  |
  | `vshlx`      | R3      | @elementwise-ops  |
  | `vshr`       | R3      | @elementwise-ops  |
  | `vshrx`      | R3      | @elementwise-ops  |
  | `vsra`       | R3      | @elementwise-ops  |
  | `vsrax`      | R3      | @elementwise-ops  |
  | `vnot`       | R2      | @elementwise-ops  |
  | `vabs`       | R2      | @elementwise-ops  |
  | `vneg`       | R2      | @elementwise-ops  |
]

#instruction-index(caption: [融合乘加指令清单])[
  | Instruction  | Format  | Section           |
  | :----------: | :-----: | :---------------- |
  | `afmadd`     | R4      | @elementwise-fma  |
  | `vfmadd`     | R4      | @elementwise-fma  |
]

#instruction-index(caption: [近似特殊函数指令清单])[
  | Instruction      | Format  | Section              |
  | :--------------: | :-----: | :------------------- |
  | `aexp2.approx`   | R2      | @elementwise-approx  |
  | `arcp.approx`    | R2      | @elementwise-approx  |
  | `arsqrt.approx`  | R2      | @elementwise-approx  |
  | `vexp2.approx`   | R2      | @elementwise-approx  |
  | `vrcp.approx`    | R2      | @elementwise-approx  |
  | `vrsqrt.approx`  | R2      | @elementwise-approx  |
]


#instruction-index(caption: [向量按行广播指令清单])[
  | Instruction    | Format  | Section             |
  | :------------: | :-----: | :------------------ |
  | `taddb.byrow`  | R3      | @elementwise-bcast  |
  | `tsubb.byrow`  | R3      | @elementwise-bcast  |
  | `tminb.byrow`  | R3      | @elementwise-bcast  |
  | `tmaxb.byrow`  | R3      | @elementwise-bcast  |
  | `tandb.byrow`  | R3      | @elementwise-bcast  |
  | `torb.byrow`   | R3      | @elementwise-bcast  |
  | `txorb.byrow`  | R3      | @elementwise-bcast  |
  | `tshlb.byrow`  | R3      | @elementwise-bcast  |
  | `tshrb.byrow`  | R3      | @elementwise-bcast  |
  | `tsrab.byrow`  | R3      | @elementwise-bcast  |
  | `aaddv.byrow`  | R3      | @elementwise-bcast  |
  | `asubv.byrow`  | R3      | @elementwise-bcast  |
  | `amulv.byrow`  | R3      | @elementwise-bcast  |
  | `adivv.byrow`  | R3      | @elementwise-bcast  |
  | `aminv.byrow`  | R3      | @elementwise-bcast  |
  | `amaxv.byrow`  | R3      | @elementwise-bcast  |
  | `aandv.byrow`  | R3      | @elementwise-bcast  |
  | `aorv.byrow`   | R3      | @elementwise-bcast  |
  | `axorv.byrow`  | R3      | @elementwise-bcast  |
  | `ashlv.byrow`  | R3      | @elementwise-bcast  |
  | `ashrv.byrow`  | R3      | @elementwise-bcast  |
  | `asrav.byrow`  | R3      | @elementwise-bcast  |
]

#instruction-index(caption: [向量按列广播指令清单])[
  | Instruction    | Format  | Section             |
  | :------------: | :-----: | :------------------ |
  | `taddb.bycol`  | R3      | @elementwise-bcast  |
  | `tsubb.bycol`  | R3      | @elementwise-bcast  |
  | `tminb.bycol`  | R3      | @elementwise-bcast  |
  | `tmaxb.bycol`  | R3      | @elementwise-bcast  |
  | `tandb.bycol`  | R3      | @elementwise-bcast  |
  | `torb.bycol`   | R3      | @elementwise-bcast  |
  | `txorb.bycol`  | R3      | @elementwise-bcast  |
  | `tshlb.bycol`  | R3      | @elementwise-bcast  |
  | `tshrb.bycol`  | R3      | @elementwise-bcast  |
  | `tsrab.bycol`  | R3      | @elementwise-bcast  |
  | `aaddv.bycol`  | R3      | @elementwise-bcast  |
  | `asubv.bycol`  | R3      | @elementwise-bcast  |
  | `amulv.bycol`  | R3      | @elementwise-bcast  |
  | `adivv.bycol`  | R3      | @elementwise-bcast  |
  | `aminv.bycol`  | R3      | @elementwise-bcast  |
  | `amaxv.bycol`  | R3      | @elementwise-bcast  |
  | `aandv.bycol`  | R3      | @elementwise-bcast  |
  | `aorv.bycol`   | R3      | @elementwise-bcast  |
  | `axorv.bycol`  | R3      | @elementwise-bcast  |
  | `ashlv.bycol`  | R3      | @elementwise-bcast  |
  | `ashrv.bycol`  | R3      | @elementwise-bcast  |
  | `asrav.bycol`  | R3      | @elementwise-bcast  |
]

#instruction-index(caption: [比较指令清单])[
  | Instruction    | Format  | Section           |
  | :------------: | :-----: | :---------------- |
  | `acmp.eq`      | R4      | @elementwise-cmp  |
  | `acmp.ne`      | R4      | @elementwise-cmp  |
  | `acmp.lt`      | R4      | @elementwise-cmp  |
  | `acmp.ge`      | R4      | @elementwise-cmp  |
  | `acmp.le`      | R4      | @elementwise-cmp  |
  | `acmp.unord`   | R4      | @elementwise-cmp  |
  | `acmpx.eq`     | R4      | @elementwise-cmp  |
  | `acmpx.ne`     | R4      | @elementwise-cmp  |
  | `acmpx.lt`     | R4      | @elementwise-cmp  |
  | `acmpx.ge`     | R4      | @elementwise-cmp  |
  | `acmpx.le`     | R4      | @elementwise-cmp  |
  | `acmpx.unord`  | R4      | @elementwise-cmp  |
  | `vcmp.eq`      | R4      | @elementwise-cmp  |
  | `vcmp.ne`      | R4      | @elementwise-cmp  |
  | `vcmp.lt`      | R4      | @elementwise-cmp  |
  | `vcmp.ge`      | R4      | @elementwise-cmp  |
  | `vcmp.le`      | R4      | @elementwise-cmp  |
  | `vcmp.unord`   | R4      | @elementwise-cmp  |
  | `vcmpx.eq`     | R4      | @elementwise-cmp  |
  | `vcmpx.ne`     | R4      | @elementwise-cmp  |
  | `vcmpx.lt`     | R4      | @elementwise-cmp  |
  | `vcmpx.ge`     | R4      | @elementwise-cmp  |
  | `vcmpx.le`     | R4      | @elementwise-cmp  |
  | `vcmpx.unord`  | R4      | @elementwise-cmp  |
]

#instruction-index(caption: [选择指令清单])[
  | Instruction  | Format  | Section              |
  | :----------: | :-----: | :------------------- |
  | `tselect`    | R4      | @elementwise-select  |
  | `aselect`    | R4      | @elementwise-select  |
  | `vselect`    | R4      | @elementwise-select  |
]

#instruction-index(caption: [Mask 指令清单])[
  | Instruction    | Format  | Section            |
  | :------------: | :-----: | :----------------- |
  | `tmask.tail`   | R4      | @elementwise-mask  |
  | `tmask.tril`   | R4      | @elementwise-mask  |
  | `tmask.triu`   | R4      | @elementwise-mask  |
  | `amask.tail`   | R4      | @elementwise-mask  |
  | `amask.tril`   | R4      | @elementwise-mask  |
  | `amask.triu`   | R4      | @elementwise-mask  |
  | `bmask.tail`   | R4      | @elementwise-mask  |
  | `vmask.tail`   | R4      | @elementwise-mask  |
  | `tmaskx.tail`  | R4      | @elementwise-mask  |
  | `tmaskx.tril`  | R4      | @elementwise-mask  |
  | `tmaskx.triu`  | R4      | @elementwise-mask  |
  | `amaskx.tail`  | R4      | @elementwise-mask  |
  | `amaskx.tril`  | R4      | @elementwise-mask  |
  | `amaskx.triu`  | R4      | @elementwise-mask  |
  | `bmaskx.tail`  | R4      | @elementwise-mask  |
  | `vmaskx.tail`  | R4      | @elementwise-mask  |
]

== 规约与类型转换

详细语义见 @reduction-conversion.

#instruction-index(caption: [规约指令清单])[
  | Instruction            | Format  | Section          |
  | :--------------------: | :-----: | :--------------- |
  | `areduce.rows.sum`     | R2      | @reduce-areduce  |
  | `areduce.rows.max`     | R2      | @reduce-areduce  |
  | `areduce.rows.min`     | R2      | @reduce-areduce  |
  | `areduce.rows.sumsq`   | R2      | @reduce-areduce  |
  | `areduce.rows.absmax`  | R2      | @reduce-areduce  |
  | `areduce.rows.argmax`  | R2      | @reduce-areduce  |
  | `vreduce.sum`          | R2      | @reduce-vreduce  |
  | `vreduce.max`          | R2      | @reduce-vreduce  |
  | `vreduce.min`          | R2      | @reduce-vreduce  |
  | `vreduce.sumsq`        | R2      | @reduce-vreduce  |
  | `vreduce.argmax`       | R4      | @reduce-argmax   |
]

#instruction-index(caption: [类型转换与扩大指令清单])[
  | Instruction      | Format  | Section        |
  | :--------------: | :-----: | :------------- |
  | `acvt.i32.f32`   | R2      | @reduce-cvt    |
  | `vcvt.i32.f32`   | R2      | @reduce-cvt    |
  | `twiden.i8.i32`  | R2      | @reduce-widen  |
]

== 量化与反量化

详细语义见 @quantization.

#instruction-index(caption: [量化与反量化指令清单])[
  | Instruction                | Format  | Section        |
  | :------------------------: | :-----: | :------------- |
  | `tquant.rows.q8s32`        | R4      | @quantization  |
  | `tquant.rows.scale.q8s32`  | R4      | @quantization  |
  | `vquant.q8s32`             | R4      | @quantization  |
  | `tdequant.rows.f32`        | R4      | @quantization  |
  | `bdequant.f32`             | R4      | @quantization  |
]
