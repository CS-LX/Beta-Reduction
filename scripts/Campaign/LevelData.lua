-- ============================================================================
-- Campaign/LevelData.lua - 闯关模式关卡定义
-- ============================================================================
-- 策划思路 (仿"图灵完备"):
--   从 3 个基础积木 (变量/抽象/应用) 出发，逐步构建直到四则运算器。
--   每关通过后，构建的表达式变成"预制积木"，后续关卡可直接使用。
--
-- 5章 14关:
--   第1章 认识 Lambda   (身份函数、选择器)
--   第2章 布尔逻辑      (TRUE/FALSE、NOT、AND/OR)
--   第3章 数字之源      (Church数、后继SUCC)
--   第4章 算术运算      (加法ADD、乘法MUL)
--   第5章 BOSS: 完整运算器 (前驱PRED、减法SUB、组合)
-- ============================================================================

local LevelData = {}

-- ============================================================================
-- 关卡定义列表
-- ============================================================================

LevelData.levels = {

    -- ========================================================================
    -- 第1章: 认识 Lambda
    -- ========================================================================

    {
        id = "1-1",
        chapter = 1,
        title = "回声镜",
        subtitle = "身份函数 I",
        description = "构建一个「回声镜」—— 无论给它什么，它都原样返回。",
        story = "在 Lambda 世界的入口，你发现了一面古老的镜子。\n"
              .. "传说中，这面镜子能映照万物的本来面目。\n\n"
              .. "你的任务：让镜子接收一个东西，然后原样返回它。",
        tutorial = {
            "这是你的第一个挑战！",
            "你有三种基础积木：",
            "  • 变量 (青色) —— 代表一个名字/占位符",
            "  • 抽象 λx.M (紫色) —— 创建函数：接收 x，返回 M",
            "  • 应用 (F A) (绿色) —— 将函数 F 应用到参数 A",
            "",
            "目标：构建 λx.x",
            "  1. 放一个「抽象」积木 (参数为 x)",
            "  2. 在它的 body 槽里放一个变量 x",
            "  3. 这就是身份函数：接收 x，返回 x",
        },
        hint = "把一个变量 x 放进 λx 的 body 槽中",
        -- 可用积木 (nil = 全部可用)
        availableBlocks = { "var", "abs" },
        -- 验证: 表达式形态
        -- "structural" = 结构匹配 (alpha等价)
        -- "behavioral" = 行为测试 (输入→输出)
        verifyMode = "behavioral",
        testCases = {
            { input = "a", expect = "a" },
            { input = "b", expect = "b" },
            { input = "(λy.y)", expect = "(λy.y)" },
        },
        -- 通关奖励: 解锁的预制积木
        reward = {
            id = "I",
            name = "I (身份)",
            expr = "λx.x",
            description = "身份函数：原样返回输入",
        },
    },

    {
        id = "1-2",
        chapter = 1,
        title = "偏心天平",
        subtitle = "第一选择器 K",
        description = "构建一个「偏心天平」—— 给它两样东西，它总是选第一个。",
        story = "在镜子旁边，你看到一架天平。\n"
              .. "这架天平有个奇怪的特性：它永远偏向左边。\n\n"
              .. "你的任务：创建一个函数，接收两个参数，返回第一个。",
        tutorial = {
            "现在你需要构建一个双参数函数。",
            "Lambda 演算中，多参数通过「嵌套」实现：",
            "  λx.λy.x  意思是：",
            "    先接收 x，再接收 y，返回 x (忽略 y)",
            "",
            "这就是「柯里化」—— 每层只接一个参数。",
            "",
            "目标：构建 λx.λy.x",
            "  1. 放一个 λx 抽象",
            "  2. 在 body 里再放一个 λy 抽象",
            "  3. 在最内层 body 放变量 x",
        },
        hint = "嵌套两层 λ：外层参数 x，内层参数 y，body 返回 x",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "a b", expect = "a" },
            { input = "hello world", expect = "hello" },
            { input = "(λx.x) foo", expect = "(λx.x)" },
        },
        reward = {
            id = "K",
            name = "K (第一)",
            expr = "λx.λy.x",
            description = "总是返回第一个参数",
        },
    },

    {
        id = "1-3",
        chapter = 1,
        title = "影子收藏家",
        subtitle = "第二选择器 KI",
        description = "构建一个「影子收藏家」—— 给它两样东西，它只要第二个。",
        story = "天平的对面有一位收藏家。\n"
              .. "他对第一个礼物毫无兴趣，只保留第二个。\n\n"
              .. "你的任务：创建一个函数，接收两个参数，返回第二个。",
        tutorial = {
            "和上一关类似，但这次返回的是第二个参数 y。",
            "",
            "目标：构建 λx.λy.y",
            "  1. 放一个 λx 抽象",
            "  2. body 里放一个 λy 抽象",
            "  3. 最内层 body 放变量 y",
            "",
            "提示：这个函数后面会作为布尔值 FALSE 使用！",
        },
        hint = "和 K 类似，但最内层返回 y 而不是 x",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "a b", expect = "b" },
            { input = "foo bar", expect = "bar" },
        },
        reward = {
            id = "KI",
            name = "KI (第二)",
            expr = "λx.λy.y",
            description = "总是返回第二个参数",
        },
    },

    -- ========================================================================
    -- 第2章: 布尔逻辑
    -- ========================================================================

    {
        id = "2-1",
        chapter = 2,
        title = "真理之门",
        subtitle = "布尔值 TRUE",
        description = "恭喜！你已经发明了 TRUE。\n回顾一下：K = λx.λy.x 就是 TRUE！",
        story = "回头看看你的「偏心天平」…… \n"
              .. "如果把两个选项看作「真」和「假」，\n"
              .. "那么「总选第一个」不就是 TRUE 吗？\n\n"
              .. "在 Lambda 世界：TRUE 和 FALSE 是「选择函数」。\n"
              .. "  TRUE  = 选第一个 = λt.λf.t\n"
              .. "  FALSE = 选第二个 = λt.λf.f\n\n"
              .. "这关让你验证这个洞察。构建 TRUE。",
        tutorial = {
            "布尔值的编码非常巧妙：",
            "  TRUE  = λt.λf.t  (选第一个参数)",
            "  FALSE = λt.λf.f  (选第二个参数)",
            "",
            "你已经会了！就是前面的 K。",
            "但这次用参数名 t 和 f 来体现布尔含义。",
            "",
            "目标：构建 λt.λf.t",
        },
        hint = "就是 K，但参数命名为 t 和 f",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "yes no", expect = "yes" },
            { input = "a b", expect = "a" },
        },
        reward = {
            id = "TRUE",
            name = "TRUE",
            expr = "λt.λf.t",
            description = "布尔真：总选第一个",
        },
    },

    {
        id = "2-2",
        chapter = 2,
        title = "虚假之门",
        subtitle = "布尔值 FALSE",
        description = "同理，FALSE = λt.λf.f（就是你的影子收藏家 KI）",
        story = "有了 TRUE，自然也需要 FALSE。\n"
              .. "FALSE = 总选第二个 = KI = λt.λf.f\n\n"
              .. "简单，对吧？动手验证一下。",
        tutorial = {
            "FALSE = λt.λf.f",
            "和上一关的 KI 一模一样。",
            "",
            "目标：构建 λt.λf.f",
        },
        hint = "就是 KI，但参数命名为 t 和 f",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "yes no", expect = "no" },
            { input = "a b", expect = "b" },
        },
        reward = {
            id = "FALSE",
            name = "FALSE",
            expr = "λt.λf.f",
            description = "布尔假：总选第二个",
        },
    },

    {
        id = "2-3",
        chapter = 2,
        title = "反转术",
        subtitle = "逻辑非 NOT",
        description = "构建 NOT —— 把 TRUE 变 FALSE，把 FALSE 变 TRUE。",
        story = "现在你有了 TRUE 和 FALSE，是时候学第一个逻辑操作了。\n\n"
              .. "NOT 如何工作？\n"
              .. "  既然 TRUE 选第一个、FALSE 选第二个，\n"
              .. "  那么 NOT b = b FALSE TRUE\n"
              .. "  （让 b 自己选，但把选项反过来！）",
        tutorial = {
            "NOT 的关键洞察：",
            "  布尔值本身就是选择函数！",
            "  TRUE f s  → f  (选第一个)",
            "  FALSE f s → s  (选第二个)",
            "",
            "所以 NOT = λb. b FALSE TRUE",
            "  当 b=TRUE:  TRUE FALSE TRUE → FALSE",
            "  当 b=FALSE: FALSE FALSE TRUE → TRUE",
            "",
            "目标：构建 λb.(b FALSE TRUE)",
            "",
            "注意：这里的 FALSE 和 TRUE 是你之前解锁的预制积木！",
            "可以直接从左侧面板拖入使用。",
        },
        hint = "λb. 然后在 body 里：应用 b 到 FALSE，再应用到 TRUE",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
            { input = "(λt.λf.t)", expect = "λt.λf.f" },   -- NOT TRUE = FALSE
            { input = "(λt.λf.f)", expect = "λt.λf.t" },   -- NOT FALSE = TRUE
        },
        reward = {
            id = "NOT",
            name = "NOT",
            expr = "λb.b (λt.λf.f) (λt.λf.t)",
            description = "逻辑非：反转布尔值",
        },
    },

    {
        id = "2-4",
        chapter = 2,
        title = "双重认证",
        subtitle = "逻辑与 AND",
        description = "构建 AND —— 两个都为真才为真。",
        story = "AND 的思路：\n"
              .. "  AND p q = p q FALSE\n"
              .. "  如果 p 为真 → 结果看 q\n"
              .. "  如果 p 为假 → 直接为假",
        tutorial = {
            "AND 的编码：",
            "  AND = λp.λq. p q FALSE",
            "",
            "逻辑：",
            "  AND TRUE  q = TRUE q FALSE  → q   (取决于q)",
            "  AND FALSE q = FALSE q FALSE → FALSE",
            "",
            "目标：构建 λp.λq.(p q FALSE)",
        },
        hint = "λp.λq. 然后 body 是: (p q) FALSE，即把 p 应用到 q 和 FALSE",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
            { input = "(λt.λf.t) (λt.λf.t)", expect = "λt.λf.t" },  -- AND T T = T
            { input = "(λt.λf.t) (λt.λf.f)", expect = "λt.λf.f" },  -- AND T F = F
            { input = "(λt.λf.f) (λt.λf.t)", expect = "λt.λf.f" },  -- AND F T = F
            { input = "(λt.λf.f) (λt.λf.f)", expect = "λt.λf.f" },  -- AND F F = F
        },
        reward = {
            id = "AND",
            name = "AND",
            expr = "λp.λq.p q (λt.λf.f)",
            description = "逻辑与：两真则真",
        },
    },

    {
        id = "2-5",
        chapter = 2,
        title = "条条大路",
        subtitle = "逻辑或 OR",
        description = "构建 OR —— 至少一个为真就为真。",
        story = "OR 的思路：\n"
              .. "  OR p q = p TRUE q\n"
              .. "  如果 p 为真 → 直接为真\n"
              .. "  如果 p 为假 → 结果看 q",
        tutorial = {
            "OR 的编码：",
            "  OR = λp.λq. p TRUE q",
            "",
            "逻辑：",
            "  OR TRUE  q = TRUE TRUE q → TRUE",
            "  OR FALSE q = FALSE TRUE q → q",
            "",
            "目标：构建 λp.λq.(p TRUE q)",
        },
        hint = "λp.λq. 然后 body 是: (p TRUE) q",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
            { input = "(λt.λf.t) (λt.λf.t)", expect = "λt.λf.t" },  -- OR T T = T
            { input = "(λt.λf.t) (λt.λf.f)", expect = "λt.λf.t" },  -- OR T F = T
            { input = "(λt.λf.f) (λt.λf.t)", expect = "λt.λf.t" },  -- OR F T = T
            { input = "(λt.λf.f) (λt.λf.f)", expect = "λt.λf.f" },  -- OR F F = F
        },
        reward = {
            id = "OR",
            name = "OR",
            expr = "λp.λq.p (λt.λf.t) q",
            description = "逻辑或：至少一真则真",
        },
    },

    -- ========================================================================
    -- 第3章: 数字之源
    -- ========================================================================

    {
        id = "3-1",
        chapter = 3,
        title = "虚无",
        subtitle = "数字 ZERO",
        description = "构建数字 0 —— Church 编码的起点。",
        story = "逻辑搞定了！现在进入数字世界。\n\n"
              .. "Church 数的核心思想：\n"
              .. "  数字 n = 「把函数 f 应用 n 次到 x 上」\n"
              .. "  0 = 不用 f，直接返回 x → λf.λx.x\n"
              .. "  1 = 用一次 f              → λf.λx.f x\n"
              .. "  2 = 用两次 f              → λf.λx.f (f x)\n\n"
              .. "先从 0 开始。",
        tutorial = {
            "Church 数编码：",
            "  n = λf.λx. f 应用 n 次到 x",
            "",
            "  ZERO = λf.λx.x  (f 用了 0 次)",
            "",
            "注意：这和 FALSE 结构相同！",
            "  FALSE = λt.λf.f",
            "  ZERO  = λf.λx.x",
            "同一个表达式，不同的名字！",
            "",
            "目标：构建 λf.λx.x",
        },
        hint = "和 FALSE/KI 结构相同：λf.λx.x",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "succ zero", expect = "zero" },  -- ZERO f x = x
        },
        -- 特殊验证: Church 数检测
        verifyChurch = 0,
        reward = {
            id = "ZERO",
            name = "ZERO (0)",
            expr = "λf.λx.x",
            description = "Church 数 0：应用 f 零次",
        },
    },

    {
        id = "3-2",
        chapter = 3,
        title = "第一道光",
        subtitle = "数字 ONE 和 TWO",
        description = "构建数字 1：把 f 应用 1 次到 x。",
        story = "有了 0，自然需要 1。\n\n"
              .. "  ONE = λf.λx. f x\n"
              .. "  （把 f 作用到 x 一次）\n\n"
              .. "构建完 1 后，试试 2：\n"
              .. "  TWO = λf.λx. f (f x)",
        tutorial = {
            "ONE = λf.λx. f x",
            "",
            "解读：接收一个函数 f 和起始值 x，",
            "      把 f 作用到 x 恰好 1 次。",
            "",
            "构建方法：",
            "  1. 放 λf 抽象",
            "  2. body 里放 λx 抽象",
            "  3. 最内层 body 放一个「应用」积木",
            "  4. 应用的 func 是变量 f，arg 是变量 x",
            "",
            "目标：构建 λf.λx.(f x)",
        },
        hint = "λf.λx.(f x)：在最内层放应用积木，左边 f 右边 x",
        availableBlocks = { "var", "abs", "app" },
        verifyChurch = 1,
        verifyMode = "behavioral",
        testCases = {
            { input = "succ zero", expect = "succ zero" },  -- ONE f x = f x
        },
        reward = {
            id = "ONE",
            name = "ONE (1)",
            expr = "λf.λx.f x",
            description = "Church 数 1：应用 f 一次",
        },
    },

    {
        id = "3-3",
        chapter = 3,
        title = "后继者",
        subtitle = "后继函数 SUCC",
        description = "构建 SUCC —— 给任何数字 +1。",
        story = "数字 0、1 你能手工搭建。但不可能手搭到 100。\n\n"
              .. "你需要「后继函数 SUCC」：\n"
              .. "  SUCC n = n + 1\n\n"
              .. "关键洞察：如果 n 是「f 应用 n 次」，\n"
              .. "那么 n+1 就是「在 n 的结果上再多应用一次 f」：\n"
              .. "  SUCC = λn.λf.λx. f (n f x)",
        tutorial = {
            "SUCC 的结构：",
            "  SUCC = λn.λf.λx. f (n f x)",
            "",
            "解读：",
            "  接收 n (一个 Church 数)",
            "  返回一个新的 Church 数：λf.λx. ...",
            "  新数的含义：先让 n 把 f 作用到 x n 次,",
            "               得到的结果再多做一次 f",
            "",
            "构建提示：",
            "  外三层: λn.λf.λx.",
            "  body: f 应用到 (n f x)",
            "  其中 (n f x) 需要两次嵌套「应用」",
            "",
            "目标：构建 λn.λf.λx.f(n f x)",
        },
        hint = "三层λ嵌套后，body 里是 (f ((n f) x))，共需要三个应用积木",
        availableBlocks = { "var", "abs", "app" },
        verifyMode = "behavioral",
        testCases = {
            -- SUCC ZERO = ONE: λf.λx.f x
            { input = "(λf.λx.x)", expect = "λf.λx.f x" },
            -- SUCC ONE = TWO: λf.λx.f (f x)
            { input = "(λf.λx.f x)", expect = "λf.λx.f (f x)" },
        },
        reward = {
            id = "SUCC",
            name = "SUCC (+1)",
            expr = "λn.λf.λx.f (n f x)",
            description = "后继函数：给 Church 数 +1",
        },
    },

    -- ========================================================================
    -- 第4章: 算术运算
    -- ========================================================================

    {
        id = "4-1",
        chapter = 4,
        title = "相加术",
        subtitle = "加法 ADD",
        description = "构建 ADD —— 两个 Church 数相加。",
        story = "有了 SUCC，加法呼之欲出：\n\n"
              .. "  ADD m n = 对 n 做 m 次 SUCC\n"
              .. "         = m SUCC n\n\n"
              .. "因为 Church 数 m 本身就是「做 m 次」！\n"
              .. "把 SUCC 作为「要做的事」传给 m，\n"
              .. "把 n 作为起始值。完美。",
        tutorial = {
            "ADD 的编码：",
            "  ADD = λm.λn. m SUCC n",
            "",
            "解读：",
            "  m 是一个 Church 数 = 「做 m 次」",
            "  让 m 把 SUCC 应用 m 次到 n 上",
            "  = n + 1 + 1 + ... (m 个 +1)",
            "  = n + m",
            "",
            "这里可以直接使用你的 SUCC 预制积木！",
            "",
            "目标：构建 λm.λn.(m SUCC n)",
            "  即 λm.λn.((m SUCC) n)",
        },
        hint = "λm.λn. body 是 ((m SUCC) n)，需要两个应用积木嵌套，以及 SUCC 预制",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "SUCC" },
        verifyMode = "behavioral",
        testCases = {
            -- ADD 1 1 = 2
            { input = "(λf.λx.f x) (λf.λx.f x)", expect = "λf.λx.f (f x)" },
            -- ADD 2 1 = 3
            { input = "(λf.λx.f (f x)) (λf.λx.f x)", expect = "λf.λx.f (f (f x))" },
        },
        reward = {
            id = "ADD",
            name = "ADD (+)",
            expr = "λm.λn.m (λn.λf.λx.f (n f x)) n",
            description = "加法：m + n",
        },
    },

    {
        id = "4-2",
        chapter = 4,
        title = "倍增术",
        subtitle = "乘法 MUL",
        description = "构建 MUL —— 两个 Church 数相乘。",
        story = "乘法同样优雅：\n\n"
              .. "  MUL m n = 做 m 次「加 n」从 0 开始\n"
              .. "         = m (ADD n) ZERO\n\n"
              .. "或者更直接的编码：\n"
              .. "  MUL = λm.λn.λf. m (n f)\n"
              .. "  含义：m 次应用 (n 次应用 f) = m*n 次应用 f",
        tutorial = {
            "MUL 有两种编码（都正确）：",
            "",
            "方案A（用预制积木）：",
            "  MUL = λm.λn. m (ADD n) ZERO",
            "",
            "方案B（纯函数组合，更简洁）：",
            "  MUL = λm.λn.λf. m (n f)",
            "  含义：把 (n f) 看作一整个函数，",
            "        m 次应用它 = m*n 次应用 f",
            "",
            "推荐方案B，只需要基础积木：",
            "目标：构建 λm.λn.λf.m (n f)",
        },
        hint = "三层λ后，body 是 (m (n f))：两个应用积木",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "ADD", "ZERO" },
        verifyMode = "behavioral",
        testCases = {
            -- MUL 2 3 = 6
            { input = "(λf.λx.f (f x)) (λf.λx.f (f (f x)))", expect = "λf.λx.f (f (f (f (f (f x)))))" },
            -- MUL 1 3 = 3
            { input = "(λf.λx.f x) (λf.λx.f (f (f x)))", expect = "λf.λx.f (f (f x))" },
        },
        reward = {
            id = "MUL",
            name = "MUL (×)",
            expr = "λm.λn.λf.m (n f)",
            description = "乘法：m × n",
        },
    },

    -- ========================================================================
    -- 第5章: BOSS 战
    -- ========================================================================

    {
        id = "5-1",
        chapter = 5,
        title = "配对术",
        subtitle = "有序对 PAIR",
        description = "构建 PAIR —— 把两个值打包在一起。前驱函数需要它。",
        story = "减法需要「前驱函数 PRED」(n-1)。\n"
              .. "但 PRED 的构建需要先学会「配对」。\n\n"
              .. "PAIR 把两个值打包：\n"
              .. "  PAIR a b = λf. f a b\n"
              .. "  （给出选择器 f，让 f 来选 a 或 b）\n\n"
              .. "配合 TRUE/FALSE 取出：\n"
              .. "  PAIR a b TRUE  → a  (取第一个)\n"
              .. "  PAIR a b FALSE → b  (取第二个)",
        tutorial = {
            "PAIR 的编码：",
            "  PAIR = λa.λb.λf. f a b",
            "",
            "用法：",
            "  PAIR x y     → λf. f x y",
            "  (PAIR x y) TRUE  → TRUE x y → x",
            "  (PAIR x y) FALSE → FALSE x y → y",
            "",
            "目标：构建 λa.λb.λf.(f a b)",
            "  即 λa.λb.λf.((f a) b)",
        },
        hint = "三层 λ 后，body 是 ((f a) b)，两个应用积木",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
            -- (PAIR a b) TRUE = a
            { input = "hello world", expect = "λf.f hello world", raw = true },
        },
        reward = {
            id = "PAIR",
            name = "PAIR",
            expr = "λa.λb.λf.f a b",
            description = "有序对：打包两个值",
        },
    },

    {
        id = "5-2",
        chapter = 5,
        title = "倒退一步",
        subtitle = "前驱函数 PRED",
        description = "构建 PRED —— 给 Church 数 -1（难度最高的一关！）",
        story = "前驱是 Lambda 演算中最具挑战性的构造！\n\n"
              .. "思路：用 PAIR 做「滑动窗口」：\n"
              .. "  从 (0, 0) 出发，\n"
              .. "  每步 (a, b) → (b, b+1)，\n"
              .. "  做 n 步后取第一个元素。\n\n"
              .. "  PRED n = FST (n STEP (PAIR ZERO ZERO))\n"
              .. "  其中 STEP = λp. PAIR (SND p) (SUCC (SND p))\n\n"
              .. "这关可以用预制积木组合！",
        tutorial = {
            "PRED 用「配对滑窗」实现：",
            "",
            "  STEP = λp. PAIR (p FALSE) (SUCC (p FALSE))",
            "    取出对的第二个值，做成新对 (old_snd, old_snd+1)",
            "",
            "  PRED = λn. n STEP (PAIR ZERO ZERO) TRUE",
            "    初始对 = (0, 0)",
            "    执行 n 次 STEP：(0,1)→(1,2)→(2,3)→...",
            "    最后取第一个 = n-1",
            "",
            "这很复杂！可以分步构建。",
            "本关允许使用所有已解锁的预制积木。",
            "",
            "目标：构建 PRED 使得 PRED n = n-1",
        },
        hint = "分步：先做 STEP，再组合 PRED = λn. (n STEP (PAIR ZERO ZERO)) TRUE",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "ZERO", "SUCC", "PAIR", "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
            -- PRED 1 = 0
            { input = "(λf.λx.f x)", expect = "λf.λx.x" },
            -- PRED 2 = 1
            { input = "(λf.λx.f (f x))", expect = "λf.λx.f x" },
            -- PRED 3 = 2
            { input = "(λf.λx.f (f (f x)))", expect = "λf.λx.f (f x)" },
        },
        reward = {
            id = "PRED",
            name = "PRED (-1)",
            expr = "λn.λf.λx.n (λg.λh.h (g f)) (λu.x) (λu.u)",
            description = "前驱函数：n - 1",
        },
    },

    {
        id = "5-3",
        chapter = 5,
        title = "减法降临",
        subtitle = "减法 SUB",
        description = "构建 SUB —— m 减 n。有了 PRED 这就简单了。",
        story = "和加法的思路对称：\n\n"
              .. "  ADD m n = m SUCC n   (对 n 做 m 次 +1)\n"
              .. "  SUB m n = n PRED m   (对 m 做 n 次 -1)\n\n"
              .. "一行搞定。",
        tutorial = {
            "SUB 的编码：",
            "  SUB = λm.λn. n PRED m",
            "",
            "解读：对 m 执行 n 次 PRED (n 次 -1)",
            "  = m - n",
            "",
            "目标：构建 λm.λn.(n PRED m)",
            "  即 λm.λn.((n PRED) m)",
        },
        hint = "λm.λn. body 是 ((n PRED) m)，和 ADD 结构对称",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "PRED" },
        verifyMode = "behavioral",
        testCases = {
            -- SUB 3 1 = 2
            { input = "(λf.λx.f (f (f x))) (λf.λx.f x)", expect = "λf.λx.f (f x)" },
            -- SUB 2 2 = 0
            { input = "(λf.λx.f (f x)) (λf.λx.f (f x))", expect = "λf.λx.x" },
        },
        reward = {
            id = "SUB",
            name = "SUB (-)",
            expr = "λm.λn.n (λn.λf.λx.n (λg.λh.h (g f)) (λu.x) (λu.u)) m",
            description = "减法：m - n",
        },
    },

    {
        id = "5-4",
        chapter = 5,
        title = "终极考验：四则运算器",
        subtitle = "BOSS: 计算器",
        description = "用你解锁的所有预制积木，构建一个能做加减乘的运算器！",
        story = "恭喜你走到了最后！\n\n"
              .. "你从三个最基础的积木出发，\n"
              .. "发明了布尔逻辑、自然数、加减乘。\n\n"
              .. "最终挑战：构建一个「运算选择器」\n"
              .. "  CALC op m n\n"
              .. "  op = 0 → ADD m n\n"
              .. "  op = 1 → SUB m n\n"
              .. "  op = 2 → MUL m n\n\n"
              .. "用 Church 数做 if-else 选择！\n"
              .. "（提示：用 PAIR 做选择表/Case分支）",
        tutorial = {
            "最终 BOSS！",
            "",
            "构建 CALC = λop.λm.λn.",
            "  如果 op=0，返回 ADD m n",
            "  如果 op=1，返回 SUB m n",
            "  如果 op=2，返回 MUL m n",
            "",
            "提示：你有多种方式实现选择逻辑，",
            "  方案1: 用嵌套 PAIR 做查找表",
            "  方案2: 用 Church 数的 n 次应用做 case 选择",
            "",
            "你可以使用所有已解锁的预制积木！",
            "祝你好运，Lambda 大师！",
        },
        hint = "一种方案：ops = PAIR (PAIR ADD SUB) MUL，然后根据 op 索引",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "ADD", "SUB", "MUL", "PAIR", "TRUE", "FALSE", "ZERO", "ONE", "SUCC" },
        verifyMode = "behavioral",
        testCases = {
            -- CALC 0 2 3 = ADD 2 3 = 5
            { input = "(λf.λx.x) (λf.λx.f (f x)) (λf.λx.f (f (f x)))",
              expect = "λf.λx.f (f (f (f (f x))))" },
            -- CALC 1 3 1 = SUB 3 1 = 2
            { input = "(λf.λx.f x) (λf.λx.f (f (f x))) (λf.λx.f x)",
              expect = "λf.λx.f (f x)" },
            -- CALC 2 2 3 = MUL 2 3 = 6
            { input = "(λf.λx.f (f x)) (λf.λx.f (f x)) (λf.λx.f (f (f x)))",
              expect = "λf.λx.f (f (f (f (f (f x)))))" },
        },
        reward = {
            id = "CALC",
            name = "CALC (计算器)",
            expr = "λop.λm.λn.op (ADD m n) (SUB m n) (MUL m n)",
            description = "四则运算选择器",
        },
        isBoss = true,
    },
}

-- ============================================================================
-- 章节元数据
-- ============================================================================

LevelData.chapters = {
    { id = 1, title = "认识 Lambda",  subtitle = "变量、抽象、应用",  icon = "🪞" },
    { id = 2, title = "布尔逻辑",    subtitle = "TRUE/FALSE/NOT/AND/OR", icon = "🔮" },
    { id = 3, title = "数字之源",    subtitle = "Church 数与后继",       icon = "🔢" },
    { id = 4, title = "算术运算",    subtitle = "加法与乘法",           icon = "➕" },
    { id = 5, title = "终极考验",    subtitle = "BOSS: 四则运算器",     icon = "⚔️" },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

function LevelData.getLevelById(id)
    for _, level in ipairs(LevelData.levels) do
        if level.id == id then return level end
    end
    return nil
end

function LevelData.getLevelIndex(id)
    for i, level in ipairs(LevelData.levels) do
        if level.id == id then return i end
    end
    return nil
end

function LevelData.getChapterLevels(chapterId)
    local result = {}
    for _, level in ipairs(LevelData.levels) do
        if level.chapter == chapterId then
            table.insert(result, level)
        end
    end
    return result
end

function LevelData.getTotalLevels()
    return #LevelData.levels
end

return LevelData
