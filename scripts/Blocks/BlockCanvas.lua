-- ============================================================================
-- Blocks/BlockCanvas.lua - 积木工作区画布 Widget
-- ============================================================================
-- Widget:Extend 自绘组件：NanoVG 渲染积木 + 拖拽吸附交互
-- 实现 Scratch-like 积木拼装体验

---@diagnostic disable: param-type-mismatch

local Widget = require("urhox-libs/UI/Core/Widget")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local BlockDefs = require("Blocks.BlockDefs")
local BlockRenderer = require("Blocks.BlockRenderer")
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
    self.timedActions_ = {}   -- { delay, fired, fn } 定时动作（延迟触发回调）

    -- 碎裂粒子动画
    self.shatterAnims_ = {}   -- { particles[], elapsed, duration, alive }

    -- 破壳动画（壳渐隐+粒子 同时 body 从壳内显现弹出）
    self.breakShellAnims_ = {} -- { shellBlock, newBlock, targetX, targetY, particles[], elapsed, duration, alive }

    -- 积木过渡动画
    self.transition_ = nil  -- { oldBlocks, elapsed, duration }

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

--- 添加飞行积木动画（真实积木从 from 飞到 to）
---@param text string 显示文本（flyBlock 为 nil 时 fallback）
---@param fromX number 起始 X（画布坐标）
---@param fromY number 起始 Y
---@param toX number 目标 X
---@param toY number 目标 Y
---@param duration number 持续时间（秒）
---@param color? number[] RGBA 颜色
---@param delay? number 延迟开始（秒）
---@param flyBlock? table 真实 Block 对象，飞行时用 _renderBlock 渲染
function BlockCanvas:AddFlowAnim(text, fromX, fromY, toX, toY, duration, color, delay, flyBlock)
    -- 如果传入了 block，确保它已测量布局到 (0,0)
    if flyBlock then
        BlockDefs.measure(flyBlock)
        BlockDefs.layout(flyBlock, 0, 0)
    end
    table.insert(self.flowAnims_, {
        text = text,
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        elapsed = -(delay or 0),
        duration = duration or 0.5,
        color = color or { 100, 220, 255 },
        alive = true,
        flyBlock = flyBlock,  -- 真实积木对象
    })
end

--- 添加积木闪烁效果
function BlockCanvas:AddFlashBlock(block, duration, color, delay)
    table.insert(self.flashBlocks_, {
        block = block,
        elapsed = -(delay or 0),
        duration = duration or 0.4,
        color = color or { 255, 255, 100 },
        alive = true,
    })
end

--- 添加槽位高亮动画（精确显示数据进入/输出的槽位）
---@param block table 包含槽位的积木
---@param slotKey string 槽位名称 ("body", "func", "arg")
---@param duration number 持续时间
---@param color number[] 颜色
---@param delay number 延迟
function BlockCanvas:AddSlotHighlight(block, slotKey, duration, color, delay)
    table.insert(self.flashBlocks_, {
        block = block,
        slotKey = slotKey,  -- 非 nil 时只高亮指定槽位
        elapsed = -(delay or 0),
        duration = duration or 0.5,
        color = color or { 100, 220, 255 },
        alive = true,
    })
end

--- 添加替换指示器动画（在积木附近显示 "x → value" 文字标签）
---@param x number 画布 X
---@param y number 画布 Y
---@param text string 显示文本（如 "x → 2"）
---@param duration number 持续时间
---@param color number[] 颜色
---@param delay number 延迟
function BlockCanvas:AddSubstitutionLabel(x, y, text, duration, color, delay)
    table.insert(self.flowAnims_, {
        text = text,
        fromX = x, fromY = y - 6,
        toX = x, toY = y - 14,   -- 轻微上浮
        elapsed = -(delay or 0),
        duration = duration or 0.8,
        color = color or { 255, 200, 80 },
        alive = true,
        isLabel = true,  -- 标记为静态标签（不画弧线，字体更大）
    })
end

--- 添加内部数据流动画（值从源点沿连线流向目标变量积木）
--- 带拖尾效果，展示数据在 lambda 内部的流动路径
---@param text string 显示文本（flyBlock 为 nil 时 fallback）
---@param fromX number 起始 X
---@param fromY number 起始 Y
---@param toX number 目标 X
---@param toY number 目标 Y
---@param duration number 持续时间
---@param color number[] 颜色
---@param delay number 延迟
---@param flyBlock? table 真实 Block 对象
function BlockCanvas:AddInternalFlow(text, fromX, fromY, toX, toY, duration, color, delay, flyBlock)
    if flyBlock then
        BlockDefs.measure(flyBlock)
        BlockDefs.layout(flyBlock, 0, 0)
    end
    table.insert(self.flowAnims_, {
        text = text,
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        elapsed = -(delay or 0),
        duration = duration or 0.4,
        color = color or { 255, 200, 80 },
        alive = true,
        isInternal = true,
        flyBlock = flyBlock,
    })
end

--- 添加变量替换动画（变量积木变色+变文字，展示替换结果）
---@param block table 被替换的变量积木
---@param newText string 替换后显示的文本
---@param duration number 持续时间
---@param color number[] 新颜色
---@param delay number 延迟
function BlockCanvas:AddVarReplace(block, newText, duration, color, delay)
    table.insert(self.flashBlocks_, {
        block = block,
        elapsed = -(delay or 0),
        duration = duration or 0.6,
        color = color or { 255, 200, 80 },
        alive = true,
        isReplace = true,   -- 标记为替换动画
        newText = newText,  -- 替换后的文字
    })
end

--- 添加碎裂粒子动画（λ壳消融效果）
--- 在积木边缘生成 8~12 个三角碎片向外飞散
---@param block table 目标积木（壳）
---@param duration number 持续时间
---@param delay number 延迟
function BlockCanvas:AddShatterAnim(block, duration, delay)
    local x, y, w, h = block.x, block.y, block.w, block.h
    local numParticles = math.random(8, 12)
    local particles = {}

    -- 获取积木颜色
    local cr, cg, cb = 140, 160, 200
    if block.kind == "abstraction" and block.param then
        cr, cg, cb = BlockDefs.getParamColor(block.param, 0.65, 0.5)
    end

    for i = 1, numParticles do
        -- 沿边缘随机分布
        local edge = math.random(1, 4) -- 上右下左
        local px, py
        if edge == 1 then
            px = x + math.random() * w
            py = y
        elseif edge == 2 then
            px = x + w
            py = y + math.random() * h
        elseif edge == 3 then
            px = x + math.random() * w
            py = y + h
        else
            px = x
            py = y + math.random() * h
        end

        -- 向外的初速度
        local cx, cy = x + w / 2, y + h / 2
        local dx = px - cx
        local dy = py - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1 then dist = 1 end
        local speed = 40 + math.random() * 60

        table.insert(particles, {
            x = px, y = py,
            vx = (dx / dist) * speed + (math.random() - 0.5) * 30,
            vy = (dy / dist) * speed + (math.random() - 0.5) * 30,
            rot = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 12,
            size = 4 + math.random() * 5,
            r = cr, g = cg, b = cb,
        })
    end

    table.insert(self.shatterAnims_, {
        particles = particles,
        elapsed = -(delay or 0),
        duration = duration or 0.6,
        alive = true,
    })
end

--- 破壳动画：壳渐隐+粒子飞散 + 新积木从壳内显现并弹到目标位置
--- 实现"内容从壳内破出"的视觉效果（替代 shatter + TransitionToBlock 的分离方案）
---@param shellBlock table 要碎裂的壳积木（lambda 或 application）
---@param newBlock table 结果积木（body 替换后的新树）
---@param targetX number 新积木最终 x
---@param targetY number 新积木最终 y
---@param duration number 总时长
---@param delay number 延迟
function BlockCanvas:AddBreakShellAnim(shellBlock, newBlock, targetX, targetY, duration, delay)
    duration = duration or 0.8
    local x, y, w, h = shellBlock.x, shellBlock.y, shellBlock.w, shellBlock.h

    -- 生成碎片粒子（同 shatter）
    local numParticles = math.random(10, 15)
    local particles = {}
    local cr, cg, cb = 140, 160, 200
    if shellBlock.kind == "abstraction" and shellBlock.param then
        cr, cg, cb = BlockDefs.getParamColor(shellBlock.param, 0.65, 0.5)
    end
    for i = 1, numParticles do
        local edge = math.random(1, 4)
        local px, py
        if edge == 1 then px, py = x + math.random() * w, y
        elseif edge == 2 then px, py = x + w, y + math.random() * h
        elseif edge == 3 then px, py = x + math.random() * w, y + h
        else px, py = x, y + math.random() * h
        end
        local cx, cy = x + w / 2, y + h / 2
        local dx, dy = px - cx, py - cy
        local dist = math.max(1, math.sqrt(dx * dx + dy * dy))
        local speed = 50 + math.random() * 70
        table.insert(particles, {
            x = px, y = py,
            vx = (dx / dist) * speed + (math.random() - 0.5) * 30,
            vy = (dy / dist) * speed + (math.random() - 0.5) * 30,
            rot = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 12,
            size = 4 + math.random() * 5,
            r = cr, g = cg, b = cb,
        })
    end

    -- 设置新积木测量
    BlockDefs.measure(newBlock)
    BlockDefs.layout(newBlock, targetX, targetY)

    -- 注意：壳积木暂不从 blocks_ 移除！
    -- 在 delay 期间壳仍然正常渲染；动画真正开始（elapsed>=0）时才移除。
    -- 新积木同样暂不加入 blocks_，动画结束后在 Update 中加入。

    table.insert(self.breakShellAnims_, {
        shellBlock = shellBlock,
        newBlock = newBlock,
        shellRemoved = false,  -- 标记：壳是否已从 blocks_ 移除
        -- 新积木动画：从壳中心 → 目标位置
        fromX = x + w / 2 - newBlock.w / 2,
        fromY = y + h / 2 - newBlock.h / 2,
        targetX = targetX,
        targetY = targetY,
        particles = particles,
        elapsed = -(delay or 0),
        duration = duration,
        alive = true,
    })
end

--- 添加定时动作（在指定延迟后执行回调，可用于动画中途替换积木树等）
---@param delay number 延迟秒数（从添加时刻计）
---@param fn function 回调
function BlockCanvas:AddTimedAction(delay, fn)
    table.insert(self.timedActions_, { elapsed = -(delay or 0), fired = false, fn = fn })
end

--- 设置动画全部完成后的回调
function BlockCanvas:SetFlowCompleteCallback(fn)
    self.flowCallback_ = fn
end

--- 清除所有动画
function BlockCanvas:ClearAnims()
    self.flowAnims_ = {}
    self.flashBlocks_ = {}
    self.shatterAnims_ = {}
    self.breakShellAnims_ = {}
    self.timedActions_ = {}
    self.flowCallback_ = nil
end

--- 检查是否有动画在播放（包括延迟等待中的）
function BlockCanvas:HasActiveAnims()
    for _, a in ipairs(self.flowAnims_) do
        if a.alive then return true end
    end
    for _, f in ipairs(self.flashBlocks_) do
        if f.alive then return true end
    end
    for _, s in ipairs(self.shatterAnims_) do
        if s.alive then return true end
    end
    for _, bs in ipairs(self.breakShellAnims_) do
        if bs.alive then return true end
    end
    for _, t in ipairs(self.timedActions_) do
        if not t.fired then return true end
    end
    return false
end

--- 替换画布上所有积木（动画中途用于展示归约中间状态）
---@param newBlocks table[] 新的根积木数组
function BlockCanvas:ReplaceBlocks(newBlocks)
    self.blocks_ = newBlocks or {}
    self.selectedBlock_ = nil
    self.dragBlock_ = nil
    self.transition_ = nil  -- 取消进行中的过渡
end

--- 带过渡动画地替换为新积木（淡出旧积木，淡入新积木）
---@param newBlock table 新的根积木
---@param x number 积木位置 X
---@param y number 积木位置 Y
---@param duration? number 过渡持续时间（默认 0.25s）
function BlockCanvas:TransitionToBlock(newBlock, x, y, duration, springFrom)
    local oldBlocks = {}
    for _, b in ipairs(self.blocks_) do
        table.insert(oldBlocks, b)
    end

    -- 设置新积木
    self.blocks_ = {}
    self.selectedBlock_ = nil
    self.dragBlock_ = nil
    if newBlock then
        newBlock.x = x or 100
        newBlock.y = y or 100
        BlockDefs.measure(newBlock)
        BlockDefs.layout(newBlock, newBlock.x, newBlock.y)
        table.insert(self.blocks_, newBlock)
    end

    -- 启动过渡动画
    self.transition_ = {
        oldBlocks = oldBlocks,
        elapsed = 0,
        duration = duration or 0.25,
    }

    -- 弹簧弹出动画（body 从壳内弹到目标位置）
    if springFrom and newBlock then
        table.insert(self.snapAnims_, {
            block = newBlock,
            fromX = springFrom.x or newBlock.x,
            fromY = springFrom.y or newBlock.y,
            toX = newBlock.x,
            toY = newBlock.y,
            elapsed = 0,
            duration = 0.5,
            spring = true,  -- 标记为弹簧动画（overshoot 缓动）
        })
    end
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

    -- 更新积木过渡动画
    if self.transition_ then
        self.transition_.elapsed = self.transition_.elapsed + dt
        if self.transition_.elapsed >= self.transition_.duration then
            self.transition_ = nil
        end
    end

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
    -- 更新碎裂粒子动画
    for _, s in ipairs(self.shatterAnims_) do
        if s.alive then
            s.elapsed = s.elapsed + dt
            if s.elapsed >= s.duration then
                s.alive = false
            elseif s.elapsed >= 0 then
                -- 更新粒子位置
                local damping = math.exp(-3.0 * dt)  -- 时间相关阻尼
                for _, p in ipairs(s.particles) do
                    p.x = p.x + p.vx * dt
                    p.y = p.y + p.vy * dt
                    p.rot = p.rot + p.rotSpeed * dt
                    -- 阻尼（帧率无关）
                    p.vx = p.vx * damping
                    p.vy = p.vy * damping
                end
                anyAlive = true
            else
                anyAlive = true
            end
        end
    end
    -- 更新破壳动画
    for _, bs in ipairs(self.breakShellAnims_) do
        if bs.alive then
            bs.elapsed = bs.elapsed + dt
            if bs.elapsed >= bs.duration then
                -- 动画完成：新积木就位，加入根列表
                BlockDefs.layout(bs.newBlock, bs.targetX, bs.targetY)
                table.insert(self.blocks_, bs.newBlock)
                bs.alive = false
            elseif bs.elapsed >= 0 then
                -- 动画正式开始：首次进入时从 blocks_ 移除壳（之前 delay 期间壳正常渲染）
                if not bs.shellRemoved then
                    for i, b in ipairs(self.blocks_) do
                        if b == bs.shellBlock then
                            table.remove(self.blocks_, i)
                            break
                        end
                    end
                    bs.shellRemoved = true
                end

                local t = bs.elapsed / bs.duration
                -- 更新粒子
                local damping = math.exp(-3.0 * dt)
                for _, p in ipairs(bs.particles) do
                    p.x = p.x + p.vx * dt
                    p.y = p.y + p.vy * dt
                    p.rot = p.rot + p.rotSpeed * dt
                    p.vx = p.vx * damping
                    p.vy = p.vy * damping
                end
                -- 更新新积木位置（从壳中心弹到目标位置，spring overshoot）
                local moveT = math.min(1.0, t / 0.7)  -- 前 70% 时间完成移动
                local spring = 1.0 - math.exp(-5.0 * moveT) * math.cos(3.0 * math.pi * moveT)
                local curX = bs.fromX + (bs.targetX - bs.fromX) * spring
                local curY = bs.fromY + (bs.targetY - bs.fromY) * spring
                BlockDefs.layout(bs.newBlock, curX, curY)
                anyAlive = true
            else
                anyAlive = true
            end
        end
    end
    -- 更新弹簧弹出动画
    for _, sa in ipairs(self.snapAnims_) do
        if sa.alive ~= false then
            sa.elapsed = sa.elapsed + dt
            if sa.elapsed >= sa.duration then
                -- 动画完成，积木放到最终位置
                sa.block.x = sa.toX
                sa.block.y = sa.toY
                BlockDefs.layout(sa.block, sa.toX, sa.toY)
                sa.alive = false
            else
                -- 弹簧缓动：overshoot 曲线 1 - e^(-6t)*cos(4πt)
                local t = sa.elapsed / sa.duration
                local spring = 1.0 - math.exp(-6.0 * t) * math.cos(4.0 * math.pi * t)
                local curX = sa.fromX + (sa.toX - sa.fromX) * spring
                local curY = sa.fromY + (sa.toY - sa.fromY) * spring
                sa.block.x = curX
                sa.block.y = curY
                BlockDefs.layout(sa.block, curX, curY)
                anyAlive = true
            end
        end
    end
    -- 更新定时动作
    for _, t in ipairs(self.timedActions_) do
        if not t.fired then
            t.elapsed = t.elapsed + dt
            if t.elapsed >= 0 then
                t.fired = true
                t.fn()
            else
                anyAlive = true
            end
        end
    end
    -- 所有动画完成后触发回调
    if not anyAlive and self.flowCallback_ then
        -- 确认确实有过动画（非空列表）
        if #self.flowAnims_ > 0 or #self.flashBlocks_ > 0 or #self.shatterAnims_ > 0 or #self.breakShellAnims_ > 0 or #self.timedActions_ > 0 then
            local cb = self.flowCallback_
            self.flowCallback_ = nil
            self.flowAnims_ = {}
            self.flashBlocks_ = {}
            self.shatterAnims_ = {}
            self.breakShellAnims_ = {}
            self.timedActions_ = {}
            self.snapAnims_ = {}
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

    -- 渲染过渡动画：土司弹出效果
    -- 旧积木（土司机）：向下压缩消失
    -- 新积木（土司）：从旧积木位置弹出（带 overshoot）
    if self.transition_ then
        local t = self.transition_.elapsed / self.transition_.duration

        -- 阶段 1 (t=0~0.4): 旧积木压缩消失
        local compressPhase = math.min(1.0, t / 0.4)
        local compressEase = compressPhase * compressPhase  -- ease-in: 加速压缩
        if compressEase < 0.99 then
            local scaleY = 1.0 - compressEase * 0.85  -- 竖直压扁到 15%
            local scaleX = 1.0 + compressEase * 0.08  -- 横向微膨胀
            local fadeOut = 1.0 - compressEase
            for _, block in ipairs(self.transition_.oldBlocks) do
                nvgSave(nvg)
                local cx = block.x + block.w / 2
                local cy = block.y + block.h  -- 以底部为锚点压缩
                nvgTranslate(nvg, cx, cy)
                nvgScale(nvg, scaleX, scaleY)
                nvgTranslate(nvg, -cx, -cy)
                nvgGlobalAlpha(nvg, fadeOut)
                self:_renderBlock(nvg, block)
                nvgRestore(nvg)
            end
        end

        -- 阶段 2 (t=0.3~1.0): 新积木从底部弹出（带 spring overshoot）
        local popPhase = math.max(0, (t - 0.3) / 0.7)
        if popPhase > 0 then
            -- spring overshoot 缓动：弹出超过终点再回弹
            local spring
            if popPhase < 0.6 then
                -- 弹出阶段：快速上升超过目标
                local p = popPhase / 0.6
                spring = p * (2 - p) * 1.12  -- overshoot to 112%
            else
                -- 回弹阶段：从 112% 回到 100%
                local p = (popPhase - 0.6) / 0.4
                spring = 1.12 - 0.12 * p  -- settle back
            end
            local offsetY = (1.0 - spring) * 30  -- 从下方 30px 弹出
            local fadeIn = math.min(1.0, popPhase * 3)  -- 快速显现
            local scaleUp = 0.85 + 0.15 * math.min(1.0, spring)

            for _, block in ipairs(self.blocks_) do
                nvgSave(nvg)
                local cx = block.x + block.w / 2
                local cy = block.y + block.h / 2
                nvgTranslate(nvg, cx, cy + offsetY)
                nvgScale(nvg, scaleUp, scaleUp)
                nvgTranslate(nvg, -cx, -cy)
                nvgGlobalAlpha(nvg, fadeIn)
                self:_renderBlock(nvg, block)
                nvgRestore(nvg)
            end
        end
    else
        -- 无过渡：正常渲染
        for _, block in ipairs(self.blocks_) do
            self:_renderBlock(nvg, block)
        end
    end

    -- 渲染积木闪烁效果（支持整块 / 槽位级高亮 / 变量替换）
    for _, f in ipairs(self.flashBlocks_) do
        if f.alive and f.elapsed >= 0 then
            local t = f.elapsed / f.duration
            local b = f.block

            if f.isReplace then
                -- 变量替换动画：覆盖积木显示新值（淡入橙色胶囊+新文字）
                local fadeIn = math.min(1, t * 3)           -- 0~0.33 淡入
                local fadeOut = math.max(0, (t - 0.7) / 0.3) -- 0.7~1.0 淡出
                local alpha = math.floor((fadeIn - fadeOut) * 220)
                if alpha > 0 then
                    local hx, hy, hw, hh = b.x, b.y, b.w, b.h
                    local r = hh / 2
                    -- 橙色覆盖胶囊（替换后的值）
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, hx - 2, hy - 1, hw + 4, hh + 2, r)
                    nvgFillColor(nvg, nvgRGBA(f.color[1], f.color[2], f.color[3], math.floor(alpha * 0.5)))
                    nvgFill(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(f.color[1], f.color[2], f.color[3], alpha))
                    nvgStrokeWidth(nvg, 1.8)
                    nvgStroke(nvg)
                    -- 新文字
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 12)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg, nvgRGBA(255, 255, 255, alpha))
                    nvgText(nvg, hx + hw / 2, hy + hh / 2, f.newText or "?")
                end
            else
                -- 普通高亮（整块 or 槽位）
                local pulse = math.sin(t * math.pi) * 0.7
                local alpha = math.floor(pulse * 180)
                if alpha > 0 then
                    local hx, hy, hw, hh
                    if f.slotKey and b.slots and b.slots[f.slotKey] then
                        local slot = b.slots[f.slotKey]
                        hx = b.x + (slot.rx or 0) - 3
                        hy = b.y + (slot.ry or 0) - 3
                        hw = (slot.rw or 40) + 6
                        hh = (slot.rh or 30) + 6
                    else
                        hx = b.x - 2
                        hy = b.y - 2
                        hw = b.w + 4
                        hh = b.h + 4
                    end
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, hx, hy, hw, hh, 8)
                    nvgFillColor(nvg, nvgRGBA(f.color[1], f.color[2], f.color[3], alpha))
                    nvgFill(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(f.color[1], f.color[2], f.color[3], math.min(255, alpha + 60)))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)
                end
            end
        end
    end

    -- 渲染数据流动画（飞行积木 + 替换标签）
    for _, a in ipairs(self.flowAnims_) do
        if a.alive and a.elapsed >= 0 then
            local t = a.elapsed / a.duration
            -- ease-out cubic
            local et = 1 - (1 - t) * (1 - t) * (1 - t)
            local cx = a.fromX + (a.toX - a.fromX) * et
            local cy = a.fromY + (a.toY - a.fromY) * et

            -- 透明度：出现 → 保持 → 消散
            local alpha = 240
            if t < 0.15 then
                alpha = math.floor(t / 0.15 * 240)
            elseif t > 0.75 then
                alpha = math.floor((1 - t) / 0.25 * 240)
            end

            if a.isInternal then
                -- 内部数据流：直线连接 + 飞行真实积木
                local trailAlpha = math.floor(alpha * 0.35)
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, a.fromX, a.fromY)
                nvgLineTo(nvg, cx, cy)
                nvgStrokeColor(nvg, nvgRGBA(a.color[1], a.color[2], a.color[3], trailAlpha))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)

                -- 飞行真实积木（缩小到 0.6 倍）
                if a.flyBlock then
                    local sc = 0.6
                    nvgSave(nvg)
                    nvgTranslate(nvg, cx - a.flyBlock.w * sc / 2, cy - a.flyBlock.h * sc / 2)
                    nvgScale(nvg, sc, sc)
                    nvgGlobalAlpha(nvg, alpha / 255)
                    self:_renderBlock(nvg, a.flyBlock)
                    nvgRestore(nvg)
                end

            elseif a.isLabel then
                -- 替换指示器标签（保持原样）
                local tw = math.max(50, #a.text * 7 + 20)
                local th = 20
                nvgSave(nvg)
                nvgTranslate(nvg, cx, cy)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, -tw / 2, -th / 2, tw, th, 4)
                nvgFillColor(nvg, nvgRGBA(30, 30, 40, math.floor(alpha * 0.8)))
                nvgFill(nvg)
                nvgStrokeColor(nvg, nvgRGBA(a.color[1], a.color[2], a.color[3], alpha))
                nvgStrokeWidth(nvg, 1)
                nvgStroke(nvg)
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 12)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(a.color[1], a.color[2], a.color[3], alpha))
                nvgText(nvg, 0, 0, a.text)
                nvgRestore(nvg)
            else
                -- 飞行真实积木：水平直线轨迹
                if a.flyBlock then
                    local sc = 1.0
                    if t < 0.1 then sc = 0.5 + t / 0.1 * 0.5 end
                    nvgSave(nvg)
                    nvgTranslate(nvg, cx - a.flyBlock.w * sc / 2, cy - a.flyBlock.h * sc / 2)
                    nvgScale(nvg, sc, sc)
                    nvgGlobalAlpha(nvg, alpha / 255)
                    self:_renderBlock(nvg, a.flyBlock)
                    nvgRestore(nvg)
                end
            end
        end
    end

    -- 渲染碎裂粒子
    for _, s in ipairs(self.shatterAnims_) do
        if s.alive and s.elapsed >= 0 then
            local t = s.elapsed / s.duration
            local fadeAlpha = math.max(0, 1 - t * 2.5)  -- 快速衰减
            for _, p in ipairs(s.particles) do
                local alpha = math.floor(fadeAlpha * 200)
                if alpha > 0 then
                    nvgSave(nvg)
                    nvgTranslate(nvg, p.x, p.y)
                    nvgRotate(nvg, p.rot)
                    -- 三角碎片
                    local sz = p.size * (1 - t * 0.4)  -- 略微缩小
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, 0, -sz)
                    nvgLineTo(nvg, sz * 0.8, sz * 0.6)
                    nvgLineTo(nvg, -sz * 0.8, sz * 0.6)
                    nvgClosePath(nvg)
                    nvgFillColor(nvg, nvgRGBA(p.r, p.g, p.b, alpha))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end
            end
        end
    end

    -- 渲染破壳动画（壳渐隐 + 新积木从壳内渐显弹出 + 粒子飞散）
    for _, bs in ipairs(self.breakShellAnims_) do
        if bs.alive and bs.elapsed >= 0 then
            local t = bs.elapsed / bs.duration

            -- 壳渐隐：前 40% 时间从 alpha 1→0，同时轻微膨胀碎裂感
            local shellAlpha = math.max(0, 1.0 - t / 0.4)
            if shellAlpha > 0 then
                nvgSave(nvg)
                local cx = bs.shellBlock.x + bs.shellBlock.w / 2
                local cy = bs.shellBlock.y + bs.shellBlock.h / 2
                local expand = 1.0 + t * 0.15  -- 轻微膨胀
                nvgTranslate(nvg, cx, cy)
                nvgScale(nvg, expand, expand)
                nvgTranslate(nvg, -cx, -cy)
                nvgGlobalAlpha(nvg, shellAlpha)
                self:_renderBlock(nvg, bs.shellBlock)
                nvgRestore(nvg)
            end

            -- 新积木渐显：从 20% 时间点开始 alpha 0→1 + 从小放大
            local showT = math.max(0, (t - 0.2) / 0.5)  -- 0.2~0.7 区间
            showT = math.min(1.0, showT)
            if showT > 0 then
                local fadeIn = math.min(1.0, showT * 2)  -- 快速达到不透明
                local scaleUp = 0.7 + 0.3 * showT  -- 从 70% 放大到 100%
                nvgSave(nvg)
                local ncx = bs.newBlock.x + bs.newBlock.w / 2
                local ncy = bs.newBlock.y + bs.newBlock.h / 2
                nvgTranslate(nvg, ncx, ncy)
                nvgScale(nvg, scaleUp, scaleUp)
                nvgTranslate(nvg, -ncx, -ncy)
                nvgGlobalAlpha(nvg, fadeIn)
                self:_renderBlock(nvg, bs.newBlock)
                nvgRestore(nvg)
            end

            -- 粒子飞散
            local particleAlpha = math.max(0, 1 - t * 2.0)
            for _, p in ipairs(bs.particles) do
                local alpha = math.floor(particleAlpha * 200)
                if alpha > 0 then
                    nvgSave(nvg)
                    nvgTranslate(nvg, p.x, p.y)
                    nvgRotate(nvg, p.rot)
                    local sz = p.size * (1 - t * 0.4)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, 0, -sz)
                    nvgLineTo(nvg, sz * 0.8, sz * 0.6)
                    nvgLineTo(nvg, -sz * 0.8, sz * 0.6)
                    nvgClosePath(nvg)
                    nvgFillColor(nvg, nvgRGBA(p.r, p.g, p.b, alpha))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end
            end
        end
    end

    -- 冻结遮罩
    if self.frozen_ and #self.flowAnims_ == 0 and #self.flashBlocks_ == 0 and #self.shatterAnims_ == 0 then
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
-- 积木渲染 — 委托 BlockRenderer 模块
-- ============================================================================

function BlockCanvas:_renderBlock(nvg, block)
    local isSelected = (self.selectedBlock_ and self.selectedBlock_.id == block.id)
    BlockRenderer.renderBlock(nvg, block, isSelected)
end

return BlockCanvas
