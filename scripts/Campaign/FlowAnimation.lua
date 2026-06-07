-- ============================================================================
-- Campaign/FlowAnimation.lua
-- 画布数据流动画：白箱归约动画 v3
-- ============================================================================
-- 两种模式：
--   A) "输入喂食"模式（有外部输入）：输入值飞入 lambda → 内部替换 → 结果飞出
--   B) "画布归约"模式（raw=true）：在已有积木上做归约动画
-- ============================================================================

local AST = require("Lambda.AST")
local Evaluator = require("Lambda.Evaluator")
local BlockDefs = require("Blocks.BlockDefs")

local M = {}

-- ============================================================================
-- 内部辅助
-- ============================================================================

--- 递归收集 block 树中所有匹配指定名称的 variable 子积木
---@param block table
---@param varName string
---@param list table[]
---@return table[]
local function collectVarBlocks(block, varName, list)
    list = list or {}
    if not block then return list end
    if block.kind == "variable" and block.name == varName then
        table.insert(list, block)
    end
    for _, slot in pairs(block.slots or {}) do
        if slot.child then
            collectVarBlocks(slot.child, varName, list)
        end
    end
    return list
end

--- 在积木树中按 Normal Order 找到第一个 redex（App 且 func 是 lambda）
--- 返回: appBlock, lambdaBlock, argBlock  或 nil
---@param block table
---@return table|nil, table|nil, table|nil
local function findRedexInBlocks(block)
    if not block then return nil, nil, nil end
    if block.kind == "application" then
        local fc = block.slots.func and block.slots.func.child
        if fc and fc.kind == "abstraction" then
            local argChild = block.slots.arg and block.slots.arg.child
            return block, fc, argChild
        end
        if fc then
            local a, l, r = findRedexInBlocks(fc)
            if a then return a, l, r end
        end
        local ac = block.slots.arg and block.slots.arg.child
        if ac then
            local a, l, r = findRedexInBlocks(ac)
            if a then return a, l, r end
        end
    elseif block.kind == "abstraction" then
        local bc = block.slots.body and block.slots.body.child
        if bc then
            return findRedexInBlocks(bc)
        end
    end
    return nil, nil, nil
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 白箱归约动画 v3
--- @param blockCanvas table BlockCanvas 实例
--- @param rootBlock table 当前画布根积木
--- @param playerAST table 玩家构建的 AST
--- @param testCases table[] 测试用例列表
--- @param pass boolean 是否通过
--- @param msg string 反馈消息
--- @param level table|nil 关卡数据（通过时弹胜利窗）
--- @param callbacks table { ASTToBlock, ShowCampaignFeedback, ShowVictoryPopup }
function M.play(blockCanvas, rootBlock, playerAST, testCases, pass, msg, level, callbacks)
    if not blockCanvas then return end

    local Verifier = require("Campaign.Verifier")
    local ASTToBlock = callbacks.ASTToBlock

    blockCanvas:SetFrozen(true)
    blockCanvas:ClearAnims()

    -- 时序常量（整体偏慢，便于观察）
    local FLY_IN_DUR = 0.7
    local FLY_OUT_DUR = 0.7
    local SLOT_HL_DUR = 0.5
    local INTERNAL_DUR = 0.45
    local REPLACE_DUR = 0.5
    local SUBST_DUR = 0.7
    local STEP_GAP = 0.45
    local TEST_GAP = 0.6

    -- 保存原始积木位置
    local origX, origY = rootBlock.x, rootBlock.y

    ---------------------------------------------------------------------------
    -- 模式 A 辅助：在 lambda 积木上展示"喂入一个值"的动画
    -- 三阶段：吞入凹槽 → 替换涌出 → 破壳弹出
    -- nextBlock: 归约结果积木（预先构建好），在破壳动画中弹出
    ---------------------------------------------------------------------------
    local function animateFeedInput(lambdaBlock, inputStr, delay, nextBlock)
        local dur = 0.0

        -- 构建真实积木对象用于飞行动画
        local inputAST = Verifier.Parser.parse(inputStr)
        local inputBlock = inputAST and ASTToBlock(inputAST) or nil

        -- 阶段1: 吞入 — 外部输入从左侧滑入 body 的半圆凹口
        local SWALLOW_DUR = 0.7
        local notchX = lambdaBlock.x + BlockDefs.HEADER_W  -- body 左侧凹口位置
        local notchY = lambdaBlock.y + lambdaBlock.h / 2   -- 垂直居中
        local startX = lambdaBlock.x - 80
        local startY = notchY
        blockCanvas:AddFlowAnim(
            inputStr, startX, startY,
            notchX, notchY,
            SWALLOW_DUR, { 100, 220, 255 }, delay + dur,
            inputBlock
        )
        -- 高亮 λ 凹槽
        blockCanvas:AddFlashBlock(lambdaBlock, SWALLOW_DUR, { 200, 140, 255 }, delay + dur)
        dur = dur + SWALLOW_DUR * 0.8

        -- 显示替换标签
        local labelText = lambdaBlock.param .. " \xe2\x86\x92 " .. inputStr
        local labelX = lambdaBlock.x + lambdaBlock.w / 2
        local labelY = lambdaBlock.y - 4
        blockCanvas:AddSubstitutionLabel(
            labelX, labelY, labelText,
            SUBST_DUR, { 255, 200, 80 }, delay + dur
        )
        dur = dur + 0.35

        -- 阶段2: 替换涌出 — body 内变量逐个膨胀为 arg 副本
        local EMERGE_DUR = 0.5
        local bodyBlock = lambdaBlock.slots.body and lambdaBlock.slots.body.child
        if bodyBlock then
            local varBlocks = collectVarBlocks(bodyBlock, lambdaBlock.param, {})
            for vi, vb in ipairs(varBlocks) do
                local varCX = vb.x + vb.w / 2
                local varCY = vb.y + vb.h / 2
                local viDelay = delay + dur + (vi - 1) * (EMERGE_DUR + 0.05)
                blockCanvas:AddVarReplace(
                    vb, inputStr, EMERGE_DUR,
                    { 255, 180, 80 }, viDelay
                )
                -- 从凹口方向流入指示
                local flowFromX = lambdaBlock.x + BlockDefs.HEADER_W + BlockDefs.BUMP_R
                local flowFromY = notchY
                blockCanvas:AddInternalFlow(
                    inputStr,
                    flowFromX, flowFromY,
                    varCX, varCY,
                    EMERGE_DUR * 0.7,
                    { 255, 180, 80 },
                    viDelay,
                    inputBlock
                )
            end
            if #varBlocks > 0 then
                dur = dur + (#varBlocks) * (EMERGE_DUR + 0.05) + EMERGE_DUR * 0.3
            else
                blockCanvas:AddFlashBlock(bodyBlock, 0.25, { 180, 220, 160 }, delay + dur)
                dur = dur + 0.25
            end
        else
            dur = dur + 0.2
        end

        -- 阶段3: 破壳弹出 — λ 壳渐隐碎裂，新积木从壳内弹出
        local BREAK_DUR = 0.8
        if nextBlock then
            blockCanvas:AddBreakShellAnim(lambdaBlock, nextBlock, origX, origY, BREAK_DUR, delay + dur)
        else
            -- fallback: 没有 nextBlock 时仍用旧的碎裂（不应发生）
            blockCanvas:AddShatterAnim(lambdaBlock, BREAK_DUR, delay + dur)
        end
        dur = dur + BREAK_DUR

        return dur
    end

    ---------------------------------------------------------------------------
    -- 模式 B 辅助：在画布积木上做一步 β-归约动画
    -- 四阶段：对接高亮 → 吞入 → 替换涌出 → 破壳弹出
    -- nextBlock: 归约结果积木（预先构建好），在破壳动画中弹出
    ---------------------------------------------------------------------------
    local function animateOneReduction(delay, nextBlock)
        local roots = blockCanvas:GetRootBlocks()
        local curBlock = roots[1]
        if not curBlock then return 0.3 end

        local appBlock, lambdaBlock, argBlock = findRedexInBlocks(curBlock)
        if not appBlock or not lambdaBlock then
            blockCanvas:AddFlashBlock(curBlock, 0.3, { 100, 200, 180 }, delay)
            return 0.3
        end

        local dur = 0.0

        -- 阶段1: 对接高亮 — 整个 application 闪烁，arg 颜色加深
        blockCanvas:AddFlashBlock(appBlock, 0.5, { 80, 160, 255 }, delay + dur)
        local argStr = "?"
        local argFlyBlock = nil
        if argBlock then
            local argAST = BlockDefs.toAST(argBlock)
            argStr = argAST and AST.toString(argAST) or argBlock.name or "?"
            argFlyBlock = argAST and ASTToBlock(argAST) or nil
            blockCanvas:AddFlashBlock(argBlock, 0.5, { 100, 220, 180 }, delay + dur)
        end
        dur = dur + 0.5

        -- 阶段2: 吞入 — arg 从右侧滑向 body 左侧半圆凹口，被吞入消失
        local SWALLOW_DUR = 0.7
        if argBlock and argFlyBlock then
            local argCX = argBlock.x + argBlock.w / 2
            local argCY = argBlock.y + argBlock.h / 2
            -- 目标: body 左侧半圆凹口（arg 到达此处即被吞入）
            local notchX = lambdaBlock.x + BlockDefs.HEADER_W
            local notchY = lambdaBlock.y + lambdaBlock.h / 2
            blockCanvas:AddFlowAnim(
                argStr, argCX, argCY,
                notchX, notchY,
                SWALLOW_DUR, { 100, 220, 255 }, delay + dur,
                argFlyBlock
            )
            -- 同时高亮 λ 凹槽区域
            blockCanvas:AddFlashBlock(lambdaBlock, SWALLOW_DUR, { 200, 140, 255 }, delay + dur)
        end
        dur = dur + SWALLOW_DUR + 0.1

        -- 显示替换标签 "x → arg"
        local labelText = lambdaBlock.param .. " \xe2\x86\x92 " .. argStr
        local labelX = lambdaBlock.x + lambdaBlock.w / 2
        local labelY = lambdaBlock.y - 8
        blockCanvas:AddSubstitutionLabel(
            labelX, labelY, labelText,
            SUBST_DUR, { 255, 200, 80 }, delay + dur
        )
        dur = dur + 0.35

        -- 阶段3: 替换涌出 — body 内同色变量逐个膨胀变形为 arg 副本
        local EMERGE_DUR = 0.5
        local bodyBlock = lambdaBlock.slots.body and lambdaBlock.slots.body.child
        if bodyBlock then
            local varBlocks = collectVarBlocks(bodyBlock, lambdaBlock.param, {})
            for vi, vb in ipairs(varBlocks) do
                local varCX = vb.x + vb.w / 2
                local varCY = vb.y + vb.h / 2
                local viDelay = delay + dur + (vi - 1) * (EMERGE_DUR + 0.05)
                -- 变量积木膨胀替换效果
                blockCanvas:AddVarReplace(
                    vb, argStr, EMERGE_DUR,
                    { 255, 180, 80 }, viDelay
                )
                -- 同时从凹口方向发出微小流动指示
                local flowFromX = lambdaBlock.x + BlockDefs.HEADER_W + BlockDefs.BUMP_R
                local flowFromY = lambdaBlock.y + lambdaBlock.h / 2
                blockCanvas:AddInternalFlow(
                    argStr,
                    flowFromX, flowFromY,
                    varCX, varCY,
                    EMERGE_DUR * 0.7,
                    { 255, 180, 80 },
                    viDelay,
                    argFlyBlock
                )
            end
            if #varBlocks > 0 then
                dur = dur + (#varBlocks) * (EMERGE_DUR + 0.05) + EMERGE_DUR * 0.3
            else
                blockCanvas:AddFlashBlock(bodyBlock, 0.25, { 180, 220, 160 }, delay + dur)
                dur = dur + 0.25
            end
        else
            dur = dur + 0.2
        end

        -- 阶段4: 破壳弹出 — 整个当前根积木(壳)渐隐碎裂，新积木从壳内弹出
        local BREAK_DUR = 0.8
        if nextBlock then
            blockCanvas:AddBreakShellAnim(curBlock, nextBlock, origX, origY, BREAK_DUR, delay + dur)
        else
            -- fallback: 没有 nextBlock 时仍用旧的碎裂（不应发生）
            blockCanvas:AddShatterAnim(curBlock, BREAK_DUR, delay + dur)
        end
        dur = dur + BREAK_DUR

        return dur
    end

    ---------------------------------------------------------------------------
    -- 链式测试用例执行
    ---------------------------------------------------------------------------
    local function runTestCase(tcIdx, onAllDone)
        if tcIdx > #testCases then
            if onAllDone then onAllDone() end
            return
        end

        local tc = testCases[tcIdx]
        local inputTokens = Verifier._splitInputs(tc.input)
        local isRaw = tc.raw

        -- 计算最终结果
        local fullExpr = AST.deepClone(playerAST)
        if #inputTokens > 0 then
            for _, inputStr in ipairs(inputTokens) do
                local inputAST = Verifier.Parser.parse(inputStr)
                if inputAST then
                    fullExpr = AST.App(fullExpr, inputAST)
                end
            end
        end
        local resultAST = Evaluator.reduceToNF(fullExpr, 200)
        local resultStr = resultAST and AST.toString(resultAST) or "?"
        local expectAST = Verifier.Parser.parse(tc.expect)
        local match = false
        if resultAST and expectAST then
            match = Verifier.alphaEquiv(resultAST, expectAST)
            if not match then
                local expectReduced = Evaluator.reduceToNF(expectAST, 200)
                if expectReduced then
                    match = Verifier.alphaEquiv(resultAST, expectReduced)
                end
            end
        end

        -- =================================================================
        -- 模式 A：有外部输入 → "喂食"动画
        -- =================================================================
        if #inputTokens > 0 and not isRaw then
            blockCanvas:ReplaceBlocks({})
            blockCanvas:AddBlock(rootBlock, origX, origY)

            local currentAST = AST.deepClone(playerAST)

            local function flyOutResult()
                local roots = blockCanvas:GetRootBlocks()
                local outBlock = roots[1]
                local outX = outBlock and (outBlock.x + outBlock.w) or (origX + 50)
                local outY = outBlock and (outBlock.y + outBlock.h / 2) or (origY + 20)
                local outColor = match and { 100, 255, 160 } or { 255, 100, 100 }
                local resultFlyBlock = resultAST and ASTToBlock(resultAST) or nil
                blockCanvas:AddFlowAnim(
                    resultStr, outX, outY,
                    outX + 100, outY,
                    FLY_OUT_DUR, outColor, 0.1,
                    resultFlyBlock
                )
                blockCanvas:AddTimedAction(FLY_OUT_DUR + TEST_GAP, function()
                    runTestCase(tcIdx + 1, onAllDone)
                end)
            end

            local function feedInput(inputIdx)
                if inputIdx > #inputTokens then
                    local trace = Evaluator.trace(currentAST, 20)
                    local numInternalSteps = #trace - 1

                    if numInternalSteps > 0 then
                        local function runInternalStep(sIdx)
                            if sIdx > numInternalSteps then
                                flyOutResult()
                                return
                            end
                            local nextBlock = ASTToBlock(trace[sIdx + 1])
                            local stepDur = animateOneReduction(0.05, nextBlock)
                            blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                                runInternalStep(sIdx + 1)
                            end)
                        end
                        runInternalStep(1)
                    else
                        flyOutResult()
                    end
                    return
                end

                local inputStr = inputTokens[inputIdx]
                local roots = blockCanvas:GetRootBlocks()
                local curBlock = roots[1]

                if curBlock and curBlock.kind == "abstraction" then
                    -- 预先计算归约结果积木
                    local inputAST = Verifier.Parser.parse(inputStr)
                    if currentAST and currentAST.kind == "abstraction" and inputAST then
                        currentAST = AST.substitute(currentAST.body, currentAST.param, inputAST)
                    end
                    local newBlock = ASTToBlock(currentAST)

                    local stepDur = animateFeedInput(curBlock, inputStr, 0.05, newBlock)

                    blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                        feedInput(inputIdx + 1)
                    end)
                else
                    for ii = inputIdx, #inputTokens do
                        local iAST = Verifier.Parser.parse(inputTokens[ii])
                        if iAST then
                            currentAST = AST.App(currentAST, iAST)
                        end
                    end
                    local trace = Evaluator.trace(currentAST, 30)
                    local reBlock = ASTToBlock(trace[1])
                    if reBlock then
                        blockCanvas:ReplaceBlocks({})
                        blockCanvas:AddBlock(reBlock, origX, origY)
                    end
                    local numSteps = #trace - 1
                    local function runFallbackStep(sIdx)
                        if sIdx > numSteps then
                            flyOutResult()
                            return
                        end
                        local nextBlock = ASTToBlock(trace[sIdx + 1])
                        local stepDur = animateOneReduction(0.05, nextBlock)
                        blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                            runFallbackStep(sIdx + 1)
                        end)
                    end
                    runFallbackStep(1)
                end
            end

            blockCanvas:AddTimedAction(0.15, function()
                feedInput(1)
            end)

        -- =================================================================
        -- 模式 B：raw=true 或无输入 → 在画布已有积木上做归约动画
        -- =================================================================
        else
            local trace = Evaluator.trace(fullExpr, 30)
            local numSteps = #trace - 1

            local startBlock = ASTToBlock(trace[1])
            if startBlock then
                blockCanvas:ReplaceBlocks({})
                blockCanvas:AddBlock(startBlock, origX, origY)
            end

            local function runStep(stepIdx)
                if stepIdx > numSteps then
                    -- 最终结果已由最后一步的 breakShell 动画放置好
                    local roots = blockCanvas:GetRootBlocks()
                    local outBlock = roots[1]
                    local outX = outBlock and (outBlock.x + outBlock.w / 2) or (origX + 50)
                    local outY = outBlock and (outBlock.y + outBlock.h / 2) or (origY + 20)
                    local outColor = match and { 100, 255, 160 } or { 255, 100, 100 }
                    local outFlyBlock = resultAST and ASTToBlock(resultAST) or nil
                    blockCanvas:AddFlowAnim(
                        resultStr, outX, outY,
                        outX + 100, outY,
                        FLY_OUT_DUR, outColor, 0.1,
                        outFlyBlock
                    )
                    blockCanvas:AddTimedAction(FLY_OUT_DUR + TEST_GAP, function()
                        runTestCase(tcIdx + 1, onAllDone)
                    end)
                    return
                end

                local nextBlock = ASTToBlock(trace[stepIdx + 1])
                local stepDur = animateOneReduction(0.05, nextBlock)
                blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                    runStep(stepIdx + 1)
                end)
            end

            blockCanvas:AddTimedAction(0.15, function()
                runStep(1)
            end)
        end
    end

    -- 启动链式测试用例执行
    runTestCase(1, function()
        blockCanvas:TransitionToBlock(rootBlock, origX, origY)
        blockCanvas:SetFrozen(false)
        if pass then
            callbacks.ShowCampaignFeedback(true, msg)
            if level then callbacks.ShowVictoryPopup(level) end
        else
            callbacks.ShowCampaignFeedback(false, msg)
        end
    end)
end

return M
