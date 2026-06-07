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

    -- 整体 C 形路径（使用圆角矩形近似）
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

    -- 左上角小标签: "函数"
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(200, 170, 255, 140))
    nvgText(nvg, x + w - 6, y + HH / 2, "\xe2\x9a\x99 \xe5\x87\xbd\xe6\x95\xb0")

    -- "λparam" 文字 + 输入标签
    nvgFontSize(nvg, 12)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 230))
    nvgText(nvg, x + 8, y + HH / 2, "\xce\xbb" .. block.param)

    -- 输入口标示 (header 下方左侧小箭头)
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(80, 200, 220, 180))
    nvgText(nvg, x + leftThick + 4, y + HH + 2, "\xe2\x86\x93 \xe8\xbe\x93\xe5\x85\xa5 " .. block.param)

    -- 左侧 C 形竖线（视觉强调）
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y + HH, leftThick, h - HH)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 50))
    nvgFill(nvg)

    -- 输出口标示 (底部)
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg, nvgRGBA(100, 255, 180, 150))
    nvgText(nvg, x + w / 2, y + h - 2, "\xe2\x86\x92 \xe8\xbe\x93\xe5\x87\xba\xe7\xbb\x93\xe6\x9e\x9c")

    -- body slot (空时画虚线框)
    local slot = block.slots.body
    if not slot.child then
        local sx = x + (slot.rx or 0)
        local sy = y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, sw, sh, 4)
        nvgFillColor(nvg, nvgRGBA(140, 100, 240, 20))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(140, 100, 240, 60))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)
        -- 占位文字: 引导用户
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(200, 170, 255, 90))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, "\xe6\x8b\x96\xe5\x85\xa5\xe5\x86\x85\xe5\xae\xb9")
    else
        self:_renderBlock(nvg, slot.child)
    end
end

--- 应用积木: 双槽咬合结构 (调用/执行)
function BlockCanvas:_renderAppBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local c = BlockDefs.Colors.application
    local rad = 6

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, rad)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 40))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], isSelected and 240 or 140))
    nvgStrokeWidth(nvg, isSelected and 2 or 1.2)
    nvgStroke(nvg)

    -- 上高光
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 1, y + 1, w - 2, h * 0.35, rad)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 12))
    nvgFill(nvg)

    -- 顶部小标签: "调用"
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 9)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(100, 220, 160, 140))
    nvgText(nvg, x + w / 2, y + 2, "\xe2\x96\xb6 \xe8\xb0\x83\xe7\x94\xa8")

    -- 中间连接器箭头
    local funcSlot = block.slots.func
    local argSlot = block.slots.arg
    local midX = x + (funcSlot.rx or 0) + (funcSlot.rw or 56) + BlockDefs.GAP
    local midY = y + h / 2
    nvgFontSize(nvg, 16)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 200, 60, 200))
    nvgText(nvg, midX + 8, midY, "\xe2\x86\x90")

    -- 箭头下方说明
    nvgFontSize(nvg, 8)
    nvgFillColor(nvg, nvgRGBA(255, 200, 60, 120))
    nvgText(nvg, midX + 8, midY + 12, "\xe5\x96\x82\xe5\x85\xa5")

    -- func slot (左侧 - 函数/机器)
    self:_renderSlot(nvg, block, "func", "\xe6\x94\xbe\xe5\x87\xbd\xe6\x95\xb0", {140, 100, 240})
    -- arg slot (右侧 - 参数/材料)
    self:_renderSlot(nvg, block, "arg", "\xe6\x94\xbe\xe5\x8f\x82\xe6\x95\xb0", {80, 200, 220})
end

function BlockCanvas:_renderSlot(nvg, block, slotKey, placeholder, hintColor)
    local slot = block.slots[slotKey]
    if not slot then return end

    hintColor = hintColor or {255, 255, 255}

    if slot.child then
        self:_renderBlock(nvg, slot.child)
    else
        local sx = block.x + (slot.rx or 0)
        local sy = block.y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H

        -- 用色彩区分不同类型的插槽
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, sx, sy, sw, sh, 4)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 15))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 50))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- 占位符文字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 80))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, placeholder)
    end
end

return BlockCanvas
