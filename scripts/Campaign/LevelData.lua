-- ============================================================================
-- Campaign/LevelData.lua - 闯关模式关卡定义
-- ============================================================================
-- 策划思路 (仿"图灵完备"):
--   从 3 个基础积木 (变量/抽象/应用) 出发，逐步构建直到四则运算器。
--   每关通过后，构建的表达式变成"预制积木"，后续关卡可直接使用。
--
-- 5章 18关 (难度曲线更平缓):
--   第1章 认识 Lambda   (4关: 身份函数、应用入门、选择器K、选择器KI)
--   第2章 布尔逻辑      (5关: TRUE/FALSE 认识、NOT、AND、OR)
--   第3章 数字之源      (4关: ZERO、ONE、TWO、SUCC)
--   第4章 算术运算      (3关: ADD、MUL、幂)
--   第5章 BOSS          (2关: PRED、组合运算)
-- ============================================================================

local LevelData = {}

-- ============================================================================
-- 关卡定义列表
-- ============================================================================

LevelData.levels = {

    -- ========================================================================
    -- 第1章: 认识 Lambda (4关)
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
            "欢迎来到 Lambda 世界！先认识积木：",
            "",
            "【变量】(青色小方块)",
            "  就像一个「名牌」，写着名字。",
            "  比如写着「x」的名牌，代表某个东西。",
            "",
            "【抽象 λ】(紫色大方块，带一个洞)",
            "  就像一台「加工机器」：",
            "  顶部写着它接收什么（参数名），",
            "  里面的洞(body)放着它会吐出什么。",
            "",
            "做法：",
            "  1. 从左边拖一个「抽象」积木 → 参数取名 x",
            "  2. 再拖一个「变量」积木，名字也叫 x",
            "  3. 把变量 x 放进抽象的洞里",
            "",
            "结果：一台「收到 x，原样吐出 x」的机器！",
        },
        hint = "把一个变量 x 放进 λx 的 body 槽中",
        availableBlocks = { "var", "abs" },
        verifyMode = "behavioral",
        testCases = {
            { input = "a", expect = "a" },
            { input = "b", expect = "b" },
            { input = "(λy.y)", expect = "(λy.y)" },
        },
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
        title = "传话筒",
        subtitle = "应用入门",
        description = "用「应用」积木把函数 I 作用到变量 a 上，得到结果 a。",
        story = "你有了镜子 I，但怎么「使用」它呢？\n"
              .. "这就需要第三种积木：「应用」。\n\n"
              .. "「应用」(绿色)把左边的函数作用到右边的参数上。\n"
              .. "试试把 I 应用到 a，看看会发生什么。",
        tutorial = {
            "新积木登场！",
            "",
            "【应用】(绿色，有左右两个洞)",
            "  把一台机器和一个东西「接上」。",
            "  左洞 = 放哪台机器",
            "  右洞 = 喂什么东西给它",
            "",
            "举例：",
            "  镜子 I 收到苹果 → 吐出苹果",
            "",
            "做法：",
            "  1. 从左边拖一个「应用」积木",
            "  2. 左洞：放入预制件「I」(从左面板拖)",
            "  3. 右洞：放一个变量，取名 a",
            "",
            "提交后系统会自动运行机器，验证结果！",
        },
        hint = "应用积木的 func 槽放 I，arg 槽放变量 a",
        availableBlocks = { "var", "app" },
        availablePrefabs = { "I" },
        verifyMode = "behavioral",
        testCases = {
            { input = "", expect = "a", raw = true },
        },
        -- 特殊验证：结果化简为 a
        verifyExact = "a",
        reward = nil,  -- 本关不解锁新积木，纯练习
    },

    {
        id = "1-3",
        chapter = 1,
        title = "偏心天平",
        subtitle = "第一选择器 K",
        description = "构建一个「偏心天平」—— 给它两样东西，它总是选第一个。",
        story = "在镜子旁边，你看到一架天平。\n"
              .. "这架天平有个奇怪的特性：它永远偏向左边。\n\n"
              .. "你的任务：创建一个函数，接收两个参数，返回第一个。",
        tutorial = {
            "这次要造一台「两步机器」：",
            "  先接收第一样东西，再接收第二样，",
            "  然后只吐出第一样。",
            "",
            "怎么做到？把机器「套」起来！",
            "  外面的机器收到 x → 吐出一台内部机器",
            "  内部机器收到 y → 吐出 x (忽略 y)",
            "",
            "做法：",
            "  1. 放一个「抽象」，参数取名 x",
            "  2. 在它的洞(body)里，再放一个「抽象」，参数取名 y",
            "  3. 在最里面那个洞里，放一个变量 x",
            "",
            "最终效果：收两样东西，永远选第一个。",
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
        id = "1-4",
        chapter = 1,
        title = "影子收藏家",
        subtitle = "第二选择器 KI",
        description = "构建一个「影子收藏家」—— 给它两样东西，它只要第二个。",
        story = "天平的对面有一位收藏家。\n"
              .. "他对第一个礼物毫无兴趣，只保留第二个。\n\n"
              .. "你的任务：创建一个函数，接收两个参数，返回第二个。",
        tutorial = {
            "和上一关几乎一样的套路！",
            "只是这次机器要「选第二样东西」。",
            "",
            "做法：",
            "  1. 放一个「抽象」，参数取名 x",
            "  2. 在它的洞里，再放一个「抽象」，参数取名 y",
            "  3. 最里面的洞放变量 y（不是 x！）",
            "",
            "结果：收两样东西，扔掉第一个，只留第二个。",
            "",
            "小剧透：后面你会发现，",
            "「选第一个」= 真 (TRUE)",
            "「选第二个」= 假 (FALSE)",
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
    -- 第2章: 布尔逻辑 (5关)
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
            "和上一章的 KI 一模一样。",
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
            "构建提示：",
            "  1. 放一个 λb 抽象",
            "  2. body 里放一个「应用」积木",
            "  3. 「应用」的左边再放一个「应用」",
            "  4. 最内层应用: func=b, arg=FALSE",
            "  5. 外层应用: func=(b FALSE), arg=TRUE",
            "",
            "注意：FALSE 和 TRUE 是预制积木，从左边面板拖入！",
        },
        hint = "λb. 然后 body 里构建 ((b FALSE) TRUE)，需要两个应用积木嵌套",
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
            "构建方法：",
            "  1. 放 λp 抽象",
            "  2. body 里放 λq 抽象",
            "  3. 最内层 body: ((p q) FALSE)",
            "     两个应用积木嵌套，最内层 func=p arg=q",
            "     外层 func=(p q) arg=FALSE",
            "",
            "目标：构建 λp.λq.(p q FALSE)",
        },
        hint = "λp.λq. body 是 ((p q) FALSE)，内层应用 p 到 q，外层再应用到 FALSE",
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
            "和 AND 结构类似，只是参数不同：",
            "  AND 用 FALSE 作兜底",
            "  OR 用 TRUE 作兜底",
            "",
            "目标：构建 λp.λq.(p TRUE q)",
        },
        hint = "λp.λq. body 是 ((p TRUE) q)",
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
    -- 第3章: 数字之源 (4关)
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
        verifyChurch = 0,
        testCases = {
            { input = "succ zero", expect = "zero" },
        },
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
        subtitle = "数字 ONE",
        description = "构建数字 1：把 f 应用 1 次到 x。\n即 λf.λx.(f x)",
        story = "有了 0，自然需要 1。\n\n"
              .. "  ONE = λf.λx. f x\n"
              .. "  （把 f 作用到 x 一次）\n\n"
              .. "这是第一次在最内层需要用「应用」积木！",
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
            { input = "succ zero", expect = "succ zero" },
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
        title = "双生",
        subtitle = "数字 TWO",
        description = "构建数字 2：把 f 应用 2 次到 x。\n即 λf.λx.f (f x)",
        story = "规律已经很明显了：\n\n"
              .. "  TWO = λf.λx. f (f x)\n"
              .. "  （把 f 作用到 x 两次）\n\n"
              .. "提示：内部结构是 f 应用到 (f x)，\n"
              .. "需要两个嵌套的「应用」积木。",
        tutorial = {
            "TWO = λf.λx. f (f x)",
            "",
            "结构分析：",
            "  最内层: (f x) —— 一个应用",
            "  外层: f (f x) —— 另一个应用",
            "  即两个应用积木嵌套",
            "",
            "构建方法：",
            "  1. 放 λf.λx 两层抽象",
            "  2. 放一个应用积木 A1: func=f, arg=x",
            "  3. 再放一个应用积木 A2: func=f, arg=A1",
            "",
            "目标：构建 λf.λx.f (f x)",
        },
        hint = "两个应用积木嵌套：外层的 arg 是内层整体",
        availableBlocks = { "var", "abs", "app" },
        verifyChurch = 2,
        verifyMode = "behavioral",
        testCases = {
            { input = "succ zero", expect = "succ (succ zero)" },
        },
        reward = {
            id = "TWO",
            name = "TWO (2)",
            expr = "λf.λx.f (f x)",
            description = "Church 数 2：应用 f 两次",
        },
    },

    {
        id = "3-4",
        chapter = 3,
        title = "后继者",
        subtitle = "后继函数 SUCC",
        description = "构建 SUCC —— 给任何数字 +1。\n不用手搭每个数字了！",
        story = "数字 0、1、2 你能手工搭建。但不可能手搭到 100。\n\n"
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
            "  body: 先让 n 把 f 作用到 x 共 n 次,",
            "        得到的结果再多做一次 f",
            "",
            "结构拆解 (由内到外)：",
            "  (n f) —— 一个应用: func=n, arg=f",
            "  ((n f) x) —— 再一个应用: func=(n f), arg=x",
            "  (f ((n f) x)) —— 最外一个应用: func=f, arg=上面结果",
            "",
            "一共 3 个应用积木 + 3 层 λ 抽象",
            "",
            "目标：构建 λn.λf.λx.f((n f) x)",
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
    -- 第4章: 算术运算 (3关)
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
            "构建方法：",
            "  1. 放 λm.λn 两层抽象",
            "  2. body: ((m SUCC) n)",
            "     内层应用: func=m, arg=SUCC预制积木",
            "     外层应用: func=(m SUCC), arg=n",
            "",
            "目标：构建 λm.λn.((m SUCC) n)",
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
        description = "构建 MUL —— 两个 Church 数相乘。\n比加法还简洁！",
        story = "乘法的编码出奇优雅：\n\n"
              .. "  MUL = λm.λn.λf. m (n f)\n"
              .. "  含义：m 次应用 (n 次应用 f) = m*n 次应用 f\n\n"
              .. "这就是函数组合！2 次做 3 件事 = 做 6 件事。",
        tutorial = {
            "MUL = λm.λn.λf. m (n f)",
            "",
            "解读：",
            "  把 (n f) 看作一整个函数 g",
            "  g 做一次 = 做 n 次 f",
            "  m 次做 g = m*n 次 f",
            "",
            "结构和 SUCC 类似，三层 λ：",
            "  1. 放 λm.λn.λf 三层抽象",
            "  2. body: (m (n f))",
            "     内层应用: func=n, arg=f",
            "     外层应用: func=m, arg=(n f)",
            "",
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
            name = "MUL (x)",
            expr = "λm.λn.λf.m (n f)",
            description = "乘法：m x n",
        },
    },

    {
        id = "4-3",
        chapter = 4,
        title = "次方术",
        subtitle = "幂运算 POW",
        description = "构建 POW —— m 的 n 次方。\n这是本章最简洁的编码！",
        story = "令人惊叹的是，幂运算的编码比加法和乘法都简洁：\n\n"
              .. "  POW = λm.λn. n m\n\n"
              .. "就这么简单！为什么？\n"
              .. "  n m = 把 m「做 n 次」\n"
              .. "  而 Church 数 m 本身是「做 m 次」\n"
              .. "  做 n 次「做 m 次」= 做 m^n 次\n\n"
              .. "（注意参数顺序：n m 而不是 m n！）",
        tutorial = {
            "POW = λm.λn. n m",
            "",
            "这可能是最简洁的运算编码了：",
            "  只有两层 λ 和一个应用积木！",
            "",
            "理解：",
            "  Church 数 n 接收一个函数后，会做 n 次",
            "  把 m (也是一个 Church 数/函数) 传给 n",
            "  = 做 n 次 m = m^n",
            "",
            "目标：构建 λm.λn.(n m)",
        },
        hint = "λm.λn. body 只需要一个应用积木: func=n, arg=m",
        availableBlocks = { "var", "abs", "app" },
        verifyMode = "behavioral",
        testCases = {
            -- POW 2 3 = 8: 2^3
            { input = "(λf.λx.f (f x)) (λf.λx.f (f (f x)))", expect = "λf.λx.f (f (f (f (f (f (f (f x)))))))" },
            -- POW 3 2 = 9: 3^2
            { input = "(λf.λx.f (f (f x))) (λf.λx.f (f x))", expect = "λf.λx.f (f (f (f (f (f (f (f (f x))))))))" },
        },
        reward = {
            id = "POW",
            name = "POW (^)",
            expr = "λm.λn.n m",
            description = "幂运算：m^n",
        },
    },

    -- ========================================================================
    -- 第5章: BOSS 战 (2关)
    -- ========================================================================

    {
        id = "5-1",
        chapter = 5,
        title = "配对术",
        subtitle = "有序对 PAIR",
        description = "构建 PAIR —— 把两个值打包在一起。\n后续的前驱函数需要它。",
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
            "结构：三层 λ + 两个应用积木",
            "  body: ((f a) b)",
            "  内层: func=f, arg=a",
            "  外层: func=(f a), arg=b",
            "",
            "目标：构建 λa.λb.λf.((f a) b)",
        },
        hint = "三层 λ 后，body 是 ((f a) b)，两个应用积木",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "TRUE", "FALSE" },
        verifyMode = "behavioral",
        testCases = {
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
        title = "终极考验：运算组合",
        subtitle = "BOSS: 运算选择器",
        description = "构建一个运算选择器：接收布尔 op、两个数 m n，\n当 op=TRUE 返回 ADD m n，当 op=FALSE 返回 MUL m n。",
        story = "恭喜你走到了最后！\n\n"
              .. "你从三个最基础的积木出发，\n"
              .. "发明了布尔逻辑、自然数、加法、乘法、幂运算。\n\n"
              .. "最终挑战：构建一个运算选择器 CALC\n"
              .. "  CALC op m n\n"
              .. "  op = TRUE  → ADD m n (加法)\n"
              .. "  op = FALSE → MUL m n (乘法)\n\n"
              .. "提示：布尔值就是选择函数！\n"
              .. "  op (ADD m n) (MUL m n)\n"
              .. "  TRUE选第一个 = ADD，FALSE选第二个 = MUL",
        tutorial = {
            "最终 BOSS！",
            "",
            "CALC = λop.λm.λn. op (ADD m n) (MUL m n)",
            "",
            "分析：",
            "  op 是一个布尔值 (TRUE/FALSE)",
            "  TRUE 选第一个参数 → ADD m n",
            "  FALSE 选第二个参数 → MUL m n",
            "",
            "结构：三层 λ + 多个应用积木",
            "  先构建 (ADD m n)：((ADD m) n)",
            "  再构建 (MUL m n)：((MUL m) n)",
            "  最后 ((op 第一个结果) 第二个结果)",
            "",
            "你可以使用所有已解锁的预制积木！",
        },
        hint = "λop.λm.λn. body 是 ((op (ADD m n)) (MUL m n))，分别构建两个运算结果再让 op 选择",
        availableBlocks = { "var", "abs", "app" },
        availablePrefabs = { "ADD", "MUL", "TRUE", "FALSE", "ZERO", "ONE", "SUCC" },
        verifyMode = "behavioral",
        testCases = {
            -- CALC TRUE 2 3 = ADD 2 3 = 5
            { input = "(λt.λf.t) (λf.λx.f (f x)) (λf.λx.f (f (f x)))",
              expect = "λf.λx.f (f (f (f (f x))))" },
            -- CALC FALSE 2 3 = MUL 2 3 = 6
            { input = "(λt.λf.f) (λf.λx.f (f x)) (λf.λx.f (f (f x)))",
              expect = "λf.λx.f (f (f (f (f (f x)))))" },
        },
        reward = {
            id = "CALC",
            name = "CALC (计算器)",
            expr = "λop.λm.λn.op (ADD m n) (MUL m n)",
            description = "运算选择器：TRUE=加法，FALSE=乘法",
        },
        isBoss = true,
    },
}

-- ============================================================================
-- 章节元数据
-- ============================================================================

LevelData.chapters = {
    { id = 1, title = "认识 Lambda",  subtitle = "变量、抽象、应用",      icon = "🪞" },
    { id = 2, title = "布尔逻辑",    subtitle = "TRUE/FALSE/NOT/AND/OR", icon = "🔮" },
    { id = 3, title = "数字之源",    subtitle = "Church 数与后继",       icon = "🔢" },
    { id = 4, title = "算术运算",    subtitle = "加法、乘法、幂",        icon = "➕" },
    { id = 5, title = "终极考验",    subtitle = "BOSS: 运算选择器",      icon = "⚔️" },
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
