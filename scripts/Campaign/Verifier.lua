-- ============================================================================
-- Campaign/Verifier.lua - 关卡验证系统
-- ============================================================================
-- 验证玩家构建的 Lambda 表达式是否满足关卡要求。
-- 两种验证模式:
--   behavioral: 给定输入，检查输出是否与期望匹配
--   structural: 直接比较 AST 结构 (alpha 等价)
-- ============================================================================

local AST = require("Lambda.AST")
local Evaluator = require("Lambda.Evaluator")

local Verifier = {}

-- ============================================================================
-- 简易 Lambda 表达式解析器 (用于解析 testCase 字符串)
-- ============================================================================

local Parser = {}

--- 解析 Lambda 表达式字符串为 AST
---@param str string  如 "λx.x" 或 "a" 或 "(f x)"
---@return table|nil
function Parser.parse(str)
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if #str == 0 then return nil end

    local pos = 1

    local function peek()
        while pos <= #str and str:sub(pos, pos) == " " do pos = pos + 1 end
        if pos > #str then return nil end
        return str:sub(pos, pos)
    end

    local function advance()
        pos = pos + 1
    end

    local function parseAtom()
        local c = peek()
        if c == nil then return nil end

        -- 括号
        if c == "(" then
            advance() -- skip (
            local expr = parseExpr()
            peek()
            if pos <= #str and str:sub(pos, pos) == ")" then
                advance() -- skip )
            end
            return expr
        end

        -- Lambda: λ 或 \
        local lambdaStart = str:find("^[λ\\]", pos)
        if lambdaStart == pos then
            -- 跳过 λ 字符 (UTF-8 多字节)
            if str:sub(pos, pos) == "\\" then
                pos = pos + 1
            else
                -- λ 在 UTF-8 中是 2 字节 (0xCE 0xBB)
                pos = pos + 2
            end
            -- 读取参数名
            peek()
            local paramStart = pos
            while pos <= #str and str:sub(pos, pos):match("[%w_']") do
                pos = pos + 1
            end
            local param = str:sub(paramStart, pos - 1)
            -- 跳过 .
            peek()
            if pos <= #str and str:sub(pos, pos) == "." then
                advance()
            end
            -- 解析 body
            local body = parseExpr()
            return AST.Abs(param, body)
        end

        -- 变量: 连续字母/数字/下划线
        if c:match("[%w_']") then
            local start = pos
            while pos <= #str and str:sub(pos, pos):match("[%w_']") do
                pos = pos + 1
            end
            return AST.Var(str:sub(start, pos - 1))
        end

        return nil
    end

    function parseExpr()
        local atoms = {}
        while true do
            local c = peek()
            if c == nil or c == ")" then break end
            local atom = parseAtom()
            if atom == nil then break end
            table.insert(atoms, atom)
        end

        if #atoms == 0 then return nil end
        if #atoms == 1 then return atoms[1] end

        -- 左结合应用
        local result = atoms[1]
        for i = 2, #atoms do
            result = AST.App(result, atoms[i])
        end
        return result
    end

    return parseExpr()
end

Verifier.Parser = Parser

-- ============================================================================
-- Alpha 等价检查
-- ============================================================================

--- 检查两个 AST 是否 alpha 等价
---@param a table|nil
---@param b table|nil
---@return boolean
function Verifier.alphaEquiv(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end

    -- 使用 de Bruijn index 标准化后比较
    local normA = Verifier._normalize(a, {})
    local normB = Verifier._normalize(b, {})
    return Verifier._structEqual(normA, normB)
end

-- 标准化: 把绑定变量替换为 de Bruijn index 表示
function Verifier._normalize(node, env)
    if node == nil then return nil end

    if node.kind == "variable" then
        -- 检查是否是绑定变量
        for i = #env, 1, -1 do
            if env[i] == node.name then
                return { kind = "bound", index = #env - i }
            end
        end
        -- 自由变量保持原名
        return { kind = "free", name = node.name }

    elseif node.kind == "abstraction" then
        local newEnv = {}
        for _, v in ipairs(env) do table.insert(newEnv, v) end
        table.insert(newEnv, node.param)
        return {
            kind = "abstraction",
            body = Verifier._normalize(node.body, newEnv),
        }

    elseif node.kind == "application" then
        return {
            kind = "application",
            func = Verifier._normalize(node.func, env),
            arg = Verifier._normalize(node.arg, env),
        }
    end
    return nil
end

-- 结构相等
function Verifier._structEqual(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    if a.kind ~= b.kind then return false end

    if a.kind == "bound" then
        return a.index == b.index
    elseif a.kind == "free" then
        return a.name == b.name
    elseif a.kind == "abstraction" then
        return Verifier._structEqual(a.body, b.body)
    elseif a.kind == "application" then
        return Verifier._structEqual(a.func, b.func)
           and Verifier._structEqual(a.arg, b.arg)
    end
    return false
end

-- ============================================================================
-- 行为验证
-- ============================================================================

--- 对玩家构建的表达式运行测试用例
---@param playerAST table     玩家构建的 AST
---@param testCases table[]   测试用例列表 { input, expect }
---@return boolean pass 是否通过
---@return string msg 错误信息
function Verifier.verifyBehavioral(playerAST, testCases)
    if playerAST == nil then
        return false, "还没有构建表达式"
    end

    for i, tc in ipairs(testCases) do
        local pass, err = Verifier._runTestCase(playerAST, tc)
        if not pass then
            return false, "测试 " .. i .. " 失败: " .. (err or "未知错误")
        end
    end

    return true, "全部测试通过！"
end

--- 运行单个测试用例
function Verifier._runTestCase(playerAST, tc)
    -- 构建完整的应用表达式: playerAST input1 input2 ...
    local inputTokens = Verifier._splitInputs(tc.input)
    local expr = AST.deepClone(playerAST)

    for _, inputStr in ipairs(inputTokens) do
        local inputAST = Parser.parse(inputStr)
        if inputAST == nil then
            return false, "无法解析输入: " .. inputStr
        end
        expr = AST.App(expr, inputAST)
    end

    -- 归约
    local result, evalErr = Evaluator.reduceToNF(expr, 500)
    if result == nil then
        return false, "归约失败: " .. (evalErr or "超时")
    end

    -- 解析期望结果
    local expectAST = Parser.parse(tc.expect)
    if expectAST == nil then
        return false, "无法解析期望结果: " .. tc.expect
    end

    -- alpha 等价比较
    if Verifier.alphaEquiv(result, expectAST) then
        return true, nil
    end

    -- 如果直接比较不通过，尝试归约期望表达式后再比较
    local expectReduced = Evaluator.reduceToNF(expectAST, 200)
    if expectReduced and Verifier.alphaEquiv(result, expectReduced) then
        return true, nil
    end

    local resultStr = AST.toString(result)
    return false, "期望 " .. tc.expect .. " 但得到 " .. resultStr
end

--- 将 input 字符串分割为多个参数
--- "a b" → {"a", "b"}
--- "(λx.x) foo" → {"(λx.x)", "foo"}
function Verifier._splitInputs(input)
    local tokens = {}
    local pos = 1
    local len = #input

    while pos <= len do
        -- 跳过空格
        while pos <= len and input:sub(pos, pos) == " " do
            pos = pos + 1
        end
        if pos > len then break end

        if input:sub(pos, pos) == "(" then
            -- 括号表达式: 找到匹配的右括号
            local depth = 0
            local start = pos
            while pos <= len do
                local c = input:sub(pos, pos)
                if c == "(" then depth = depth + 1
                elseif c == ")" then
                    depth = depth - 1
                    if depth == 0 then pos = pos + 1; break end
                end
                pos = pos + 1
            end
            table.insert(tokens, input:sub(start, pos - 1))
        else
            -- 普通 token
            local start = pos
            while pos <= len and input:sub(pos, pos) ~= " " and input:sub(pos, pos) ~= "(" do
                pos = pos + 1
            end
            table.insert(tokens, input:sub(start, pos - 1))
        end
    end

    return tokens
end

-- ============================================================================
-- Church 数验证
-- ============================================================================

--- 检查 AST 是否是指定的 Church 数
---@param ast table
---@param n number 期望的数字
---@return boolean
function Verifier.isChurchNumeral(ast, n)
    local target = AST.Presets.Num(n)
    return Verifier.alphaEquiv(ast, target)
end

-- ============================================================================
-- 主验证入口
-- ============================================================================

--- 验证玩家的解答
---@param playerAST table       玩家构建的 AST
---@param level table           关卡数据
---@return boolean pass
---@return string msg
function Verifier.verify(playerAST, level)
    if playerAST == nil then
        return false, "还没有构建表达式"
    end

    -- Church 数专门验证
    if level.verifyChurch ~= nil then
        if Verifier.isChurchNumeral(playerAST, level.verifyChurch) then
            return true, "正确！这是 Church 数 " .. level.verifyChurch
        end
    end

    -- 行为验证
    if level.verifyMode == "behavioral" and level.testCases then
        return Verifier.verifyBehavioral(playerAST, level.testCases)
    end

    -- 结构验证 (fallback)
    if level.reward and level.reward.expr then
        local targetAST = Parser.parse(level.reward.expr)
        if targetAST and Verifier.alphaEquiv(playerAST, targetAST) then
            return true, "结构完全匹配！"
        end
    end

    return false, "表达式不正确，再试试？"
end

return Verifier
