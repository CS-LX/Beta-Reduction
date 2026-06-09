-- ============================================================================
-- Campaign/FeatureGate.lua - 功能解锁门控（知识锁系统）
-- ============================================================================
-- 纯数据查询模块，零外部依赖。
-- 根据玩家当前进度判断哪些功能已解锁。
--
-- 设计理念：
--   玩家从最原始的积木拼装开始，逐步解锁高层抽象工具。
--   每种工具的解锁绑定到特定关卡完成，形成"知识锁"。
--
-- 解锁层级：
--   Lv0 基础积木 (var/abs/app)     — 始终可用
--   Lv1 积木组 (预制组合子折叠)    — 通过 1-5 后解锁
--   Lv2 节点图 (函数组合视图)      — 通过 2-4 后解锁
-- ============================================================================

local FeatureGate = {}

-- ============================================================================
-- 功能定义
-- ============================================================================

--- 功能 ID → 解锁条件（需完成的关卡 ID）
FeatureGate.UNLOCK_MAP = {
    block_group = "1-5",   -- 积木组：通过第1章最后一关解锁
    node_graph  = "2-4",   -- 节点图：通过第2章 NOT 关解锁
}

--- 功能 ID → 显示名称
FeatureGate.FEATURE_NAMES = {
    block_group = "积木组",
    node_graph  = "节点图",
}

--- 功能 ID → 解锁提示文案
FeatureGate.UNLOCK_MESSAGES = {
    block_group = "恭喜！你已经掌握了基础组合子。\n"
               .. "从现在起，预制积木会折叠成紧凑的「积木组」，\n"
               .. "双击可以展开查看内部结构。",
    node_graph  = "你已经可以像搭积木一样构建复杂逻辑了。\n"
              .. "现在解锁「节点图」视图——\n"
              .. "把每个组合子当作一个节点，用连线表达数据流。\n"
              .. "这是更高层的抽象方式！",
}

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 检查某功能是否已解锁
--- @param featureId string "block_group" | "node_graph"
--- @param completedLevels table 已完成关卡 ID 列表（有序数组或 set 均可）
--- @return boolean
function FeatureGate.isUnlocked(featureId, completedLevels)
    local requiredLevel = FeatureGate.UNLOCK_MAP[featureId]
    if not requiredLevel then return true end  -- 未定义的功能默认解锁
    -- 支持数组或 set 两种格式
    if #completedLevels > 0 then
        for _, id in ipairs(completedLevels) do
            if id == requiredLevel then return true end
        end
        return false
    else
        return completedLevels[requiredLevel] == true
    end
end

--- 获取当前解锁的所有功能列表
--- @param completedLevels table
--- @return table 已解锁的 featureId 数组
function FeatureGate.getUnlockedFeatures(completedLevels)
    local result = {}
    for featureId, _ in pairs(FeatureGate.UNLOCK_MAP) do
        if FeatureGate.isUnlocked(featureId, completedLevels) then
            result[#result + 1] = featureId
        end
    end
    return result
end

--- 检查某关卡完成后是否触发了新功能解锁
--- @param levelId string 刚完成的关卡 ID
--- @return string|nil featureId 如果触发了解锁则返回功能ID，否则nil
function FeatureGate.checkNewUnlock(levelId)
    for featureId, requiredLevel in pairs(FeatureGate.UNLOCK_MAP) do
        if requiredLevel == levelId then
            return featureId
        end
    end
    return nil
end

--- 获取解锁提示消息
--- @param featureId string
--- @return string
function FeatureGate.getUnlockMessage(featureId)
    return FeatureGate.UNLOCK_MESSAGES[featureId] or ""
end

--- 判断当前关卡是否允许使用积木组（collapsed preset）
--- @param completedLevels table
--- @return boolean
function FeatureGate.canUseBlockGroup(completedLevels)
    return FeatureGate.isUnlocked("block_group", completedLevels)
end

--- 判断当前关卡是否允许使用节点图视图
--- @param completedLevels table
--- @return boolean
function FeatureGate.canUseNodeGraph(completedLevels)
    return FeatureGate.isUnlocked("node_graph", completedLevels)
end

return FeatureGate
