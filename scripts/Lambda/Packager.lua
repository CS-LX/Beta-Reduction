-- ============================================================================
-- Lambda/Packager.lua - 积木 AST → 节点图端口封装
-- ============================================================================
-- 将一棵完整的积木 AST 打包为一个带 Input/Output Port 的节点

local AST = require("Lambda.AST")

local Packager = {}

-- ============================================================================
-- 核心封装函数
-- ============================================================================

--- 将 AST 封装为节点定义（含输入/输出端口）
---@param ast table       完整的 AST 树
---@param nodeName string 节点名称
---@return table          { name, inputs[], outputs[], ast }
function Packager.package(ast, nodeName)
    if ast == nil then
        return {
            name = nodeName or "Empty",
            inputs = {},
            outputs = { { name = "result", direction = "output" } },
            ast = nil,
        }
    end

    -- 展开柯里化参数
    local params, innerBody = AST.unrollCurried(ast)

    local inputs = {}

    -- 柯里化参数 → 输入端口
    for _, p in ipairs(params) do
        table.insert(inputs, {
            name = p,
            direction = "input",
            origin = "bound_param",
        })
    end

    -- 内核中的自由变量 → 额外输入端口
    if innerBody then
        local boundSet = {}
        for _, p in ipairs(params) do boundSet[p] = true end
        local freeInBody = AST.freeVars(innerBody, boundSet)
        -- 排序保证稳定
        local sorted = {}
        for name in pairs(freeInBody) do
            table.insert(sorted, name)
        end
        table.sort(sorted)
        for _, varName in ipairs(sorted) do
            table.insert(inputs, {
                name = varName,
                direction = "input",
                origin = "free_var",
            })
        end
    end

    local outputs = {
        { name = "result", direction = "output" }
    }

    return {
        name = nodeName or "Lambda",
        inputs = inputs,
        outputs = outputs,
        ast = AST.deepClone(ast),
        displayExpr = AST.toString(ast),
    }
end

--- 对封装节点执行求值（给定输入值后归约）
---@param nodeDef table   Packager.package() 的返回值
---@param inputValues table<string, table>  portName → AST 值
---@return table|nil 归约结果 AST
function Packager.evaluate(nodeDef, inputValues)
    local Evaluator = require("Lambda.Evaluator")

    if nodeDef.ast == nil then return nil end
    local ast = AST.deepClone(nodeDef.ast)

    -- 将输入值替换进 AST
    for _, port in ipairs(nodeDef.inputs) do
        local value = inputValues[port.name]
        if value then
            if port.origin == "bound_param" then
                -- 柯里化参数: 剥开最外层 λ 执行替换
                if ast.kind == "abstraction" and ast.param == port.name then
                    ast = AST.substitute(ast.body, port.name, value)
                end
            else
                -- 自由变量: 直接替换
                ast = AST.substitute(ast, port.name, value)
            end
        end
    end

    -- 归约到正常形式
    local result, err = Evaluator.reduceToNF(ast, 200)
    return result
end

return Packager
