-- ============================================================================
-- Campaign/CampaignEditor.lua
-- 闯关模式 UI 构建 + Inspector + 提交 + 胜利弹窗
-- ============================================================================

local UI = require("urhox-libs/UI")
local AST = require("Lambda.AST")
local BlockDefs = require("Blocks.BlockDefs")
local BlockCanvas = require("Blocks.BlockCanvas")
local Evaluator = require("Lambda.Evaluator")
local CampaignManager = require("Campaign.CampaignManager")
local CampaignUI = require("Campaign.CampaignUI")
local LevelData = require("Campaign.LevelData")
local FlowAnimation = require("Campaign.FlowAnimation")

local M = {}

-- ============================================================================
-- 模块内部引用 (通过 init 注入)
-- ============================================================================

local mainCallbacks_ = nil  -- { ASTToBlock, EnterCampaignSelect, EnterMainMenu,
                            --   EnterCampaignLevel, AddBlockToCurrent, DeleteSelected,
                            --   ShowRenameDialogFor }

--- 初始化，注入 main 的回调
function M.init(callbacks)
    mainCallbacks_ = callbacks
end

-- ============================================================================
-- 模块状态 (仅闯关模式 UI 使用的引用)
-- ============================================================================

local blockCanvas_ = nil
local evalExprLabel_ = nil
local leftPanelTitle_ = nil
local leftPanelContent_ = nil
local inspectorContent_ = nil
local feedbackPanel_ = nil
local feedbackLabel_ = nil
local reductionPanel_ = nil
local reductionStepsContainer_ = nil
local reductionVisible_ = false
local campaignHUD_ = nil
local victoryPopup_ = nil
local uiRoot_ = nil
local evalExpr_ = ""
local appMode_ = "menu"

-- ============================================================================
-- 状态存取 (供 main 模块协调使用)
-- ============================================================================

function M.getBlockCanvas() return blockCanvas_ end
function M.getUIRoot() return uiRoot_ end
function M.setAppMode(mode) appMode_ = mode end

-- ============================================================================
-- 关卡信息面板
-- ============================================================================

local function CreateCampaignInfoPanel(level)
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
                            M.submitAnswer()
                        end,
                    },
                    UI.Button {
                        text = "提示",
                        variant = "outline",
                        size = "sm",
                        flex = 1,
                        onClick = function()
                            M.showHint()
                        end,
                    },
                }
            },
        }
    }
end

-- ============================================================================
-- Inspector
-- ============================================================================

local function AddCampaignInspectorRow(label, value)
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

function M.updateInspector()
    if not inspectorContent_ then return end
    if appMode_ ~= "campaign_level" then return end
    inspectorContent_:ClearChildren()

    local sel = blockCanvas_ and blockCanvas_:GetSelected()
    if sel then
        local kindNames = { variable = "变量", abstraction = "抽象 λ", application = "应用" }
        inspectorContent_:AddChild(UI.Label {
            text = kindNames[sel.kind] or sel.kind,
            fontSize = 12,
            fontColor = { 140, 200, 255, 240 },
            paddingLeft = 10, paddingTop = 4,
        })

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
                    M.updateInspector()
                end
            end,
        })
    else
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

-- ============================================================================
-- 左侧面板 (受限积木库)
-- ============================================================================

local function PopulateLeftPanelForCampaign(levelId)
    if not leftPanelContent_ then return end
    leftPanelContent_:ClearChildren()

    local availableBlocks = CampaignManager.getAvailableBlocks(levelId)
    local availablePrefabs = CampaignManager.getAvailablePrefabs(levelId)

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
        local allowed = (availableBlocks == nil)
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
                    mainCallbacks_.AddBlockToCurrent(item.kind)
                end,
            })
        end
    end

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
                    M.addPrefabBlock(prefab.id)
                end,
            })
        end
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
        onClick = function() mainCallbacks_.DeleteSelected() end,
    })
end

-- ============================================================================
-- 预制积木
-- ============================================================================

function M.addPrefabBlock(prefabId)
    if not blockCanvas_ then return end
    local ast = CampaignManager.getPrefabAST(prefabId)
    if ast then
        local block = mainCallbacks_.ASTToBlock(ast)
        if block then
            local rx = 100 + math.random(0, 200)
            local ry = 80 + math.random(0, 150)
            blockCanvas_:AddBlock(block, rx, ry)
        end
    end
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

function M.exitLevel()
    CampaignManager.exitLevel()
    mainCallbacks_.EnterCampaignSelect()
end

function M.showHint()
    local hint = CampaignManager.getHint()
    if hint then
        M.showFeedback(false, "提示: " .. hint)
    end
end

function M.showFeedback(success, message)
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

function M.hideReductionPanel()
    if reductionPanel_ then
        reductionPanel_:SetVisible(false)
    end
    reductionVisible_ = false
    if blockCanvas_ then
        blockCanvas_:SetFrozen(false)
        blockCanvas_:ClearAnims()
    end
end

-- ============================================================================
-- 提交答案
-- ============================================================================

function M.submitAnswer()
    if appMode_ ~= "campaign_level" then return end
    if not blockCanvas_ then return end

    if blockCanvas_:IsFrozen() or blockCanvas_:HasActiveAnims() then
        return
    end

    local roots = blockCanvas_:GetRootBlocks()
    if #roots == 0 then
        M.showFeedback(false, "画布为空！请构建一个 Lambda 表达式。")
        return
    end

    local playerAST = BlockDefs.toAST(roots[1])
    if not playerAST then
        M.showFeedback(false, "无法解析积木为表达式，请检查是否有未连接的槽位。")
        return
    end

    print("[Campaign] 提交答案: " .. AST.toString(playerAST))

    local pass, msg = CampaignManager.submitAnswer(playerAST)

    local level = CampaignManager.getCurrentLevel()
        or LevelData.getLevelById(CampaignManager.getCurrentLevelId() or "")
    local testCases = level and level.testCases or {}

    if #testCases > 0 then
        FlowAnimation.play(blockCanvas_, roots[1], playerAST, testCases, pass, msg, level, {
            ASTToBlock = mainCallbacks_.ASTToBlock,
            ShowCampaignFeedback = M.showFeedback,
            ShowVictoryPopup = function(lvl) M.showVictoryPopup(lvl) end,
        })
    else
        if pass then
            M.showFeedback(true, msg)
            if level then M.showVictoryPopup(level) end
        else
            M.showFeedback(false, msg)
        end
    end
end

-- ============================================================================
-- 胜利弹窗
-- ============================================================================

function M.showVictoryPopup(level)
    local idx = LevelData.getLevelIndex(level.id)
    local nextLevel = LevelData.levels[idx + 1]
    local isFinalBoss = (level.isBoss and not nextLevel)

    victoryPopup_ = CampaignUI.createVictoryPopup(level, function()
        if isFinalBoss or not nextLevel then
            mainCallbacks_.EnterMainMenu()
        else
            CampaignManager.exitLevel()
            mainCallbacks_.EnterCampaignLevel(nextLevel.id)
        end
    end)

    if uiRoot_ then
        uiRoot_:AddChild(victoryPopup_)
    end
end

-- ============================================================================
-- 主 UI 构建
-- ============================================================================

function M.createLevelUI(levelId)
    local level = LevelData.getLevelById(levelId)
    if not level then return end

    appMode_ = "campaign_level"

    -- 创建积木画布
    blockCanvas_ = BlockCanvas {
        id = "campaignCanvas",
        width = "100%",
        height = "100%",
        onBlockChanged = function()
            local roots = blockCanvas_ and blockCanvas_:GetRootBlocks() or {}
            if #roots > 0 then
                local ast = BlockDefs.toAST(roots[1])
                if ast then
                    evalExpr_ = AST.toString(ast)
                    if evalExprLabel_ then evalExprLabel_:SetText(evalExpr_) end
                end
            end
            M.updateInspector()
        end,
        onBlockSelected = function(block)
            M.updateInspector()
        end,
        onBlockDoubleClick = function(block)
            mainCallbacks_.ShowRenameDialogFor(block)
        end,
    }

    evalExprLabel_ = UI.Label {
        id = "campaignExpr",
        text = "",
        fontSize = 12,
        fontColor = { 160, 220, 180, 220 },
        numberOfLines = 2,
        flex = 1,
    }

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

    inspectorContent_ = UI.Panel {
        id = "campaignInspectorContent",
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }

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

    reductionStepsContainer_ = UI.Panel {
        id = "reductionSteps",
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }
    reductionPanel_ = UI.Panel {
        id = "reductionPanel",
        position = "absolute",
        top = 12,
        left = "5%",
        right = "5%",
        bottom = 60,
        borderRadius = 10,
        backgroundColor = { 15, 18, 30, 240 },
        borderWidth = 1,
        borderColor = { 80, 140, 255, 120 },
        flexDirection = "column",
        visible = false,
        children = {
            UI.Panel {
                width = "100%",
                height = 36,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12, paddingRight = 8,
                backgroundColor = { 25, 35, 60, 200 },
                borderBottom = 1,
                borderColor = { 60, 80, 140, 100 },
                children = {
                    UI.Label {
                        text = "运行过程",
                        fontSize = 13,
                        fontColor = { 140, 200, 255, 255 },
                        flex = 1,
                    },
                    UI.Button {
                        text = "×",
                        variant = "ghost",
                        size = "sm",
                        onClick = function()
                            M.hideReductionPanel()
                        end,
                    },
                }
            },
            UI.ScrollView {
                width = "100%",
                flex = 1,
                paddingTop = 8,
                paddingBottom = 8,
                paddingLeft = 12,
                paddingRight = 12,
                children = { reductionStepsContainer_ },
            },
        }
    }
    reductionVisible_ = false

    campaignHUD_ = CreateCampaignInfoPanel(level)

    -- 整体布局
    uiRoot_ = UI.Panel {
        id = "campaignRoot",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            -- 顶部
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
                            M.exitLevel()
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
            -- 内容区
            UI.Panel {
                width = "100%",
                flex = 1,
                flexDirection = "row",
                children = {
                    -- 左侧
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
                    -- 中间
                    UI.Panel {
                        flex = 1,
                        height = "100%",
                        children = {
                            blockCanvas_,
                            feedbackPanel_,
                            reductionPanel_,
                        },
                    },
                    -- 右侧
                    UI.Panel {
                        width = 240,
                        height = "100%",
                        flexDirection = "column",
                        backgroundColor = { 18, 20, 32, 240 },
                        borderLeft = 1,
                        borderColor = { 50, 60, 90, 80 },
                        children = {
                            campaignHUD_,
                            UI.Panel { width = "90%", height = 1, alignSelf = "center", backgroundColor = { 60, 70, 110, 80 } },
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
    M.updateInspector()

    return uiRoot_, blockCanvas_
end

return M
