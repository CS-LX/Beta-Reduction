-- ============================================================================
-- Lambda/AST.lua - Lambda 演算抽象语法树
-- ============================================================================
-- 三种基础节点: Variable / Abstraction / Application
-- 提供: 深拷贝、自由变量收集、替换（含 α-重命名避免捕获）

local AST = {}

-- UID 生成器
local uidCounter = 0
local function uid()
    uidCounter = uidCounter + 1
    return "ast_" .. uidCounter
end

-- Fresh name 生成（α-重命名用）
local freshCounter = 0
local function freshName(base)
    freshCounter = freshCounter + 1
    return base .. "'" .. freshCounter
end

-- ============================================================================
-- 构造器
-- ============================================================================

--- 创建变量节点
---@param name string
---@return table
function AST.Var(name)
    return { kind = "variable", id = uid(), name = name }
end

--- 创建抽象节点 (λparam.body)
---@param param string
---@param body table|nil
---@return table
function AST.Abs(param, body)
    return { kind = "abstraction", id = uid(), param = param, body = body }
end

--- 创建应用节点 (func arg)
---@param func table|nil
---@param arg table|nil
---@return table
function AST.App(func, arg)
    return { kind = "application", id = uid(), func = func, arg = arg }
end

-- ============================================================================
-- 深拷贝
-- ============================================================================

function AST.deepClone(node)
    if node == nil then return nil end
    if node.kind == "variable" then
        return { kind = "variable", id = uid(), name = node.name }
    elseif node.kind == "abstraction" then
        return { kind = "abstraction", id = uid(), param = node.param, body = AST.deepClone(node.body) }
    elseif node.kind == "application" then
        return { kind = "application", id = uid(), func = AST.deepClone(node.func), arg = AST.deepClone(node.arg) }
    end
    return nil
end

-- ============================================================================
-- 自由变量收集
-- ============================================================================

--- 收集 AST 中所有自由变量名
---@param node table
---@param bound table<string, boolean>|nil
---@return table<string, boolean>
function AST.freeVars(node, bound)
    bound = bound or {}
    if node == nil then return {} end

    if node.kind == "variable" then
        if not bound[node.name] then
            return { [node.name] = true }
        end
        return {}

    elseif node.kind == "abstraction" then
        local innerBound = {}
        for k, v in pairs(bound) do innerBound[k] = v end
        innerBound[node.param] = true
        return AST.freeVars(node.body, innerBound)

    elseif node.kind == "application" then
        local left = AST.freeVars(node.func, bound)
        local right = AST.freeVars(node.arg, bound)
        -- union
        for k, v in pairs(right) do left[k] = v end
        return left
    end

    return {}
end

-- ============================================================================
-- 替换 [N/x]M - 在 M 中将自由出现的 x 替换为 N
-- ============================================================================

function AST.substitute(M, x, N)
    if M == nil then return nil end

    if M.kind == "variable" then
        if M.name == x then
            return AST.deepClone(N)
        end
        return AST.deepClone(M)

    elseif M.kind == "abstraction" then
        if M.param == x then
            -- x 被遮蔽，不再向内替换
            return AST.deepClone(M)
        end
        -- 检测变量捕获
        local fvN = AST.freeVars(N, {})
        if fvN[M.param] then
            -- α-重命名
            local fresh = freshName(M.param)
            local renamedBody = AST.substitute(M.body, M.param, AST.Var(fresh))
            return AST.Abs(fresh, AST.substitute(renamedBody, x, N))
        end
        return AST.Abs(M.param, AST.substitute(M.body, x, N))

    elseif M.kind == "application" then
        return AST.App(
            AST.substitute(M.func, x, N),
            AST.substitute(M.arg, x, N)
        )
    end

    return nil
end

-- ============================================================================
-- AST 转字符串 (用于显示)
-- ============================================================================

function AST.toString(node)
    if node == nil then return "?" end

    if node.kind == "variable" then
        return node.name

    elseif node.kind == "abstraction" then
        return "λ" .. node.param .. "." .. AST.toString(node.body)

    elseif node.kind == "application" then
        local funcStr = AST.toString(node.func)
        local argStr = AST.toString(node.arg)
        -- 如果 func 是 abstraction 需要加括号
        if node.func and node.func.kind == "abstraction" then
            funcStr = "(" .. funcStr .. ")"
        end
        -- 如果 arg 是 application 需要加括号
        if node.arg and (node.arg.kind == "application" or node.arg.kind == "abstraction") then
            argStr = "(" .. argStr .. ")"
        end
        return funcStr .. " " .. argStr
    end

    return "?"
end

-- ============================================================================
-- 展开柯里化 λx.λy.λz.body → params[], innerBody
-- ============================================================================

function AST.unrollCurried(node)
    local params = {}
    local current = node
    while current and current.kind == "abstraction" do
        table.insert(params, current.param)
        current = current.body
    end
    return params, current
end

-- ============================================================================
-- Church 编码常用组合子（预制积木）
-- ============================================================================

AST.Presets = {}

-- I = λx.x (恒等)
function AST.Presets.I()
    return AST.Abs("x", AST.Var("x"))
end

-- K = λx.λy.x (常量)
function AST.Presets.K()
    return AST.Abs("x", AST.Abs("y", AST.Var("x")))
end

-- S = λx.λy.λz.((x z)(y z))
function AST.Presets.S()
    return AST.Abs("x", AST.Abs("y", AST.Abs("z",
        AST.App(
            AST.App(AST.Var("x"), AST.Var("z")),
            AST.App(AST.Var("y"), AST.Var("z"))
        )
    )))
end

-- TRUE = λt.λf.t
function AST.Presets.TRUE()
    return AST.Abs("t", AST.Abs("f", AST.Var("t")))
end

-- FALSE = λt.λf.f
function AST.Presets.FALSE()
    return AST.Abs("t", AST.Abs("f", AST.Var("f")))
end

-- ZERO = λf.λx.x
function AST.Presets.ZERO()
    return AST.Abs("f", AST.Abs("x", AST.Var("x")))
end

-- SUCC = λn.λf.λx.f (n f x)
function AST.Presets.SUCC()
    return AST.Abs("n", AST.Abs("f", AST.Abs("x",
        AST.App(AST.Var("f"), AST.App(AST.App(AST.Var("n"), AST.Var("f")), AST.Var("x")))
    )))
end

-- Church numeral n
function AST.Presets.Num(n)
    -- λf.λx. f(f(...(f x)...))
    local body = AST.Var("x")
    for _ = 1, n do
        body = AST.App(AST.Var("f"), body)
    end
    return AST.Abs("f", AST.Abs("x", body))
end

return AST
