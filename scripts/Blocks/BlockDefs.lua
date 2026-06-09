-- ============================================================================
-- Blocks/BlockDefs.lua - 积木定义、布局计算、吸附逻辑
-- ============================================================================
-- 设计原则 v3：扁平水平拼图
--   1. 半圆凸起(bump)完美嵌入半圆凹口(indent)—— 几何严格咬合
--   2. 所有积木扁平水平排列 —— 取消容器嵌套
--   3. Application 不可见 —— func 和 arg 直接 bump⊃⊂indent 咬合
--   4. Abstraction 不是容器 —— [λx头]⊃⊂[body] 水平排列

local AST = require("Lambda.AST")

local BlockDefs = {}

-- ============================================================================
-- 常量
-- ============================================================================

BlockDefs.BLOCK_H = 38       -- 标准积木高度
BlockDefs.BUMP_R = 7         -- 半圆凸起/凹口半径（关键咬合尺寸）
BlockDefs.HEADER_W = 46      -- λx 头部宽度
BlockDefs.VAR_PAD = 14       -- 变量积木文本水平 padding
BlockDefs.SLOT_MIN_W = 48    -- 空槽最小宽度
BlockDefs.SLOT_MIN_H = 36    -- 空槽最小高度
BlockDefs.CORNER_R = 4       -- 积木圆角半径
BlockDefs.SNAP_RADIUS = 30

-- ============================================================================
-- 参数名 → 色相映射系统
-- ============================================================================

local PARAM_HUES = {
    x = 200,  y = 140,  z = 320,  f = 45,   g = 270,
    n = 170,  m = 10,   a = 60,   b = 230,  p = 100,
    q = 290,  s = 350,  t = 80,
}

function BlockDefs.getParamHue(name)
    if not name then return 200 end
    if PARAM_HUES[name] then return PARAM_HUES[name] end
    local b = string.byte(name, 1) or 120
    return (b * 37) % 360
end

function BlockDefs.hslToRGBA(hue, sat, lit, alpha)
    local h = hue / 360
    local s, l = sat, lit
    local function hue2rgb(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    local r, g, b
    if s == 0 then
        r, g, b = l, l, l
    else
        local q2 = l < 0.5 and (l * (1 + s)) or (l + s - l * s)
        local p = 2 * l - q2
        r = hue2rgb(p, q2, h + 1/3)
        g = hue2rgb(p, q2, h)
        b = hue2rgb(p, q2, h - 1/3)
    end
    return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), alpha or 230
end

function BlockDefs.getParamColor(name, sat, lit, alpha)
    local hue = BlockDefs.getParamHue(name)
    return BlockDefs.hslToRGBA(hue, sat or 0.7, lit or 0.6, alpha or 230)
end

-- ============================================================================
-- Block ID 生成
-- ============================================================================

local blockIdCounter = 0
local function newBlockId()
    blockIdCounter = blockIdCounter + 1
    return "blk_" .. blockIdCounter
end

-- ============================================================================
-- Block 构造器
-- ============================================================================

function BlockDefs.createVar(name)
    return {
        id = newBlockId(),
        kind = "variable",
        name = name,
        slots = {},
        parent = nil,
        parentSlotKey = nil,
        x = 0, y = 0, w = 0, h = 0,
    }
end

function BlockDefs.createAbs(paramName)
    return {
        id = newBlockId(),
        kind = "abstraction",
        param = paramName or "x",
        slots = { body = { child = nil } },
        parent = nil,
        parentSlotKey = nil,
        x = 0, y = 0, w = 0, h = 0,
    }
end

function BlockDefs.createApp()
    return {
        id = newBlockId(),
        kind = "application",
        slots = {
            func = { child = nil },
            arg  = { child = nil },
        },
        parent = nil,
        parentSlotKey = nil,
        x = 0, y = 0, w = 0, h = 0,
    }
end

-- ============================================================================
-- 布局计算 — 全扁平水平拼图
-- ============================================================================
-- 核心原则:
--   每个积木的「body宽度」不含外部凸起/凹口（那是视觉叠加层）
--   连接时，左块的右侧 bump 视觉上嵌入右块左侧 indent
--   Layout 只关心 body width——bump/indent 由渲染层画出

local function estimateTextWidth(text, fontSize)
    if not text then return 40 end
    local w = 0
    for _ in text:gmatch("[%z\1-\127]") do w = w + (fontSize or 14) * 0.6 end
    for _ in text:gmatch("[\194-\244][\128-\191]+") do w = w + (fontSize or 14) end
    if w < 20 then w = #text * 8 end
    return w
end

function BlockDefs.measure(block)
    local BH = BlockDefs.BLOCK_H
    local HW = BlockDefs.HEADER_W
    local SM_W = BlockDefs.SLOT_MIN_W
    local SM_H = BlockDefs.SLOT_MIN_H

    -- 积木组 collapsed → 壳尺寸（紧凑）
    if BlockDefs.isCollapsedGroup(block) then
        local group = block.group
        local nameW = estimateTextWidth(group.name, 15)
        local paramW = 0
        if group.params and group.params ~= "" then
            paramW = estimateTextWidth(group.params, 11) + 4
        end
        local indicatorW = 16  -- 右侧折叠指示符 "▸"
        block.w = math.max(BlockDefs.GROUP_MIN_W, 8 + nameW + paramW + indicatorW + 6)
        block.h = BH
        return
    end

    if block.kind == "variable" then
        local textW = estimateTextWidth(block.name, 14)
        block.w = math.max(52, textW + BlockDefs.VAR_PAD * 2)
        block.h = BH

    elseif block.kind == "abstraction" then
        -- 扁平水平: [λx header] 紧接 [body]
        local bodyW, bodyH = SM_W, SM_H
        if block.slots.body.child then
            BlockDefs.measure(block.slots.body.child)
            bodyW = block.slots.body.child.w
            bodyH = block.slots.body.child.h
        end
        block.w = HW + bodyW
        block.h = math.max(BH, bodyH)
        -- body slot 位于 header 右侧
        block.slots.body.rx = HW
        block.slots.body.ry = (block.h - bodyH) / 2
        block.slots.body.rw = bodyW
        block.slots.body.rh = bodyH

    elseif block.kind == "application" then
        -- 扁平水平: [func] 紧接 [arg]
        local funcW, funcH = SM_W, SM_H
        local argW, argH = SM_W, SM_H
        if block.slots.func.child then
            BlockDefs.measure(block.slots.func.child)
            funcW = block.slots.func.child.w
            funcH = block.slots.func.child.h
        end
        if block.slots.arg.child then
            BlockDefs.measure(block.slots.arg.child)
            argW = block.slots.arg.child.w
            argH = block.slots.arg.child.h
        end
        block.w = funcW + argW
        block.h = math.max(funcH, argH)
        local maxH = block.h
        block.slots.func.rx = 0
        block.slots.func.ry = (maxH - funcH) / 2
        block.slots.func.rw = funcW
        block.slots.func.rh = funcH
        block.slots.arg.rx = funcW
        block.slots.arg.ry = (maxH - argH) / 2
        block.slots.arg.rw = argW
        block.slots.arg.rh = argH
    end
end

function BlockDefs.layout(block, ox, oy)
    block.x = ox
    block.y = oy
    -- 积木组 collapsed → 不展开内部子块布局
    if BlockDefs.isCollapsedGroup(block) then return end
    for _, slot in pairs(block.slots) do
        if slot.child then
            BlockDefs.layout(slot.child, ox + (slot.rx or 0), oy + (slot.ry or 0))
        end
    end
end

-- ============================================================================
-- 吸附检测
-- ============================================================================

function BlockDefs.findSnapTarget(dragBlock, allBlocks, cursorX, cursorY)
    local best = nil
    local bestDist = BlockDefs.SNAP_RADIUS
    local dcx = cursorX or (dragBlock.x + dragBlock.w / 2)
    local dcy = cursorY or (dragBlock.y + dragBlock.h / 2)
    for _, root in ipairs(allBlocks) do
        BlockDefs._searchSlots(root, dragBlock, dcx, dcy, bestDist, function(target, slotKey, dist)
            if dist < bestDist then
                bestDist = dist
                best = { targetBlock = target, slotKey = slotKey, dist = dist }
            end
        end)
    end
    return best
end

function BlockDefs._searchSlots(block, dragBlock, dcx, dcy, threshold, callback)
    if block.id == dragBlock.id then return end
    if BlockDefs.isDescendant(block, dragBlock) then return end
    for key, slot in pairs(block.slots) do
        if slot.child == nil then
            local scx = block.x + (slot.rx or 0) + (slot.rw or BlockDefs.SLOT_MIN_W) / 2
            local scy = block.y + (slot.ry or 0) + (slot.rh or BlockDefs.SLOT_MIN_H) / 2
            local dx = dcx - scx
            local dy = dcy - scy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < threshold then
                callback(block, key, dist)
            end
        else
            BlockDefs._searchSlots(slot.child, dragBlock, dcx, dcy, threshold, callback)
        end
    end
end

function BlockDefs.isDescendant(block, potentialParent)
    for _, slot in pairs(potentialParent.slots) do
        if slot.child then
            if slot.child.id == block.id then return true end
            if BlockDefs.isDescendant(block, slot.child) then return true end
        end
    end
    return false
end

-- ============================================================================
-- 吸附/分离操作
-- ============================================================================

function BlockDefs.attach(dragBlock, targetBlock, slotKey)
    BlockDefs.detach(dragBlock)
    targetBlock.slots[slotKey].child = dragBlock
    dragBlock.parent = targetBlock
    dragBlock.parentSlotKey = slotKey
end

function BlockDefs.detach(block)
    if block.parent and block.parentSlotKey then
        block.parent.slots[block.parentSlotKey].child = nil
    end
    block.parent = nil
    block.parentSlotKey = nil
end

-- ============================================================================
-- AST 重建
-- ============================================================================

function BlockDefs.toAST(block)
    if block == nil then return nil end
    if block.kind == "variable" then
        return AST.Var(block.name)
    elseif block.kind == "abstraction" then
        local bodyAST = block.slots.body.child and BlockDefs.toAST(block.slots.body.child) or nil
        return AST.Abs(block.param, bodyAST)
    elseif block.kind == "application" then
        local funcAST = block.slots.func.child and BlockDefs.toAST(block.slots.func.child) or nil
        local argAST = block.slots.arg.child and BlockDefs.toAST(block.slots.arg.child) or nil
        return AST.App(funcAST, argAST)
    end
    return nil
end

function BlockDefs.collectAll(block, list)
    list = list or {}
    table.insert(list, block)
    for _, slot in pairs(block.slots) do
        if slot.child then
            BlockDefs.collectAll(slot.child, list)
        end
    end
    return list
end

function BlockDefs.findRoot(block)
    local current = block
    while current.parent do
        current = current.parent
    end
    return current
end

-- ============================================================================
-- 积木组 (Block Group) — 预制积木封装壳
-- ============================================================================
-- 设计:
--   group 信息挂在根积木上: block.group = { name, params, collapsed }
--   collapsed=true 时: 整棵树渲染为单个壳（带连接器）
--   collapsed=false 时: 正常渲染内部积木
--   双击壳 → 展开（碎裂动画）；长按/右键 → 收起

BlockDefs.GROUP_SHELL_PAD_X = 10   -- 壳内水平 padding
BlockDefs.GROUP_SHELL_PAD_Y = 4    -- 壳内垂直 padding
BlockDefs.GROUP_MIN_W = 72         -- 壳最小宽度

--- 预制积木参数映射表
BlockDefs.PRESET_PARAMS = {
    I     = "x",
    K     = "x,y",
    KI    = "x,y",
    S     = "x,y,z",
    TRUE  = "t,f",
    FALSE = "t,f",
    NOT   = "b",
    AND   = "p,q",
    OR    = "p,q",
    ZERO  = "f,x",
    ONE   = "f,x",
    TWO   = "f,x",
    SUCC  = "n,f,x",
    ADD   = "m,n",
    MUL   = "m,n,f",
    POW   = "m,n",
    PAIR  = "a,b,f",
    CALC  = "op,m,n",
}

--- 积木组颜色分类（按功能域，每组 {顶色r,g,b,a, 底色r,g,b,a}）
BlockDefs.GROUP_COLORS = {
    combinator = { top = {80, 70, 140, 230},  bot = {55, 45, 105, 240} },  -- 紫蓝 — 组合子
    boolean    = { top = {45, 110, 80, 230},   bot = {30, 80, 58, 240} },   -- 翡翠绿 — 布尔
    number     = { top = {140, 95, 40, 230},   bot = {105, 70, 25, 240} },  -- 琥珀 — Church数
    arith      = { top = {140, 55, 55, 230},   bot = {105, 38, 38, 240} },  -- 珊瑚红 — 算术
    data       = { top = {45, 100, 120, 230},  bot = {30, 72, 90, 240} },   -- 青蓝 — 数据结构
}

--- 预制积木 → 颜色分类映射
BlockDefs.PRESET_COLOR_CATEGORY = {
    I     = "combinator",
    K     = "combinator",
    KI    = "combinator",
    S     = "combinator",
    TRUE  = "boolean",
    FALSE = "boolean",
    NOT   = "boolean",
    AND   = "boolean",
    OR    = "boolean",
    ZERO  = "number",
    ONE   = "number",
    TWO   = "number",
    SUCC  = "arith",
    ADD   = "arith",
    MUL   = "arith",
    POW   = "arith",
    PAIR  = "data",
    CALC  = "data",
}

--- 便捷方法: 为预制积木自动包裹积木组壳
--- @param block table 已构建的积木树
--- @param presetName string 预制名（如 "TRUE"）
--- @return table 已附加 group 字段的 block
function BlockDefs.wrapPresetAsGroup(block, presetName)
    local params = BlockDefs.PRESET_PARAMS[presetName] or ""
    local category = BlockDefs.PRESET_COLOR_CATEGORY[presetName] or "combinator"
    local color = BlockDefs.GROUP_COLORS[category]
    return BlockDefs.wrapAsGroup(block, presetName, params, color)
end

--- 计算积木树节点总数（用于完整性签名）
--- @param block table
--- @return integer
function BlockDefs.countTreeNodes(block)
    if not block then return 0 end
    local count = 1
    if block.slots then
        for _, slot in pairs(block.slots) do
            if slot.child then
                count = count + BlockDefs.countTreeNodes(slot.child)
            end
        end
    end
    return count
end

--- 为积木树附加积木组壳
--- @param block table 根积木（已构建好的完整积木树）
--- @param name string 显示名称（如 "TRUE", "SUCC"）
--- @param params? string 参数列表文字（如 "t,f"）
--- @param color? table 颜色配置 {top={r,g,b,a}, bot={r,g,b,a}}
--- @return table 原 block（已附加 group 字段）
function BlockDefs.wrapAsGroup(block, name, params, color)
    block.group = {
        name = name,
        params = params or "",
        color = color,
        collapsed = true,
        signature = BlockDefs.countTreeNodes(block),
    }
    return block
end

--- 检测积木组是否可以收起（结构未被破坏）
--- @param block table
--- @return boolean
function BlockDefs.canCollapseGroup(block)
    if not block.group then return false end
    local sig = block.group.signature
    if not sig then return true end  -- 无签名则允许（兼容旧数据）
    return BlockDefs.countTreeNodes(block) == sig
end

--- 展开积木组壳
function BlockDefs.expandGroup(block)
    if block.group then
        block.group.collapsed = false
    end
end

--- 收起积木组壳（不检查完整性，由调用方先调 canCollapseGroup）
function BlockDefs.collapseGroup(block)
    if block.group then
        block.group.collapsed = true
    end
end

--- 检测积木是否是收起状态的积木组
function BlockDefs.isCollapsedGroup(block)
    return block.group ~= nil and block.group.collapsed == true
end

return BlockDefs
