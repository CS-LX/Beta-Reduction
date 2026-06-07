-- ============================================================================
-- AppState: 全局共享状态
-- ============================================================================
-- 所有模块通过 require("AppState") 获取同一份状态引用

local M = {}

-- 应用模式: "menu" | "sandbox" | "campaign_select" | "campaign_level"
M.appMode = "menu"

-- UI 根引用
M.uiRoot = nil

-- 画布/图引用
M.blockCanvas = nil
M.lambdaGraph = nil

-- 视图状态: "graph" (节点图) | "blocks" (积木编辑)
M.currentView = "graph"
M.editingNodeId = nil
M.editingNodeName = ""

-- 求值状态 (沙盒模式)
M.evalExpr = ""
M.evalResult = ""
M.evalTrace = {}
M.traceIndex = 0

-- Inspector 引用
M.inspectorPanel = nil
M.inspectorContent = nil

-- 顶部面板引用
M.evalExprLabel = nil
M.evalResultLabel = nil

-- 左侧面板引用
M.leftPanelTitle = nil
M.leftPanelContent = nil

-- 中间画布容器
M.blockViewPanel = nil
M.graphViewPanel = nil

-- 面包屑/视图指示
M.breadcrumbLabel = nil

-- 闯关模式 HUD 引用
M.campaignHUD = nil
M.victoryPopup = nil
M.feedbackPanel = nil
M.feedbackLabel = nil

-- 归约可视化状态
M.reductionPanel = nil
M.reductionStepsContainer = nil
M.reductionVisible = false

-- 对话框状态
M.renameDialogOpen = false

return M
