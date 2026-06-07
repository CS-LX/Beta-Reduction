-- ============================================================================
-- Blocks/BlockCanvas.lua - 积木工作区画布 Widget
-- ============================================================================
-- Widget:Extend 自绘组件：NanoVG 渲染积木 + 拖拽吸附交互
-- 实现 Scratch-like 积木拼装体验

---@diagnostic disable: param-type-mismatch

local Widget = require("urhox-libs/UI/Core/Widget")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local BlockDefs = require("Blocks.BlockDefs")
local AST = require("Lambda.AST")

local BlockCanvas = Widget:Extend("BlockCanvas")

-- ============================================================================
-- 初始化
-- ============================================================================

function BlockCanvas:Init(props)
    props = props or {}
    props.overflow = "hidden"
    props.backgroundColor = props.backgroundColor or { 18, 22, 30, 255 }

    -- 画布状态
    self.blocks_ = {}         -- 根积木列表 (未嵌入其他积木的顶层 block)
    self.zoom_ = 1.0
    self.panX_ = 0
    self.panY_ = 0

    -- 拖拽状态
    self.isDragging_ = false
    self.dragBlock_ = nil
    self.dragOffX_ = 0
    self.dragOffY_ = 0
    self.isPanning_ = false
    self.lastPanX_ = 0
    self.lastPanY_ = 0

    -- 吸附预览
    self.snapTarget_ = nil  -- { targetBlock, slotKey }

    -- 动画
    self.time_ = 0
    self.snapAnims_ = {}    -- { block, fromX, fromY, toX, toY, elapsed, duration }

    -- 冻结状态（运行动画时禁止交互）
    self.frozen_ = false

    -- 数据流动画
    self.flowAnims_ = {}      -- { text, x, y, toX, toY, elapsed, duration, color, opacity, scale }
    self.flashBlocks_ = {}    -- { block, elapsed, duration, color } 积木闪烁效果
    self.flowCallback_ = nil  -- 所有动画播完后的回调

    -- 双击检测
    self.lastClickTime_ = 0
    self.lastClickBlock_ = nil
    self.DOUBLE_CLICK_TIME = 0.35

    -- 回调
    self.onBlockChanged_ = props.onBlockChanged   -- 积木树变化时
    self.onBlockSelected_ = props.onBlockSelected -- 选中积木时
    self.onBlockDoubleClick_ = props.onBlockDoubleClick -- 双击积木时

    self.selectedBlock_ = nil

    Widget.Init(self, props)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 添加一个新积木到画布
function BlockCanvas:AddBlock(block, x, y)
    block.x = x or 100
    block.y = y or 100
    BlockDefs.measure(block)
    BlockDefs.layout(block, block.x, block.y)
    table.insert(self.blocks_, block)
    return block
end

--- 获取所有根积木
function BlockCanvas:GetRootBlocks()
    return self.blocks_
end

--- 获取选中的积木
function BlockCanvas:GetSelected()
    return self.selectedBlock_
end

--- 获取选中积木对应的 AST（用于求值/打包）
function BlockCanvas:GetSelectedAST()
    if not self.selectedBlock_ then return nil end
    return BlockDefs.toAST(self.selectedBlock_)
end

--- 冻结/解冻画布（冻结时禁止所有交互）
function BlockCanvas:SetFrozen(frozen)
    self.frozen_ = frozen
    if frozen then
        self.isDragging_ = false
        self.dragBlock_ = nil
        self.isPanning_ = false
        self.snapTarget_ = nil
    end
end

function BlockCanvas:IsFrozen()
    return self.frozen_
end

--- 添加数据流动画（胶囊方块从 from 飘到 to）
---@param text string 显示文本
---@param fromX number 起始 X（画布坐标）
---@param fromY number 起始 Y
---@param toX number 目标 X
---@param toY number 目标 Y
---@param duration number 持续时间（秒）
---@param color? number[] RGBA 颜色
---@param delay? number 延迟开始（秒）
function BlockCanvas:AddFlowAnim(text, fromX, fromY, toX, toY, duration, color, delay)
    table.insert(self.flowAnims_, {
        text = text,
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        elapsed = -(delay or 0),  -- 负值表示延迟等待
        duration = duration or 0.5,
        color = color or { 100, 220, 255 },
        alive = true,
    })
end

--- 添加积木闪烁效果
function BlockCanvas:AddFlashBlock(block, duration, color)
    table.insert(self.flashBlocks_, {
        block = block,
        elapsed = 0,
        duration = duration or 0.4,
        color = color or { 255, 255, 100 },
        alive = true,
    })
end

--- 设置动画全部完成后的回调
function BlockCanvas:SetFlowCompleteCallback(fn)
    self.flowCallback_ = fn
end

--- 清除所有动画
function BlockCanvas:ClearAnims()
    self.flowAnims_ = {}
    self.flashBlocks_ = {}
    self.flowCallback_ = nil
end

--- 检查是否有动画在播放
function BlockCanvas:HasActiveAnims()
    for _, a in ipairs(self.flowAnims_) do
        if a.alive then return true end
    end
    for _, f in ipairs(self.flashBlocks_) do
        if f.alive then return true end
    end
    return false
end

--- 清空画布
function BlockCanvas:Clear()
    self.blocks_ = {}
    self.selectedBlock_ = nil
    self.dragBlock_ = nil
end

--- 删除指定积木（从根列表或父级中移除）
function BlockCanvas:RemoveBlock(block)
    BlockDefs.detach(block)
    for i, b in ipairs(self.blocks_) do
        if b.id == block.id then
            table.remove(self.blocks_, i)
            break
        end
    end
    if self.selectedBlock_ and self.selectedBlock_.id == block.id then
        self.selectedBlock_ = nil
    end
    self:_refreshAll()
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

function BlockCanvas:ScreenToCanvas(sx, sy)
    local layout = self:GetAbsoluteLayout()
    if not layout then return sx, sy end
    local cx = (sx - layout.x - self.panX_) / self.zoom_
    local cy = (sy - layout.y - self.panY_) / self.zoom_
    return cx, cy
end

-- ============================================================================
-- 命中检测
-- ============================================================================

function BlockCanvas:FindBlockAt(cx, cy)
    -- 反向遍历（后添加的在上层）
    for i = #self.blocks_, 1, -1 do
        local hit = self:_hitTest(self.blocks_[i], cx, cy)
        if hit then return hit end
    end
    return nil
end

function BlockCanvas:_hitTest(block, cx, cy)
    -- 先检查子积木（子积木在上层）
    for _, slot in pairs(block.slots) do
        if slot.child then
            local hit = self:_hitTest(slot.child, cx, cy)
            if hit then return hit end
        end
    end
    -- 再检查自身
    if cx >= block.x and cx <= block.x + block.w
        and cy >= block.y and cy <= block.y + block.h then
        return block
    end
    return nil
end

-- ============================================================================
-- 交互事件
-- ============================================================================

function BlockCanvas:OnPointerDown(event)
    Widget.OnPointerDown(self, event)
    if self.frozen_ then return true end
    local cx, cy = self:ScreenToCanvas(event.x, event.y)

    -- 右键/中键: 平移画布
    if event.button == PointerEvent.Button.Right or event.button == PointerEvent.Button.Middle then
        self.isPanning_ = true
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if event.button == PointerEvent.Button.Left then
        local block = self:FindBlockAt(cx, cy)
        if block then
            -- 双击检测
            local now = self.time_ or 0
            if self.lastClickBlock_ and self.lastClickBlock_.id == block.id
                and (now - self.lastClickTime_) < self.DOUBLE_CLICK_TIME then
                -- 触发双击
                if self.onBlockDoubleClick_ then
                    self.onBlockDoubleClick_(block)
                end
                self.lastClickBlock_ = nil
                self.lastClickTime_ = 0
                return true
            end
            self.lastClickTime_ = now
            self.lastClickBlock_ = block

            self.selectedBlock_ = block
            if self.onBlockSelected_ then
                self.onBlockSelected_(block)
            end

            -- 开始拖拽
            self.isDragging_ = true
            self.dragBlock_ = block
            self.dragOffX_ = cx - block.x
            self.dragOffY_ = cy - block.y

            -- 如果是子积木，先从父级分离
            if block.parent then
                BlockDefs.detach(block)
                -- 加入根列表
                table.insert(self.blocks_, block)
                self:_refreshAll()
            end

            -- 提升到顶层
            self:_bringToTop(block)
            return true
        else
            self.selectedBlock_ = nil
        end
    end
    return true
end

function BlockCanvas:OnPointerMove(event)
    Widget.OnPointerMove(self, event)
    if self.frozen_ then return true end

    if self.isPanning_ then
        local dx = event.x - self.lastPanX_
        local dy = event.y - self.lastPanY_
        self.panX_ = self.panX_ + dx
        self.panY_ = self.panY_ + dy
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if self.isDragging_ and self.dragBlock_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        self.dragBlock_.x = cx - self.dragOffX_
        self.dragBlock_.y = cy - self.dragOffY_
        -- 重新布局该积木的子树
        BlockDefs.measure(self.dragBlock_)
        BlockDefs.layout(self.dragBlock_, self.dragBlock_.x, self.dragBlock_.y)

        -- 检测吸附
        self.snapTarget_ = BlockDefs.findSnapTarget(self.dragBlock_, self.blocks_, cx, cy)
        return true
    end
end

function BlockCanvas:OnPointerUp(event)
    Widget.OnPointerUp(self, event)
    if self.frozen_ then return true end

    if self.isPanning_ then
        self.isPanning_ = false
        return true
    end

    if self.isDragging_ and self.dragBlock_ then
        -- 执行吸附
        if self.snapTarget_ then
            local target = self.snapTarget_.targetBlock
            local slotKey = self.snapTarget_.slotKey
            BlockDefs.attach(self.dragBlock_, target, slotKey)
            -- 从根列表移除
            for i, b in ipairs(self.blocks_) do
                if b.id == self.dragBlock_.id then
                    table.remove(self.blocks_, i)
                    break
                end
            end
            self:_refreshAll()
            if self.onBlockChanged_ then
                self.onBlockChanged_()
            end
        end
        self.isDragging_ = false
        self.dragBlock_ = nil
        self.snapTarget_ = nil
        return true
    end

    self.isDragging_ = false
end

function BlockCanvas:OnWheel(dx, dy)
    local factor = dy > 0 and 1.12 or (1.0 / 1.12)
    self.zoom_ = math.max(0.4, math.min(2.5, self.zoom_ * factor))
end

-- ============================================================================
-- 内部辅助
-- ============================================================================

function BlockCanvas:_bringToTop(block)
    for i, b in ipairs(self.blocks_) do
        if b.id == block.id then
            table.remove(self.blocks_, i)
            table.insert(self.blocks_, block)
            return
        end
    end
end

function BlockCanvas:_refreshAll()
    for _, block in ipairs(self.blocks_) do
        BlockDefs.measure(block)
        BlockDefs.layout(block, block.x, block.y)
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function BlockCanvas:Update(dt)
    self.time_ = (self.time_ or 0) + dt

    -- 更新数据流动画
    local anyAlive = false
    for _, a in ipairs(self.flowAnims_) do
        if a.alive then
            a.elapsed = a.elapsed + dt
            if a.elapsed >= a.duration then
                a.alive = false
            else
                anyAlive = true
            end
        end
    end
    -- 更新闪烁动画
    for _, f in ipairs(self.flashBlocks_) do
        if f.alive then
            f.elapsed = f.elapsed + dt
            if f.elapsed >= f.duration then
                f.alive = false
            else
                anyAlive = true
            end
        end
    end
    -- 所有动画完成后触发回调
    if not anyAlive and self.flowCallback_ then
        -- 确认确实有过动画（非空列表）
        if #self.flowAnims_ > 0 or #self.flashBlocks_ > 0 then
            local cb = self.flowCallback_
            self.flowCallback_ = nil
            self.flowAnims_ = {}
            self.flashBlocks_ = {}
            cb()
        end
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

function BlockCanvas:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then return end

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, layout.x, layout.y, layout.w, layout.h, 2)
    nvgFillColor(nvg, nvgRGBA(18, 22, 30, 255))
    nvgFill(nvg)

    nvgSave(nvg)
    nvgIntersectScissor(nvg, layout.x, layout.y, layout.w, layout.h)

    -- 网格
    self:_renderGrid(nvg, layout)

    -- 变换到画布坐标系
    nvgTranslate(nvg, layout.x + self.panX_, layout.y + self.panY_)
    nvgScale(nvg, self.zoom_, self.zoom_)

    -- 吸附预览
    if self.snapTarget_ then
        self:_renderSnapPreview(nvg)
    end

    -- 渲染所有积木
    for _, block in ipairs(self.blocks_) do
        self:_renderBlock(nvg, block)
    end

    -- 渲染积木闪烁效果
    for _, f in ipairs(self.flashBlocks_) do
        if f.alive and f.elapsed >= 0 then
            local t = f.elapsed / f.duration
            -- 脉冲衰减: 先亮后暗
            local pulse = math.sin(t * math.pi) * 0.7
            local alpha = math.floor(pulse * 180)
            if alpha > 0 then
                local b = f.block
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, b.x - 2, b.y - 2, b.w + 4, b.h + 4, 10)
                nvgFillColor(nvg, nvgRGBA(f.color[1], f.color[2], f.color[3], alpha))
                nvgFill(nvg)
            end
        end
    end

    -- 渲染数据流动画（飘动胶囊）
    for _, a in ipairs(self.flowAnims_) do
        if a.alive and a.elapsed >= 0 then
            local t = a.elapsed / a.duration
            -- ease-out cubic
            local et = 1 - (1 - t) * (1 - t) * (1 - t)
            local cx = a.fromX + (a.toX - a.fromX) * et
            local cy = a.fromY + (a.toY - a.fromY) * et
            -- 轻微弧形偏移
            local arcOffset = math.sin(et * math.pi) * 20
            cy = cy - arcOffset

            -- 透明度：出现 → 保持 → 微弱消散
            local alpha = 240
            if t < 0.15 then
                alpha = math.floor(t / 0.15 * 240)
            elseif t > 0.85 then
                alpha = math.floor((1 - t) / 0.15 * 240)
            end

            -- 缩放
            local sc = 1.0
            if t < 0.1 then sc = 0.5 + t / 0.1 * 0.5 end

            -- 绘制胶囊
            local tw = math.max(40, #a.text * 8 + 16)
            local th = 22
            nvgSave(nvg)
            nvgTranslate(nvg, cx, cy)
            nvgScale(nvg, sc, sc)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, -tw / 2, -th / 2, tw, th, th / 2)
            nvgFillColor(nvg, nvgRGBA(a.color[1], a.color[2], a.color[3], math.floor(alpha * 0.4)))
            nvgFill(nvg)
            nvgStrokeColor(nvg, nvgRGBA(a.color[1], a.color[2], a.color[3], alpha))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)

            -- 文字
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 11)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
            nvgText(nvg, 0, 0, a.text)
            nvgRestore(nvg)
        end
    end

    -- 冻结遮罩
    if self.frozen_ and #self.flowAnims_ == 0 and #self.flashBlocks_ == 0 then
        -- 没有动画时轻微变暗提示冻结
        nvgBeginPath(nvg)
        nvgRect(nvg, -9999, -9999, 99999, 99999)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 30))
        nvgFill(nvg)
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- 网格背景
-- ============================================================================

function BlockCanvas:_renderGrid(nvg, layout)
    local gridSize = 40 * self.zoom_
    if gridSize < 8 then return end

    local ox = self.panX_ % gridSize
    local oy = self.panY_ % gridSize
    local alpha = math.floor(math.min(40, 20 * (gridSize / 40)))

    nvgBeginPath(nvg)
    nvgStrokeColor(nvg, nvgRGBA(60, 70, 90, alpha))
    nvgStrokeWidth(nvg, 0.5)

    local x = layout.x + ox
    while x < layout.x + layout.w do
        nvgMoveTo(nvg, x, layout.y)
        nvgLineTo(nvg, x, layout.y + layout.h)
        x = x + gridSize
    end
    local y = layout.y + oy
    while y < layout.y + layout.h do
        nvgMoveTo(nvg, layout.x, y)
        nvgLineTo(nvg, layout.x + layout.w, y)
        y = y + gridSize
    end
    nvgStroke(nvg)
end

-- ============================================================================
-- 吸附预览
-- ============================================================================

function BlockCanvas:_renderSnapPreview(nvg)
    local target = self.snapTarget_.targetBlock
    local slotKey = self.snapTarget_.slotKey
    local slot = target.slots[slotKey]
    if not slot then return end

    local sx = target.x + (slot.rx or 0)
    local sy = target.y + (slot.ry or 0)
    local sw = slot.rw or BlockDefs.SLOT_MIN_W
    local sh = slot.rh or BlockDefs.SLOT_MIN_H

    -- 发光矩形
    local pulse = 0.6 + 0.4 * math.sin(self.time_ * 6)
    local a = math.floor(80 * pulse)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, sx - 2, sy - 2, sw + 4, sh + 4, 6)
    nvgStrokeColor(nvg, nvgRGBA(100, 255, 200, a))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

-- ============================================================================
-- 积木渲染（玻璃质感 Glassmorphism）
-- ============================================================================

function BlockCanvas:_renderBlock(nvg, block)
    local isSelected = (self.selectedBlock_ and self.selectedBlock_.id == block.id)

    if block.kind == "variable" then
        self:_renderVarBlock(nvg, block, isSelected)
    elseif block.kind == "abstraction" then
        self:_renderAbsBlock(nvg, block, isSelected)
    elseif block.kind == "application" then
        self:_renderAppBlock(nvg, block, isSelected)
    end
end

--- 变量积木: 胶囊体
function BlockCanvas:_renderVarBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local c = BlockDefs.Colors.variable
    local r = h / 2  -- 圆角 = 高度一半 → 胶囊

    -- 玻璃背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, r)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 60))
    nvgFill(nvg)

    -- 边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, r)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], isSelected and 255 or 160))
    nvgStrokeWidth(nvg, isSelected and 2 or 1.2)
    nvgStroke(nvg)

    -- 上高光 (glassmorphism)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 2, y + 1, w - 4, h * 0.4, r)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 20))
    nvgFill(nvg)

    -- 文字
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 13)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgText(nvg, x + w / 2, y + h / 2, block.name)
end

--- 抽象积木: C 形包裹容器 (函数/机器)
function BlockCanvas:_renderAbsBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local c = BlockDefs.Colors.abstraction
    local HH = BlockDefs.HEADER_H
    local leftThick = 10
    local rad = 8

    -- 整体 C 形路径（半透明底色 + 描边）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, rad)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 40))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], isSelected and 240 or 140))
    nvgStrokeWidth(nvg, isSelected and 2 or 1.2)
    nvgStroke(nvg)

    -- Header 区域
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, HH, rad)
    nvgRect(nvg, x, y + HH - rad, w, rad)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 80))
    nvgFill(nvg)

    -- "λparam" 文字
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
    nvgText(nvg, x + 8, y + HH / 2, "\xce\xbb" .. block.param)

    -- 左侧 C 形竖线（视觉强调）
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y + HH, leftThick, h - HH)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 50))
    nvgFill(nvg)

    -- body slot (空时画虚线框)
    local slot = block.slots.body
    if not slot.child then
        local sx = x + (slot.rx or 0)
        local sy = y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, sw, sh, 4)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 15))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 40))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
        -- 占位文字
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 60))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, "body")
    else
        self:_renderBlock(nvg, slot.child)
    end
end

--- 应用积木: 双槽水平排列 (函数调用)
function BlockCanvas:_renderAppBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local c = BlockDefs.Colors.application
    local rad = 6

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, rad)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 35))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], isSelected and 240 or 120))
    nvgStrokeWidth(nvg, isSelected and 2 or 1)
    nvgStroke(nvg)

    -- 上高光
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 1, y + 1, w - 2, h * 0.3, rad)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 10))
    nvgFill(nvg)

    -- 中间连接三角（简洁的方向指示，替代文字箭头）
    local funcSlot = block.slots.func
    local midX = x + (funcSlot.rx or 0) + (funcSlot.rw or 56) + BlockDefs.GAP * 0.5
    local midY = y + h / 2
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, midX + 2, midY - 4)
    nvgLineTo(nvg, midX + 8, midY)
    nvgLineTo(nvg, midX + 2, midY + 4)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 100))
    nvgFill(nvg)

    -- func slot (左侧)
    self:_renderSlot(nvg, block, "func", "f", {c[1], c[2], c[3]})
    -- arg slot (右侧)
    self:_renderSlot(nvg, block, "arg", "x", {c[1], c[2], c[3]})
end

function BlockCanvas:_renderSlot(nvg, block, slotKey, placeholder, hintColor)
    local slot = block.slots[slotKey]
    if not slot then return end

    hintColor = hintColor or {100, 120, 160}

    if slot.child then
        self:_renderBlock(nvg, slot.child)
    else
        local sx = block.x + (slot.rx or 0)
        local sy = block.y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H

        -- 简洁的虚线插槽
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, sw, sh, 4)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 10))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 35))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- 极简占位符
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 50))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, placeholder)
    end
end

return BlockCanvas
