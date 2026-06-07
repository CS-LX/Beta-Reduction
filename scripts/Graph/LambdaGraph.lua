-- ============================================================================
-- Graph/LambdaGraph.lua - Lambda 节点图画布（基于 Widget:Extend）
-- ============================================================================
-- 无限画布：节点拖拽、端口连线、缩放平移
-- 每个节点代表一个封装好的 Lambda 表达式（来自 Packager）

---@diagnostic disable: param-type-mismatch

local Widget = require("urhox-libs/UI/Core/Widget")
local PointerEvent = require("urhox-libs/UI/Core/PointerEvent")
local AST = require("Lambda.AST")
local Packager = require("Lambda.Packager")

local LambdaGraph = Widget:Extend("LambdaGraph")

-- ============================================================================
-- 常量
-- ============================================================================

local NODE_MIN_W   = 160
local NODE_HEADER  = 28
local PORT_H       = 22
local PORT_RADIUS  = 5
local PORT_GAP     = 4
local MIN_ZOOM     = 0.25
local MAX_ZOOM     = 3.0
local GRID_SIZE    = 50

-- 配色：Frutiger Aero + Arknights glassmorphism
local COLORS = {
    bg          = { 20, 22, 30, 255 },
    grid        = { 50, 55, 70, 40 },
    nodeBg      = { 35, 38, 50, 230 },
    nodeHeader  = { 60, 130, 220, 255 },     -- 蓝色标题栏
    nodePreset  = { 180, 80, 200, 255 },     -- 紫色预置节点
    portInput   = { 100, 220, 180, 255 },    -- 青色输入
    portOutput  = { 255, 180, 80, 255 },     -- 橙色输出
    edge        = { 140, 200, 255, 180 },    -- 浅蓝连线
    edgePending = { 255, 220, 100, 160 },    -- 黄色待连接
    selected    = { 255, 255, 255, 200 },
    hovered     = { 180, 200, 255, 80 },
    textPrimary = { 240, 245, 255, 255 },
    textSecond  = { 160, 170, 190, 220 },
}

-- ============================================================================
-- 初始化
-- ============================================================================

function LambdaGraph:Init(props)
    props = props or {}
    props.overflow = "hidden"
    props.backgroundColor = COLORS.bg

    -- 画布状态
    self.zoom_ = 1.0
    self.panX_ = 0
    self.panY_ = 0
    self.time_ = 0

    -- 节点数据: { id -> LambdaNode }
    -- LambdaNode: { id, name, x, y, nodeDef, inputs[], outputs[], isPreset }
    self.nodes_ = {}
    -- 连线数据: { { fromNodeId, fromPortIdx, toNodeId, toPortIdx } }
    self.edges_ = {}
    self.nextId_ = 1

    -- 交互状态
    self.isPanning_ = false
    self.lastPanX_ = 0
    self.lastPanY_ = 0
    self.isDragging_ = false
    self.dragNodeId_ = nil
    self.dragOffX_ = 0
    self.dragOffY_ = 0
    self.isConnecting_ = false
    self.connectFrom_ = nil   -- { nodeId, portIdx, direction="output" }
    self.connectEndX_ = 0
    self.connectEndY_ = 0
    self.selectedId_ = nil
    self.hoveredId_ = nil

    -- 双击检测
    self.lastClickTime_ = 0
    self.lastClickNodeId_ = nil
    self.doubleClickThreshold_ = 0.35  -- 秒

    -- 回调
    self.onEvaluate_ = props.onEvaluate
    self.onSelectionChanged_ = props.onSelectionChanged
    self.onNodeDoubleClick_ = props.onNodeDoubleClick

    Widget.Init(self, props)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 添加一个 Lambda 节点（从 Packager 封装结果）
---@param nodeDef table  Packager.package() 的返回值
---@param x number       画布坐标 X
---@param y number       画布坐标 Y
---@return string nodeId
function LambdaGraph:AddNode(nodeDef, x, y)
    local id = "ln_" .. self.nextId_
    self.nextId_ = self.nextId_ + 1

    local node = {
        id = id,
        name = nodeDef.name,
        x = x,
        y = y,
        nodeDef = nodeDef,
        inputs = {},
        outputs = {},
        isPreset = nodeDef.isPreset or false,
    }

    -- 构建端口列表
    for i, port in ipairs(nodeDef.inputs or {}) do
        node.inputs[i] = {
            name = port.name,
            origin = port.origin or "free_var",
            connectedFrom = nil,  -- { nodeId, portIdx }
        }
    end
    for i, port in ipairs(nodeDef.outputs or {}) do
        node.outputs[i] = {
            name = port.name,
            connections = {},  -- { { nodeId, portIdx }, ... }
        }
    end

    self.nodes_[id] = node
    return id
end

--- 添加预置组合子节点
---@param name string    预置名 ("I", "K", "S", "TRUE", "FALSE", "ZERO", "SUCC")
---@param x number
---@param y number
---@return string|nil nodeId
function LambdaGraph:AddPresetNode(name, x, y)
    local presetFn = AST.Presets[name]
    if not presetFn then
        print("[LambdaGraph] Unknown preset: " .. tostring(name))
        return nil
    end
    local ast = presetFn()
    local nodeDef = Packager.package(ast, name)
    nodeDef.isPreset = true
    return self:AddNode(nodeDef, x, y)
end

--- 连接两个端口
---@param fromNodeId string
---@param fromPortIdx number   输出端口索引
---@param toNodeId string
---@param toPortIdx number     输入端口索引
---@return boolean success
function LambdaGraph:Connect(fromNodeId, fromPortIdx, toNodeId, toPortIdx)
    local fromNode = self.nodes_[fromNodeId]
    local toNode = self.nodes_[toNodeId]
    if not fromNode or not toNode then return false end
    if fromNodeId == toNodeId then return false end
    if not fromNode.outputs[fromPortIdx] then return false end
    if not toNode.inputs[toPortIdx] then return false end

    -- 检查输入端口是否已连接（一个输入只能有一条连线）
    if toNode.inputs[toPortIdx].connectedFrom then
        -- 断开旧连接
        self:Disconnect(toNodeId, toPortIdx)
    end

    -- 建立连接
    toNode.inputs[toPortIdx].connectedFrom = { nodeId = fromNodeId, portIdx = fromPortIdx }
    table.insert(fromNode.outputs[fromPortIdx].connections, { nodeId = toNodeId, portIdx = toPortIdx })
    table.insert(self.edges_, {
        fromNodeId = fromNodeId,
        fromPortIdx = fromPortIdx,
        toNodeId = toNodeId,
        toPortIdx = toPortIdx,
    })
    return true
end

--- 断开输入端口连接
function LambdaGraph:Disconnect(toNodeId, toPortIdx)
    local toNode = self.nodes_[toNodeId]
    if not toNode then return end
    local conn = toNode.inputs[toPortIdx].connectedFrom
    if not conn then return end

    -- 从输出端口移除
    local fromNode = self.nodes_[conn.nodeId]
    if fromNode and fromNode.outputs[conn.portIdx] then
        local conns = fromNode.outputs[conn.portIdx].connections
        for i = #conns, 1, -1 do
            if conns[i].nodeId == toNodeId and conns[i].portIdx == toPortIdx then
                table.remove(conns, i)
                break
            end
        end
    end

    -- 清除输入
    toNode.inputs[toPortIdx].connectedFrom = nil

    -- 移除边
    for i = #self.edges_, 1, -1 do
        local e = self.edges_[i]
        if e.toNodeId == toNodeId and e.toPortIdx == toPortIdx then
            table.remove(self.edges_, i)
            break
        end
    end
end

--- 删除节点
function LambdaGraph:RemoveNode(nodeId)
    local node = self.nodes_[nodeId]
    if not node then return end

    -- 断开所有连接
    for i, inp in ipairs(node.inputs) do
        if inp.connectedFrom then
            self:Disconnect(nodeId, i)
        end
    end
    for i, outp in ipairs(node.outputs) do
        for _, conn in ipairs(outp.connections) do
            local targetNode = self.nodes_[conn.nodeId]
            if targetNode and targetNode.inputs[conn.portIdx] then
                targetNode.inputs[conn.portIdx].connectedFrom = nil
            end
        end
    end

    -- 移除关联边
    local newEdges = {}
    for _, e in ipairs(self.edges_) do
        if e.fromNodeId ~= nodeId and e.toNodeId ~= nodeId then
            newEdges[#newEdges + 1] = e
        end
    end
    self.edges_ = newEdges

    self.nodes_[nodeId] = nil
    if self.selectedId_ == nodeId then self.selectedId_ = nil end
end

--- 对选中节点执行求值
function LambdaGraph:EvaluateNode(nodeId)
    local node = self.nodes_[nodeId]
    if not node or not node.nodeDef then return nil end

    -- 收集输入值（从连线上游获取）
    local inputValues = {}
    for i, inp in ipairs(node.inputs) do
        if inp.connectedFrom then
            local srcNode = self.nodes_[inp.connectedFrom.nodeId]
            if srcNode and srcNode.nodeDef and srcNode.nodeDef.ast then
                inputValues[inp.name] = AST.deepClone(srcNode.nodeDef.ast)
            end
        end
    end

    local result = Packager.evaluate(node.nodeDef, inputValues)
    if self.onEvaluate_ then
        self.onEvaluate_(nodeId, result)
    end
    return result
end

--- 清空画布
function LambdaGraph:ClearAll()
    self.nodes_ = {}
    self.edges_ = {}
    self.nextId_ = 1
    self.selectedId_ = nil
end

-- ============================================================================
-- 内部：坐标转换
-- ============================================================================

function LambdaGraph:ScreenToCanvas(sx, sy)
    local layout = self:GetAbsoluteLayout()
    if not layout then return 0, 0 end
    local cx = (sx - layout.x - self.panX_) / self.zoom_
    local cy = (sy - layout.y - self.panY_) / self.zoom_
    return cx, cy
end

function LambdaGraph:CanvasToScreen(cx, cy)
    local layout = self:GetAbsoluteLayout()
    if not layout then return 0, 0 end
    local sx = cx * self.zoom_ + self.panX_ + layout.x
    local sy = cy * self.zoom_ + self.panY_ + layout.y
    return sx, sy
end

-- ============================================================================
-- 内部：节点尺寸计算
-- ============================================================================

function LambdaGraph:GetNodeSize(node)
    local portCount = math.max(#node.inputs, #node.outputs)
    local h = NODE_HEADER + math.max(1, portCount) * (PORT_H + PORT_GAP) + PORT_GAP
    local w = NODE_MIN_W
    return w, h
end

function LambdaGraph:GetInputPortPos(node, portIdx)
    local w, _ = self:GetNodeSize(node)
    local py = node.y + NODE_HEADER + PORT_GAP + (portIdx - 1) * (PORT_H + PORT_GAP) + PORT_H * 0.5
    return node.x, py
end

function LambdaGraph:GetOutputPortPos(node, portIdx)
    local w, _ = self:GetNodeSize(node)
    local py = node.y + NODE_HEADER + PORT_GAP + (portIdx - 1) * (PORT_H + PORT_GAP) + PORT_H * 0.5
    return node.x + w, py
end

-- ============================================================================
-- 内部：命中检测
-- ============================================================================

function LambdaGraph:HitNode(cx, cy)
    for id, node in pairs(self.nodes_) do
        local w, h = self:GetNodeSize(node)
        if cx >= node.x and cx <= node.x + w and cy >= node.y and cy <= node.y + h then
            return id
        end
    end
    return nil
end

function LambdaGraph:HitPort(cx, cy)
    for id, node in pairs(self.nodes_) do
        -- 输出端口
        for i = 1, #node.outputs do
            local px, py = self:GetOutputPortPos(node, i)
            local dx, dy = cx - px, cy - py
            if dx * dx + dy * dy <= (PORT_RADIUS + 5) * (PORT_RADIUS + 5) then
                return { nodeId = id, portIdx = i, direction = "output" }
            end
        end
        -- 输入端口
        for i = 1, #node.inputs do
            local px, py = self:GetInputPortPos(node, i)
            local dx, dy = cx - px, cy - py
            if dx * dx + dy * dy <= (PORT_RADIUS + 5) * (PORT_RADIUS + 5) then
                return { nodeId = id, portIdx = i, direction = "input" }
            end
        end
    end
    return nil
end

-- ============================================================================
-- 交互事件
-- ============================================================================

function LambdaGraph:OnPointerDown(event)
    Widget.OnPointerDown(self, event)
    local cx, cy = self:ScreenToCanvas(event.x, event.y)

    -- 右键/中键：平移
    if event.button == PointerEvent.Button.Right or event.button == PointerEvent.Button.Middle then
        self.isPanning_ = true
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if event.button == PointerEvent.Button.Left then
        -- 检测端口点击（开始连线）
        local port = self:HitPort(cx, cy)
        if port then
            self.isConnecting_ = true
            self.connectFrom_ = port
            self.connectEndX_ = cx
            self.connectEndY_ = cy
            return true
        end

        -- 检测节点点击（开始拖拽 + 双击检测）
        local nodeId = self:HitNode(cx, cy)
        if nodeId then
            -- 双击检测
            local now = self.time_ or 0
            if self.lastClickNodeId_ == nodeId and (now - self.lastClickTime_) < self.doubleClickThreshold_ then
                -- 双击触发
                self.lastClickNodeId_ = nil
                self.lastClickTime_ = 0
                if self.onNodeDoubleClick_ then
                    self.onNodeDoubleClick_(nodeId)
                end
                return true
            end
            self.lastClickNodeId_ = nodeId
            self.lastClickTime_ = now

            self.selectedId_ = nodeId
            self.isDragging_ = true
            self.dragNodeId_ = nodeId
            local node = self.nodes_[nodeId]
            self.dragOffX_ = cx - node.x
            self.dragOffY_ = cy - node.y
            if self.onSelectionChanged_ then
                self.onSelectionChanged_(node)
            end
            return true
        end

        -- 点击空白取消选择
        self.selectedId_ = nil
        if self.onSelectionChanged_ then
            self.onSelectionChanged_(nil)
        end
        return true
    end
end

function LambdaGraph:OnPointerMove(event)
    Widget.OnPointerMove(self, event)

    if self.isPanning_ then
        self.panX_ = self.panX_ + (event.x - self.lastPanX_)
        self.panY_ = self.panY_ + (event.y - self.lastPanY_)
        self.lastPanX_ = event.x
        self.lastPanY_ = event.y
        return true
    end

    if self.isDragging_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        local node = self.nodes_[self.dragNodeId_]
        if node then
            node.x = cx - self.dragOffX_
            node.y = cy - self.dragOffY_
        end
        return true
    end

    if self.isConnecting_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        self.connectEndX_ = cx
        self.connectEndY_ = cy
        return true
    end

    -- Hover
    local cx, cy = self:ScreenToCanvas(event.x, event.y)
    self.hoveredId_ = self:HitNode(cx, cy)
end

function LambdaGraph:OnPointerUp(event)
    Widget.OnPointerUp(self, event)

    if self.isPanning_ then
        self.isPanning_ = false
        return true
    end

    if self.isDragging_ then
        self.isDragging_ = false
        self.dragNodeId_ = nil
        return true
    end

    if self.isConnecting_ then
        local cx, cy = self:ScreenToCanvas(event.x, event.y)
        local targetPort = self:HitPort(cx, cy)

        if targetPort and self.connectFrom_ then
            -- 连接逻辑：output → input 或 input → output
            local from = self.connectFrom_
            if from.direction == "output" and targetPort.direction == "input" then
                self:Connect(from.nodeId, from.portIdx, targetPort.nodeId, targetPort.portIdx)
            elseif from.direction == "input" and targetPort.direction == "output" then
                self:Connect(targetPort.nodeId, targetPort.portIdx, from.nodeId, from.portIdx)
            end
        end

        self.isConnecting_ = false
        self.connectFrom_ = nil
        return true
    end
end

function LambdaGraph:OnPointerLeave(event)
    Widget.OnPointerLeave(self, event)
    self.hoveredId_ = nil
    if self.isPanning_ then self.isPanning_ = false end
end

function LambdaGraph:OnWheel(dx, dy)
    local factor = dy > 0 and 1.12 or (1.0 / 1.12)
    local newZoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, self.zoom_ * factor))

    local layout = self:GetAbsoluteLayout()
    if layout then
        local centerX = layout.w * 0.5
        local centerY = layout.h * 0.5
        local scale = newZoom / self.zoom_
        self.panX_ = centerX - (centerX - self.panX_) * scale
        self.panY_ = centerY - (centerY - self.panY_) * scale
    end
    self.zoom_ = newZoom
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function LambdaGraph:Update(dt)
    self.time_ = (self.time_ or 0) + dt
end

-- ============================================================================
-- 渲染
-- ============================================================================

function LambdaGraph:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    if not layout or layout.w <= 0 or layout.h <= 0 then return end

    -- 背景
    self:RenderFullBackground(nvg)

    nvgSave(nvg)
    nvgIntersectScissor(nvg, layout.x, layout.y, layout.w, layout.h)

    -- 网格
    self:DrawGrid(nvg, layout)

    -- 进入画布坐标
    nvgTranslate(nvg, layout.x + self.panX_, layout.y + self.panY_)
    nvgScale(nvg, self.zoom_, self.zoom_)

    -- 连线
    self:DrawEdges(nvg)

    -- 待连线
    if self.isConnecting_ and self.connectFrom_ then
        self:DrawPendingEdge(nvg)
    end

    -- 节点
    self:DrawNodes(nvg)

    nvgRestore(nvg)
end

function LambdaGraph:DrawGrid(nvg, layout)
    local gridSize = GRID_SIZE * self.zoom_
    if gridSize < 8 then return end

    local ox = self.panX_ % gridSize
    local oy = self.panY_ % gridSize
    local alpha = math.floor(math.min(50, 30 * (gridSize / 40)))

    nvgBeginPath(nvg)
    nvgStrokeColor(nvg, nvgRGBA(COLORS.grid[1], COLORS.grid[2], COLORS.grid[3], alpha))
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

function LambdaGraph:DrawEdges(nvg)
    for _, edge in ipairs(self.edges_) do
        local fromNode = self.nodes_[edge.fromNodeId]
        local toNode = self.nodes_[edge.toNodeId]
        if fromNode and toNode then
            local x1, y1 = self:GetOutputPortPos(fromNode, edge.fromPortIdx)
            local x2, y2 = self:GetInputPortPos(toNode, edge.toPortIdx)

            local cpDist = math.abs(x2 - x1) * 0.4 + 40
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgBezierTo(nvg, x1 + cpDist, y1, x2 - cpDist, y2, x2, y2)

            -- 发光效果
            nvgStrokeColor(nvg, nvgRGBA(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], 60))
            nvgStrokeWidth(nvg, 4)
            nvgStroke(nvg)

            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgBezierTo(nvg, x1 + cpDist, y1, x2 - cpDist, y2, x2, y2)
            nvgStrokeColor(nvg, nvgRGBA(COLORS.edge[1], COLORS.edge[2], COLORS.edge[3], COLORS.edge[4]))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
        end
    end
end

function LambdaGraph:DrawPendingEdge(nvg)
    local from = self.connectFrom_
    local fromNode = self.nodes_[from.nodeId]
    if not fromNode then return end

    local x1, y1
    if from.direction == "output" then
        x1, y1 = self:GetOutputPortPos(fromNode, from.portIdx)
    else
        x1, y1 = self:GetInputPortPos(fromNode, from.portIdx)
    end
    local x2, y2 = self.connectEndX_, self.connectEndY_

    local cpDist = math.abs(x2 - x1) * 0.4 + 40
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x1, y1)
    nvgBezierTo(nvg, x1 + cpDist, y1, x2 - cpDist, y2, x2, y2)
    nvgStrokeColor(nvg, nvgRGBA(COLORS.edgePending[1], COLORS.edgePending[2], COLORS.edgePending[3], COLORS.edgePending[4]))
    nvgStrokeWidth(nvg, 2)
    nvgLineCap(nvg, NVG_ROUND)
    nvgStroke(nvg)
end

function LambdaGraph:DrawNodes(nvg)
    for id, node in pairs(self.nodes_) do
        self:DrawNode(nvg, id, node)
    end
end

function LambdaGraph:DrawNode(nvg, id, node)
    local x, y = node.x, node.y
    local w, h = self:GetNodeSize(node)
    local isSelected = (id == self.selectedId_)
    local isHovered = (id == self.hoveredId_)
    local headerColor = node.isPreset and COLORS.nodePreset or COLORS.nodeHeader

    -- 选中发光
    if isSelected then
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, x - 3, y - 3, w + 6, h + 6, 10)
        nvgStrokeColor(nvg, nvgRGBA(COLORS.selected[1], COLORS.selected[2], COLORS.selected[3], COLORS.selected[4]))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    -- 节点背景（毛玻璃效果模拟）
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, 8)
    local bgAlpha = isHovered and 245 or COLORS.nodeBg[4]
    nvgFillColor(nvg, nvgRGBA(COLORS.nodeBg[1], COLORS.nodeBg[2], COLORS.nodeBg[3], bgAlpha))
    nvgFill(nvg)

    -- 半透明边框
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, h, 8)
    nvgStrokeColor(nvg, nvgRGBA(100, 120, 160, 60))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 标题栏渐变
    local headerGrad = nvgLinearGradient(nvg, x, y, x, y + NODE_HEADER,
        nvgRGBA(headerColor[1], headerColor[2], headerColor[3], 200),
        nvgRGBA(headerColor[1], headerColor[2], headerColor[3], 100))
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, x, y, w, NODE_HEADER, 8)
    nvgRect(nvg, x, y + NODE_HEADER - 8, w, 8)  -- 底部直角
    nvgFillPaint(nvg, headerGrad)
    nvgFill(nvg)

    -- 标题文字
    nvgFontSize(nvg, 13)
    nvgFontFace(nvg, "sans")
    nvgFillColor(nvg, nvgRGBA(COLORS.textPrimary[1], COLORS.textPrimary[2], COLORS.textPrimary[3], COLORS.textPrimary[4]))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + 10, y + NODE_HEADER * 0.5, node.name)

    -- 表达式缩写（右上角）
    if node.nodeDef and node.nodeDef.displayExpr then
        local expr = node.nodeDef.displayExpr
        if #expr > 16 then expr = string.sub(expr, 1, 14) .. ".." end
        nvgFontSize(nvg, 9)
        nvgFillColor(nvg, nvgRGBA(COLORS.textSecond[1], COLORS.textSecond[2], COLORS.textSecond[3], 160))
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, x + w - 8, y + NODE_HEADER * 0.5, expr)
    end

    -- 端口绘制
    self:DrawPorts(nvg, node, x, y, w)
end

function LambdaGraph:DrawPorts(nvg, node, x, y, w)
    -- 输入端口（左侧）
    for i, inp in ipairs(node.inputs) do
        local px, py = self:GetInputPortPos(node, i)
        local connected = (inp.connectedFrom ~= nil)

        -- 端口圆点
        nvgBeginPath(nvg)
        nvgCircle(nvg, px, py, PORT_RADIUS)
        if connected then
            nvgFillColor(nvg, nvgRGBA(COLORS.portInput[1], COLORS.portInput[2], COLORS.portInput[3], 255))
        else
            nvgFillColor(nvg, nvgRGBA(COLORS.portInput[1], COLORS.portInput[2], COLORS.portInput[3], 100))
        end
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(COLORS.portInput[1], COLORS.portInput[2], COLORS.portInput[3], 200))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- 端口标签
        nvgFontSize(nvg, 10)
        nvgFillColor(nvg, nvgRGBA(COLORS.textSecond[1], COLORS.textSecond[2], COLORS.textSecond[3], COLORS.textSecond[4]))
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local label = inp.name
        if inp.origin == "bound_param" then label = "λ" .. label end
        nvgText(nvg, px + PORT_RADIUS + 4, py, label)
    end

    -- 输出端口（右侧）
    for i, outp in ipairs(node.outputs) do
        local px, py = self:GetOutputPortPos(node, i)
        local connected = (#outp.connections > 0)

        nvgBeginPath(nvg)
        nvgCircle(nvg, px, py, PORT_RADIUS)
        if connected then
            nvgFillColor(nvg, nvgRGBA(COLORS.portOutput[1], COLORS.portOutput[2], COLORS.portOutput[3], 255))
        else
            nvgFillColor(nvg, nvgRGBA(COLORS.portOutput[1], COLORS.portOutput[2], COLORS.portOutput[3], 100))
        end
        nvgFill(nvg)
        nvgStrokeColor(nvg, nvgRGBA(COLORS.portOutput[1], COLORS.portOutput[2], COLORS.portOutput[3], 200))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        -- 标签
        nvgFontSize(nvg, 10)
        nvgFillColor(nvg, nvgRGBA(COLORS.textSecond[1], COLORS.textSecond[2], COLORS.textSecond[3], COLORS.textSecond[4]))
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(nvg, px - PORT_RADIUS - 4, py, outp.name)
    end
end

return LambdaGraph
