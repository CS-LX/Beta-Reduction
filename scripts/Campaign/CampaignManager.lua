-- ============================================================================
-- Campaign/CampaignManager.lua - 闯关模式管理器
-- ============================================================================
-- 负责:
--   1. 进度管理 (已通关关卡、当前关卡)
--   2. 预制积木管理 (通关奖励 → 后续关卡可用)
--   3. 存档 (本地保存/加载)
--   4. 当前关卡状态 (可用积木列表、教程步骤等)
-- ============================================================================

local LevelData = require("Campaign.LevelData")
local Verifier = require("Campaign.Verifier")
local AST = require("Lambda.AST")
local FeatureGate = require("Campaign.FeatureGate")

local CampaignManager = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local state = {
    -- 已完成的关卡 id 列表 (有序)
    completedLevels = {},
    -- 解锁的预制积木 id → expr 字符串
    unlockedPrefabs = {},
    -- 当前正在玩的关卡 id (nil = 在关卡选择界面)
    currentLevelId = nil,
    -- 最高已解锁关卡索引 (1-based, 初始 = 1, 即第一关可玩)
    highestUnlocked = 1,
}

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化闯关管理器 (尝试加载存档)
function CampaignManager.init()
    CampaignManager.load()
    print("[CampaignManager] 初始化完成, 已通关 " .. #state.completedLevels .. " 关")
end

-- ============================================================================
-- 进度查询
-- ============================================================================

--- 获取关卡状态
---@param levelId string
---@return string  "locked" | "unlocked" | "completed"
function CampaignManager.getLevelStatus(levelId)
    -- 已完成
    for _, id in ipairs(state.completedLevels) do
        if id == levelId then return "completed" end
    end
    -- 检查是否已解锁
    local idx = LevelData.getLevelIndex(levelId)
    if idx and idx <= state.highestUnlocked then
        return "unlocked"
    end
    return "locked"
end

--- 获取所有已完成关卡列表
---@return string[]
function CampaignManager.getCompletedLevels()
    return state.completedLevels
end

--- 获取当前可玩的最高关卡索引
---@return number
function CampaignManager.getHighestUnlocked()
    return state.highestUnlocked
end

--- 获取完成进度 (已完成数 / 总数)
---@return number, number
function CampaignManager.getProgress()
    return #state.completedLevels, LevelData.getTotalLevels()
end

-- ============================================================================
-- 关卡操作
-- ============================================================================

--- 进入指定关卡
---@param levelId string
---@return boolean, string  成功/失败, 错误信息
function CampaignManager.enterLevel(levelId)
    local status = CampaignManager.getLevelStatus(levelId)
    if status == "locked" then
        return false, "该关卡尚未解锁"
    end

    local level = LevelData.getLevelById(levelId)
    if not level then
        return false, "关卡不存在: " .. tostring(levelId)
    end

    state.currentLevelId = levelId
    print("[CampaignManager] 进入关卡: " .. level.title .. " (" .. levelId .. ")")
    return true, ""
end

--- 退出当前关卡 (回到关卡选择)
function CampaignManager.exitLevel()
    state.currentLevelId = nil
end

--- 获取当前关卡数据
---@return table|nil
function CampaignManager.getCurrentLevel()
    if not state.currentLevelId then return nil end
    return LevelData.getLevelById(state.currentLevelId)
end

--- 获取当前关卡 ID
---@return string|nil
function CampaignManager.getCurrentLevelId()
    return state.currentLevelId
end

-- ============================================================================
-- 验证与通关
-- ============================================================================

--- 提交玩家的解答并验证
---@param playerAST table  玩家构建的 AST
---@return boolean success 是否通过
---@return string msg 反馈信息
---@return table|nil newUnlock 新解锁的功能 { featureId, message }
function CampaignManager.submitAnswer(playerAST)
    local level = CampaignManager.getCurrentLevel()
    if not level then
        return false, "当前不在关卡中", nil
    end

    -- 调用验证器
    local pass, msg = Verifier.verify(playerAST, level)

    if pass then
        local newUnlock = CampaignManager._markCompleted(level)
        return true, msg, newUnlock
    end

    return false, msg, nil
end

--- 标记关卡完成, 解锁奖励
---@return table|nil  新解锁的功能信息 { featureId, message }
function CampaignManager._markCompleted(level)
    -- 避免重复记录
    for _, id in ipairs(state.completedLevels) do
        if id == level.id then
            print("[CampaignManager] 关卡已经完成过: " .. level.id)
            return nil
        end
    end

    -- 记录完成
    table.insert(state.completedLevels, level.id)
    print("[CampaignManager] 通关: " .. level.title)

    -- 解锁奖励预制积木
    if level.reward then
        state.unlockedPrefabs[level.reward.id] = level.reward.expr
        print("[CampaignManager] 解锁预制积木: " .. level.reward.name)
    end

    -- 检测新功能解锁（知识锁）
    local newUnlockId = FeatureGate.checkNewUnlock(level.id)
    local newUnlock = nil
    if newUnlockId then
        newUnlock = {
            featureId = newUnlockId,
            message = FeatureGate.getUnlockMessage(newUnlockId),
        }
        print("[CampaignManager] 新功能解锁: " .. newUnlockId)
    end

    -- 更新最高解锁
    local idx = LevelData.getLevelIndex(level.id)
    if idx then
        local nextIdx = idx + 1
        if nextIdx > state.highestUnlocked then
            state.highestUnlocked = nextIdx
        end
    end

    -- 自动保存
    CampaignManager.save()

    return newUnlock
end

-- ============================================================================
-- 预制积木管理
-- ============================================================================

--- 获取所有已解锁的预制积木
---@return table[]  { id, name, expr, description, ast }
function CampaignManager.getUnlockedPrefabs()
    local result = {}
    for _, level in ipairs(LevelData.levels) do
        if level.reward and state.unlockedPrefabs[level.reward.id] then
            table.insert(result, {
                id = level.reward.id,
                name = level.reward.name,
                expr = level.reward.expr,
                description = level.reward.description,
            })
        end
    end
    return result
end

--- 获取指定关卡可用的预制积木列表
---@param levelId string|nil  为nil则返回全部已解锁
---@return table[]
function CampaignManager.getAvailablePrefabs(levelId)
    if not levelId then
        return CampaignManager.getUnlockedPrefabs()
    end

    local level = LevelData.getLevelById(levelId)
    if not level or not level.availablePrefabs then
        return {}
    end

    -- 只返回关卡指定的且已解锁的预制
    local result = {}
    for _, prefabId in ipairs(level.availablePrefabs) do
        if state.unlockedPrefabs[prefabId] then
            -- 从 LevelData 中找到对应 reward 信息
            for _, lv in ipairs(LevelData.levels) do
                if lv.reward and lv.reward.id == prefabId then
                    table.insert(result, {
                        id = lv.reward.id,
                        name = lv.reward.name,
                        expr = lv.reward.expr,
                        description = lv.reward.description,
                    })
                    break
                end
            end
        end
    end
    return result
end

--- 获取指定关卡可用的基础积木类型
---@param levelId string|nil
---@return table|nil  nil = 全部可用
function CampaignManager.getAvailableBlocks(levelId)
    if not levelId then return nil end
    local level = LevelData.getLevelById(levelId)
    if not level then return nil end
    return level.availableBlocks -- nil = all available
end

--- 将预制积木 expr 解析为 AST
---@param prefabId string
---@return table|nil
function CampaignManager.getPrefabAST(prefabId)
    local expr = state.unlockedPrefabs[prefabId]
    if not expr then return nil end
    return Verifier.Parser.parse(expr)
end

-- ============================================================================
-- 存档 (使用 cjson + File API)
-- ============================================================================

local SAVE_FILE = "campaign_save.json"

--- 保存进度到本地
function CampaignManager.save()
    local saveData = {
        completedLevels = state.completedLevels,
        unlockedPrefabs = state.unlockedPrefabs,
        highestUnlocked = state.highestUnlocked,
        version = 1,
    }

    local ok, jsonStr = pcall(cjson.encode, saveData)
    if not ok then
        print("[CampaignManager] 序列化存档失败: " .. tostring(jsonStr))
        return false
    end

    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        print("[CampaignManager] 存档已保存")
        return true
    else
        print("[CampaignManager] 无法打开存档文件写入")
        return false
    end
end

--- 加载本地存档
function CampaignManager.load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[CampaignManager] 无存档，使用初始状态")
        return false
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then
        print("[CampaignManager] 无法打开存档文件")
        return false
    end

    local content = file:ReadString()
    file:Close()

    if not content or #content == 0 then
        print("[CampaignManager] 存档为空")
        return false
    end

    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        print("[CampaignManager] 存档解析失败: " .. tostring(data))
        return false
    end

    -- 恢复状态
    state.completedLevels = data.completedLevels or {}
    state.unlockedPrefabs = data.unlockedPrefabs or {}
    state.highestUnlocked = data.highestUnlocked or 1

    print("[CampaignManager] 存档加载成功")
    return true
end

--- 重置全部进度
function CampaignManager.resetProgress()
    state.completedLevels = {}
    state.unlockedPrefabs = {}
    state.highestUnlocked = 1
    state.currentLevelId = nil
    CampaignManager.save()
    print("[CampaignManager] 进度已重置")
end

-- ============================================================================
-- 教程/提示
-- ============================================================================

--- 获取当前关卡的教程步骤列表
---@return string[]|nil
function CampaignManager.getTutorial()
    local level = CampaignManager.getCurrentLevel()
    if not level then return nil end
    return level.tutorial
end

--- 获取当前关卡的提示
---@return string|nil
function CampaignManager.getHint()
    local level = CampaignManager.getCurrentLevel()
    if not level then return nil end
    return level.hint
end

--- 获取当前关卡的故事文本
---@return string|nil
function CampaignManager.getStory()
    local level = CampaignManager.getCurrentLevel()
    if not level then return nil end
    return level.story
end

-- ============================================================================
-- 章节信息
-- ============================================================================

--- 获取章节列表及其进度
---@return table[]  { id, title, subtitle, icon, total, completed, unlocked }
function CampaignManager.getChaptersWithProgress()
    local result = {}
    for _, ch in ipairs(LevelData.chapters) do
        local levels = LevelData.getChapterLevels(ch.id)
        local completedCount = 0
        local hasUnlocked = false
        for _, lv in ipairs(levels) do
            local status = CampaignManager.getLevelStatus(lv.id)
            if status == "completed" then
                completedCount = completedCount + 1
            end
            if status ~= "locked" then
                hasUnlocked = true
            end
        end
        table.insert(result, {
            id = ch.id,
            title = ch.title,
            subtitle = ch.subtitle,
            icon = ch.icon,
            total = #levels,
            completed = completedCount,
            unlocked = hasUnlocked,
        })
    end
    return result
end

return CampaignManager
