-- ============================================================================
-- Blocks/BlockRenderer.lua
-- 积木渲染 v3 — 半圆拼图咬合 + 扁平水平排列
-- ============================================================================
-- 职责: 「积木长什么样」—— 纯渲染，不含交互/动画逻辑
-- 从 BlockCanvas.lua 提取，降低单文件复杂度
--
-- 设计原则:
--   1. 半圆 bump (⊃) 完美嵌入半圆 indent (⊂) — 拼图几何
--   2. Variable: 扁平药片，右侧 bump + 左侧 indent
--   3. Abstraction: 扁平 [λx 头] bump⊃⊂indent [body]，不是容器
--   4. Application: 不可见，func bump⊃⊂indent arg 直接咬合

local BlockDefs = require("Blocks.BlockDefs")

local M = {}

-- ============================================================================
-- 常量
-- ============================================================================

local NVG_CW = 2
local NVG_CCW = 1

-- ============================================================================
-- 核心几何: 拼图块路径
-- ============================================================================

--- 画拼图块路径（核心几何）
--- hasLeftIndent: 左侧是否有半圆凹口
--- hasRightBump: 右侧是否有半圆凸起
function M.drawPiecePath(nvg, x, y, w, h, hasLeftIndent, hasRightBump)
    local R = BlockDefs.BUMP_R
    local cr = BlockDefs.CORNER_R
    local cy = y + h / 2

    nvgBeginPath(nvg)

    -- 起点: 左上角
    nvgMoveTo(nvg, x + cr, y)

    -- ═══ 顶边 ═══
    nvgLineTo(nvg, x + w - cr, y)

    -- ═══ 右上圆角 ═══
    nvgArcTo(nvg, x + w, y, x + w, y + cr, cr)

    -- ═══ 右边（含 bump）═══
    if hasRightBump then
        nvgLineTo(nvg, x + w, cy - R)
        -- 半圆凸起: 向右突出 R 像素
        nvgArc(nvg, x + w, cy, R, -math.pi / 2, math.pi / 2, NVG_CW)
    end
    nvgLineTo(nvg, x + w, y + h - cr)

    -- ═══ 右下圆角 ═══
    nvgArcTo(nvg, x + w, y + h, x + w - cr, y + h, cr)

    -- ═══ 底边 ═══
    nvgLineTo(nvg, x + cr, y + h)

    -- ═══ 左下圆角 ═══
    nvgArcTo(nvg, x, y + h, x, y + h - cr, cr)

    -- ═══ 左边（含 indent）═══
    if hasLeftIndent then
        nvgLineTo(nvg, x, cy + R)
        -- 半圆凹口: 向右凹入 R 像素（与 bump 完美互补）
        nvgArc(nvg, x, cy, R, math.pi / 2, -math.pi / 2, NVG_CCW)
    end
    nvgLineTo(nvg, x, y + cr)

    -- ═══ 左上圆角 ═══
    nvgArcTo(nvg, x, y, x + cr, y, cr)

    nvgClosePath(nvg)
end

-- ============================================================================
-- 上下文连接器判断
-- ============================================================================

--- 判断积木是否处于「右侧位置」（需要左侧 indent）
function M.needsLeftIndent(block)
    if not block.parent then return false end
    -- 作为 arg 或 body slot 的子块 → 左侧有 indent
    return block.parentSlotKey == "arg" or block.parentSlotKey == "body"
end

--- 判断积木是否处于「左侧位置」（需要右侧 bump）
function M.needsRightBump(block)
    if not block.parent then return false end
    -- 作为 func slot 的子块 → 右侧有 bump
    return block.parentSlotKey == "func"
end

-- ============================================================================
-- 积木渲染入口
-- ============================================================================

--- 渲染单个积木（根据 kind 分发）
--- @param nvg userdata NanoVG context
--- @param block table 积木数据
--- @param isSelected boolean 是否选中
function M.renderBlock(nvg, block, isSelected)
    if block.kind == "variable" then
        M.renderVarBlock(nvg, block, isSelected)
    elseif block.kind == "abstraction" then
        M.renderAbsBlock(nvg, block, isSelected)
    elseif block.kind == "application" then
        M.renderAppBlock(nvg, block, isSelected)
    end
end

-- ============================================================================
-- 变量积木: 扁平药片 + 半圆连接器
-- ============================================================================

function M.renderVarBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h

    -- 根据上下文决定连接器
    local leftIndent = M.needsLeftIndent(block)
    local rightBump = M.needsRightBump(block)

    -- 颜色
    local paramName = block.boundParam or block.name
    local cr, cg, cb = BlockDefs.getParamColor(paramName, 0.7, 0.55)

    -- 画拼图形状
    M.drawPiecePath(nvg, x, y, w, h, leftIndent, rightBump)

    -- 实心填充
    nvgFillColor(nvg, nvgRGBA(cr, cg, cb, 210))
    nvgFill(nvg)

    -- 描边
    nvgStrokeColor(nvg, nvgRGBA(
        math.min(255, cr + 60), math.min(255, cg + 60), math.min(255, cb + 60),
        isSelected and 255 or 180
    ))
    nvgStrokeWidth(nvg, isSelected and 2.5 or 1.5)
    nvgStroke(nvg)

    -- 顶部高光（3D 立体感）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 4, y + 2, w - 8, h * 0.3, 3)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 40))
    nvgFill(nvg)

    -- 底部阴影
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 4, y + h * 0.72, w - 8, h * 0.22, 3)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 30))
    nvgFill(nvg)

    -- 变量名文字
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 250))
    nvgText(nvg, x + w / 2, y + h / 2, block.name)
end

-- ============================================================================
-- 抽象积木: [λx 头部] bump⊃⊂indent [body] — 扁平水平拼图
-- ============================================================================

function M.renderAbsBlock(nvg, block, isSelected)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local HW = BlockDefs.HEADER_W
    local R = BlockDefs.BUMP_R

    -- 颜色
    local cr, cg, cb = BlockDefs.getParamColor(block.param, 0.55, 0.45)

    -- 上下文连接器
    local leftIndent = M.needsLeftIndent(block)
    -- 头部右侧始终有 bump（连接到 body）
    local headerRightBump = true

    -- ═══ 画头部: [λx] ═══
    M.drawPiecePath(nvg, x, y, HW, h, leftIndent, headerRightBump)

    -- 头部填充（深色，与 body 区分）
    nvgFillColor(nvg, nvgRGBA(cr, cg, cb, 180))
    nvgFill(nvg)

    -- 头部描边
    nvgStrokeColor(nvg, nvgRGBA(
        math.min(255, cr + 50), math.min(255, cg + 50), math.min(255, cb + 50),
        isSelected and 255 or 160
    ))
    nvgStrokeWidth(nvg, isSelected and 2.5 or 1.5)
    nvgStroke(nvg)

    -- 头部顶部高光
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x + 4, y + 2, HW - 8, h * 0.28, 3)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 35))
    nvgFill(nvg)

    -- "λx" 文字
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
    nvgText(nvg, x + HW / 2, y + h / 2, "\xce\xbb" .. block.param)

    -- ═══ body 部分 ═══
    local slot = block.slots.body
    if slot.child then
        -- body 子块自己负责渲染（它的左侧会有 indent）
        M.renderBlock(nvg, slot.child, false)
    else
        -- 空 body slot: 画出有 indent 形状的虚线框
        local sx = x + (slot.rx or 0)
        local sy = y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H

        M.drawPiecePath(nvg, sx, sy, sw, sh, true, false)
        nvgFillColor(nvg, nvgRGBA(cr, cg, cb, 15))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(cr, cg, cb, 60))
        nvgStrokeWidth(nvg, 1.0)
        nvgStroke(nvg)

        -- 占位文字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 50))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, "body")
    end

    -- 选中整体高亮
    if isSelected then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 2, y - 2, w + 4, h + 4, 6)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 100, 80))
        nvgStrokeWidth(nvg, 1.5)
        nvgStroke(nvg)
    end
end

-- ============================================================================
-- 应用积木: 完全不可见 —— func 和 arg 通过 bump⊃⊂indent 直接咬合
-- ============================================================================

function M.renderAppBlock(nvg, block, isSelected)
    -- 选中时微弱边框提示
    if isSelected then
        local x, y, w, h = block.x, block.y, block.w, block.h
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 1, y - 1, w + 2, h + 2, 3)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 35))
        nvgStrokeWidth(nvg, 0.8)
        nvgStroke(nvg)
    end

    -- 渲染 func 和 arg（它们的 bump/indent 自动互锁）
    M.renderSlot(nvg, block, "func", "\xce\xbb", {140, 100, 240})
    M.renderSlot(nvg, block, "arg", "?", {80, 200, 220})
end

-- ============================================================================
-- Slot 渲染（有子块则递归渲染，空则画占位形状）
-- ============================================================================

function M.renderSlot(nvg, block, slotKey, placeholder, hintColor)
    local slot = block.slots[slotKey]
    if not slot then return end

    if slot.child then
        M.renderBlock(nvg, slot.child, false)
    else
        -- 空 slot: 画拼图形状轮廓
        local sx = block.x + (slot.rx or 0)
        local sy = block.y + (slot.ry or 0)
        local sw = slot.rw or BlockDefs.SLOT_MIN_W
        local sh = slot.rh or BlockDefs.SLOT_MIN_H

        -- func slot 左侧有 indent（接收外部），右侧有 bump（准备连 arg）
        -- arg slot 左侧有 indent（接收 func 的 bump）
        local leftIndent = (slotKey == "arg") or (slotKey == "body")
        local rightBump = (slotKey == "func")

        hintColor = hintColor or {100, 120, 160}
        M.drawPiecePath(nvg, sx, sy, sw, sh, leftIndent, rightBump)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 15))
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 50))
        nvgStrokeWidth(nvg, 1.0)
        nvgStroke(nvg)

        -- 占位符文字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(hintColor[1], hintColor[2], hintColor[3], 50))
        nvgText(nvg, sx + sw / 2, sy + sh / 2, placeholder)
    end
end

return M
