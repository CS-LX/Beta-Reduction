-- ============================================================================
-- Lambda/Evaluator.lua - 蹦床式 Beta 归约求值器
-- ============================================================================
-- Normal Order 归约策略（最左最外优先）
-- 使用 Trampoline 模式避免深递归栈溢出

local AST = require("Lambda.AST")

local Evaluator = {}

-- ============================================================================
-- 蹦床核心
-- ============================================================================

local THUNK_TAG = "__thunk__"

local function thunk(fn)
    return { [THUNK_TAG] = true, cont = fn }
end

local function isThunk(v)
    return type(v) == "table" and v[THUNK_TAG] == true
end

--- 蹦床主循环
function Evaluator.trampoline(result, maxSteps)
    maxSteps = maxSteps or 10000
    local steps = 0
    while isThunk(result) do
        steps = steps + 1
        if steps > maxSteps then
            return nil, "归约步数超限 (" .. maxSteps .. ")"
        end
        result = result.cont()
    end
    return result, nil
end

-- ============================================================================
-- 单步归约 (Normal Order)
-- ============================================================================

--- 执行单步 Normal Order 归约
---@param node table|nil AST 节点
---@return table|nil, boolean  (归约后节点, 是否发生了归约)
function Evaluator.step(node)
    if node == nil then return node, false end

    if node.kind == "application" then
        -- 核心: 若 func 是 Abstraction，执行 β-归约
        if node.func and node.func.kind == "abstraction" then
            local result = AST.substitute(node.func.body, node.func.param, node.arg)
            return result, true
        end

        -- 先尝试归约 func 侧
        if node.func then
            local newFunc, reduced = Evaluator.step(node.func)
            if reduced then
                return AST.App(newFunc, node.arg), true
            end
        end

        -- func 无法归约，尝试 arg 侧
        if node.arg then
            local newArg, reduced = Evaluator.step(node.arg)
            if reduced then
                return AST.App(node.func, newArg), true
            end
        end

        return node, false

    elseif node.kind == "abstraction" then
        -- 归约函数体
        if node.body then
            local newBody, reduced = Evaluator.step(node.body)
            if reduced then
                return AST.Abs(node.param, newBody), true
            end
        end
        return node, false

    else -- variable
        return node, false
    end
end

-- ============================================================================
-- 完整归约到正常形式 (Normal Form)
-- ============================================================================

--- 归约到正常形式
---@param node table AST
---@param maxSteps number|nil 最大步数（默认 500）
---@return table|nil, string|nil  (结果AST, 错误信息)
function Evaluator.reduceToNF(node, maxSteps)
    maxSteps = maxSteps or 500
    local current = AST.deepClone(node)

    local function loop()
        local result, reduced = Evaluator.step(current)
        if reduced then
            current = result
            return thunk(loop)
        end
        return current
    end

    return Evaluator.trampoline(thunk(loop), maxSteps)
end

-- ============================================================================
-- 单步模式（用于动画演示）
-- ============================================================================

--- 单步归约，返回新 AST 和是否有变化
function Evaluator.stepOnce(node)
    local cloned = AST.deepClone(node)
    return Evaluator.step(cloned)
end

-- ============================================================================
-- 归约轨迹（收集每步中间状态用于动画回放）
-- ============================================================================

--- 收集完整归约路径
---@param node table AST
---@param maxSteps number|nil
---@return table[] 每步的 AST 快照数组
function Evaluator.trace(node, maxSteps)
    maxSteps = maxSteps or 100
    local history = { AST.deepClone(node) }
    local current = AST.deepClone(node)
    local steps = 0

    while steps < maxSteps do
        local next, reduced = Evaluator.step(current)
        if not reduced then break end
        current = next
        steps = steps + 1
        table.insert(history, AST.deepClone(current))
    end

    return history
end

-- ============================================================================
-- 辅助：判断是否为正常形式
-- ============================================================================

function Evaluator.isNormalForm(node)
    if node == nil then return true end
    local _, reduced = Evaluator.step(AST.deepClone(node))
    return not reduced
end

return Evaluator
