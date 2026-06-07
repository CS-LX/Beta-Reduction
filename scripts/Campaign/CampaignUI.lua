-- ============================================================================
-- Campaign/CampaignUI.lua - 闯关模式 UI
-- ============================================================================
-- 负责:
--   1. 主菜单 (选择沙盒模式 / 闯关模式)
--   2. 关卡选择界面 (章节列表 + 关卡网格)
--   3. 关卡内 UI (目标面板、教程面板、提交按钮、结果反馈)
-- ============================================================================

local UI = require("urhox-libs/UI")
local LevelData = require("Campaign.LevelData")
local CampaignManager = require("Campaign.CampaignManager")

local CampaignUI = {}

-- ============================================================================
-- 内部引用
-- ============================================================================

-- 回调 (由 main.lua 设置)
local callbacks = {
    onEnterSandbox = nil,    -- 进入沙盒模式
    onEnterLevel = nil,      -- 进入某关卡(levelId)
    onExitLevel = nil,       -- 退出关卡回到选择界面
    onSubmitAnswer = nil,    -- 提交答案
    onShowHint = nil,        -- 显示提示
}

-- UI 元素引用
local mainMenuRoot_ = nil
local levelSelectRoot_ = nil
local levelHUDRoot_ = nil
local tutorialPanel_ = nil
local objectiveLabel_ = nil
local feedbackPanel_ = nil
local feedbackLabel_ = nil

-- ============================================================================
-- 初始化
-- ============================================================================

--- 设置回调
function CampaignUI.setCallbacks(cbs)
    for k, v in pairs(cbs) do
        callbacks[k] = v
    end
end

-- ============================================================================
-- 主菜单
-- ============================================================================

--- 创建主菜单 (沙盒/闯关选择)
---@return any UI widget
function CampaignUI.createMainMenu()
    local completed, total = CampaignManager.getProgress()

    mainMenuRoot_ = UI.Panel {
        id = "mainMenu",
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 12, 14, 22, 255 },
        children = {
            UI.Panel {
                flexDirection = "column",
                alignItems = "center",
                gap = 24,
                children = {
                    -- 标题
                    UI.Label {
                        text = "Lambda Calculus",
                        fontSize = 32,
                        fontColor = { 140, 200, 255, 255 },
                    },
                    UI.Label {
                        text = "可视化编程沙盒",
                        fontSize = 18,
                        fontColor = { 160, 170, 200, 200 },
                    },
                    -- 间距
                    UI.Panel { height = 20 },
                    -- 闯关模式按钮
                    UI.Button {
                        text = "闯关模式",
                        variant = "primary",
                        size = "lg",
                        width = 220,
                        onClick = function()
                            if callbacks.onEnterLevel then
                                CampaignUI.showLevelSelect()
                            end
                        end,
                    },
                    -- 进度提示
                    UI.Label {
                        text = completed > 0
                            and ("进度: " .. completed .. "/" .. total)
                            or "从零开始学习 Lambda 演算",
                        fontSize = 12,
                        fontColor = { 120, 130, 160, 160 },
                    },
                    -- 间距
                    UI.Panel { height = 8 },
                    -- 沙盒按钮
                    UI.Button {
                        text = "沙盒模式",
                        variant = "outline",
                        size = "lg",
                        width = 220,
                        onClick = function()
                            if callbacks.onEnterSandbox then
                                callbacks.onEnterSandbox()
                            end
                        end,
                    },
                    UI.Label {
                        text = "自由创作，无限制",
                        fontSize = 12,
                        fontColor = { 120, 130, 160, 160 },
                    },
                    -- 重置进度 (小字)
                    UI.Panel { height = 30 },
                    UI.Button {
                        text = "重置进度",
                        variant = "ghost",
                        size = "sm",
                        fontColor = { 120, 80, 80, 160 },
                        onClick = function()
                            CampaignManager.resetProgress()
                            -- 刷新显示
                            CampaignUI.showMainMenu()
                        end,
                    },
                }
            },
        }
    }

    return mainMenuRoot_
end

-- ============================================================================
-- 关卡选择界面
-- ============================================================================

function CampaignUI.showMainMenu()
    if callbacks.onEnterLevel then
        -- 通过回调让 main 切换 UI
        -- 先重建主菜单
    end
end

--- 创建关卡选择界面
---@return any UI widget
function CampaignUI.createLevelSelect()
    local chapters = CampaignManager.getChaptersWithProgress()

    local chapterWidgets = {}
    for _, ch in ipairs(chapters) do
        table.insert(chapterWidgets, CampaignUI._createChapterSection(ch))
    end

    levelSelectRoot_ = UI.Panel {
        id = "levelSelect",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = { 12, 14, 22, 255 },
        children = {
            -- 顶栏
            UI.Panel {
                width = "100%",
                height = 56,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 16,
                paddingRight = 16,
                backgroundColor = { 22, 25, 38, 245 },
                borderBottom = 1,
                borderColor = { 50, 60, 90, 80 },
                children = {
                    UI.Button {
                        text = "← 返回",
                        variant = "ghost",
                        size = "sm",
                        onClick = function()
                            if callbacks.onExitLevel then
                                callbacks.onExitLevel()
                            end
                        end,
                    },
                    UI.Panel { flex = 1 },
                    UI.Label {
                        text = "闯关模式",
                        fontSize = 16,
                        fontColor = { 140, 200, 255, 255 },
                    },
                    UI.Panel { flex = 1 },
                    UI.Label {
                        text = CampaignManager.getProgress() .. "/" .. LevelData.getTotalLevels(),
                        fontSize = 13,
                        fontColor = { 160, 170, 200, 180 },
                    },
                }
            },
            -- 章节滚动区域
            UI.ScrollView {
                width = "100%",
                flex = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        paddingTop = 16,
                        paddingBottom = 32,
                        paddingLeft = 24,
                        paddingRight = 24,
                        gap = 20,
                        children = chapterWidgets,
                    }
                }
            },
        }
    }

    return levelSelectRoot_
end

--- 创建单个章节区块
function CampaignUI._createChapterSection(ch)
    local levels = LevelData.getChapterLevels(ch.id)
    local levelBtns = {}

    for _, lv in ipairs(levels) do
        local status = CampaignManager.getLevelStatus(lv.id)
        table.insert(levelBtns, CampaignUI._createLevelButton(lv, status))
    end

    local headerColor = ch.unlocked and { 180, 200, 230, 255 } or { 80, 90, 110, 180 }
    local progressText = ch.completed .. "/" .. ch.total

    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 10,
        children = {
            -- 章节标题
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = ch.icon or "",
                        fontSize = 18,
                    },
                    UI.Label {
                        text = "第" .. ch.id .. "章: " .. ch.title,
                        fontSize = 15,
                        fontColor = headerColor,
                    },
                    UI.Label {
                        text = ch.subtitle,
                        fontSize = 11,
                        fontColor = { 120, 130, 160, 140 },
                    },
                    UI.Panel { flex = 1 },
                    UI.Label {
                        text = progressText,
                        fontSize = 12,
                        fontColor = ch.completed == ch.total
                            and { 100, 220, 140, 255 }
                            or { 140, 150, 170, 180 },
                    },
                }
            },
            -- 关卡按钮列表
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 8,
                children = levelBtns,
            },
        }
    }
end

--- 创建单个关卡按钮
function CampaignUI._createLevelButton(lv, status)
    local bgColor, textColor, borderClr
    if status == "completed" then
        bgColor = { 30, 60, 45, 240 }
        textColor = { 100, 220, 140, 255 }
        borderClr = { 60, 140, 90, 200 }
    elseif status == "unlocked" then
        bgColor = { 30, 35, 55, 240 }
        textColor = { 180, 200, 255, 255 }
        borderClr = { 80, 100, 180, 200 }
    else -- locked
        bgColor = { 25, 25, 30, 200 }
        textColor = { 70, 75, 90, 180 }
        borderClr = { 40, 45, 55, 120 }
    end

    local statusIcon = ""
    if status == "completed" then statusIcon = " ✓"
    elseif status == "locked" then statusIcon = " 🔒"
    end

    return UI.Button {
        text = lv.id .. " " .. lv.title .. statusIcon,
        width = 160,
        height = 48,
        variant = "ghost",
        size = "sm",
        backgroundColor = bgColor,
        fontColor = textColor,
        borderWidth = 1,
        borderColor = borderClr,
        borderRadius = 6,
        disabled = (status == "locked"),
        onClick = function()
            if status ~= "locked" and callbacks.onEnterLevel then
                callbacks.onEnterLevel(lv.id)
            end
        end,
    }
end

-- ============================================================================
-- 关卡内 HUD (叠加在编辑界面上)
-- ============================================================================

--- 创建关卡内 HUD
---@param levelId string
---@return any UI widget
function CampaignUI.createLevelHUD(levelId)
    local level = LevelData.getLevelById(levelId)
    if not level then return UI.Panel {} end

    -- 目标面板
    objectiveLabel_ = UI.Label {
        id = "objective",
        text = level.description,
        fontSize = 12,
        fontColor = { 200, 210, 230, 220 },
        numberOfLines = 4,
    }

    -- 反馈面板 (验证结果)
    feedbackLabel_ = UI.Label {
        id = "feedback",
        text = "",
        fontSize = 13,
        fontColor = { 255, 200, 100, 255 },
        numberOfLines = 3,
    }

    feedbackPanel_ = UI.Panel {
        id = "feedbackPanel",
        width = "100%",
        paddingTop = 6,
        paddingBottom = 6,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 6,
        backgroundColor = { 40, 35, 20, 200 },
        visible = false,
        children = { feedbackLabel_ },
    }

    -- 教程面板
    tutorialPanel_ = CampaignUI._createTutorialPanel(level)

    levelHUDRoot_ = UI.Panel {
        id = "levelHUD",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        -- 不拦截事件 (仅 HUD 面板本身响应)
        children = {
            -- 左上: 目标 + 操作
            UI.Panel {
                position = "absolute",
                top = 78,
                left = 8,
                width = 200,
                flexDirection = "column",
                gap = 8,
                paddingTop = 10,
                paddingBottom = 10,
                paddingLeft = 10,
                paddingRight = 10,
                borderRadius = 8,
                backgroundColor = { 18, 20, 32, 220 },
                borderWidth = 1,
                borderColor = { 50, 60, 100, 100 },
                children = {
                    -- 关卡标题
                    UI.Label {
                        text = level.id .. " " .. level.title,
                        fontSize = 14,
                        fontColor = { 140, 200, 255, 255 },
                    },
                    UI.Label {
                        text = level.subtitle,
                        fontSize = 11,
                        fontColor = { 120, 130, 160, 160 },
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 50, 60, 90, 80 },
                        marginTop = 4, marginBottom = 4,
                    },
                    -- 目标描述
                    objectiveLabel_,
                    -- 反馈
                    feedbackPanel_,
                    -- 按钮
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 6,
                        marginTop = 6,
                        children = {
                            UI.Button {
                                text = "提交",
                                variant = "success",
                                size = "sm",
                                flex = 1,
                                onClick = function()
                                    if callbacks.onSubmitAnswer then
                                        callbacks.onSubmitAnswer()
                                    end
                                end,
                            },
                            UI.Button {
                                text = "提示",
                                variant = "outline",
                                size = "sm",
                                flex = 1,
                                onClick = function()
                                    CampaignUI.showHint()
                                end,
                            },
                        }
                    },
                    UI.Button {
                        text = "← 退出关卡",
                        variant = "ghost",
                        size = "sm",
                        width = "100%",
                        marginTop = 4,
                        fontColor = { 180, 130, 100, 200 },
                        onClick = function()
                            if callbacks.onExitLevel then
                                callbacks.onExitLevel()
                            end
                        end,
                    },
                }
            },
            -- 右侧: 教程面板
            tutorialPanel_,
        }
    }

    return levelHUDRoot_
end

--- 创建教程面板 (右侧)
function CampaignUI._createTutorialPanel(level)
    if not level.tutorial or #level.tutorial == 0 then
        return UI.Panel {}
    end

    local lines = {}
    for _, line in ipairs(level.tutorial) do
        table.insert(lines, UI.Label {
            text = line,
            fontSize = 11,
            fontColor = { 190, 200, 220, 210 },
            numberOfLines = 3,
        })
    end

    return UI.Panel {
        position = "absolute",
        top = 78,
        right = 8,
        width = 240,
        maxHeight = 400,
        flexDirection = "column",
        gap = 3,
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 10,
        paddingRight = 10,
        borderRadius = 8,
        backgroundColor = { 18, 20, 32, 210 },
        borderWidth = 1,
        borderColor = { 50, 60, 100, 80 },
        children = {
            UI.Label {
                text = "教程",
                fontSize = 12,
                fontColor = { 140, 200, 255, 220 },
                marginBottom = 6,
            },
            UI.ScrollView {
                width = "100%",
                flex = 1,
                maxHeight = 340,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        gap = 2,
                        children = lines,
                    }
                }
            },
        }
    }
end

-- ============================================================================
-- HUD 交互
-- ============================================================================

--- 显示验证结果反馈
---@param success boolean
---@param message string
function CampaignUI.showFeedback(success, message)
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

--- 隐藏反馈
function CampaignUI.hideFeedback()
    if feedbackPanel_ then
        feedbackPanel_:SetVisible(false)
    end
end

--- 显示提示
function CampaignUI.showHint()
    local hint = CampaignManager.getHint()
    if hint then
        CampaignUI.showFeedback(false, "提示: " .. hint)
    end
end

-- ============================================================================
-- 通关弹窗
-- ============================================================================

--- 创建通关庆祝面板
---@param level table  关卡数据
---@param onContinue function  继续回调
---@return any UI widget
function CampaignUI.createVictoryPopup(level, onContinue)
    local rewardText = ""
    if level.reward then
        rewardText = "解锁预制积木: " .. level.reward.name .. "\n" .. level.reward.description
    end

    local isBoss = level.isBoss

    return UI.Panel {
        id = "victoryPopup",
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0, left = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 320,
                flexDirection = "column",
                alignItems = "center",
                gap = 12,
                paddingTop = 24,
                paddingBottom = 24,
                paddingLeft = 20,
                paddingRight = 20,
                borderRadius = 12,
                backgroundColor = { 25, 30, 45, 245 },
                borderWidth = 2,
                borderColor = isBoss and { 255, 200, 50, 200 } or { 80, 180, 120, 200 },
                children = {
                    UI.Label {
                        text = isBoss and "通关！" or "正确！",
                        fontSize = 24,
                        fontColor = isBoss and { 255, 220, 80, 255 } or { 100, 255, 150, 255 },
                    },
                    UI.Label {
                        text = level.title .. " 完成",
                        fontSize = 15,
                        fontColor = { 200, 210, 230, 230 },
                    },
                    -- 奖励
                    UI.Panel {
                        width = "100%",
                        paddingTop = 8,
                        paddingBottom = 8,
                        paddingLeft = 12,
                        paddingRight = 12,
                        borderRadius = 6,
                        backgroundColor = { 40, 45, 60, 200 },
                        marginTop = 4,
                        children = {
                            UI.Label {
                                text = rewardText,
                                fontSize = 12,
                                fontColor = { 200, 180, 255, 220 },
                                numberOfLines = 3,
                            },
                        }
                    },
                    -- Boss 特殊文字
                    isBoss and UI.Label {
                        text = "你已掌握 Lambda 演算的精髓！\n从三个基础积木到四则运算器，\n你就是 Lambda 大师！",
                        fontSize = 12,
                        fontColor = { 255, 220, 140, 200 },
                        numberOfLines = 4,
                        textAlign = "center",
                        marginTop = 4,
                    } or UI.Panel {},
                    -- 按钮
                    UI.Panel {
                        flexDirection = "row",
                        gap = 12,
                        marginTop = 12,
                        children = {
                            UI.Button {
                                text = isBoss and "回到主菜单" or "下一关",
                                variant = "primary",
                                size = "md",
                                onClick = function()
                                    if onContinue then onContinue() end
                                end,
                            },
                            UI.Button {
                                text = "关卡选择",
                                variant = "outline",
                                size = "md",
                                onClick = function()
                                    if callbacks.onExitLevel then
                                        callbacks.onExitLevel()
                                    end
                                end,
                            },
                        }
                    },
                }
            },
        }
    }
end

return CampaignUI
