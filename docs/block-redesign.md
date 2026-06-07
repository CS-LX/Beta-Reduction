# 积木系统重构策划案

> 版本: v2.0 | 日期: 2026-06-08
> 状态: ✅ 全部完成

---

## 设计目标

让玩家发出"哇原来 lambda 演算这么直观这么神奇"——

1. 体现 lambda 演算的三个基本元（变量/函数/应用）
2. 积木咬合表达"不可分"的组合关系
3. 积木设计服务动画表现，动画表现服务积木设计
4. 核心洞见：**基本元就是函数，函数就是基本元**

---

## 设计参考

| 方法 | 采纳点 |
|------|--------|
| Alligator Eggs | "吃→替换→壳消失"的物理动作感 |
| Visual Lambda (Bubble) | 色彩标识作用域 |
| 管道/机器隐喻 | 入口→内部→出口的数据流 |
| **拼图块** | 半圆凸起⊃嵌入半圆凹口⊂ — 几何严格互补 |

---

## 核心设计原则（v2 — 半圆拼图 + 扁平水平）

1. **半圆凸起(bump) ⊃ 完美嵌入半圆凹口(indent) ⊂** — 同半径几何互补
2. **所有积木扁平水平排列** — 彻底取消容器嵌套，不再看起来像 AST
3. **Application 不可见** — func 和 arg 通过 bump⊃⊂indent 直接咬合
4. **Abstraction 不是容器** — `[λx 头]⊃⊂[body]` 水平并排

---

## 关键常量

```lua
BLOCK_H   = 38    -- 标准积木高度
BUMP_R    = 7     -- 半圆凸起/凹口半径（关键咬合尺寸）
HEADER_W  = 46    -- λx 头部宽度
VAR_PAD   = 14    -- 变量积木文本水平 padding
SLOT_MIN_W = 48   -- 空槽最小宽度
SLOT_MIN_H = 36   -- 空槽最小高度
CORNER_R  = 4     -- 积木圆角半径
SNAP_RADIUS = 30  -- 吸附检测半径
```

---

## 三种基本元的物理形态

### Variable (变量) — "扁平药片"

```
    ╭──────────╮
    │    x     │     ← 扁平药片，h=38
    ╰──────────╯

    上下文决定连接器:
    - 作为 func slot 子块 → 右侧半圆 bump ⊃
    - 作为 arg/body slot 子块 → 左侧半圆 indent ⊂
    - 顶层独立 → 无连接器
```

- 形状: 圆角矩形 + **上下文感知的半圆连接器**
- 颜色: 继承其绑定 λ 的色相（同色 = 同源）
- 尺寸: `w = max(52, textW + VAR_PAD*2)`, `h = BLOCK_H`

### Abstraction (函数) — "头部 + body 水平拼图"

```
    ╭────────╮⊃⊂╭────────────╮
    │  λx    │    │   body     │
    ╰────────╯    ╰────────────╯
     头部(46px)     body子块

    头部右侧始终有 bump ⊃（连接 body）
    body 子块左侧始终有 indent ⊂（接收头部的 bump）
    整体上下文连接器由 parentSlotKey 决定
```

- 形状: `[λx 头部]` 水平紧接 `[body]`，**不是容器**
- 头部颜色: 参数名色相（深色调）
- 头部右侧: 始终有 bump（连接 body）
- body: 独立渲染的子积木（自带左侧 indent）
- 尺寸: `w = HEADER_W + bodyW`, `h = max(BLOCK_H, bodyH)`
- 隐喻: "把东西从左侧推入，在内部同色位置涌出"

### Application (应用) — "不可见咬合"

```
    ╭────────╮⊃⊂╭────────╮
    │  func  │    │  arg   │
    ╰────────╯    ╰────────╯

    func 右侧 bump ⊃ 嵌入 arg 左侧 indent ⊂
    Application 本身不渲染任何外壳
```

- **完全不可见** — 仅在选中时微弱虚线边框
- func slot 子块: 右侧有 bump（`parentSlotKey == "func"`）
- arg slot 子块: 左侧有 indent（`parentSlotKey == "arg"`）
- 两者 bump⊃⊂indent 视觉上严格互锁
- 尺寸: `w = funcW + argW`, `h = max(funcH, argH)`
- 隐喻: "钥匙插入锁孔，即将发生反应"

---

## 半圆几何实现（NanoVG）

```lua
--- 右侧凸起: 从 cy-R 向右画半圆到 cy+R
nvgArc(nvg, x + w, cy, R, -math.pi/2, math.pi/2, NVG_CW)

--- 左侧凹口: 从 cy+R 向右凹入画半圆到 cy-R
nvgArc(nvg, x, cy, R, math.pi/2, -math.pi/2, NVG_CCW)
```

**关键**: 同半径 R=7px，凸起向右突出 R 像素，凹口向右凹入 R 像素，几何严格互补。

---

## 上下文连接器规则

| parentSlotKey | 左侧 indent | 右侧 bump |
|---------------|-------------|-----------|
| `"func"` | ✗ | ✓ |
| `"arg"` | ✓ | ✗ |
| `"body"` | ✓ | ✗ |
| 无 parent（顶层） | ✗ | ✗ |
| 抽象头部（特殊） | 由上下文决定 | ✓（始终连 body） |

---

## 色彩系统：参数名 → 色相映射

```lua
local PARAM_HUES = {
    x = 200,   -- 天蓝
    y = 140,   -- 翠绿
    z = 320,   -- 玫红
    f = 45,    -- 橙金
    g = 270,   -- 紫
    n = 170,   -- 青
    m = 10,    -- 红橙
    a = 60,    -- 黄
    b = 230,   -- 靛蓝
    p = 100,   -- 草绿
    q = 290,   -- 粉紫
    s = 350,   -- 桃红
    t = 80,    -- 柠檬绿
}
-- 未列出的：hue = (string.byte(name, 1) * 37) % 360
```

---

## 归约动画四阶段

β-reduction `(λx.body) arg` → `body[x:=arg]`:

| 阶段 | 名称 | 视觉效果 | 时长 |
|------|------|---------|------|
| 1 | **对接高亮** | 整个 application 闪烁，arg 颜色加深 | 0.5s |
| 2 | **吞入** | arg 滑向 body 左侧半圆凹口，缩小消失 | 0.7s |
| 3 | **替换涌出** | body 内同色变量逐个膨胀变形为 arg 副本 | 0.5s/个 |
| 4 | **破壳弹出** | λ 壳碎裂粒子蒸发，新积木 spring overshoot 弹出 | 0.8s |

### 动画坐标说明（v2）

- **吞入目标**: `lambdaBlock.x + HEADER_W`（body 左侧凹口 X）, `lambdaBlock.y + h/2`（垂直居中）
- **内部流动起点**: `lambdaBlock.x + HEADER_W + BUMP_R`（凹口内侧）
- **破壳弹出**: 新积木从壳中心用 `1 - e^(-6t)*cos(4πt)` spring overshoot 弹出

---

## 布局算法（扁平水平）

```
Variable:
  w = max(52, textWidth + VAR_PAD * 2)
  h = BLOCK_H (38)

Abstraction:
  w = HEADER_W + bodyW
  h = max(BLOCK_H, bodyH)
  slots.body.rx = HEADER_W   ← body 在头部右侧
  slots.body.ry = (h - bodyH) / 2

Application:
  w = funcW + argW
  h = max(funcH, argH)
  slots.func.rx = 0
  slots.arg.rx = funcW        ← arg 紧接 func 右侧
```

---

## 文件清单

| 文件 | 职责 |
|------|------|
| `scripts/Blocks/BlockDefs.lua` | 积木数据结构、扁平布局计算、色彩映射、吸附检测 |
| `scripts/Blocks/BlockCanvas.lua` | 积木渲染（NanoVG 半圆拼图绘制）+ 动画播放 |
| `scripts/Campaign/FlowAnimation.lua` | 归约动画编排（四阶段白箱动画） |
| `scripts/Campaign/CampaignScene.lua` | ASTToBlock 转换（含 boundParam 绑定） |

---

## 设计演进历史

| 版本 | 方案 | 问题 |
|------|------|------|
| v0 | AST 树形嵌套 | 看起来像语法树，非物理拼图 |
| v1 | 三角梯形齿 | 两个反向梯形几何上无法咬合 |
| **v2** | **半圆 bump/indent** | ✅ 同半径几何严格互补，扁平水平不像 AST |

---

## 注意事项

- 整个重构保持 Block 数据结构向后兼容（`kind`, `slots`, `name`, `param` 字段不变）
- 新增字段: `block.boundParam`（变量的绑定参数名，用于颜色查找）
- bump/indent 是**纯视觉渲染层**，不影响布局宽度计算（layout 只管 body width）
- 拖拽/吸附逻辑不受影响（仍用 slot 中心点距离检测）
