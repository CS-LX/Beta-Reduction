-- ============================================================================
-- Lambda 演算可视化编程沙盒 (Lambda Calculus Visual Programming Sandbox)
-- ============================================================================
-- 系统总览：
--   1. 积木工作区（BlockCanvas）- Scratch-like 积木拼装
--   2. 节点图画布（LambdaGraph）- 节点连线组合
--   3. 求值面板 - 显示 β-归约过程
-- 视觉：Frutiger Aero + Arknights Glassmorphism
-- ============================================================================

local UI = require("urhox-libs/UI")
local AST = require("Lambda.AST")
local Evaluator = require("Lambda.Evaluator")
local Packager = require("Lambda.Packager")
local BlockDefs = require("Blocks.BlockDefs")
local BlockCanvas = require("Blocks.BlockCanvas")
local LambdaGraph = require("Graph.LambdaGraph")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type any
local uiRoot_ = nil
local blockCanvas_ = nil
local lambdaGraph_ = nil
local currentView_ = "blocks"   -- "blocks" | "graph"
local evalResult_ = ""
local evalTrace_ = {}
local traceIndex_ = 0
local hintLabel_ = nil          -- 底部提示文字

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "λ Sandbox - Lambda Calculus Visual Programming"

    InitUI()
    CreateUI()
    SubscribeToEvents()

    -- 初始化默认积木
    AddDefaultBlocks()

    print("=== Lambda Sandbox Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- UI 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function CreateUI()
    -- 积木画布
    blockCanvas_ = BlockCanvas {
        id = "blockCanvas",
        width = "100%",
        height = "100%",
        onBlockChanged = function()
            local sel = blockCanvas_ and blockCanvas_:GetSelected()
            if sel then
                local ast = BlockDefs.toAST(sel)
                UpdateEvaluation(ast)
            end
        end,
        onBlockSelected = function(block)
            UpdateHint(block)
        end,
        onBlockDoubleClick = function(block)
            ShowRenameDialogFor(block)
        end,
    }

    -- 节点图画布
    lambdaGraph_ = LambdaGraph {
        id = "lambdaGraph",
        width = "100%",
        height = "100%",
        onEvaluate = function(nodeId, result)
            if result then
                evalResult_ = AST.toString(result)
            else
                evalResult_ = "(无结果)"
            end
            UpdateResultLabel()
        end,
    }

    -- 底部提示栏
    hintLabel_ = UI.Label {
        id = "hintLabel",
        text = "点击左侧面板添加积木  |  拖拽积木到插槽中组合  |  双击变量重命名",
        fontSize = 11,
        fontColor = { 150, 170, 200, 180 },
        paddingLeft = 12,
    }

    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            -- 顶部工具栏
            CreateToolbar(),
            -- 主内容区
            UI.Panel {
                id = "mainContent",
                width = "100%",
                flex = 1,
                flexDirection = "row",
                children = {
                    -- 左侧面板：积木面板/预置列表
                    CreateSidePanel(),
                    -- 中间：画布区域
                    UI.Panel {
                        id = "canvasArea",
                        flex = 1,
                        height = "100%",
                        children = {
                            -- 积木视图
                            UI.Panel {
                                id = "blockView",
                                width = "100%",
                                height = "100%",
                                position = "absolute",
                                top = 0, left = 0,
                                children = { blockCanvas_ },
                            },
                            -- 节点图视图
                            UI.Panel {
                                id = "graphView",
                                width = "100%",
                                height = "100%",
                                position = "absolute",
                                top = 0, left = 0,
                                visible = false,
                                children = { lambdaGraph_ },
                            },
                        }
                    },
                    -- 右侧：求值面板
                    CreateEvalPanel(),
                }
            },
            -- 底部提示栏
            UI.Panel {
                id = "hintBar",
                width = "100%",
                height = 28,
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = { 20, 22, 32, 220 },
                borderTop = 1,
                borderColor = { 50, 60, 90, 60 },
                children = { hintLabel_ },
            },
        }
    }

    UI.SetRoot(uiRoot_)
end

-- ============================================================================
-- 工具栏
-- ============================================================================

function CreateToolbar()
    return UI.Panel {
        id = "toolbar",
        width = "100%",
        height = 48,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 16,
        paddingRight = 16,
        gap = 8,
        backgroundColor = { 25, 28, 40, 240 },
        borderBottom = 1,
        borderColor = { 60, 70, 100, 100 },
        children = {
            -- 标题
            UI.Label {
                text = "λ Sandbox",
                fontSize = 18,
                fontColor = { 140, 200, 255, 255 },
            },
            -- 分隔
            UI.Panel { width = 1, height = 24, backgroundColor = { 60, 70, 100, 100 } },
            -- 视图切换按钮
            UI.Button {
                id = "btnBlocks",
                text = "积木",
                variant = "primary",
                size = "sm",
                onClick = function() SwitchView("blocks") end,
            },
            UI.Button {
                id = "btnGraph",
                text = "节点图",
                variant = "outline",
                size = "sm",
                onClick = function() SwitchView("graph") end,
            },
            -- 分隔
            UI.Panel { width = 1, height = 24, backgroundColor = { 60, 70, 100, 100 } },
            -- 操作按钮
            UI.Button {
                id = "btnEval",
                text = "求值",
                variant = "success",
                size = "sm",
                onClick = function() EvaluateCurrent() end,
            },
            UI.Button {
                id = "btnStep",
                text = "单步",
                variant = "outline",
                size = "sm",
                onClick = function() StepEval() end,
            },
            UI.Button {
                id = "btnPackage",
                text = "打包为节点",
                variant = "outline",
                size = "sm",
                onClick = function() ShowPackageDialog() end,
            },
            -- 分隔
            UI.Panel { width = 1, height = 24, backgroundColor = { 60, 70, 100, 100 } },
            UI.Button {
                id = "btnRename",
                text = "重命名",
                variant = "ghost",
                size = "sm",
                onClick = function() ShowRenameDialog() end,
            },
            UI.Button {
                id = "btnDelete",
                text = "删除",
                variant = "danger",
                size = "sm",
                onClick = function() DeleteSelected() end,
            },
            -- 弹性空白
            UI.Panel { flex = 1 },
            -- 提示
            UI.Label {
                text = "[Tab] 切换  [Space] 求值  [Del] 删除  [双击] 重命名",
                fontSize = 11,
                fontColor = { 120, 130, 160, 200 },
            },
        }
    }
end

-- ============================================================================
-- 左侧积木/预置面板
-- ============================================================================

function CreateSidePanel()
    return UI.Panel {
        id = "sidePanel",
        width = 180,
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 22, 25, 38, 240 },
        borderRight = 1,
        borderColor = { 50, 60, 90, 80 },
        children = {
            UI.Label {
                text = "积木库",
                fontSize = 13,
                fontColor = { 180, 190, 210, 255 },
                paddingLeft = 12,
                paddingTop = 12,
                paddingBottom = 8,
            },
            -- 变量积木
            CreatePaletteItem("变量 (x)", "var", { 80, 200, 220, 255 }),
            CreatePaletteItem("抽象 (λx.M)", "abs", { 160, 100, 220, 255 }),
            CreatePaletteItem("应用 (M N)", "app", { 80, 180, 120, 255 }),
            -- 分隔线
            UI.Panel {
                width = "90%", height = 1,
                marginTop = 8, marginBottom = 8,
                alignSelf = "center",
                backgroundColor = { 60, 70, 100, 60 },
            },
            UI.Label {
                text = "预置组合子",
                fontSize = 13,
                fontColor = { 180, 190, 210, 255 },
                paddingLeft = 12,
                paddingBottom = 8,
            },
            CreatePaletteItem("I = λx.x", "preset_I", { 200, 140, 255, 255 }),
            CreatePaletteItem("K = λx.λy.x", "preset_K", { 200, 140, 255, 255 }),
            CreatePaletteItem("S = λx.λy.λz.xz(yz)", "preset_S", { 200, 140, 255, 255 }),
            CreatePaletteItem("TRUE = λx.λy.x", "preset_TRUE", { 200, 140, 255, 255 }),
            CreatePaletteItem("FALSE = λx.λy.y", "preset_FALSE", { 200, 140, 255, 255 }),
            CreatePaletteItem("ZERO = λf.λx.x", "preset_ZERO", { 200, 140, 255, 255 }),
            CreatePaletteItem("SUCC", "preset_SUCC", { 200, 140, 255, 255 }),
        }
    }
end

function CreatePaletteItem(label, kind, color)
    return UI.Button {
        text = label,
        variant = "ghost",
        size = "sm",
        width = "100%",
        textAlign = "left",
        fontColor = color,
        onClick = function()
            OnPaletteClick(kind)
        end,
    }
end

-- ============================================================================
-- 右侧求值面板
-- ============================================================================

function CreateEvalPanel()
    return UI.Panel {
        id = "evalPanel",
        width = 240,
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 22, 25, 38, 240 },
        borderLeft = 1,
        borderColor = { 50, 60, 90, 80 },
        padding = 12,
        gap = 8,
        children = {
            UI.Label {
                text = "求值结果",
                fontSize = 14,
                fontColor = { 180, 200, 240, 255 },
            },
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 60, 70, 100, 60 },
            },
            -- 当前表达式
            UI.Label {
                id = "exprLabel",
                text = "等待输入...",
                fontSize = 12,
                fontColor = { 160, 220, 180, 220 },
                numberOfLines = 0,
            },
            -- 分隔
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 60, 70, 100, 40 },
            },
            -- 归约步骤
            UI.Label {
                text = "β-归约步骤:",
                fontSize = 11,
                fontColor = { 140, 150, 180, 200 },
            },
            UI.ScrollView {
                id = "traceScroll",
                width = "100%",
                flex = 1,
                children = {
                    UI.Panel {
                        id = "traceList",
                        width = "100%",
                        flexDirection = "column",
                        gap = 4,
                    }
                }
            },
            -- 结果
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 60, 70, 100, 60 },
            },
            UI.Label {
                text = "正规形式:",
                fontSize = 11,
                fontColor = { 140, 150, 180, 200 },
            },
            UI.Label {
                id = "resultLabel",
                text = "-",
                fontSize = 14,
                fontColor = { 255, 200, 100, 255 },
                numberOfLines = 0,
            },
        }
    }
end

-- ============================================================================
-- 逻辑：视图切换
-- ============================================================================

function SwitchView(view)
    currentView_ = view
    local blockView = uiRoot_:FindById("blockView")
    local graphView = uiRoot_:FindById("graphView")
    local btnBlocks = uiRoot_:FindById("btnBlocks")
    local btnGraph = uiRoot_:FindById("btnGraph")

    if view == "blocks" then
        if blockView then blockView:SetVisible(true) end
        if graphView then graphView:SetVisible(false) end
        if btnBlocks then btnBlocks:SetVariant("primary") end
        if btnGraph then btnGraph:SetVariant("outline") end
    else
        if blockView then blockView:SetVisible(false) end
        if graphView then graphView:SetVisible(true) end
        if btnBlocks then btnBlocks:SetVariant("outline") end
        if btnGraph then btnGraph:SetVariant("primary") end
    end
    UpdateHint(nil)
end

-- ============================================================================
-- 逻辑：面板点击 → 添加积木/预置节点
-- ============================================================================

function OnPaletteClick(kind)
    if currentView_ == "blocks" then
        -- 积木模式：在画布中添加积木
        local block = nil
        if kind == "var" then
            block = BlockDefs.createVar("x")
        elseif kind == "abs" then
            block = BlockDefs.createAbs("x")
        elseif kind == "app" then
            block = BlockDefs.createApp()
        elseif kind:sub(1, 7) == "preset_" then
            local name = kind:sub(8)
            local presetFn = AST.Presets[name]
            if presetFn then
                block = ASTToBlock(presetFn())
            end
        end
        if block and blockCanvas_ then
            -- 随机偏移避免完全重叠
            local rx = 100 + math.random(0, 200)
            local ry = 80 + math.random(0, 150)
            blockCanvas_:AddBlock(block, rx, ry)
        end
    else
        -- 节点图模式：添加预置节点
        if kind:sub(1, 7) == "preset_" then
            local name = kind:sub(8)
            local rx = 100 + math.random(0, 300)
            local ry = 80 + math.random(0, 200)
            lambdaGraph_:AddPresetNode(name, rx, ry)
        end
    end
end

--- AST → Block 树 (递归转换)
function ASTToBlock(ast)
    if ast.kind == "variable" then
        return BlockDefs.createVar(ast.name)
    elseif ast.kind == "abstraction" then
        local block = BlockDefs.createAbs(ast.param)
        local bodyBlock = ASTToBlock(ast.body)
        if bodyBlock then
            BlockDefs.attach(bodyBlock, block, "body")
        end
        return block
    elseif ast.kind == "application" then
        local block = BlockDefs.createApp()
        local funcBlock = ASTToBlock(ast.func)
        local argBlock = ASTToBlock(ast.arg)
        if funcBlock then
            BlockDefs.attach(funcBlock, block, "func")
        end
        if argBlock then
            BlockDefs.attach(argBlock, block, "arg")
        end
        return block
    end
    return nil
end

-- ============================================================================
-- 逻辑：删除选中积木
-- ============================================================================

function DeleteSelected()
    if currentView_ == "blocks" then
        if not blockCanvas_ then return end
        local sel = blockCanvas_:GetSelected()
        if sel then
            blockCanvas_:RemoveBlock(sel)
            UpdateHint(nil)
            print("[Lambda] 已删除积木: " .. (sel.name or sel.kind))
        end
    elseif currentView_ == "graph" then
        if lambdaGraph_ and lambdaGraph_.selectedId_ then
            lambdaGraph_:RemoveNode(lambdaGraph_.selectedId_)
        end
    end
end

-- ============================================================================
-- 逻辑：重命名（双击或按钮触发）
-- ============================================================================

function ShowRenameDialog()
    if not blockCanvas_ then return end
    local sel = blockCanvas_:GetSelected()
    if sel then
        ShowRenameDialogFor(sel)
    end
end

function ShowRenameDialogFor(block)
    if not block then return end

    -- 只有变量和抽象（参数名）可以重命名
    local currentName = ""
    local isVar = (block.kind == "variable")
    local isAbs = (block.kind == "abstraction")
    if isVar then
        currentName = block.name or ""
    elseif isAbs then
        currentName = block.param or ""
    else
        -- application 积木没有可重命名的字段
        if hintLabel_ then
            hintLabel_:SetText("应用积木无法重命名，请选中变量或抽象积木")
        end
        return
    end

    local inputField = UI.TextField {
        value = currentName,
        placeholder = "输入新名称...",
        maxLength = 20,
        fontSize = 14,
    }

    local modal = UI.Modal {
        title = isVar and "重命名变量" or "重命名参数",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function(self)
            self:Destroy()
        end,
    }

    modal:AddContent(UI.Panel {
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = isVar and "变量名:" or "参数名 (λ后面的名称):",
                fontSize = 12,
                fontColor = { 180, 190, 210, 220 },
            },
            inputField,
        }
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 8,
        children = {
            UI.Button {
                text = "取消",
                size = "sm",
                onClick = function() modal:Close() end,
            },
            UI.Button {
                text = "确认",
                variant = "primary",
                size = "sm",
                onClick = function()
                    local newName = inputField:GetValue()
                    if newName and #newName > 0 then
                        if isVar then
                            block.name = newName
                        elseif isAbs then
                            block.param = newName
                        end
                        -- 刷新布局
                        if blockCanvas_ then
                            blockCanvas_:_refreshAll()
                        end
                        print("[Lambda] 已重命名为: " .. newName)
                    end
                    modal:Close()
                end,
            },
        }
    })

    modal:Open()
end

-- ============================================================================
-- 逻辑：打包 → 节点图（带自定义名称对话框）
-- ============================================================================

function ShowPackageDialog()
    if not blockCanvas_ then return end

    local ast = blockCanvas_:GetSelectedAST()
    if not ast then
        if hintLabel_ then
            hintLabel_:SetText("请先选中一个积木树再打包")
        end
        return
    end

    local inputField = UI.TextField {
        value = "MyNode",
        placeholder = "节点名称...",
        maxLength = 30,
        fontSize = 14,
    }

    local modal = UI.Modal {
        title = "打包为节点",
        size = "sm",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function(self)
            self:Destroy()
        end,
    }

    modal:AddContent(UI.Panel {
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Label {
                text = "表达式: " .. AST.toString(ast),
                fontSize = 12,
                fontColor = { 160, 220, 180, 220 },
                numberOfLines = 0,
            },
            UI.Label {
                text = "节点名称:",
                fontSize = 12,
                fontColor = { 180, 190, 210, 220 },
            },
            inputField,
        }
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 8,
        children = {
            UI.Button {
                text = "取消",
                size = "sm",
                onClick = function() modal:Close() end,
            },
            UI.Button {
                text = "打包",
                variant = "primary",
                size = "sm",
                onClick = function()
                    local name = inputField:GetValue()
                    if not name or #name == 0 then
                        name = "Node" .. math.random(100, 999)
                    end
                    PackageWithName(ast, name)
                    modal:Close()
                end,
            },
        }
    })

    modal:Open()
end

function PackageWithName(ast, name)
    local nodeDef = Packager.package(ast, name)

    -- 添加到节点图
    local rx = 100 + math.random(0, 300)
    local ry = 80 + math.random(0, 200)
    lambdaGraph_:AddNode(nodeDef, rx, ry)

    print("[Lambda] 已打包为节点: " .. name .. " (" .. #nodeDef.inputs .. " 输入端口)")

    -- 自动切到节点图视图
    SwitchView("graph")

    if hintLabel_ then
        hintLabel_:SetText("已打包 \"" .. name .. "\"  |  拖动端口连线组合节点")
    end
end

-- ============================================================================
-- 逻辑：提示更新
-- ============================================================================

function UpdateHint(block)
    if not hintLabel_ then return end
    if not block then
        if currentView_ == "blocks" then
            hintLabel_:SetText("点击左侧面板添加积木  |  拖拽积木到插槽中组合  |  双击变量重命名")
        else
            hintLabel_:SetText("从左侧面板添加预置节点  |  拖动端口创建连线  |  滚轮缩放")
        end
        return
    end

    if block.kind == "variable" then
        hintLabel_:SetText("变量 \"" .. block.name .. "\"  |  双击重命名  |  Del 删除  |  拖入其他积木的插槽")
    elseif block.kind == "abstraction" then
        hintLabel_:SetText("λ" .. block.param .. "  |  双击修改参数名  |  拖积木到 body 插槽  |  Space 求值")
    elseif block.kind == "application" then
        hintLabel_:SetText("应用 (f x)  |  拖积木到 func/arg 插槽  |  Space 求值  |  打包为节点")
    end
end

-- ============================================================================
-- 逻辑：求值
-- ============================================================================

function EvaluateCurrent()
    if currentView_ == "blocks" then
        -- 积木模式：对选中积木求值
        local ast = blockCanvas_ and blockCanvas_:GetSelectedAST()
        if not ast then
            print("[Lambda] 请先选中一个积木")
            return
        end
        RunEvaluation(ast)
    else
        -- 节点图模式：对选中节点求值
        if lambdaGraph_ and lambdaGraph_.selectedId_ then
            lambdaGraph_:EvaluateNode(lambdaGraph_.selectedId_)
        end
    end
end

function RunEvaluation(ast)
    -- 获取归约 trace
    evalTrace_ = Evaluator.trace(ast, 50)
    traceIndex_ = #evalTrace_

    -- 更新 UI
    local exprLabel = uiRoot_:FindById("exprLabel")
    if exprLabel then
        exprLabel:SetText(AST.toString(ast))
    end

    -- 显示 trace
    UpdateTraceDisplay()

    -- 最终结果
    if #evalTrace_ > 0 then
        evalResult_ = AST.toString(evalTrace_[#evalTrace_])
    else
        evalResult_ = AST.toString(ast)
    end
    UpdateResultLabel()
end

function StepEval()
    if #evalTrace_ == 0 then
        EvaluateCurrent()
        traceIndex_ = 1
    else
        traceIndex_ = math.min(traceIndex_ + 1, #evalTrace_)
    end
    UpdateTraceDisplay()
end

function UpdateEvaluation(ast)
    if ast then
        local exprLabel = uiRoot_:FindById("exprLabel")
        if exprLabel then
            exprLabel:SetText(AST.toString(ast))
        end
    end
end

function UpdateResultLabel()
    local resultLabel = uiRoot_:FindById("resultLabel")
    if resultLabel then
        resultLabel:SetText(evalResult_)
    end
end

function UpdateTraceDisplay()
    local traceList = uiRoot_:FindById("traceList")
    if not traceList then return end

    -- 清除旧内容
    traceList:ClearChildren()

    -- 添加步骤
    local showCount = math.min(traceIndex_, #evalTrace_)
    for i = 1, showCount do
        local stepText = "→ " .. AST.toString(evalTrace_[i])
        local isLast = (i == showCount)
        traceList:AddChild(UI.Label {
            text = stepText,
            fontSize = 11,
            fontColor = isLast and { 255, 220, 100, 255 } or { 140, 160, 190, 200 },
            numberOfLines = 0,
        })
    end
end

-- ============================================================================
-- 默认积木（启动时展示）
-- ============================================================================

function AddDefaultBlocks()
    if not blockCanvas_ then return end

    -- 添加一个 Identity 组合子 I = λx.x
    local iBlock = ASTToBlock(AST.Presets.I())
    if iBlock then
        blockCanvas_:AddBlock(iBlock, 80, 60)
    end

    -- 添加一个应用积木 (I y)
    local appBlock = BlockDefs.createApp()
    local iBlock2 = ASTToBlock(AST.Presets.I())
    local yVar = BlockDefs.createVar("y")
    if iBlock2 then BlockDefs.attach(iBlock2, appBlock, "func") end
    BlockDefs.attach(yVar, appBlock, "arg")
    blockCanvas_:AddBlock(appBlock, 80, 200)

    -- 在节点图中放置几个预置节点
    lambdaGraph_:AddPresetNode("I", 80, 60)
    lambdaGraph_:AddPresetNode("K", 80, 200)
    lambdaGraph_:AddPresetNode("S", 300, 60)
end

-- ============================================================================
-- 帧更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- UI 系统自动处理 canvas 的 Update 和 Render
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_TAB then
        -- Tab 切换视图
        if currentView_ == "blocks" then
            SwitchView("graph")
        else
            SwitchView("blocks")
        end
        UpdateHint(nil)
    elseif key == KEY_SPACE then
        EvaluateCurrent()
    elseif key == KEY_DELETE or key == KEY_BACKSPACE then
        DeleteSelected()
    elseif key == KEY_F2 then
        -- F2 快捷键重命名
        ShowRenameDialog()
    end
end
