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

    -- 时序常量
    local FLY_IN_DUR = 0.4
    local FLY_OUT_DUR = 0.4
    local SLOT_HL_DUR = 0.3
    local INTERNAL_DUR = 0.25
    local REPLACE_DUR = 0.35
    local SUBST_DUR = 0.5
    local STEP_GAP = 0.3
    local TEST_GAP = 0.5

    -- 保存原始积木位置
    local origX, origY = rootBlock.x, rootBlock.y

    ---------------------------------------------------------------------------
    -- 模式 A 辅助：在 lambda 积木上展示"喂入一个值"的动画
    ---------------------------------------------------------------------------
    local function animateFeedInput(lambdaBlock, inputStr, delay)
        local dur = 0.0

        -- 1) 输入值从右侧飞入 lambda 积木
        local targetX = lambdaBlock.x + lambdaBlock.w / 2
        local targetY = lambdaBlock.y + (BlockDefs.HEADER_H or 26) / 2
        local startX = lambdaBlock.x + lambdaBlock.w + 60
        local startY = targetY
        blockCanvas:AddFlowAnim(
            inputStr, startX, startY,
            targetX, targetY,
            FLY_IN_DUR, { 100, 220, 255 }, delay + dur
        )
        dur = dur + FLY_IN_DUR * 0.7

        -- 2) Lambda header 高亮 + 替换标签
        blockCanvas:AddFlashBlock(lambdaBlock, 0.4, { 200, 140, 255 }, delay + dur)
        local labelText = lambdaBlock.param .. " → " .. inputStr
        local labelX = lambdaBlock.x + lambdaBlock.w / 2
        local labelY = lambdaBlock.y - 4
        blockCanvas:AddSubstitutionLabel(
            labelX, labelY, labelText,
            SUBST_DUR, { 255, 200, 80 }, delay + dur
        )
        dur = dur + 0.35

        -- 3) 值从 header 流向 body 内所有匹配变量
        local flowStartX = lambdaBlock.x + lambdaBlock.w / 2
        local flowStartY = lambdaBlock.y + (BlockDefs.HEADER_H or 26)
        local bodyBlock = lambdaBlock.slots.body and lambdaBlock.slots.body.child
        if bodyBlock then
            local varBlocks = collectVarBlocks(bodyBlock, lambdaBlock.param, {})
            for vi, vb in ipairs(varBlocks) do
                local varCX = vb.x + vb.w / 2
                local varCY = vb.y + vb.h / 2
                local viDelay = delay + dur + (vi - 1) * (INTERNAL_DUR + 0.05)
                blockCanvas:AddInternalFlow(
                    inputStr,
                    flowStartX, flowStartY,
                    varCX, varCY,
                    INTERNAL_DUR,
                    { 255, 180, 80 },
                    viDelay
                )
                blockCanvas:AddVarReplace(
                    vb, inputStr, REPLACE_DUR,
                    { 255, 180, 80 }, viDelay + INTERNAL_DUR
                )
            end
            if #varBlocks > 0 then
                dur = dur + (#varBlocks) * (INTERNAL_DUR + 0.05) + REPLACE_DUR * 0.6
            else
                blockCanvas:AddFlashBlock(bodyBlock, 0.25, { 180, 220, 160 }, delay + dur)
                dur = dur + 0.25
            end
        else
            dur = dur + 0.2
        end

        return dur
    end

    ---------------------------------------------------------------------------
    -- 模式 B 辅助：在画布积木上做一步 β-归约动画
    ---------------------------------------------------------------------------
    local function animateOneReduction(delay)
        local roots = blockCanvas:GetRootBlocks()
        local curBlock = roots[1]
        if not curBlock then return 0.3 end

        local appBlock, lambdaBlock, argBlock = findRedexInBlocks(curBlock)
        if not appBlock or not lambdaBlock then
            blockCanvas:AddFlashBlock(curBlock, 0.3, { 100, 200, 180 }, delay)
            return 0.3
        end

        local dur = 0.0

        -- 1) 高亮 redex application 积木
        blockCanvas:AddFlashBlock(appBlock, 0.35, { 80, 160, 255 }, delay + dur)
        dur = dur + 0.25

        -- 2) 高亮 arg 积木
        local argStr = "?"
        if argBlock then
            local argAST = BlockDefs.toAST(argBlock)
            argStr = argAST and AST.toString(argAST) or argBlock.name or "?"
            blockCanvas:AddSlotHighlight(appBlock, "arg", SLOT_HL_DUR, { 100, 200, 255 }, delay + dur)
            blockCanvas:AddFlashBlock(argBlock, SLOT_HL_DUR, { 100, 220, 180 }, delay + dur)
            dur = dur + SLOT_HL_DUR * 0.6
        end

        -- 3) Lambda header + 替换标签
        blockCanvas:AddFlashBlock(lambdaBlock, 0.4, { 200, 140, 255 }, delay + dur)
        local labelText = lambdaBlock.param .. " → " .. argStr
        local labelX = lambdaBlock.x + lambdaBlock.w / 2
        local labelY = lambdaBlock.y - 4
        blockCanvas:AddSubstitutionLabel(
            labelX, labelY, labelText,
            SUBST_DUR, { 255, 200, 80 }, delay + dur
        )
        dur = dur + 0.35

        -- 4) 值流向 body 内变量
        local flowStartX = lambdaBlock.x + lambdaBlock.w / 2
        local flowStartY = lambdaBlock.y + (BlockDefs.HEADER_H or 26)
        local bodyBlock = lambdaBlock.slots.body and lambdaBlock.slots.body.child
        if bodyBlock then
            local varBlocks = collectVarBlocks(bodyBlock, lambdaBlock.param, {})
            for vi, vb in ipairs(varBlocks) do
                local varCX = vb.x + vb.w / 2
                local varCY = vb.y + vb.h / 2
                local viDelay = delay + dur + (vi - 1) * (INTERNAL_DUR + 0.05)
                blockCanvas:AddInternalFlow(
                    argStr,
                    flowStartX, flowStartY,
                    varCX, varCY,
                    INTERNAL_DUR,
                    { 255, 180, 80 },
                    viDelay
                )
                blockCanvas:AddVarReplace(
                    vb, argStr, REPLACE_DUR,
                    { 255, 180, 80 }, viDelay + INTERNAL_DUR
                )
            end
            if #varBlocks > 0 then
                dur = dur + (#varBlocks) * (INTERNAL_DUR + 0.05) + REPLACE_DUR * 0.6
            else
                blockCanvas:AddFlashBlock(bodyBlock, 0.25, { 180, 220, 160 }, delay + dur)
                dur = dur + 0.25
            end
        else
            dur = dur + 0.2
        end

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
                local outX = outBlock and (outBlock.x + outBlock.w / 2) or (origX + 50)
                local outY = outBlock and (outBlock.y + outBlock.h / 2) or (origY + 20)
                local outColor = match and { 100, 255, 160 } or { 255, 100, 100 }
                blockCanvas:AddFlowAnim(
                    resultStr, outX, outY,
                    outX + 80, outY - 20,
                    FLY_OUT_DUR, outColor, 0.1
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
                            local stepDur = animateOneReduction(0.05)
                            blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                                local nextAST = trace[sIdx + 1]
                                local nextBlock = ASTToBlock(nextAST)
                                if nextBlock then
                                    blockCanvas:ReplaceBlocks({})
                                    blockCanvas:AddBlock(nextBlock, origX, origY)
                                end
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
                    local stepDur = animateFeedInput(curBlock, inputStr, 0.05)

                    blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                        local inputAST = Verifier.Parser.parse(inputStr)
                        if currentAST and currentAST.kind == "abstraction" and inputAST then
                            currentAST = AST.substitute(currentAST.body, currentAST.param, inputAST)
                        end
                        local newBlock = ASTToBlock(currentAST)
                        if newBlock then
                            blockCanvas:ReplaceBlocks({})
                            blockCanvas:AddBlock(newBlock, origX, origY)
                        end
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
                        local stepDur = animateOneReduction(0.05)
                        blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                            local nextBlock = ASTToBlock(trace[sIdx + 1])
                            if nextBlock then
                                blockCanvas:ReplaceBlocks({})
                                blockCanvas:AddBlock(nextBlock, origX, origY)
                            end
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
                    local finalBlock = ASTToBlock(resultAST)
                    if finalBlock then
                        blockCanvas:ReplaceBlocks({})
                        blockCanvas:AddBlock(finalBlock, origX, origY)
                    end
                    local roots = blockCanvas:GetRootBlocks()
                    local outBlock = roots[1]
                    local outX = outBlock and (outBlock.x + outBlock.w / 2) or (origX + 50)
                    local outY = outBlock and (outBlock.y + outBlock.h / 2) or (origY + 20)
                    local outColor = match and { 100, 255, 160 } or { 255, 100, 100 }
                    blockCanvas:AddFlowAnim(
                        resultStr, outX, outY,
                        outX + 80, outY - 20,
                        FLY_OUT_DUR, outColor, 0.1
                    )
                    blockCanvas:AddTimedAction(FLY_OUT_DUR + TEST_GAP, function()
                        runTestCase(tcIdx + 1, onAllDone)
                    end)
                    return
                end

                local stepDur = animateOneReduction(0.05)
                blockCanvas:AddTimedAction(stepDur + STEP_GAP, function()
                    local nextBlock = ASTToBlock(trace[stepIdx + 1])
                    if nextBlock then
                        blockCanvas:ReplaceBlocks({})
                        blockCanvas:AddBlock(nextBlock, origX, origY)
                    end
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
        blockCanvas:ReplaceBlocks({})
        blockCanvas:AddBlock(rootBlock, origX, origY)
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
