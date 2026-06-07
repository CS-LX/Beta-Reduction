-- ============================================================================
-- Lambda 演算可视化编程沙盒 — 入口与胶水层
-- ============================================================================
-- 模式:
--   - 主菜单: 选择沙盒/闯关模式
--   - 沙盒模式: Blender 风格布局，自由创作
--   - 闯关模式: 关卡选择 + 限制积木的编辑器
-- ============================================================================

local UI = require("urhox-libs/UI")
local AST = require("Lambda.AST")
local BlockDefs = require("Blocks.BlockDefs")
local CampaignManager = require("Campaign.CampaignManager")
local CampaignUI = require("Campaign.CampaignUI")
local LevelData = require("Campaign.LevelData")

local CampaignEditor = require("Campaign.CampaignEditor")
local SandboxEditor = require("Sandbox.SandboxEditor")

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

-- 当前活跃的画布/图引用 (由子模块管理，main 只做路由)
local blockCanvas_ = nil
local lambdaGraph_ = nil

-- 当前活跃视图 (sandbox 用)
local currentView_ = "graph"

-- 对话框状态（防止键盘事件穿透）
local renameDialogOpen_ = false

-- ============================================================================
-- 共享工具函数
-- ============================================================================

--- AST → Block 树 (递归转换)
--- @param ast table AST 节点
--- @param scope table|nil 当前作用域栈（param名 → 最近绑定的λ参数名）
function ASTToBlock(ast, scope)
    if ast == nil then return nil end
    scope = scope or {}

    if ast.kind == "variable" then
        local block = BlockDefs.createVar(ast.name)
        -- 查找该变量绑定的参数名（用于颜色映射）
        block.boundParam = scope[ast.name] or ast.name
        return block
    elseif ast.kind == "abstraction" then
        local block = BlockDefs.createAbs(ast.param)
        -- 构建新作用域：当前参数名绑定到自身
        local childScope = {}
        for k, v in pairs(scope) do childScope[k] = v end
        childScope[ast.param] = ast.param
        local bodyBlock = ASTToBlock(ast.body, childScope)
        if bodyBlock then
            BlockDefs.attach(bodyBlock, block, "body")
        end
        return block
    elseif ast.kind == "application" then
        local block = BlockDefs.createApp()
        local funcBlock = ASTToBlock(ast.func, scope)
        local argBlock = ASTToBlock(ast.arg, scope)
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
-- 重命名对话框 (共享 — 沙盒+闯关都用)
-- ============================================================================

function ShowRenameDialog()
    if not blockCanvas_ then return end
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
                        -- 通知当前活跃模块刷新 Inspector
                        if appMode_ == "campaign_level" then
                            CampaignEditor.updateInspector()
                        elseif appMode_ == "sandbox" then
                            SandboxEditor.updateInspector()
                        end
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
-- 删除选中 (路由到当前活跃模块)
-- ============================================================================

function DeleteSelected()
    if appMode_ == "campaign_level" then
        if blockCanvas_ then
            local sel = blockCanvas_:GetSelected()
            if sel then
                blockCanvas_:RemoveBlock(sel)
                CampaignEditor.updateInspector()
            end
        end
    elseif appMode_ == "sandbox" then
        SandboxEditor.deleteSelected()
    end
end

-- ============================================================================
-- 模式切换
-- ============================================================================

--- 进入主菜单
function EnterMainMenu()
    appMode_ = "menu"
    currentView_ = "graph"
    blockCanvas_ = nil
    lambdaGraph_ = nil

    local menu = CampaignUI.createMainMenu()
    UI.SetRoot(menu)

    print("[App] 进入主菜单")
end

--- 进入沙盒模式
function EnterSandbox()
    appMode_ = "sandbox"
    currentView_ = "graph"

    SandboxEditor.createUI()
    SandboxEditor.addDefaultNodes()

    blockCanvas_ = SandboxEditor.getBlockCanvas()
    lambdaGraph_ = SandboxEditor.getLambdaGraph()

    print("[App] 进入沙盒模式")
end

--- 进入闯关关卡选择
function EnterCampaignSelect()
    appMode_ = "campaign_select"
    currentView_ = "graph"
    blockCanvas_ = nil
    lambdaGraph_ = nil

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
    currentView_ = "blocks"

    CampaignEditor.createLevelUI(levelId)
    blockCanvas_ = CampaignEditor.getBlockCanvas()
    lambdaGraph_ = nil

    -- 预置变量：为 raw=true 关卡自动在画布中放置命名变量
    local level = LevelData.getLevelById(levelId)
    if level and level.initialVars and blockCanvas_ then
        for i, varName in ipairs(level.initialVars) do
            local block = BlockDefs.createVar(varName)
            local x = 120 + (i - 1) * 120
            local y = 100
            blockCanvas_:AddBlock(block, x, y)
        end
    end

    print("[App] 进入闯关关卡: " .. levelId)
end

-- ============================================================================
-- 闯关回调设置
-- ============================================================================

local function SetupCampaignCallbacks()
    CampaignUI.setCallbacks({
        onEnterSandbox = function()
            EnterSandbox()
        end,
        onEnterLevel = function(levelId)
            EnterCampaignLevel(levelId)
        end,
        onExitLevel = function()
            if appMode_ == "campaign_level" then
                CampaignManager.exitLevel()
                EnterCampaignSelect()
            elseif appMode_ == "campaign_select" then
                EnterMainMenu()
            end
        end,
        onSubmitAnswer = function()
            CampaignEditor.submitAnswer()
        end,
        onShowHint = function()
            CampaignEditor.showHint()
        end,
        onShowLevelSelect = function()
            EnterCampaignSelect()
        end,
    })
end

-- ============================================================================
-- 模块初始化 (注入回调)
-- ============================================================================

local function InitModules()
    CampaignEditor.init({
        ASTToBlock = ASTToBlock,
        EnterCampaignSelect = EnterCampaignSelect,
        EnterMainMenu = EnterMainMenu,
        EnterCampaignLevel = EnterCampaignLevel,
        AddBlockToCurrent = function(kind)
            -- 闯关模式的 addBlock 直接代理到 CampaignEditor 没有的场景
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
        end,
        DeleteSelected = DeleteSelected,
        ShowRenameDialogFor = ShowRenameDialogFor,
    })

    SandboxEditor.init({
        ASTToBlock = ASTToBlock,
        EnterMainMenu = EnterMainMenu,
        ShowRenameDialogFor = ShowRenameDialogFor,
        ShowRenameDialog = ShowRenameDialog,
    })
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "λ Sandbox - Lambda Calculus Visual Programming"

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    CampaignManager.init()
    InitModules()
    SetupCampaignCallbacks()
    EnterMainMenu()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== Lambda Sandbox Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 帧更新预留
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_ESCAPE then
        if appMode_ == "sandbox" then
            currentView_ = SandboxEditor.getCurrentView()
            if currentView_ == "blocks" then
                SandboxEditor.exitBlockEditor()
                currentView_ = "graph"
            end
        elseif appMode_ == "campaign_level" then
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
            SandboxEditor.evaluateCurrent()
        end
    elseif key == KEY_RETURN then
        if appMode_ == "campaign_level" then
            CampaignEditor.submitAnswer()
        end
    end
end
