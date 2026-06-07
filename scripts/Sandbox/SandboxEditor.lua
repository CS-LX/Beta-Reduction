-- ============================================================================
-- Sandbox/SandboxEditor.lua
-- 沙盒模式 UI 构建 + Inspector + 积木/节点图编辑 + 求值
-- ============================================================================

local UI = require("urhox-libs/UI")
local AST = require("Lambda.AST")
local Evaluator = require("Lambda.Evaluator")
local Packager = require("Lambda.Packager")
local BlockDefs = require("Blocks.BlockDefs")
local BlockCanvas = require("Blocks.BlockCanvas")
local LambdaGraph = require("Graph.LambdaGraph")

local M = {}

-- ============================================================================
-- 模块内部引用 (通过 init 注入)
-- ============================================================================

local mainCallbacks_ = nil  -- { ASTToBlock, EnterMainMenu, ShowRenameDialogFor, ShowRenameDialog }

--- 初始化，注入 main 的回调
function M.init(callbacks)
    mainCallbacks_ = callbacks
end

-- ============================================================================
-- 模块状态
-- ============================================================================

local blockCanvas_ = nil
local lambdaGraph_ = nil
local uiRoot_ = nil

local currentView_ = "graph"
local editingNodeId_ = nil
local editingNodeName_ = ""

local evalExpr_ = ""
local evalResult_ = ""
local evalTrace_ = {}
local traceIndex_ = 0

local evalExprLabel_ = nil
local evalResultLabel_ = nil
local breadcrumbLabel_ = nil
local leftPanelTitle_ = nil
local leftPanelContent_ = nil
local inspectorContent_ = nil
local graphViewPanel_ = nil
local blockViewPanel_ = nil

-- ============================================================================
-- 状态存取
-- ============================================================================

function M.getBlockCanvas() return blockCanvas_ end
function M.getLambdaGraph() return lambdaGraph_ end
function M.getUIRoot() return uiRoot_ end
function M.getCurrentView() return currentView_ end
function M.isRenameDialogOpen() return false end  -- 代理到 main 模块

-- ============================================================================
-- 求值逻辑
-- ============================================================================

local function RunEvaluation(ast)
    evalTrace_ = Evaluator.trace(ast, 50)
    traceIndex_ = #evalTrace_
    evalExpr_ = AST.toString(ast)
    if evalExprLabel_ then evalExprLabel_:SetText(evalExpr_) end

    if #evalTrace_ > 0 then
        evalResult_ = AST.toString(evalTrace_[#evalTrace_])
    else
        evalResult_ = AST.toString(ast)
    end
    if evalResultLabel_ then evalResultLabel_:SetText(evalResult_) end
end

function M.evaluateCurrent()
    if currentView_ == "graph" then
        if lambdaGraph_ and lambdaGraph_.selectedId_ then
            local result = lambdaGraph_:EvaluateNode(lambdaGraph_.selectedId_)
            if result then
                evalResult_ = AST.toString(result)
                if evalResultLabel_ then evalResultLabel_:SetText(evalResult_) end
            end
            local node = lambdaGraph_.nodes_[lambdaGraph_.selectedId_]
            if node and node.nodeDef then
                evalExpr_ = node.nodeDef.displayExpr or "?"
                if evalExprLabel_ then evalExprLabel_:SetText(evalExpr_) end
            end
        end
    else
        local ast = blockCanvas_ and blockCanvas_:GetSelectedAST()
        if not ast then
            local roots = blockCanvas_:GetRootBlocks()
            if #roots > 0 then
                ast = BlockDefs.toAST(roots[1])
            end
        end
        if ast then
            RunEvaluation(ast)
        end
    end
end

function M.stepEval()
    if #evalTrace_ == 0 then
        M.evaluateCurrent()
        traceIndex_ = 1
    else
        traceIndex_ = math.min(traceIndex_ + 1, #evalTrace_)
    end
    if traceIndex_ > 0 and traceIndex_ <= #evalTrace_ then
        local stepAST = evalTrace_[traceIndex_]
        if evalExprLabel_ then
            evalExprLabel_:SetText("→ " .. AST.toString(stepAST))
        end
    end
end

-- ============================================================================
-- 积木操作
-- ============================================================================

function M.addBlockToCurrent(kind)
    if not blockCanvas_ then return end
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
            block = mainCallbacks_.ASTToBlock(presetFn())
        end
    end
    if block then
        local rx = 100 + math.random(0, 200)
        local ry = 80 + math.random(0, 150)
        blockCanvas_:AddBlock(block, rx, ry)
    end
end

function M.deleteSelected()
    if currentView_ == "graph" then
        if lambdaGraph_ then
            if lambdaGraph_.selectedEdgeIdx_ then
                lambdaGraph_:RemoveSelectedEdge()
                M.updateInspector()
            elseif lambdaGraph_.selectedId_ then
                lambdaGraph_:RemoveNode(lambdaGraph_.selectedId_)
                M.updateInspector()
            end
        end
    else
        if blockCanvas_ then
            local sel = blockCanvas_:GetSelected()
            if sel then
                blockCanvas_:RemoveBlock(sel)
                M.updateInspector()
            end
        end
    end
end

-- ============================================================================
-- 视图切换
-- ============================================================================

function M.enterBlockEditor(nodeId)
    local node = lambdaGraph_.nodes_[nodeId]
    if not node then return end

    editingNodeId_ = nodeId
    editingNodeName_ = node.name
    currentView_ = "blocks"

    blockCanvas_:Clear()
    if node.nodeDef and node.nodeDef.ast then
        local block = mainCallbacks_.ASTToBlock(node.nodeDef.ast)
        if block then
            blockCanvas_:AddBlock(block, 120, 80)
        end
    end

    if graphViewPanel_ then graphViewPanel_:SetVisible(false) end
    if blockViewPanel_ then blockViewPanel_:SetVisible(true) end

    if breadcrumbLabel_ then
        breadcrumbLabel_:SetText("节点图 > " .. editingNodeName_ .. " [编辑中]")
    end

    PopulateLeftPanelForBlocks()
    M.updateInspector()

    print("[Lambda] 进入积木编辑: " .. editingNodeName_)
end

function M.exitBlockEditor()
    if currentView_ ~= "blocks" or not editingNodeId_ then
        return
    end

    local roots = blockCanvas_:GetRootBlocks()
    local newAST = nil
    if #roots > 0 then
        newAST = BlockDefs.toAST(roots[1])
    end

    local node = lambdaGraph_.nodes_[editingNodeId_]
    if node and newAST then
        local newDef = Packager.package(newAST, node.name)
        node.nodeDef = newDef
        node.inputs = {}
        node.outputs = {}
        for i, port in ipairs(newDef.inputs or {}) do
            node.inputs[i] = {
                name = port.name,
                origin = port.origin or "free_var",
                connectedFrom = nil,
            }
        end
        for i, port in ipairs(newDef.outputs or {}) do
            node.outputs[i] = {
                name = port.name,
                connections = {},
            }
        end
        local newEdges = {}
        for _, e in ipairs(lambdaGraph_.edges_) do
            if e.fromNodeId ~= editingNodeId_ and e.toNodeId ~= editingNodeId_ then
                newEdges[#newEdges + 1] = e
            end
        end
        ---@diagnostic disable-next-line: assign-type-mismatch
        lambdaGraph_.edges_ = newEdges
        print("[Lambda] 已更新节点: " .. node.name .. " = " .. (newDef.displayExpr or "?"))
    end

    currentView_ = "graph"
    editingNodeId_ = nil
    editingNodeName_ = ""

    if graphViewPanel_ then graphViewPanel_:SetVisible(true) end
    if blockViewPanel_ then blockViewPanel_:SetVisible(false) end

    if breadcrumbLabel_ then
        breadcrumbLabel_:SetText("节点图")
    end

    PopulateLeftPanelForGraph()
    M.updateInspector()
end

-- ============================================================================
-- 默认节点
-- ============================================================================

function M.addDefaultNodes()
    if not lambdaGraph_ then return end
    lambdaGraph_:AddPresetNode("I", 80, 60)
    lambdaGraph_:AddPresetNode("K", 80, 200)
    lambdaGraph_:AddPresetNode("S", 300, 60)
    lambdaGraph_:AddPresetNode("TRUE", 300, 200)
    M.updateInspector()
end

-- ============================================================================
-- Inspector
-- ============================================================================

local function AddInspectorRow(label, value)
    inspectorContent_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 4, paddingRight = 4,
        paddingTop = 2, paddingBottom = 2,
        children = {
            UI.Label { text = label, fontSize = 11, fontColor = { 140, 150, 180, 200 } },
            UI.Label { text = value or "-", fontSize = 11, fontColor = { 200, 210, 230, 240 } },
        }
    })
end

local function AddInspectorSection(title)
    inspectorContent_:AddChild(UI.Panel {
        width = "100%",
        marginTop = 8, marginBottom = 4,
        flexDirection = "column",
        children = {
            UI.Label {
                text = title,
                fontSize = 11,
                fontColor = { 160, 180, 220, 220 },
                paddingLeft = 4,
            },
            UI.Panel { width = "100%", height = 1, backgroundColor = { 50, 60, 90, 50 }, marginTop = 2 },
        }
    })
end

local function UpdateInspectorForGraph()
    local selId = lambdaGraph_ and lambdaGraph_.selectedId_
    if selId then
        local node = lambdaGraph_.nodes_[selId]
        if not node then return end

        AddInspectorRow("名称", node.name)
        AddInspectorRow("ID", node.id)
        AddInspectorRow("预置", node.isPreset and "是" or "否")

        if node.nodeDef and node.nodeDef.displayExpr then
            AddInspectorSection("表达式")
            inspectorContent_:AddChild(UI.Label {
                text = node.nodeDef.displayExpr,
                fontSize = 11,
                fontColor = { 160, 220, 180, 220 },
                numberOfLines = 0,
                paddingLeft = 4,
            })
        end

        if #node.inputs > 0 then
            AddInspectorSection("输入端口 (" .. #node.inputs .. ")")
            for i, inp in ipairs(node.inputs) do
                local status = inp.connectedFrom and "已连接" or "空"
                local prefix = inp.origin == "bound_param" and "λ" or ""
                AddInspectorRow("  " .. prefix .. inp.name, status)
            end
        end

        if #node.outputs > 0 then
            AddInspectorSection("输出端口 (" .. #node.outputs .. ")")
            for i, outp in ipairs(node.outputs) do
                local connCount = #outp.connections
                AddInspectorRow("  " .. outp.name, connCount .. " 连接")
            end
        end

        AddInspectorSection("操作")
        inspectorContent_:AddChild(UI.Button {
            text = "编辑表达式",
            variant = "primary",
            size = "sm",
            width = "100%",
            onClick = function()
                M.enterBlockEditor(selId)
            end,
        })
        inspectorContent_:AddChild(UI.Button {
            text = "求值此节点",
            variant = "success",
            size = "sm",
            width = "100%",
            marginTop = 4,
            onClick = function()
                if lambdaGraph_ then
                    lambdaGraph_:EvaluateNode(selId)
                end
            end,
        })
        inspectorContent_:AddChild(UI.Button {
            text = "删除节点",
            variant = "danger",
            size = "sm",
            width = "100%",
            marginTop = 4,
            onClick = function()
                if lambdaGraph_ then
                    lambdaGraph_:RemoveNode(lambdaGraph_.selectedId_)
                    M.updateInspector()
                end
            end,
        })
    else
        AddInspectorSection("节点图概览")
        local nodeCount = 0
        if lambdaGraph_ then
            for _ in pairs(lambdaGraph_.nodes_) do nodeCount = nodeCount + 1 end
        end
        AddInspectorRow("节点数", tostring(nodeCount))
        AddInspectorRow("连线数", tostring(lambdaGraph_ and #lambdaGraph_.edges_ or 0))

        AddInspectorSection("操作提示")
        inspectorContent_:AddChild(UI.Label {
            text = "• 左侧面板添加节点\n• 拖动端口创建连线\n• 双击节点编辑表达式\n• 右键/中键平移画布\n• 滚轮缩放",
            fontSize = 11,
            fontColor = { 140, 160, 190, 200 },
            numberOfLines = 0,
            paddingLeft = 4,
        })
    end
end

local function UpdateInspectorForBlocks()
    local sel = blockCanvas_ and blockCanvas_:GetSelected()
    if sel then
        AddInspectorRow("类型", sel.kind)
        AddInspectorRow("ID", sel.id)

        if sel.kind == "variable" then
            AddInspectorRow("变量名", sel.name)
            AddInspectorSection("操作")
            inspectorContent_:AddChild(UI.Button {
                text = "重命名",
                variant = "primary",
                size = "sm",
                width = "100%",
                onClick = function() mainCallbacks_.ShowRenameDialogFor(sel) end,
            })
        elseif sel.kind == "abstraction" then
            AddInspectorRow("参数", "λ" .. sel.param)
            local hasBody = sel.slots.body.child ~= nil
            AddInspectorRow("body", hasBody and "已填充" or "空")
            AddInspectorSection("操作")
            inspectorContent_:AddChild(UI.Button {
                text = "重命名参数",
                variant = "primary",
                size = "sm",
                width = "100%",
                onClick = function() mainCallbacks_.ShowRenameDialogFor(sel) end,
            })
        elseif sel.kind == "application" then
            local hasFunc = sel.slots.func.child ~= nil
            local hasArg = sel.slots.arg.child ~= nil
            AddInspectorRow("func", hasFunc and "已填充" or "空")
            AddInspectorRow("arg", hasArg and "已填充" or "空")
        end

        local ast = BlockDefs.toAST(sel)
        if ast then
            AddInspectorSection("预览")
            inspectorContent_:AddChild(UI.Label {
                text = AST.toString(ast),
                fontSize = 11,
                fontColor = { 160, 220, 180, 220 },
                numberOfLines = 0,
                paddingLeft = 4,
            })
        end

        AddInspectorSection("")
        inspectorContent_:AddChild(UI.Button {
            text = "删除积木",
            variant = "danger",
            size = "sm",
            width = "100%",
            onClick = function()
                if blockCanvas_ then
                    blockCanvas_:RemoveBlock(sel)
                    M.updateInspector()
                end
            end,
        })
    else
        AddInspectorSection("编辑中: " .. editingNodeName_)

        local roots = blockCanvas_ and blockCanvas_:GetRootBlocks() or {}
        AddInspectorRow("根积木数", tostring(#roots))

        if #roots > 0 then
            AddInspectorSection("表达式预览")
            for i, block in ipairs(roots) do
                local ast = BlockDefs.toAST(block)
                local txt = ast and AST.toString(ast) or "?"
                if #txt > 30 then txt = txt:sub(1, 28) .. ".." end
                inspectorContent_:AddChild(UI.Label {
                    text = i .. ". " .. txt,
                    fontSize = 11,
                    fontColor = { 180, 200, 220, 200 },
                    numberOfLines = 0,
                    paddingLeft = 4,
                    paddingBottom = 2,
                })
            end
        end

        AddInspectorSection("操作提示")
        inspectorContent_:AddChild(UI.Label {
            text = "• 左侧面板添加积木\n• 拖积木到插槽中组合\n• 双击变量重命名\n• Del 删除积木\n• Esc 返回节点图",
            fontSize = 11,
            fontColor = { 140, 160, 190, 200 },
            numberOfLines = 0,
            paddingLeft = 4,
        })

        AddInspectorSection("")
        inspectorContent_:AddChild(UI.Button {
            text = "保存并返回节点图",
            variant = "primary",
            size = "sm",
            width = "100%",
            onClick = function() M.exitBlockEditor() end,
        })
    end
end

function M.updateInspector()
    if not inspectorContent_ then return end
    inspectorContent_:ClearChildren()

    if currentView_ == "graph" then
        UpdateInspectorForGraph()
    else
        UpdateInspectorForBlocks()
    end
end

-- ============================================================================
-- 左侧面板
-- ============================================================================

local function PopulateLeftPanelForGraph_inner()
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()
    if leftPanelTitle_ then leftPanelTitle_:SetText("节点库") end

    local items = {
        { label = "I = λx.x", kind = "I" },
        { label = "K = λx.λy.x", kind = "K" },
        { label = "S = λx.λy.λz.xz(yz)", kind = "S" },
        { label = "TRUE = λt.λf.t", kind = "TRUE" },
        { label = "FALSE = λt.λf.f", kind = "FALSE" },
        { label = "ZERO = λf.λx.x", kind = "ZERO" },
        { label = "SUCC", kind = "SUCC" },
    }

    leftPanelContent_:AddChild(UI.Label {
        text = "预置组合子",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    for _, item in ipairs(items) do
        leftPanelContent_:AddChild(UI.Button {
            text = item.label,
            variant = "ghost",
            size = "sm",
            width = "100%",
            textAlign = "left",
            fontColor = { 200, 140, 255, 255 },
            onClick = function()
                local rx = 100 + math.random(0, 300)
                local ry = 80 + math.random(0, 200)
                lambdaGraph_:AddPresetNode(item.kind, rx, ry)
            end,
        })
    end

    leftPanelContent_:AddChild(UI.Panel {
        width = "90%", height = 1,
        marginTop = 8, marginBottom = 8,
        alignSelf = "center",
        backgroundColor = { 60, 70, 100, 60 },
    })

    leftPanelContent_:AddChild(UI.Label {
        text = "操作",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "删除选中节点",
        variant = "danger",
        size = "sm",
        width = "100%",
        onClick = function() M.deleteSelected() end,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "求值选中节点",
        variant = "success",
        size = "sm",
        width = "100%",
        onClick = function() M.evaluateCurrent() end,
    })
end

-- module-level alias
PopulateLeftPanelForGraph = PopulateLeftPanelForGraph_inner

function PopulateLeftPanelForBlocks()
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()
    if leftPanelTitle_ then leftPanelTitle_:SetText("积木库") end

    leftPanelContent_:AddChild(UI.Label {
        text = "基础积木",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    local basicItems = {
        { label = "变量 (x)", kind = "var", color = { 80, 200, 220, 255 } },
        { label = "抽象 (λx.M)", kind = "abs", color = { 160, 100, 220, 255 } },
        { label = "应用 (M N)", kind = "app", color = { 80, 180, 120, 255 } },
    }

    for _, item in ipairs(basicItems) do
        leftPanelContent_:AddChild(UI.Button {
            text = item.label,
            variant = "ghost",
            size = "sm",
            width = "100%",
            textAlign = "left",
            fontColor = item.color,
            onClick = function()
                M.addBlockToCurrent(item.kind)
            end,
        })
    end

    leftPanelContent_:AddChild(UI.Panel {
        width = "90%", height = 1,
        marginTop = 8, marginBottom = 8,
        alignSelf = "center",
        backgroundColor = { 60, 70, 100, 60 },
    })

    leftPanelContent_:AddChild(UI.Label {
        text = "预置表达式",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    local presets = {
        { label = "I = λx.x", kind = "preset_I" },
        { label = "K = λx.λy.x", kind = "preset_K" },
        { label = "S 组合子", kind = "preset_S" },
    }
    for _, item in ipairs(presets) do
        leftPanelContent_:AddChild(UI.Button {
            text = item.label,
            variant = "ghost",
            size = "sm",
            width = "100%",
            textAlign = "left",
            fontColor = { 200, 140, 255, 255 },
            onClick = function()
                M.addBlockToCurrent(item.kind)
            end,
        })
    end

    leftPanelContent_:AddChild(UI.Panel {
        width = "90%", height = 1,
        marginTop = 8, marginBottom = 8,
        alignSelf = "center",
        backgroundColor = { 60, 70, 100, 60 },
    })

    leftPanelContent_:AddChild(UI.Label {
        text = "操作",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "重命名选中",
        variant = "ghost",
        size = "sm",
        width = "100%",
        onClick = function() mainCallbacks_.ShowRenameDialog() end,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "删除选中积木",
        variant = "danger",
        size = "sm",
        width = "100%",
        onClick = function() M.deleteSelected() end,
    })

    leftPanelContent_:AddChild(UI.Panel {
        width = "90%", height = 1,
        marginTop = 8, marginBottom = 8,
        alignSelf = "center",
        backgroundColor = { 60, 70, 100, 60 },
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "← 返回节点图",
        variant = "outline",
        size = "sm",
        width = "100%",
        fontColor = { 255, 180, 80, 255 },
        onClick = function() M.exitBlockEditor() end,
    })
end

-- ============================================================================
-- 面板构建
-- ============================================================================

local function CreateTopPanel()
    return UI.Panel {
        id = "topPanel",
        width = "100%",
        height = 72,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        gap = 12,
        backgroundColor = { 22, 25, 38, 245 },
        borderBottom = 1,
        borderColor = { 50, 60, 90, 80 },
        children = {
            UI.Panel {
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label {
                        text = "λ Sandbox",
                        fontSize = 16,
                        fontColor = { 140, 200, 255, 255 },
                    },
                    breadcrumbLabel_,
                }
            },
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            UI.Panel {
                flexDirection = "column",
                flex = 1,
                gap = 2,
                children = {
                    UI.Label { text = "表达式", fontSize = 10, fontColor = { 120, 130, 160, 180 } },
                    evalExprLabel_,
                }
            },
            UI.Button {
                text = "求值",
                variant = "success",
                size = "sm",
                onClick = function() M.evaluateCurrent() end,
            },
            UI.Button {
                text = "单步",
                variant = "outline",
                size = "sm",
                onClick = function() M.stepEval() end,
            },
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            UI.Panel {
                flexDirection = "column",
                width = 180,
                gap = 2,
                children = {
                    UI.Label { text = "正规形式", fontSize = 10, fontColor = { 120, 130, 160, 180 } },
                    evalResultLabel_,
                }
            },
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            UI.Button {
                text = "菜单",
                variant = "ghost",
                size = "sm",
                onClick = function() mainCallbacks_.EnterMainMenu() end,
            },
        }
    }
end

local function CreateLeftPanel()
    leftPanelTitle_ = UI.Label {
        id = "leftTitle",
        text = "节点库",
        fontSize = 13,
        fontColor = { 180, 190, 210, 255 },
        paddingLeft = 12,
        paddingTop = 10,
        paddingBottom = 6,
    }

    leftPanelContent_ = UI.Panel {
        id = "leftContent",
        width = "100%",
        flexDirection = "column",
        flex = 1,
    }

    PopulateLeftPanelForGraph()

    return UI.Panel {
        id = "leftPanel",
        width = 170,
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 22, 25, 38, 240 },
        borderRight = 1,
        borderColor = { 50, 60, 90, 80 },
        children = {
            leftPanelTitle_,
            UI.ScrollView {
                width = "100%",
                flex = 1,
                children = { leftPanelContent_ },
            },
        }
    }
end

local function CreateCenterPanel()
    return UI.Panel {
        id = "centerPanel",
        flex = 1,
        height = "100%",
        children = {
            graphViewPanel_,
            blockViewPanel_,
        }
    }
end

local function CreateRightPanel()
    return UI.Panel {
        id = "rightPanel",
        width = 220,
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 22, 25, 38, 240 },
        borderLeft = 1,
        borderColor = { 50, 60, 90, 80 },
        children = {
            UI.Label {
                text = "Inspector",
                fontSize = 13,
                fontColor = { 180, 190, 210, 255 },
                paddingLeft = 12,
                paddingTop = 10,
                paddingBottom = 6,
            },
            UI.Panel { width = "90%", height = 1, alignSelf = "center", backgroundColor = { 50, 60, 90, 60 } },
            UI.ScrollView {
                width = "100%",
                flex = 1,
                padding = 10,
                children = { inspectorContent_ },
            },
        }
    }
end

-- ============================================================================
-- 主 UI 构建
-- ============================================================================

function M.createUI()
    blockCanvas_ = BlockCanvas {
        id = "blockCanvas",
        width = "100%",
        height = "100%",
        onBlockChanged = function()
            M.updateInspector()
            local sel = blockCanvas_ and blockCanvas_:GetSelected()
            if sel then
                local ast = BlockDefs.toAST(sel)
                if ast then
                    evalExpr_ = AST.toString(ast)
                    if evalExprLabel_ then evalExprLabel_:SetText(evalExpr_) end
                end
            end
        end,
        onBlockSelected = function(block)
            M.updateInspector()
        end,
        onBlockDoubleClick = function(block)
            mainCallbacks_.ShowRenameDialogFor(block)
        end,
    }

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
            if evalResultLabel_ then evalResultLabel_:SetText(evalResult_) end
        end,
        onSelectionChanged = function(node)
            M.updateInspector()
        end,
        onNodeDoubleClick = function(nodeId)
            M.enterBlockEditor(nodeId)
        end,
    }

    evalExprLabel_ = UI.Label {
        id = "evalExpr",
        text = "等待输入...",
        fontSize = 12,
        fontColor = { 160, 220, 180, 220 },
        numberOfLines = 2,
        flex = 1,
    }

    evalResultLabel_ = UI.Label {
        id = "evalResult",
        text = "-",
        fontSize = 13,
        fontColor = { 255, 200, 100, 255 },
        numberOfLines = 2,
        flex = 1,
    }

    breadcrumbLabel_ = UI.Label {
        id = "breadcrumb",
        text = "节点图",
        fontSize = 12,
        fontColor = { 140, 200, 255, 255 },
    }

    graphViewPanel_ = UI.Panel {
        id = "graphView",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        children = { lambdaGraph_ },
    }

    blockViewPanel_ = UI.Panel {
        id = "blockView",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        visible = false,
        children = { blockCanvas_ },
    }

    inspectorContent_ = UI.Panel {
        id = "inspectorContent",
        width = "100%",
        flexDirection = "column",
        gap = 6,
    }

    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            CreateTopPanel(),
            UI.Panel {
                id = "mainArea",
                width = "100%",
                flex = 1,
                flexDirection = "row",
                children = {
                    CreateLeftPanel(),
                    CreateCenterPanel(),
                    CreateRightPanel(),
                }
            },
        }
    }

    UI.SetRoot(uiRoot_)

    return uiRoot_, blockCanvas_, lambdaGraph_
end

return M
