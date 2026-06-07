-- ============================================================================
-- Lambda 演算可视化编程沙盒 (Lambda Calculus Visual Programming Sandbox)
-- ============================================================================
-- 模式:
--   - 主菜单: 选择沙盒/闯关模式
--   - 沙盒模式: Blender 风格布局，自由创作
--   - 闯关模式: 关卡选择 + 限制积木的编辑器
--
-- Blender 风格布局 (沙盒 + 闯关编辑):
--   上方: 求值/归约面板
--   左侧: 积木库/预置节点面板
--   中间: 画布 (节点图 或 积木编辑)
--   右侧: Inspector 属性面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local AST = require("Lambda.AST")
local Evaluator = require("Lambda.Evaluator")
local Packager = require("Lambda.Packager")
local BlockDefs = require("Blocks.BlockDefs")
local BlockCanvas = require("Blocks.BlockCanvas")
local LambdaGraph = require("Graph.LambdaGraph")
local CampaignManager = require("Campaign.CampaignManager")
local CampaignUI = require("Campaign.CampaignUI")
local LevelData = require("Campaign.LevelData")

-- ============================================================================
-- 应用模式状态机
-- ============================================================================
-- appMode_:
--   "menu"             → 主菜单 (选择沙盒/闯关)
--   "sandbox"          → 沙盒模式 (完整编辑器)
--   "campaign_select"  → 关卡选择界面
--   "campaign_level"   → 闯关中 (限制积木编辑器)
-- ============================================================================

local appMode_ = "menu"

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type any
local uiRoot_ = nil
local blockCanvas_ = nil
local lambdaGraph_ = nil

-- 视图状态: "graph" (主视图) | "blocks" (积木编辑某个节点)
local currentView_ = "graph"
local editingNodeId_ = nil    -- 当前正在积木编辑的节点ID
local editingNodeName_ = ""   -- 当前编辑的节点名称

-- 求值状态
local evalExpr_ = ""
local evalResult_ = ""
local evalTrace_ = {}
local traceIndex_ = 0

-- Inspector 引用
local inspectorPanel_ = nil
local inspectorContent_ = nil

-- 顶部面板引用
local evalExprLabel_ = nil
local evalResultLabel_ = nil

-- 左侧面板引用
local leftPanelTitle_ = nil
local leftPanelContent_ = nil

-- 中间画布容器
local blockViewPanel_ = nil
local graphViewPanel_ = nil

-- 面包屑/视图指示
local breadcrumbLabel_ = nil

-- 闯关模式 HUD 引用
local campaignHUD_ = nil
local victoryPopup_ = nil
local feedbackPanel_ = nil
local feedbackLabel_ = nil

-- 对话框状态（防止键盘事件穿透）
local renameDialogOpen_ = false

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "λ Sandbox - Lambda Calculus Visual Programming"

    InitUI()
    CampaignManager.init()
    SetupCampaignCallbacks()
    EnterMainMenu()
    SubscribeToEvents()

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
-- 闯关回调设置
-- ============================================================================

function SetupCampaignCallbacks()
    CampaignUI.setCallbacks({
        onEnterSandbox = function()
            EnterSandbox()
        end,
        onEnterLevel = function(levelId)
            EnterCampaignLevel(levelId)
        end,
        onExitLevel = function()
            -- 从关卡或关卡选择退回
            if appMode_ == "campaign_level" then
                CampaignManager.exitLevel()
                EnterCampaignSelect()
            elseif appMode_ == "campaign_select" then
                EnterMainMenu()
            end
        end,
        onSubmitAnswer = function()
            SubmitCampaignAnswer()
        end,
        onShowHint = function()
            ShowCampaignHint()
        end,
        onShowLevelSelect = function()
            EnterCampaignSelect()
        end,
    })
end

-- ============================================================================
-- 模式切换
-- ============================================================================

--- 进入主菜单
function EnterMainMenu()
    appMode_ = "menu"
    currentView_ = "graph"
    editingNodeId_ = nil

    local menu = CampaignUI.createMainMenu()
    UI.SetRoot(menu)

    print("[App] 进入主菜单")
end

--- 进入沙盒模式
function EnterSandbox()
    appMode_ = "sandbox"
    currentView_ = "graph"
    editingNodeId_ = nil

    CreateSandboxUI()
    AddDefaultNodes()

    print("[App] 进入沙盒模式")
end

--- 进入闯关关卡选择
function EnterCampaignSelect()
    appMode_ = "campaign_select"
    currentView_ = "graph"
    editingNodeId_ = nil

    local selectUI = CampaignUI.createLevelSelect()
    UI.SetRoot(selectUI)

    print("[App] 进入关卡选择")
end

--- 进入闯关关卡
function EnterCampaignLevel(levelId)
    local ok, err = CampaignManager.enterLevel(levelId)
    if not ok then
        print("[App] 无法进入关卡: " .. err)
        return
    end

    appMode_ = "campaign_level"
    currentView_ = "blocks"  -- 闯关模式直接使用积木编辑
    editingNodeId_ = nil
    victoryPopup_ = nil

    CreateCampaignLevelUI(levelId)

    print("[App] 进入闯关关卡: " .. levelId)
end

-- ============================================================================
-- 沙盒模式 UI 构建 (Blender 风格)
-- ============================================================================

function CreateSandboxUI()
    -- 积木画布 (用于编辑单个节点的内部表达式)
    blockCanvas_ = BlockCanvas {
        id = "blockCanvas",
        width = "100%",
        height = "100%",
        onBlockChanged = function()
            UpdateInspector()
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
            UpdateInspector()
        end,
        onBlockDoubleClick = function(block)
            ShowRenameDialogFor(block)
        end,
    }

    -- 节点图画布 (主视图)
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
            UpdateInspector()
        end,
        onNodeDoubleClick = function(nodeId)
            EnterBlockEditor(nodeId)
        end,
    }

    -- 构建面板引用
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

    -- 节点视图面板
    graphViewPanel_ = UI.Panel {
        id = "graphView",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        children = { lambdaGraph_ },
    }

    -- 积木视图面板
    blockViewPanel_ = UI.Panel {
        id = "blockView",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        visible = false,
        children = { blockCanvas_ },
    }

    -- Inspector 内容容器
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
            -- 上方: 求值/归约面板
            CreateTopPanel(),
            -- 下方: 左 + 中 + 右
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
end

-- ============================================================================
-- 闯关模式 UI 构建
-- ============================================================================

function CreateCampaignLevelUI(levelId)
    local level = LevelData.getLevelById(levelId)
    if not level then return end

    -- 创建积木画布 (闯关模式只用积木视图)
    blockCanvas_ = BlockCanvas {
        id = "campaignCanvas",
        width = "100%",
        height = "100%",
        onBlockChanged = function()
            -- 积木变化时更新表达式预览
            local roots = blockCanvas_ and blockCanvas_:GetRootBlocks() or {}
            if #roots > 0 then
                local ast = BlockDefs.toAST(roots[1])
                if ast then
                    evalExpr_ = AST.toString(ast)
                    if evalExprLabel_ then evalExprLabel_:SetText(evalExpr_) end
                end
            end
            UpdateCampaignInspector()
        end,
        onBlockSelected = function(block)
            UpdateCampaignInspector()
        end,
        onBlockDoubleClick = function(block)
            ShowRenameDialogFor(block)
        end,
    }

    -- 表达式显示
    evalExprLabel_ = UI.Label {
        id = "campaignExpr",
        text = "",
        fontSize = 12,
        fontColor = { 160, 220, 180, 220 },
        numberOfLines = 2,
        flex = 1,
    }

    -- 左侧积木面板 (受限)
    leftPanelTitle_ = UI.Label {
        id = "leftTitle",
        text = "积木库",
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
    PopulateLeftPanelForCampaign(levelId)

    -- Inspector 内容容器 (关卡模式)
    inspectorContent_ = UI.Panel {
        id = "campaignInspectorContent",
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }

    -- 浮动反馈 Toast (absolute 定位在画布底部居中)
    feedbackLabel_ = UI.Label {
        id = "feedback",
        text = "",
        fontSize = 13,
        fontColor = { 255, 200, 100, 255 },
        flexShrink = 1,
    }
    feedbackPanel_ = UI.Panel {
        id = "feedbackPanel",
        position = "absolute",
        bottom = 16,
        left = "15%",
        right = "15%",
        paddingTop = 8, paddingBottom = 8,
        paddingLeft = 14, paddingRight = 14,
        borderRadius = 8,
        backgroundColor = { 30, 30, 40, 230 },
        borderWidth = 1,
        borderColor = { 80, 90, 130, 150 },
        visible = false,
        pointerEvents = "none",
        children = { feedbackLabel_ },
    }

    -- 关卡信息/教程/提交面板
    campaignHUD_ = CreateCampaignInfoPanel(level)

    -- 整体布局
    uiRoot_ = UI.Panel {
        id = "campaignRoot",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            -- 顶部: 简化版 (只显示表达式)
            UI.Panel {
                width = "100%",
                height = 44,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                gap = 12,
                backgroundColor = { 22, 25, 38, 245 },
                borderBottom = 1,
                borderColor = { 50, 60, 90, 80 },
                children = {
                    UI.Button {
                        text = "← 退出",
                        variant = "ghost",
                        size = "sm",
                        fontColor = { 180, 140, 110, 220 },
                        onClick = function()
                            if CampaignUI then
                                local cbs = CampaignUI._getCallbacks and CampaignUI._getCallbacks()
                            end
                            ExitCampaignLevel()
                        end,
                    },
                    UI.Panel { width = 1, height = 28, backgroundColor = { 50, 60, 90, 80 } },
                    UI.Label {
                        text = level.id .. " " .. level.title,
                        fontSize = 13,
                        fontColor = { 140, 200, 255, 255 },
                    },
                    UI.Panel { flex = 1 },
                    UI.Label { text = "表达式:", fontSize = 11, fontColor = { 120, 130, 160, 180 } },
                    evalExprLabel_,
                }
            },
            -- 内容区: 左 积木库 | 中 画布 | 右 教程+Inspector
            UI.Panel {
                width = "100%",
                flex = 1,
                flexDirection = "row",
                children = {
                    -- 左侧: 受限积木库
                    UI.Panel {
                        width = 150,
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
                    },
                    -- 中间: 积木画布 + 浮动Toast
                    UI.Panel {
                        flex = 1,
                        height = "100%",
                        children = {
                            blockCanvas_,
                            -- 浮动反馈Toast (absolute定位在画布底部居中)
                            feedbackPanel_,
                        },
                    },
                    -- 右侧: 关卡信息 + Inspector
                    UI.Panel {
                        width = 240,
                        height = "100%",
                        flexDirection = "column",
                        backgroundColor = { 18, 20, 32, 240 },
                        borderLeft = 1,
                        borderColor = { 50, 60, 90, 80 },
                        children = {
                            -- 上半: 关卡信息/教程/按钮
                            campaignHUD_,
                            -- 分隔
                            UI.Panel { width = "90%", height = 1, alignSelf = "center", backgroundColor = { 60, 70, 110, 80 } },
                            -- 下半: Inspector
                            UI.Label {
                                text = "属性",
                                fontSize = 12,
                                fontColor = { 160, 180, 220, 220 },
                                paddingLeft = 10,
                                paddingTop = 8,
                                paddingBottom = 4,
                            },
                            UI.ScrollView {
                                width = "100%",
                                flex = 1,
                                children = { inspectorContent_ },
                            },
                        }
                    },
                }
            },
        }
    }

    UI.SetRoot(uiRoot_)
    UpdateCampaignInspector()
end

-- ============================================================================
-- 关卡信息/教程面板 (嵌入右侧栏上半部分)
-- ============================================================================

function CreateCampaignInfoPanel(level)
    -- 教程内容
    local tutorialChildren = {}
    if level.tutorial and #level.tutorial > 0 then
        for _, line in ipairs(level.tutorial) do
            table.insert(tutorialChildren, UI.Label {
                text = line,
                fontSize = 11,
                fontColor = { 190, 200, 220, 200 },
            })
        end
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        flexShrink = 1,
        children = {
            -- 关卡描述
            UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 6,
                paddingLeft = 10, paddingRight = 10,
                children = {
                    UI.Label {
                        text = level.description,
                        fontSize = 12,
                        fontColor = { 200, 210, 230, 220 },
                    },
                },
            },
            -- 教程 (可滚动)
            UI.ScrollView {
                width = "100%",
                flex = 1,
                maxHeight = 200,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        paddingLeft = 10, paddingRight = 10,
                        paddingBottom = 6,
                        children = tutorialChildren,
                    }
                }
            },
            -- 按钮区
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 6, paddingBottom = 10,
                children = {
                    UI.Button {
                        text = "提交",
                        variant = "success",
                        size = "sm",
                        flex = 1,
                        onClick = function()
                            SubmitCampaignAnswer()
                        end,
                    },
                    UI.Button {
                        text = "提示",
                        variant = "outline",
                        size = "sm",
                        flex = 1,
                        onClick = function()
                            ShowCampaignHint()
                        end,
                    },
                }
            },
        }
    }
end

-- ============================================================================
-- 关卡模式 Inspector (显示选中积木属性，支持 InputBox 改名)
-- ============================================================================

function UpdateCampaignInspector()
    if not inspectorContent_ then return end
    if appMode_ ~= "campaign_level" then return end
    inspectorContent_:ClearChildren()

    local sel = blockCanvas_ and blockCanvas_:GetSelected()
    if sel then
        -- 类型
        local kindNames = { variable = "变量", abstraction = "抽象 λ", application = "应用" }
        inspectorContent_:AddChild(UI.Label {
            text = kindNames[sel.kind] or sel.kind,
            fontSize = 12,
            fontColor = { 140, 200, 255, 240 },
            paddingLeft = 10, paddingTop = 4,
        })

        -- 属性编辑
        if sel.kind == "variable" then
            inspectorContent_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                paddingLeft = 10, paddingRight = 10, paddingTop = 6,
                children = {
                    UI.Label { text = "变量名", fontSize = 10, fontColor = { 130, 140, 170, 180 } },
                    UI.TextField {
                        value = sel.name or "",
                        placeholder = "变量名",
                        maxLength = 12,
                        fontSize = 13,
                        onChange = function(self, val)
                            if val and #val > 0 then
                                sel.name = val
                                if blockCanvas_ then blockCanvas_:_refreshAll() end
                            end
                        end,
                    },
                },
            })
        elseif sel.kind == "abstraction" then
            inspectorContent_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "column",
                gap = 4,
                paddingLeft = 10, paddingRight = 10, paddingTop = 6,
                children = {
                    UI.Label { text = "参数名 (λ 后面)", fontSize = 10, fontColor = { 130, 140, 170, 180 } },
                    UI.TextField {
                        value = sel.param or "",
                        placeholder = "参数名",
                        maxLength = 12,
                        fontSize = 13,
                        onChange = function(self, val)
                            if val and #val > 0 then
                                sel.param = val
                                if blockCanvas_ then blockCanvas_:_refreshAll() end
                            end
                        end,
                    },
                },
            })
            local hasBody = sel.slots and sel.slots.body and sel.slots.body.child ~= nil
            AddCampaignInspectorRow("body", hasBody and "已填充" or "空")
        elseif sel.kind == "application" then
            local hasFunc = sel.slots and sel.slots.func and sel.slots.func.child ~= nil
            local hasArg = sel.slots and sel.slots.arg and sel.slots.arg.child ~= nil
            AddCampaignInspectorRow("func", hasFunc and "已填充" or "空")
            AddCampaignInspectorRow("arg", hasArg and "已填充" or "空")
        end

        -- 表达式预览
        local ast = BlockDefs.toAST(sel)
        if ast then
            inspectorContent_:AddChild(UI.Panel {
                width = "100%",
                paddingLeft = 10, paddingRight = 10, paddingTop = 8,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label { text = "预览", fontSize = 10, fontColor = { 130, 140, 170, 180 } },
                    UI.Label {
                        text = AST.toString(ast),
                        fontSize = 11,
                        fontColor = { 160, 220, 180, 220 },
                    },
                },
            })
        end

        -- 删除按钮
        inspectorContent_:AddChild(UI.Button {
            text = "删除",
            variant = "danger",
            size = "sm",
            width = "90%",
            alignSelf = "center",
            marginTop = 10,
            onClick = function()
                if blockCanvas_ then
                    blockCanvas_:RemoveBlock(sel)
                    UpdateCampaignInspector()
                end
            end,
        })
    else
        -- 未选中状态: 概览
        local roots = blockCanvas_ and blockCanvas_:GetRootBlocks() or {}
        inspectorContent_:AddChild(UI.Label {
            text = "选中积木查看属性",
            fontSize = 11,
            fontColor = { 120, 130, 160, 160 },
            paddingLeft = 10, paddingTop = 6,
        })
        if #roots > 0 then
            inspectorContent_:AddChild(UI.Panel {
                width = "100%",
                paddingLeft = 10, paddingRight = 10, paddingTop = 8,
                flexDirection = "column",
                gap = 2,
                children = {
                    UI.Label { text = "当前表达式", fontSize = 10, fontColor = { 130, 140, 170, 180 } },
                    UI.Label {
                        text = evalExpr_ ~= "" and evalExpr_ or "?",
                        fontSize = 11,
                        fontColor = { 160, 220, 180, 200 },
                    },
                },
            })
        end
    end
end

function AddCampaignInspectorRow(label, value)
    inspectorContent_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 10, paddingRight = 10, paddingTop = 3,
        children = {
            UI.Label { text = label, fontSize = 11, fontColor = { 130, 140, 170, 180 } },
            UI.Label { text = value or "-", fontSize = 11, fontColor = { 200, 210, 230, 220 } },
        }
    })
end

--- 填充闯关模式左侧面板 (受限积木)
function PopulateLeftPanelForCampaign(levelId)
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()

    local availableBlocks = CampaignManager.getAvailableBlocks(levelId)
    local availablePrefabs = CampaignManager.getAvailablePrefabs(levelId)

    -- 基础积木
    leftPanelContent_:AddChild(UI.Label {
        text = "基础积木",
        fontSize = 11,
        fontColor = { 140, 150, 180, 180 },
        paddingLeft = 12,
        paddingBottom = 4,
    })

    local allBasic = {
        { label = "变量 (x)", kind = "var", color = { 80, 200, 220, 255 } },
        { label = "抽象 (λx.M)", kind = "abs", color = { 160, 100, 220, 255 } },
        { label = "应用 (M N)", kind = "app", color = { 80, 180, 120, 255 } },
    }

    for _, item in ipairs(allBasic) do
        -- 检查是否可用
        local allowed = (availableBlocks == nil) -- nil = 全部可用
        if not allowed and availableBlocks then
            for _, b in ipairs(availableBlocks) do
                if b == item.kind then allowed = true; break end
            end
        end
        if allowed then
            leftPanelContent_:AddChild(UI.Button {
                text = item.label,
                variant = "ghost",
                size = "sm",
                width = "100%",
                textAlign = "left",
                fontColor = item.color,
                onClick = function()
                    AddBlockToCurrent(item.kind)
                end,
            })
        end
    end

    -- 预制积木
    if #availablePrefabs > 0 then
        leftPanelContent_:AddChild(UI.Panel {
            width = "90%", height = 1,
            marginTop = 8, marginBottom = 8,
            alignSelf = "center",
            backgroundColor = { 60, 70, 100, 60 },
        })

        leftPanelContent_:AddChild(UI.Label {
            text = "预制积木",
            fontSize = 11,
            fontColor = { 140, 150, 180, 180 },
            paddingLeft = 12,
            paddingBottom = 4,
        })

        for _, prefab in ipairs(availablePrefabs) do
            leftPanelContent_:AddChild(UI.Button {
                text = prefab.name,
                variant = "ghost",
                size = "sm",
                width = "100%",
                textAlign = "left",
                fontColor = { 200, 140, 255, 255 },
                onClick = function()
                    AddPrefabBlock(prefab.id)
                end,
            })
        end
    end

    -- 操作区
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
        text = "清空画布",
        variant = "danger",
        size = "sm",
        width = "100%",
        onClick = function()
            if blockCanvas_ then blockCanvas_:Clear() end
        end,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "删除选中",
        variant = "ghost",
        size = "sm",
        width = "100%",
        onClick = function() DeleteSelected() end,
    })
end

--- 添加预制积木到画布
function AddPrefabBlock(prefabId)
    if not blockCanvas_ then return end
    local ast = CampaignManager.getPrefabAST(prefabId)
    if ast then
        local block = ASTToBlock(ast)
        if block then
            local rx = 100 + math.random(0, 200)
            local ry = 80 + math.random(0, 150)
            blockCanvas_:AddBlock(block, rx, ry)
        end
    end
end

-- ============================================================================
-- 闯关辅助函数
-- ============================================================================

function ExitCampaignLevel()
    CampaignManager.exitLevel()
    EnterCampaignSelect()
end

function ShowCampaignHint()
    local hint = CampaignManager.getHint()
    if hint then
        ShowCampaignFeedback(false, "提示: " .. hint)
    end
end

function ShowCampaignFeedback(success, message)
    if not feedbackPanel_ or not feedbackLabel_ then return end
    feedbackLabel_:SetText(message)
    if success then
        feedbackLabel_:SetFontColor({ 100, 255, 150, 255 })
        feedbackPanel_:SetBackgroundColor({ 20, 50, 30, 220 })
    else
        feedbackLabel_:SetFontColor({ 255, 150, 100, 255 })
        feedbackPanel_:SetBackgroundColor({ 50, 30, 20, 220 })
    end
    feedbackPanel_:SetVisible(true)
end

-- ============================================================================
-- 闯关提交答案
-- ============================================================================

function SubmitCampaignAnswer()
    if appMode_ ~= "campaign_level" then return end
    if not blockCanvas_ then return end

    -- 从画布获取根积木 → 转 AST
    local roots = blockCanvas_:GetRootBlocks()
    if #roots == 0 then
        ShowCampaignFeedback(false, "画布为空！请构建一个 Lambda 表达式。")
        return
    end

    -- 取第一个根积木作为答案
    local playerAST = BlockDefs.toAST(roots[1])
    if not playerAST then
        ShowCampaignFeedback(false, "无法解析积木为表达式，请检查是否有未连接的槽位。")
        return
    end

    print("[Campaign] 提交答案: " .. AST.toString(playerAST))

    -- 验证
    local pass, msg = CampaignManager.submitAnswer(playerAST)

    if pass then
        ShowCampaignFeedback(true, msg)
        -- 延迟显示胜利弹窗
        local level = CampaignManager.getCurrentLevel()
            or LevelData.getLevelById(CampaignManager.getCurrentLevelId() or "")
        if level then
            ShowVictoryPopup(level)
        end
    else
        ShowCampaignFeedback(false, msg)
    end
end

function ShowVictoryPopup(level)
    -- 找到当前 level 的下一关
    local idx = LevelData.getLevelIndex(level.id)
    local nextLevel = LevelData.levels[idx + 1]
    local isFinalBoss = (level.isBoss and not nextLevel)

    victoryPopup_ = CampaignUI.createVictoryPopup(level, function()
        -- "下一关" / "回到主菜单" 回调
        if isFinalBoss or not nextLevel then
            EnterMainMenu()
        else
            CampaignManager.exitLevel()
            EnterCampaignLevel(nextLevel.id)
        end
    end)

    -- 把弹窗叠加到当前 UI 之上 (利用 absolute 定位)
    if uiRoot_ then
        uiRoot_:AddChild(victoryPopup_)
    end
end

-- ============================================================================
-- 上方: 求值/归约面板 (沙盒模式)
-- ============================================================================

function CreateTopPanel()
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
            -- 标题 + 视图指示
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
            -- 分隔
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            -- 表达式
            UI.Panel {
                flexDirection = "column",
                flex = 1,
                gap = 2,
                children = {
                    UI.Label { text = "表达式", fontSize = 10, fontColor = { 120, 130, 160, 180 } },
                    evalExprLabel_,
                }
            },
            -- 操作按钮
            UI.Button {
                text = "求值",
                variant = "success",
                size = "sm",
                onClick = function() EvaluateCurrent() end,
            },
            UI.Button {
                text = "单步",
                variant = "outline",
                size = "sm",
                onClick = function() StepEval() end,
            },
            -- 分隔
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            -- 结果
            UI.Panel {
                flexDirection = "column",
                width = 180,
                gap = 2,
                children = {
                    UI.Label { text = "正规形式", fontSize = 10, fontColor = { 120, 130, 160, 180 } },
                    evalResultLabel_,
                }
            },
            -- 返回主菜单
            UI.Panel { width = 1, height = 44, backgroundColor = { 50, 60, 90, 80 } },
            UI.Button {
                text = "菜单",
                variant = "ghost",
                size = "sm",
                onClick = function() EnterMainMenu() end,
            },
        }
    }
end

-- ============================================================================
-- 左侧面板: 积木库 / 预置节点 (沙盒模式)
-- ============================================================================

function CreateLeftPanel()
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

    -- 初始填充节点视图的面板内容
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

function PopulateLeftPanelForGraph()
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()
    if leftPanelTitle_ then leftPanelTitle_:SetText("节点库") end

    -- 预置组合子
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

    -- 分隔
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
        onClick = function() DeleteSelected() end,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "求值选中节点",
        variant = "success",
        size = "sm",
        width = "100%",
        onClick = function() EvaluateCurrent() end,
    })
end

function PopulateLeftPanelForBlocks()
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()
    if leftPanelTitle_ then leftPanelTitle_:SetText("积木库") end

    -- 基础积木
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
                AddBlockToCurrent(item.kind)
            end,
        })
    end

    -- 分隔
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
                AddBlockToCurrent(item.kind)
            end,
        })
    end

    -- 分隔
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
        onClick = function() ShowRenameDialog() end,
    })

    leftPanelContent_:AddChild(UI.Button {
        text = "删除选中积木",
        variant = "danger",
        size = "sm",
        width = "100%",
        onClick = function() DeleteSelected() end,
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
        onClick = function() ExitBlockEditor() end,
    })
end

-- ============================================================================
-- 中间: 画布区域
-- ============================================================================

function CreateCenterPanel()
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

-- ============================================================================
-- 右侧: Inspector 面板
-- ============================================================================

function CreateRightPanel()
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
-- Inspector 更新逻辑
-- ============================================================================

function UpdateInspector()
    if not inspectorContent_ then return end
    inspectorContent_:ClearChildren()

    if currentView_ == "graph" then
        UpdateInspectorForGraph()
    else
        UpdateInspectorForBlocks()
    end
end

function UpdateInspectorForGraph()
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
                EnterBlockEditor(selId)
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
                    UpdateInspector()
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

function UpdateInspectorForBlocks()
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
                onClick = function() ShowRenameDialogFor(sel) end,
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
                onClick = function() ShowRenameDialogFor(sel) end,
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
                    UpdateInspector()
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
            onClick = function() ExitBlockEditor() end,
        })
    end
end

-- Inspector 辅助
function AddInspectorRow(label, value)
    inspectorContent_:AddChild(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 4,
        paddingRight = 4,
        paddingTop = 2,
        paddingBottom = 2,
        children = {
            UI.Label { text = label, fontSize = 11, fontColor = { 140, 150, 180, 200 } },
            UI.Label { text = value or "-", fontSize = 11, fontColor = { 200, 210, 230, 240 } },
        }
    })
end

function AddInspectorSection(title)
    inspectorContent_:AddChild(UI.Panel {
        width = "100%",
        marginTop = 8,
        marginBottom = 4,
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

-- ============================================================================
-- 视图切换: 进入积木编辑器 (沙盒模式)
-- ============================================================================

function EnterBlockEditor(nodeId)
    if appMode_ ~= "sandbox" then return end

    local node = lambdaGraph_.nodes_[nodeId]
    if not node then return end

    editingNodeId_ = nodeId
    editingNodeName_ = node.name
    currentView_ = "blocks"

    -- 清空积木画布，加载节点的 AST
    blockCanvas_:Clear()
    if node.nodeDef and node.nodeDef.ast then
        local block = ASTToBlock(node.nodeDef.ast)
        if block then
            blockCanvas_:AddBlock(block, 120, 80)
        end
    end

    -- 切换面板可见性
    if graphViewPanel_ then graphViewPanel_:SetVisible(false) end
    if blockViewPanel_ then blockViewPanel_:SetVisible(true) end

    -- 更新面包屑
    if breadcrumbLabel_ then
        breadcrumbLabel_:SetText("节点图 > " .. editingNodeName_ .. " [编辑中]")
    end

    -- 更新左侧面板
    PopulateLeftPanelForBlocks()
    UpdateInspector()

    print("[Lambda] 进入积木编辑: " .. editingNodeName_)
end

-- ============================================================================
-- 视图切换: 退出积木编辑器 → 回到节点图 (沙盒模式)
-- ============================================================================

function ExitBlockEditor()
    if appMode_ ~= "sandbox" then return end
    if currentView_ ~= "blocks" or not editingNodeId_ then
        return
    end

    -- 从积木画布收集 AST
    local roots = blockCanvas_:GetRootBlocks()
    local newAST = nil
    if #roots > 0 then
        newAST = BlockDefs.toAST(roots[1])
    end

    -- 更新节点定义
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

    -- 切回节点图
    currentView_ = "graph"
    editingNodeId_ = nil
    editingNodeName_ = ""

    if graphViewPanel_ then graphViewPanel_:SetVisible(true) end
    if blockViewPanel_ then blockViewPanel_:SetVisible(false) end

    if breadcrumbLabel_ then
        breadcrumbLabel_:SetText("节点图")
    end

    PopulateLeftPanelForGraph()
    UpdateInspector()
end

-- ============================================================================
-- 积木操作
-- ============================================================================

function AddBlockToCurrent(kind)
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
            block = ASTToBlock(presetFn())
        end
    end
    if block then
        local rx = 100 + math.random(0, 200)
        local ry = 80 + math.random(0, 150)
        blockCanvas_:AddBlock(block, rx, ry)
    end
end

--- AST → Block 树 (递归转换)
function ASTToBlock(ast)
    if ast == nil then return nil end
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
-- 删除选中
-- ============================================================================

function DeleteSelected()
    if appMode_ == "campaign_level" then
        -- 闯关模式: 只有积木
        if blockCanvas_ then
            local sel = blockCanvas_:GetSelected()
            if sel then
                blockCanvas_:RemoveBlock(sel)
            end
        end
        return
    end

    -- 沙盒模式
    if currentView_ == "graph" then
        if lambdaGraph_ then
            if lambdaGraph_.selectedEdgeIdx_ then
                lambdaGraph_:RemoveSelectedEdge()
                UpdateInspector()
            elseif lambdaGraph_.selectedId_ then
                lambdaGraph_:RemoveNode(lambdaGraph_.selectedId_)
                UpdateInspector()
            end
        end
    else
        if blockCanvas_ then
            local sel = blockCanvas_:GetSelected()
            if sel then
                blockCanvas_:RemoveBlock(sel)
                UpdateInspector()
            end
        end
    end
end

-- ============================================================================
-- 重命名对话框
-- ============================================================================

function ShowRenameDialog()
    if currentView_ ~= "blocks" or not blockCanvas_ then return end
    local sel = blockCanvas_:GetSelected()
    if sel then ShowRenameDialogFor(sel) end
end

function ShowRenameDialogFor(block)
    if not block then return end
    local isVar = (block.kind == "variable")
    local isAbs = (block.kind == "abstraction")
    if not isVar and not isAbs then return end

    local currentName = isVar and (block.name or "") or (block.param or "")

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
            renameDialogOpen_ = false
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
                        if isVar then block.name = newName
                        else block.param = newName end
                        if blockCanvas_ then blockCanvas_:_refreshAll() end
                        UpdateInspector()
                    end
                    modal:Close()
                end,
            },
        }
    })

    modal:Open()
    renameDialogOpen_ = true
end

-- ============================================================================
-- 求值逻辑 (沙盒模式)
-- ============================================================================

function EvaluateCurrent()
    if appMode_ ~= "sandbox" then return end

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

function RunEvaluation(ast)
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

function StepEval()
    if appMode_ ~= "sandbox" then return end

    if #evalTrace_ == 0 then
        EvaluateCurrent()
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
-- 默认节点 (沙盒模式)
-- ============================================================================

function AddDefaultNodes()
    if not lambdaGraph_ then return end
    lambdaGraph_:AddPresetNode("I", 80, 60)
    lambdaGraph_:AddPresetNode("K", 80, 200)
    lambdaGraph_:AddPresetNode("S", 300, 60)
    lambdaGraph_:AddPresetNode("TRUE", 300, 200)

    UpdateInspector()
end

-- ============================================================================
-- 帧更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        if appMode_ == "sandbox" then
            if currentView_ == "blocks" then
                ExitBlockEditor()
            end
        elseif appMode_ == "campaign_level" then
            -- ESC 退出当前关卡
            CampaignManager.exitLevel()
            EnterCampaignSelect()
        elseif appMode_ == "campaign_select" then
            EnterMainMenu()
        end
    elseif key == KEY_DELETE or key == KEY_BACKSPACE then
        if not renameDialogOpen_ and not UI.GetFocus() then
            DeleteSelected()
        end
    elseif key == KEY_F2 then
        ShowRenameDialog()
    elseif key == KEY_SPACE then
        if appMode_ == "sandbox" then
            EvaluateCurrent()
        end
    elseif key == KEY_RETURN then
        if appMode_ == "campaign_level" then
            SubmitCampaignAnswer()
        end
    end
end
