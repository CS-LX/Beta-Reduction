# 积木系统重构策划案

> 版本: v1.0 | 日期: 2026-06-07
> 状态追踪: 每个 Phase 完成后标记 ✅ READY

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
| 拼图/USB 接口 | 凹凸咬合的"插入"手感 |

---

## 三种基本元的物理形态

### Variable (变量) — "出口喷嘴/钥匙"

```
    ╭──────╮
    │  x  ◂├▷  ← 右侧三角凸起（齿形，可插入 λ 入口）
    ╰──────╯
```

- 形状: 圆角矩形 + **右侧三角凸起**
- 颜色: 继承其绑定 λ 的色相（同色 = 同源）
- 隐喻: "这里会涌出东西" — 替换时参数从这些位置冒出

### Abstraction (函数) — "管道机器"

```
    ┏━━━━━━━━━━━━━━━━━━━━━━━┓
◁━━━┫  λx                    ┃
入口 ┃  ┌─────────────────┐  ┃
(三角┃  │     body         │  ┃
 凹槽)  │   (内部空间)     │  ┃
    ┃  └─────────────────┘  ┃
    ┗━━━━━━━━━━━━━━━━━━━━━━━┛
```

- 形状: 左侧有**三角凹槽入口**的管道容器
- 入口颜色 = 参数名色相
- header 区展示 `λ参数名`
- body 区内嵌子积木
- 隐喻: "把东西从三角入口塞进去，内部同色出口涌出"

### Application (应用) — "咬合/对接"

```
    ┏━━━━━━━━━━┓╔══════╗
◁━━━┫  λx      ┃║ arg ◂├▷  ← arg 的凸起嵌入 func 的凹口
    ┃  body    ┣◁▷     ║
    ┃          ┃║      ║
    ┗━━━━━━━━━━┛╚══════╝
```

- 保留**极淡背景**区分层级（不画明显外壳）
- func 和 arg 通过三角齿形物理咬合
- 隐喻: "钥匙插入锁孔，即将发生反应"

---

## 色彩系统：参数名 → 色相映射

```lua
-- 每个参数名映射到唯一色相，变量自动继承绑定者的颜色
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
-- 未列出的：基于名字首字符 hash 计算
-- hue = (string.byte(name, 1) * 37) % 360
```

---

## 归约动画四阶段

β-reduction `(λx.body) arg` → `body[x:=arg]`:

| 阶段 | 名称 | 视觉效果 | 时长 |
|------|------|---------|------|
| 1 | **对接高亮** | 整个 application 闪烁，arg 颜色加深 | 0.5s |
| 2 | **吞入** | arg 积木滑向 λ 的入口凹槽，缩小消失 | 0.7s |
| 3 | **替换涌出** | body 内同色变量逐个膨胀变形为 arg 副本 | 0.5s/个 |
| 4 | **壳消融** | λ 外壳碎裂成粒子蒸发，body 弹出释放 | 0.6s |

### 壳消融粒子效果

```
λ 外壳拆解为 8~12 个三角碎片:
- 每片从边缘位置生成
- 初速度向外 + 略微旋转
- 透明度快速衰减 (0.4s 内消失)
- 同时 body 积木从中心弹出 (spring overshoot)
```

---

## 实施 Phases

### Phase 1: 重写 _renderVarBlock — ✅ READY

改动文件: `scripts/Blocks/BlockCanvas.lua`, `scripts/Blocks/BlockDefs.lua`

- 新增 `BlockDefs.getParamHue(name)` 色相映射函数
- 新增 `BlockDefs.hueToRGBA(hue, sat, lightness, alpha)` HSL→RGBA 转换
- variable 积木加入**右侧三角凸起**渲染
- variable 颜色由 `block.boundParam`（绑定者的参数名）决定色相
- 在 `ASTToBlock` 转换时，写入 `block.boundParam` 字段（向上查找绑定的 λ）

### Phase 2: 重写 _renderAbsBlock — ✅ READY

改动文件: `scripts/Blocks/BlockCanvas.lua`, `scripts/Blocks/BlockDefs.lua`

- header 区使用参数名色相着色
- 左侧绘制**三角凹槽**入口（Path: 上边→凹三角→下边）
- 入口凹槽颜色 = 参数名色相（与内部变量同色）
- body 区保持深色背景
- 调整 measure: `leftThick` 改为含凹槽的宽度

### Phase 3: 重写 _renderAppBlock — ✅ READY

改动文件: `scripts/Blocks/BlockCanvas.lua`, `scripts/Blocks/BlockDefs.lua`

- 移除绿色外壳描边
- 改为极淡背景 (alpha ~15) 仅区分层级
- func 和 arg 之间绘制**咬合连接区**:
  - func 右侧的凹口（如果 func 是 abstraction）
  - arg 左侧的凸起
  - 两者紧密贴合（gap 缩小为 0）
- 中间三角指示符改为咬合齿形

### Phase 4: 调整 measure/layout — ✅ READY

改动文件: `scripts/Blocks/BlockDefs.lua`

- variable: 宽度增加三角凸起 (TOOTH_W ≈ 8px)
- abstraction: 左侧增加凹槽空间
- application: gap 和 connectorW 调整，反映咬合状态
- 新增常量: `TOOTH_W = 8`, `TOOTH_H = 12`, `NOTCH_DEPTH = 8`

### Phase 5: 重写归约动画 — ✅ READY

改动文件: `scripts/Campaign/FlowAnimation.lua`, `scripts/Blocks/BlockCanvas.lua`

- 新增 `BlockCanvas:AddShatterAnim(block, duration, delay)` — 碎裂粒子
- 修改 `animateOneReduction`:
  1. 高亮 application
  2. arg 滑入 λ 凹槽 (从右向左飞入，缩小消失)
  3. body 内变量逐个膨胀替换
  4. λ 壳碎裂消融 + body 弹出
- 修改 `animateFeedInput`:
  1. 外部输入从左侧滑入凹槽
  2. 内部变量涌出替换
  3. λ 壳消融

---

## 文件清单

| 文件 | 职责 |
|------|------|
| `scripts/Blocks/BlockDefs.lua` | 积木数据结构、尺寸计算、色彩映射 |
| `scripts/Blocks/BlockCanvas.lua` | 积木渲染（NanoVG 绘制）+ 动画播放 |
| `scripts/Campaign/FlowAnimation.lua` | 归约动画编排 |
| `scripts/Campaign/CampaignScene.lua` | ASTToBlock 转换（需添加 boundParam） |

---

## 注意事项

- 整个重构保持 Block 数据结构向后兼容（`kind`, `slots`, `name`, `param` 字段不变）
- 新增字段: `block.boundParam`（变量的绑定参数名，用于颜色查找）
- 新增字段: `block.bindingHue`（缓存计算好的色相值）
- 拖拽/吸附逻辑暂不改动（Phase 4 只改尺寸，不改吸附机制）
