#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cstddef>
#include <cstdint>

// 张量元素类型
enum class TensorDType : std::uint8_t {
  Int8,
  FP8,
  Int16,
  Int32,
  FP16,
  BF16,
  FP32,
};
enum class TileDType : std::uint8_t {
  Int8,
  FP8,
};
enum class AccDType : std::uint8_t {
  Int16,
  Int32,
  FP16,
  BF16,
  FP32,
};
enum class Vec8DType : std::uint8_t {
  Int8,
  FP8,
};
enum class Vec32DType : std::uint8_t {
  Int16,
  Int32,
  FP16,
  BF16,
  FP32,
};
static constexpr int TILE = 32;
struct Tile;
struct Acc;
struct Vec8;
struct Vec32;
struct Tensor;
// Tile存储8bit数据
// 这四种数据结构都存了各自配置寄存器，访存寄存器与自身数据。在实际使用中，会将成员访问编译为寄存器读写，成员函数也会被编译成对应的npu指令
struct Tile {
  std::byte *data;
  std::array<std::int32_t, 2> stride;
  std::array<std::int32_t, 2> valid_zone;
  TileDType dtype;
  std::byte *base; // 表示tile中真正存的数据；
  void gather_from_vec(
      const Tensor &tensor,
      Vec32 &index); // 从Tensor中由vec进行索引加载进base，主要用于embedding
  void load();       // 从data中加载数据进base
  void store();      // 从base中向data存入数据
  void fill(std::int8_t v); // base 全部填充为 v（padding 等）
  void matmul(
      Tile &left, Acc &acc, bool zero, bool lt,
      bool
          rt); // 矩阵乘，zero表示需不需要累加，lt，rt表示两个操作数需不需要转置，调用方为右矩阵
  void dequant(
      Vec32 &scale,
      bool col =
          true); // 反量化，col=true代表矩阵一行乘以向量对应元素，false代表一行乘以整个向量
};
// Acc存储16bit/32bit数据
struct Acc {
  std::byte *data;
  std::array<std::int32_t, 2> stride;
  std::array<std::int32_t, 2> valid_zone;
  AccDType dtype;
  std::byte *base; // 表示acc中真正存的数据
  void load();     // 从data中加载数据进base
  void store();    // 从base中向data存入数据
  void fill(float v); // base 全部填充为 v（mask 快速路径、清零）
  // 生成对角 mask：c - r > diag（对角线右上方）或 c ≥ valid_zone[1]（本 tile 越界
  // 列）的位置填 v_mask，其余填 0；diag = 行起点 − 列起点。
  // 快速路径：diag ≥ 31 时全 0、diag ≤ -32 时全 mask（fill 即可），
  // 仅对角线附近的 tile 需要本指令
  void mask(std::int32_t diag, float v_mask = -3.402823466e+38F);
  void quant(Vec32 &max, Tile &tile);
  void add(const Acc &b); // this += b（in-place，供累加循环使用）
  void sub(const Acc &b); // this -= b
  void mul(const Acc &b); // this *= b
  void div(const Acc &b); // this /= b
  void add(float s);      // this += s（标量广播）
  void mul(float s);      // this *= s（per-tensor scale）
  void abs();             // this = |this|（量化前）
  void exp();             // this = e^this（softmax）
  void silu();            // this = this·sigmoid(this)（SwiGLU 的 gate 激活）
  void sin();             // this = sin(this)（rope 造表等）
  void cos();             // this = cos(this)
  // 与 Vec32 的广播运算：col=true 时第 r 行与 v[r] 运算；col=false 时所有行
  // 按列与 v[c] 逐元素运算（语义对齐 Tile::dequant 的 col 参数）
  void add(const Vec32 &v, bool col = true); // 加偏置（per-channel: col=false）
  void sub(const Vec32 &v, bool col = true); // softmax 减行最大值
  void mul(const Vec32 &v,
           bool col = true); // 反量化 scale / online softmax 行修正
  void div(const Vec32 &v, bool col = true); // softmax 除以行和
  // 行归约：每行归约出一个值，组成 32 宽向量
  Vec32 row_max() const;    // 每行最大值（softmax / 量化）
  Vec32 row_sum() const;    // 每行求和（softmax 归一 / 均值）
  Vec32 row_sum_sq() const; // 每行平方和（RMSNorm 的 Σx²）
  Vec32 row_absmax() const; // 每行绝对值最大（量化 scale）
  // 带向量参数的归约版本：每行结果与 v 合并后写回 v（跨 tile 循环维护运行值）
  void row_max(Vec32 &v) const;    // v[r] = max(v[r], 第r行最大值)
  void row_sum(Vec32 &v) const;    // v[r] += 第r行求和
  void row_sum_sq(Vec32 &v) const; // v[r] += 第r行平方和
  void row_absmax(Vec32 &v) const; // v[r] = max(v[r], 第r行绝对值最大)
  // 每行最大值的列索引（tile 内局部列号 0~31）
  Vec32 row_argmax() const;
  // 跨 tile 合并 argmax：本 tile 第 r 行最大值若超过 max_val[r]，更新
  // max_val[r]， 并把全局列号 col_base + 局部列号写入
  // idx[r]（贪心解码在词表上循环合并）
  void row_argmax(Vec32 &max_val, Vec32 &idx, std::int32_t col_base) const;
};
// Vec8存储8bit数据
struct Vec8 {
  std::byte *data;
  int32_t stride;
  int32_t valid_zone;
  Vec8DType dtype;
  std::byte *base; // 表示vec中真正存的数据
  void gather_from_vec(
      const Tensor &tensor,
      Vec32 &index); // 从Tensor中由vec进行索引加载进base，index为元素级索引
  void load();       // 从data中加载数据进base
  void store();      // 从base中向data存入数据
};
// Vec32存储16bit/32bit数据
struct Vec32 {
  std::byte *data;
  int32_t stride;
  int32_t valid_zone;
  Vec32DType dtype;
  std::byte *base; // 表示vec中真正存的数据
  void gather_from_vec(
      const Tensor &tensor,
      Vec32 &index); // 从Tensor中由vec进行索引加载进base，index为元素级索引
  void load();       // 从data中加载数据进base
  void store();      // 从base中向data存入数据
  // ---- 向量运算（in-place；rms/scale/softmax 因子在向量上计算）----
  void add(const Vec32 &b); // this += b
  void sub(const Vec32 &b); // this -= b
  void mul(const Vec32 &b); // this *= b
  void div(const Vec32 &b); // this /= b
  void add(float s);        // this += s
  void mul(float s);        // this *= s
  void rsqrt();             // this = 1/√this（RMSNorm）
  void exp();               // e^x（online softmax 的修正因子）
  void max(const Vec32 &b); // this = max(this, b)（跨 tile 合并行最大值）
  void fill(float v);       // base 全部填充为 v（初始化运行值）
  void copy(const Vec32 &b); // this = b（值拷贝；区别于句柄拷贝导致的 base 共享）
};

// ===== Acc 二元运算（非成员形式）：生成新 Acc =====
// 双目运算符在 C++ 中不要求成员身份；返回值即为"新的 acc"，
// 其 base（指令目的操作数）由编译器分配，对应三操作数 NPU 指令 add dst, a, b
Acc add(const Acc &a, const Acc &b);
Acc sub(const Acc &a, const Acc &b);
Acc mul(const Acc &a, const Acc &b);
Acc div(const Acc &a, const Acc &b);
Acc operator+(const Acc &a, const Acc &b);
Acc operator-(const Acc &a, const Acc &b);
Acc operator*(const Acc &a, const Acc &b);
Acc operator/(const Acc &a, const Acc &b);

// 元素大小（字节）
inline std::size_t elem_size(TensorDType t) {
  switch (t) {
  case TensorDType::Int8:
  case TensorDType::FP8:
    return 1;
  case TensorDType::Int16:
  case TensorDType::FP16:
  case TensorDType::BF16:
    return 2;
  default:
    return 4; // Int32, FP32
  }
}
inline std::size_t elem_size(TileDType) { return 1; }
inline std::size_t elem_size(Vec8DType) { return 1; }
inline std::size_t elem_size(AccDType t) {
  switch (t) {
  case AccDType::Int16:
  case AccDType::FP16:
  case AccDType::BF16:
    return 2;
  default:
    return 4; // Int32, FP32
  }
}
inline std::size_t elem_size(Vec32DType t) {
  switch (t) {
  case Vec32DType::Int16:
  case Vec32DType::FP16:
  case Vec32DType::BF16:
    return 2;
  default:
    return 4; // Int32, FP32
  }
}

// 视图类型转换：只允许同位宽映射（8bit 张量取 Tile/Vec8，16/32bit 张量取
// Acc/Vec32）
inline TileDType to_tile_dtype(TensorDType t) {
  assert(t == TensorDType::Int8 || t == TensorDType::FP8);
  return t == TensorDType::FP8 ? TileDType::FP8 : TileDType::Int8;
}
inline AccDType to_acc_dtype(TensorDType t) {
  switch (t) {
  case TensorDType::Int16:
    return AccDType::Int16;
  case TensorDType::Int32:
    return AccDType::Int32;
  case TensorDType::FP16:
    return AccDType::FP16;
  case TensorDType::BF16:
    return AccDType::BF16;
  default:
    assert(t == TensorDType::FP32);
    return AccDType::FP32;
  }
}
inline Vec8DType to_vec8_dtype(TensorDType t) {
  assert(t == TensorDType::Int8 || t == TensorDType::FP8);
  return t == TensorDType::FP8 ? Vec8DType::FP8 : Vec8DType::Int8;
}
inline Vec32DType to_vec32_dtype(TensorDType t) {
  switch (t) {
  case TensorDType::Int16:
    return Vec32DType::Int16;
  case TensorDType::Int32:
    return Vec32DType::Int32;
  case TensorDType::FP16:
    return Vec32DType::FP16;
  case TensorDType::BF16:
    return Vec32DType::BF16;
  default:
    assert(t == TensorDType::FP32);
    return Vec32DType::FP32;
  }
}

struct Tensor {
  std::byte *data; // 无类型数据缓冲，按 dtype 解释
  TensorDType dtype;
  uint32_t storage_offset;            // 相对 data 的元素偏移
  std::array<std::int32_t, 4> shape;  // 各维长度
  std::array<std::int32_t, 4> stride; // 各维步长（以元素计）

  // 元素偏移（以元素计，含 storage_offset）→ 字节地址
  std::byte *elem_ptr(std::ptrdiff_t offset) const {
    return data + (static_cast<std::ptrdiff_t>(storage_offset) + offset) *
                      static_cast<std::ptrdiff_t>(elem_size(dtype));
  }

  // 取 (i, j) 号 32×32 tile 视图：地址为原点偏移，stride 继承张量，valid_zone
  // 截断边界
  Tile get_tile(int i, int j) const {
    const int r0 = i * TILE, c0 = j * TILE;
    assert(r0 < shape[0] && c0 < shape[1]);
    return Tile{
        .data = elem_ptr(static_cast<std::ptrdiff_t>(r0) * stride[0] +
                         static_cast<std::ptrdiff_t>(c0) * stride[1]),
        .stride = {stride[0], stride[1]},
        .valid_zone = {std::min(TILE, shape[0] - r0),
                       std::min(TILE, shape[1] - c0)},
        .dtype = to_tile_dtype(dtype),
    };
  }

  // 取 (i, j) 号 32×32 acc 视图，逻辑与 get_tile 相同，位宽 16/32bit
  Acc get_acc(int i, int j) const {
    const int r0 = i * TILE, c0 = j * TILE;
    assert(r0 < shape[0] && c0 < shape[1]);
    return Acc{
        .data = elem_ptr(static_cast<std::ptrdiff_t>(r0) * stride[0] +
                         static_cast<std::ptrdiff_t>(c0) * stride[1]),
        .stride = {stride[0], stride[1]},
        .valid_zone = {std::min(TILE, shape[0] - r0),
                       std::min(TILE, shape[1] - c0)},
        .dtype = to_acc_dtype(dtype),
    };
  }

  // 取第 i 行的 32 宽向量视图（如每行 scale / bias）
  Vec8 get_vec8(int i) const {
    assert(i < shape[0]);
    return Vec8{
        .data = elem_ptr(static_cast<std::ptrdiff_t>(i) * stride[0]),
        .stride = stride[1],
        .valid_zone = std::min(TILE, shape[1]),
        .dtype = to_vec8_dtype(dtype),
    };
  }

  // 取第 i 行的 32 宽向量视图，位宽 16/32bit
  Vec32 get_vec32(int i) const {
    assert(i < shape[0]);
    return Vec32{
        .data = elem_ptr(static_cast<std::ptrdiff_t>(i) * stride[0]),
        .stride = stride[1],
        .valid_zone = std::min(TILE, shape[1]),
        .dtype = to_vec32_dtype(dtype),
    };
  }

  // ---- 存储级基本操作（句柄自操作，类似 at::Tensor 的 copy_/fill_/zero_）----
  void fill_(float v);           // 全量填充（mask/scale 缓冲初始化）
  void zero_();                  // 清零
  void copy_(const Tensor &src); // 同形状整体拷贝（dst ← src）
};

// ===== 张量算子库（自由函数，类似 at::xxx，不是 Tensor 的成员）=====
// 与 PyTorch 相同的划分：Tensor 只是句柄 + 视图/访问；算子是外部函数，
// 模型层可以用 get_tile/get_acc 原语自行实现（见 qwen3.cpp），
// 也可由工具链 lowering 成 NPU 指令——两种实现可自由替换。
// 约定：
//  1. 运算按 dim0=M、dim1=N 的二维视图处理；batch/head 维由调用方循环或切片视图；
//  2. GEMM epilogue 的 scale 为 [⌈len/32⌉, 32] 分块 fp32（get_vec32(块号) 取）；
//     attention 的 KV scale 为 [S] 一维 fp32（token 连续存放，支持非 32 对齐追加）；
//  3. 输出张量由调用方分配（arena），算子不做内存分配；
//  4. 作为指令目的操作数的局部对象，其 base 由工具链分配（C++ 层零初始化即可）。
namespace ops {

void add(const Tensor &a, const Tensor &b, Tensor &out); // out = a + b（残差连接）
void mul(const Tensor &a, float s, Tensor &out);         // out = a × s（采样温度等）
void rmsnorm(const Tensor &x, const Tensor &weight, Tensor &out,
             float eps = 1e-6f); // 行 RMSNorm（weight per-channel 分块）
void softmax(const Tensor &x, Tensor &out);  // 行 softmax
void swiglu(const Tensor &gate_up, Tensor &out); // [M,2I] gate_up → [M,I]
// GEMM：a [M,K] int8 × b [K,N] int8 → out [M,N] fp32；
// epilogue：out ×= a_scale（per-token，按行）× w_scale（per-channel，按列）
void matmul(const Tensor &a, const Tensor &b, Tensor &out,
            const Tensor *a_scale = nullptr, const Tensor *w_scale = nullptr,
            bool accum = false);
// 量化：x(fp) → out_q8(int8) + out_scale（per-token，[⌈M/32⌉,32] 分块，
// absmax 按 ≤256 元素分块归约以满足寄存器约束）
void quant(const Tensor &x, Tensor &out_q8, Tensor &out_scale);
// 反量化：x(int8) → out(fp)，scale per-token 分块
void dequant(const Tensor &x, const Tensor &scale, Tensor &out);
// Embedding：ids（int32 分块 [⌈M/32⌉,32]）→ out/out_scale = int8 行 + per-token scale
//（table_scale 为 [vocab] 一维）
void embedding(const Tensor &ids, const Tensor &table, const Tensor &table_scale,
               Tensor &out, Tensor &out_scale);
// RoPE（LLaMA rotate-half，就地修改 x [M, H·128] fp）；
// cos_t/sin_t 为 [S,64] fp32（行=位置，列=频率 lane），pos0 为 x 第 0 行对应位置
void rope(Tensor &x, const Tensor &cos_t, const Tensor &sin_t, int pos0);
// 因果注意力（FlashAttention 式 online softmax，支持 GQA）：
// q int8 [M, Hq·128]，qs 为其 per-token scale（[⌈M/32⌉,32] 分块）；
// k/v int8 [S, Hk·128]；ks/vs 为 [S] 一维 per-token scale；
// out fp [M, Hq·128]；scratch fp ≥ [M,S]；scratch_q8 int8 ≥ [32,32]
void attention(const Tensor &q, const Tensor &qs, const Tensor &k,
               const Tensor &ks, const Tensor &v, const Tensor &vs, Tensor &out,
               Tensor &scratch, Tensor &scratch_q8, bool causal = true);
// 贪心解码：x 每行最大值的全局列号 → ids（int32 分块 [⌈M/32⌉,32]）
void argmax(const Tensor &x, Tensor &ids);
// 数据搬运（KV cache 追加）：2D 行块拷贝；1D 元素拷贝（scale 追加，支持非对齐位置）
void copy_rows_to(const Tensor &src, Tensor &dst, int dst_row0);
void copy_to(const Tensor &src, Tensor &dst, int dst_elem0);

} // namespace ops
