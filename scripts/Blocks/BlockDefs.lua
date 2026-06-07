-- ============================================================================
-- Blocks/BlockDefs.lua - 积木定义、布局计算、吸附逻辑
-- ============================================================================
-- Block 是 AST 节点的可视化表达
-- 每个 Block 有 slots (插槽) 供其他 Block 嵌入

local AST = require("Lambda.AST")

local BlockDefs = {}

-- ============================================================================
-- 常量
-- ============================================================================

BlockDefs.PADDING = 10
BlockDefs.SLOT_MIN_W = 56
BlockDefs.SLOT_MIN_H = 30
BlockDefs.HEADER_H = 26
BlockDefs.VAR_H = 30
BlockDefs.GAP = 8
BlockDefs.SNAP_RADIUS = 28

-- 颜色方案 (Frutiger Aero + Arknights: 玻璃质感科幻)
BlockDefs.Colors = {
    variable    = { 80, 200, 220, 230 },   -- 青色胶囊
    abstraction = { 140, 100, 240, 230 },  -- 紫色 C 形
    application = { 60, 160, 120, 230 },   -- 绿色咬合
    slot_empty  = { 255, 255, 255, 30 },   -- 空槽位
    slot_hover  = { 255, 255, 100, 60 },   -- 吸附高亮
    text        = { 255, 255, 255, 240 },
    border      = { 255, 255, 255, 80 },
    glow        = { 100, 200, 255, 40 },
}

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

--- 创建 Variable 积木
function BlockDefs.createVar(name)
    return {
        id = newBlockId(),
        kind = "variable",
        name = name,
        slots = {},
        parent = nil,
        parentSlotKey = nil,
        x = 0, y = 0,
        w = 0, h = 0,  -- 由 measure 计算
    }
end

--- 创建 Abstraction 积木 (λparam.body)
function BlockDefs.createAbs(paramName)
    return {
        id = newBlockId(),
        kind = "abstraction",
        param = paramName or "x",
        slots = {
            body = { child = nil },
        },
        parent = nil,
        parentSlotKey = nil,
        x = 0, y = 0,
        w = 0, h = 0,
    }
end

--- 创建 Application 积木 (func arg)
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
        x = 0, y = 0,
        w = 0, h = 0,
    }
end

-- ============================================================================
-- 布局计算（递归测量）
-- ============================================================================

--- 测量文本宽度估算（简易方式: 每字符约 8px）
local function estimateTextWidth(text, fontSize)
    if not text then return 40 end
    -- 中文字符宽度约等于 fontSize，ASCII 约等于 fontSize * 0.6
    local w = 0
    for _ in text:gmatch("[%z\1-\127]") do w = w + (fontSize or 12) * 0.6 end
    for _ in text:gmatch("[\194-\244][\128-\191]+") do w = w + (fontSize or 12) end
    if w < 20 then w = #text * 7 end
    return w
end

--- 递归测量 block 的尺寸，同时计算各 slot 的相对坐标
function BlockDefs.measure(block)
    local P = BlockDefs.PADDING
    local SM_W = BlockDefs.SLOT_MIN_W
    local SM_H = BlockDefs.SLOT_MIN_H
    local HH = BlockDefs.HEADER_H

    if block.kind == "variable" then
        local textW = estimateTextWidth(block.name, 13)
        block.w = math.max(60, textW + P * 2 + 16)
        block.h = BlockDefs.VAR_H

    elseif block.kind == "abstraction" then
        -- 测量 body 子积木
        local bodyW, bodyH = SM_W, SM_H
        if block.slots.body.child then
            BlockDefs.measure(block.slots.body.child)
            bodyW = block.slots.body.child.w
            bodyH = block.slots.body.child.h
        end
        -- C 形容器: header + body + 底部
        local leftThick = 10  -- C 形左侧厚度
        block.w = leftThick + P + bodyW + P
        block.h = HH + P + bodyH + P
        -- 记录 slot 的相对位置（用于渲染和吸附检测）
        block.slots.body.rx = leftThick + P
        block.slots.body.ry = HH + P
        block.slots.body.rw = bodyW
        block.slots.body.rh = bodyH

    elseif block.kind == "application" then
        -- 测量 func 和 arg
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
        local gap = BlockDefs.GAP
        local connectorW = 16  -- 中间咬合图形宽度
        block.w = P + funcW + gap + connectorW + gap + argW + P
        block.h = P + math.max(funcH, argH) + P
        -- slot 相对位置
        local maxH = math.max(funcH, argH)
        block.slots.func.rx = P
        block.slots.func.ry = P + (maxH - funcH) / 2
        block.slots.func.rw = funcW
        block.slots.func.rh = funcH
        block.slots.arg.rx = P + funcW + gap + connectorW + gap
        block.slots.arg.ry = P + (maxH - argH) / 2
        block.slots.arg.rw = argW
        block.slots.arg.rh = argH
    end
end

--- 递归定位：根据父级位置确定所有子积木的绝对坐标
function BlockDefs.layout(block, ox, oy)
    block.x = ox
    block.y = oy
    for _, slot in pairs(block.slots) do
        if slot.child then
            BlockDefs.layout(slot.child, ox + (slot.rx or 0), oy + (slot.ry or 0))
        end
    end
end

-- ============================================================================
-- 吸附检测
-- ============================================================================

--- 查找最近的合法吸附点
---@param dragBlock table   被拖拽的积木
---@param allBlocks table[] 画布上所有根积木
---@param cursorX number|nil 鼠标光标的画布 X 坐标（若提供则用光标位置判定吸附）
---@param cursorY number|nil 鼠标光标的画布 Y 坐标
---@return table|nil  { targetBlock, slotKey, dist }
function BlockDefs.findSnapTarget(dragBlock, allBlocks, cursorX, cursorY)
    local best = nil
    local bestDist = BlockDefs.SNAP_RADIUS
    -- 使用光标位置（如果提供），否则回退到积木中心
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

-- 递归搜索所有空 slot
function BlockDefs._searchSlots(block, dragBlock, dcx, dcy, threshold, callback)
    -- 不检测自身
    if block.id == dragBlock.id then return end
    -- 不检测 dragBlock 的子孙
    if BlockDefs.isDescendant(block, dragBlock) then return end

    for key, slot in pairs(block.slots) do
        if slot.child == nil then
            -- 计算 slot 的绝对中心
            local scx = block.x + (slot.rx or 0) + (slot.rw or BlockDefs.SLOT_MIN_W) / 2
            local scy = block.y + (slot.ry or 0) + (slot.rh or BlockDefs.SLOT_MIN_H) / 2
            local dx = dcx - scx
            local dy = dcy - scy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < threshold then
                callback(block, key, dist)
            end
        else
            -- 递归进入子积木
            BlockDefs._searchSlots(slot.child, dragBlock, dcx, dcy, threshold, callback)
        end
    end
end

--- 检查 block 是否是 potentialParent 的子孙
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

--- 将 dragBlock 吸附到 target 的 slotKey
function BlockDefs.attach(dragBlock, targetBlock, slotKey)
    -- 先从旧父级断开
    BlockDefs.detach(dragBlock)
    -- 建立关系
    targetBlock.slots[slotKey].child = dragBlock
    dragBlock.parent = targetBlock
    dragBlock.parentSlotKey = slotKey
end

--- 从父级分离
function BlockDefs.detach(block)
    if block.parent and block.parentSlotKey then
        block.parent.slots[block.parentSlotKey].child = nil
    end
    block.parent = nil
    block.parentSlotKey = nil
end

-- ============================================================================
-- 从 Block 树重建 AST
-- ============================================================================

function BlockDefs.toAST(block)
    if block == nil then return nil end

    if block.kind == "variable" then
        return AST.Var(block.name)

    elseif block.kind == "abstraction" then
        local bodyAST = nil
        if block.slots.body.child then
            bodyAST = BlockDefs.toAST(block.slots.body.child)
        end
        return AST.Abs(block.param, bodyAST)

    elseif block.kind == "application" then
        local funcAST = nil
        local argAST = nil
        if block.slots.func.child then
            funcAST = BlockDefs.toAST(block.slots.func.child)
        end
        if block.slots.arg.child then
            argAST = BlockDefs.toAST(block.slots.arg.child)
        end
        return AST.App(funcAST, argAST)
    end

    return nil
end

--- 收集一棵 block 树中的所有 block（扁平列表）
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

--- 找到某 block 的根节点
function BlockDefs.findRoot(block)
    local current = block
    while current.parent do
        current = current.parent
    end
    return current
end

return BlockDefs
