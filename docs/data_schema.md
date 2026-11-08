# 当前实现的数据契约

2026-11-05。本文件记录已实现的技术格式，不新增游戏设定。

## 静态配置

使用 UTF-8 JSON。`core/content_catalog.gd` 中 PATHS 是唯一表注册入口；常规表为对象数组，每条有唯一字符串id，加载时转为只读用途的索引字典。rules/prototype 为单个对象。读取正式表不等于创建运行时状态，运行状态在 OperationService 内独立维护，UI 只读快照。

- items：id/name/type/rarity/stack_limit/buy_price/sell_price/description/use_effect。恢复效果为stat/amount，秘籍效果为learn。装备实例数量不进入普通物品字典。
- equipment：id 引用 items。旧模板沿用 id/slot/hp/attack/defense/realm。V1 普通装备采用 id/name/tier/quality/slot/element/recommended_realm/base_stats/traits/nurture_level/nurture_max/value/description。器蕴以 id/name/type/amount 表示。recommended_realm 使用 0 凡人、1 炼气、2 筑基。
- artifacts：法宝配置独立索引，含 power、ability（id/name/target/mana/cooldown/actions/effects）、refine_field、refine_level 和 refine_max。当前仅加载配置。
- 玩家装备实例和槽位继续使用 equipment_instances 与 equipped。可选 equipment_nurture 按实例 ID 保存整数层数，缺项为 0，售出实例时一并移除。可选 qi_equipment_claimed 保存套装领取状态，旧档缺项为未领取。
- techniques：基础hp/defense/attack/practice/fire及对应_step，每级追加；rarity关联升级消耗。
- spells：element/mp/cd/multiplier/heal/guard/status/buy_price。cd按自身行动计算；状态由战斗模块统一结算。
- herbs：id/seed_id/days/yield_count。recipes：materials/cost/days/output。
- monsters：属性、特殊行动周期、灵石区间、独立掉落数组[item_id,quantity,probability]。可追加第 4 项最大数量，命中后从 quantity 到最大数量含边界均匀抽取。
- `prototype.outskirts_routes` 配置山外围首页的探索入口，字段为稳定 `id`、`name`、`outcomes` 和 `herbs`。结果索引沿用 `rules.exploration_weights` 顺序（灰牙野狼、山林獠猪、青尾灵狐、采药、清泉）。路线内按入选结果的相对权重抽取；`unavailable` 表示入口禁用并给出原因。探索请求携带可选 `route`，玩家地点仍为 `area_qinglan_outskirts`，无新增存档字段。
- 采矿路线以 `mining` 数组替代 `outcomes` 和 `herbs`。每条记录含现有材料 ID `item_id` 和整数百分比 `chance`（1–100），每次命中发放 1 件。必得矿石直接结算，其他矿石使用已保存的探索随机流独立抽取。
- 采矿路线可配 `encounter`，包含已注册妖兽 `monster_id` 和整数百分比 `chance`（1–100）。先推进探索时间，再抽遭遇。命中即进入现有战斗，未命中才结算矿石。战斗和存档沿用现有结构。
- quests：previous/realm/target/required_item/money/rewards/description。
- shops：npc_id/location/stock/restock。运行库存是初始配置的独立副本。
- 新增 NPC 与店铺可使用 `seed_on_restore: true`，允许版本 1 存档补录整个缺失条目。已有 NPC、已扣减或为零的库存照常恢复，已有条目仍校验结构。原有必需店铺缺失仍视为存档异常。NPC 可用 `stationary: true` 关闭既有月度跨城迁移，初始定义会将其带入运行状态。
- NPC 定义可用 `identity_from_catalog: true` 在旧档恢复时同步既有人物的名字和职业，保留 ID 与状态，作者覆盖版仍优先。宗门 NPC 的 `sect_area` 引用所属宗门区域 ID，受限区域的人物沿用区域通行限制。
- NPC 运行态可保存当前 `hp/mp/blood`、永久 `fortunes` 和 `loadout`。旧档缺项时补录，保留已有值和手工装配。基础属性优先使用档案 `base`，缺项读取原型基础档和已有法修成长表。非编辑版 NPC 的随机初始装配和气运按人物 ID 派生，普通新游戏采用新档标识，旧档首次补录采用已保存的随机状态，现有随机流不被消耗。
- NPC 的 `realm` 是实际法修层级，`realm_known` 是可选布尔公开标记，缺省为 false。定义和存档共同校验二者。人物交互、拍卖名册和编辑器游戏预览采用同一显示规则。
- 开发模式的原型 NPC 气运同步可写入多项永久气运与原档案气运，沿用互斥验证及现有保存结构。原型 NPC 同步保留当前装配和地点。
- NPC 编辑器可校验并原位更新用户选定的存档。每个存档目录使用 `npc_backups/npc_backup_1.json` 至 `npc_backup_5.json` 轮换备份。备份信封附 `npc_backup_source`（原文件名）及 `npc_backup_order`（写入顺序），原始 payload 与校验和保留。普通读档列表只列存档目录顶层的原文件。
- 存档模式应用现有编辑器字段。被编辑的原型 NPC 在该档转换为编辑版结构，旧式装配转换为独立装备实例和技能槽。原人物 ID、财富和未编辑的运行状态继续沿用，资源按新上限校准，年龄改动同步年龄基准。
- realms：required/growth，growth顺序为hp/mp/attack/defense/speed。
- rules为现有内容数值；prototype为单独授权的原型规则，见decisions.md。
- `prototype.sects[].residence` 为可选驻地定义，包含稳定且不与其他地点重复的 `location_id`、显示 `name` 和正整数 `travel_hours`。到达后的地点 ID 沿用 `player.location`；无驻地页面或通行资格的独立存档字段。旧地点 ID 和存档版本保持兼容。
- `world/sect_areas.json` 按宗门 ID 存放已配置驻地的四区展示数据。每区包含 `id`、`name`、`heading`、`restriction` 和 `cards`。卡片 ID 在区内唯一，包含名称和说明，可选 `entry` 仅用于外门山门出口或隐藏未发现地点。布局预览是界面状态，读档后从外门入口重新打开。
- 默认弟子身份按 DEC-040 由已保存的 `state.sect` 派生；现阶段没有独立职级字段，旧档无需迁移。
- starting_character.json沿用S00局部字段，完整运行角色由角色服务和rules共同初始化。

正式表中尚未定义的背景设定不由技术默认值冒充。

## 运行状态与存档

运行角色包含随机生成身份、姓名、灵根、境界、基础属性、当前HP/MP、钱包、修为、年龄寿元、位置、背包、装备实例映射、装备槽、已学技能等级、技能槽和服丹日。世界状态包括绝对小时、任务、田地、库存、NPC、价格、战斗、阵法、洞府、仓库、宗门贡献、新闻和已提交操作ID。

普通物品保存总数量，界面按每组99展示组数；装备以唯一实例ID保存，出售实例前须卸下。静态物品ID不与实例ID混用。

存档外层：version/checksum/payload。payload是JSON字符串，checksum为该字符串SHA-256；payload内含version/state/random/sequence。随机流的64位state使用十进制字符串避免JSON精度损失。运行整数读取后规范为整数；价格系数使用整数万分比。

保存采用新修订文件+临时文件重命名，不覆盖旧存档。加载先验证后替换状态；损坏或不支持版本明确失败。不自动迁移未知历史格式。测试存档隔离在user://test_saves，玩家存档在user://saves。

所有操作在状态副本上验证和执行，失败不提交，并恢复随机状态；成功提交后才通知UI。显式operation_id重复时拒绝，已完成任务和战斗等持久状态另有重复结算保护。时间只通过TimeSystem修改。跨系统目标事件由事务内EventBus通知任务模块。

## 2026-11-05：任务实例V2与调查事件
任务静态模板继续保留稳定id及旧name/previous/realm/target/required_item/money/rewards字段供兼容读者使用。新增quest_id/title/quest_type/giver_npc_id/recommended_realm/requirements/objectives/completion_mode/serial。id=quest_id、name=title、previous=requirements.previous_quest_id、realm=requirements.min_realm由配置验证器校验一致，旧target不再承担任务完成判定。rewards为原道具奖励映射，money为原灵石奖励，未改数值。
目标为objective_id/description/objective_type/target_id/target_location_id/required_count/completion_condition/hint；专属选项label/response存于completion_condition。无运行状态写入共享配置。

已接取任务存于state.quests[id]：schema_version=2、quest_id、status、current_objective_id、objectives{objective_id:{status,current_count}}，progress为旧0/1视图兼容缓存，不再作为唯一完成依据。未接取AVAILABLE/LOCKED由接取条件查询推导，不创建假任务实例。

单目标 `ITEM_DELIVERY` 委托可在 `quests.json` 配置 `delivery_dialogue`。复制 `quest_test_collect_001` 时更新任务 ID 和兼容字段、发布者、交付目标的物品/数量/NPC/地点、文案及奖励。可选 `delivery_shop_id` 须引用同一 NPC 和地点的店铺，用于任务面板展示。

对话按 `AVAILABLE`、`ACTIVE`、`READY_TO_TURN_IN`、`COMPLETED` 配置 `line` 和 `options`。选项包含唯一的 `id`、`label`、`response` 及 `kind`。接取阶段须有 `accept`，可交付阶段须有 `delivery`，`reply` 仅返回对话。可选 `follow` 支持 `hide_self` 和 `close`，分别在本轮对话隐藏刚选的选项或本委托的选项，重新交谈时重置。完成阶段只配置问候。配置了此字段的任务由 NPC 对话接取和交付。

激活的交付目标用当前背包数量计算展示进度，上限为所需数量。目标实例的完成计数在原交付事务中更新，完成状态随现有任务实例持久化。对话分支没有新增存档字段。

配置了 `delivery_dialogue` 的单目标收集委托，将目标的 `hint` 显示在任务详情中的独立「获取线索」区块。可选布尔字段 `fail_on_giver_death` 默认沿用发布者死亡导致失败的规则。设为 `false` 时任务保持进行中，交付仍须发布者存活并可交互。
state.tracked_quest_id持久化追踪选择。state.completed_events保存真实调查的选项、完成世界小时和次数，支持先调查后接任务；串行目标仍按前置顺序激活。
世界事件静态表data/world/events.json注册到ContentCatalog.events；当前只有用户授权的妖兽踪迹调查，位置/选项/文案/小时均配置化。

旧外层存档version=1和校验包格式保持兼容；任务局部schema_version区分新旧。加载先校验，再在内存迁移缺少schema_version的任务，不覆盖原文件；具体策略见quest_refactor_review.md。

## 2026-11-07：城镇榜文

`data/towns/announcements.json` 注册为 `ContentCatalog.announcements`。每条以 `id` 作为稳定榜文 ID，必填 `town_id` 和 `category`。可选 `publisher_id`、`location_id`、`created_at`、`expires_at` 和 `quest_id`。日期为 TimeSystem 的绝对游戏小时，发布时间含边界，过期时间起停止接取。省略日期表示常设榜文，常设榜文不计入今日新增。已接取或完成的任务继续按任务状态显示，过期榜文可供查阅。

任务关联榜文的标题、正文、境界、资格、目标、奖励和重复接取规则取自现有任务模板及 QuestSystem。纯展示榜文填写 `title` 和 `description`。传闻和普通告示仅供查阅。接取使用 `accept_announcement` 和榜文 `id`，在原事务内校验城镇、发布日期、期限和任务状态后转给 QuestSystem。榜文刷新只读。

加载后从 `state.quests`、`tracked_quest_id` 和世界时间重新派生榜文状态。青岚镇包含三项既有委托及「清剿山狼」「青灵草征集」两项测试委托，云溪城显示空态。重复任务冷却期间在榜文列表中隐藏。

`completion_mode: BOARD` 表示从关联榜文接取，并以 `claim_announcement` 提交榜文 ID 和当前轮次交付。榜文城镇、轮次和待交付状态通过校验后，复用任务奖励事务。未配置重复的公告栏委托默认一次性。启用 `repeatable` 时须有关联榜文和正整数 `repeat_interval_days`，由公告栏统一管理下一轮接取。目标类型与冷却独立。

公告栏材料委托使用 `BOARD` 和 `ITEM_DELIVERY`，交付目标的 `target_location_id` 须等于榜文的 `town_id`，省略 `completion_condition.npc_id` 并将 `giver_npc_id` 留空。公告栏和任务面板读取同一实时背包进度。每轮交付重新验证并扣除配置数量，沿用原奖励事务和任务实例存档。

可重复任务在原 v2 实例中记录 `round`、`completed_count`、`last_completed_time`、`next_available_time`。本轮 `COMPLETED` 即已发奖，累计完成次数和最近完成时间在开始下一轮时保留。冷却按 TimeSystem 的绝对游戏秒和每游戏日时数计算。旧档缺少新增字段仍可加载，读取不发奖。

击杀目标沿用 `KILL_ENEMY`。胜利事件携带 `target`、`location`、`count` 和 `battle_id`，任务核对当前胜利战斗并以可选 `last_battle_id` 防止重复计数。现行战斗为 1 对 1，正式事件的 `count` 为 1。

## 2026-11-05：战斗结算报告
新增可选state.battle_report，含id/confirmed/result/location/return_location/monster/turns/money/drops/growth/hp/mp/background/log。growth为name/realm/type/gain/current/target的展示记录；background只保存结算时player与battle快照。报告在原结算事务内写入，确认只修改confirmed；不是待领取奖励。旧档没有该字段可正常加载，新档持久化标记，详情见ui_battle_result_review.md。

## 2026-11-05：店铺首页展示配置
shops新增shop_type/description/environment/announcement字符串，只供首页展示，不参与价格、补货或库存计算。店内人物沿用shop.npc_id，并支持实际NPC已有shop_id的过滤；没有新增运行位置或存档字段。

## 2026-11-05：客栈配置与入住请求
inns表位于data/towns/inns.json，常规唯一id数组，注册ContentCatalog。字段为name/location/inn_type/description/scene_description/owner_npc_id/available_rooms/menu_items/rumor_source/npc_list/observation。available_rooms的id/name/available/action，当前仅原inn行为；价格与天数继续读取rules.inn_cost/inn_days。空NPC引用与列表表示没有正式店内人物，不生成虚假NPC。
inn_stay请求inn/room，复用原inn与TimeSystem，在统一事务记录operation_id防重。没有新增存档版本或持久状态；餐食字段当前为空，只作明确占位，不定义增益。

## 2026-11-05：战斗展示事件
battle 新增可选 events 数组，原 action 整轮结算过程中按真实速度顺序记录。每项含 actor/kind/label/before/after/critical/turn，before/after 以单位 ID 索引 hp/mp/statuses/defending；statuses 为原状态副本。数组仅保存最近一轮展示记录，不是待执行动作或奖励。旧档无此字段照常加载，加载不触发回放或结算。结算报告 background 随原 battle 快照保存；外层存档版本、伤害规则与随机流格式不变。

## 2026-11-05：战斗日志语义记录
battle 新增可选 log_entries 数组，原 log 纯文字保留兼容。记录 type：round(turn)、action(actor/kind/label)、hp/mp(target/amount/before/after/critical/source_spell)、status(target/id/turns/change)、defend(target)、result(result)、legacy/system(text)。amount 是真实 after-before；critical 仅真实伤害暴击，source_spell 为当次真实法术显示名；change 为 apply/refresh/tick/expire。记录不含颜色或 BBCode，不是待执行动作。
结果记录写入原 battle_report.background.battle.log_entries。旧档可缺字段，旧历史在继续行动时逐条包装 legacy，不重算旧战斗。加载校验结构及数字关系，不更改外层版本。avoidance(target/outcome=dodge|block) 为格式化器已支持的表现类型，当前正式战斗没有生产者，不冒充已实现机制。详见 ui_battle_log_review.md。

## 2026-11-05：在线时间和闭关状态
新增data/balance/time_rules.json，ContentCatalog.time_rules：game_seconds_per_real_second=60、idle_pause_seconds=300、idle_pause_enabled=true、natural_day=10、practice_day=20、retreat_day=40，均由用户确认；数值正整数及开关类型校验。
state.hours继续为绝对整小时，time_seconds为0..3599的不足一小时秒数，唯一由TimeSystem推进；cultivation_fraction为每个修为单位的剩余分子，分母hours_day×3600×10000，非负且严格小于分母。到当前境界修为上限清余数，但不削减旧存档已有整数溢出。time_paused和idle_pause_enabled为可选布尔开关。旧档缺字段按默认读取，不改原世界日期、ID、外层存档版本。
可选state.retreat_report：id/start/end/requested/elapsed/gain/after/age/realm/interrupted/reason/groups。时间单位为游戏秒，groups含cultivation/npc/sect/economy/world/quest的实际文字数组；报告无待领取收益，不可通过查看重领。
retreat仍传days，新增retreat_target按真实瓶颈/效率求时间；UI请求附稳定_request_id，由main传入原操作防重接口。自动advance_realtime是单一在线驱动的同步事务，不写每秒operation记录、不读取现实时间补离线。正式任务格式未变，完整限制及验证见world_time_review.md。

## 2026-11-05：暂停字段废止
用户要求时间不可暂停。time_rules不再包含idle_pause_seconds/idle_pause_enabled。新状态不写time_paused/idle_pause_enabled，旧档若存在布尔字段则验证后移除，不能影响时钟。time_pause/idle_pause请求不再支持。秒余数、修为余数、报告及存档外层版本不变；实时推进不再检查战斗或UI门控，只有未创建角色/原寿元终局不继续模拟，忙碌事务由原同步服务防重入。退出仍无离线计算。

## 2026-11-06：法体路线与根基温养

- `data/cultivation/progression.json` 保存成长和倾向参数，功法定义新增 `cultivation_route`，值为 `qi` 或 `body`。原功法 ID 和被动数值保留。
- `player.growth` 包含 `body_level`、`body_cultivation`、`body_fraction`、`attributes`、`nurture_fraction`、`focus`。凡体层级为 0，通脉为 1–9。属性键为 `qi_sea`、`meridians`、`bones`、`physique`。温养余数及倾向按 `qi/body` 分开。炼体修为余数使用原修为分母，温养余数以 3600000 分之一点为单位。
- 旧档缺少 `growth` 时在内存初始化，原法修层级与修为余数保留，四项上限按已有对应路线层级推导。已存在的成长数据须先验证再替换状态。外层版本仍为 1，旧档文件原样保留。
- `practice/retreat/retreat_target/promote` 支持可选 `route`（默认 `qi`），`cultivation_focus` 要求 `route/focus`。闭关报告新增可选 `route`，旧报告默认法修；`after/realm/gain` 对应报告路线。UI 路线标签属于页面选择，存档只记录角色成长及各路线倾向。

## 2026-11-06：法体九阶和灵气试算

- `player.realm` 为 1–81，`player.growth.body_level` 为 0–81，原 1–9 以及法修 10 保持含义；层号为 `(level−1)%9+1`。境界阈值、寿元、材料及战斗成长配置见 `data/cultivation/realm_tiers.json`，原炼气配置继续有效。
- 可选 `player.growth.breakthrough_quality` 按 `qi/body` 存 `base/middle/high`，仅在首次成功筑基或锻骨时记录。旧档不补历史品质。寿元取现值和成功突破的阶位寿元较高者。
- `player.traits` 存灵根品质 `root_quality` 与六维 `aptitudes`，`player.blood` 存当前独立气血。旧档缺字段时补普通品质、六维各 20、当前气血 80。根基衍生上限按配置重算，不自动补满当前资源。字段有类型和范围校验，外层版本仍为 1。
- 灵气试算参数存于 `data/cultivation/spirit_flow.json`，开发者可另存本地覆盖 `user://spirit_flow_trial.json`。模拟储量和能量账本只存在试算内存，不写角色存档。

## 2026-11-06：正式灵气储量

- `spirit_flow.json` 注册为正式配置，`locations` 用稳定地点 ID 映射环境，F1 本地覆盖仍只供独立试算。时间配置只负责时钟速度。旧功法修炼加成、环境倍率、阵法倍率和旧倾向倍率不再参与收益。
- 外层存档版本仍为 1。新增 `state.spirit.pools[location_id]` 的 `stock/reference/pending/surrounding`，分别是可提取储量、小时内引气参考储量、等待回池的余能、周围储量；数量使用 1 灵气点 = 36000000 整数量子。首页浓度使用 `stock+pending`。
- `state.spirit.progress[qi/body]` 的 `cultivation/nurture` 分别是两种成长尚未凑整的灵气量，`loss_carry/split_carry` 是万分比分摊余量；`hour_attributes` 固定本小时的根基处理能力。旧档缺 `spirit` 时按正式配置生成储量并换算三个旧修炼余量字段，保留已结算进度，不补离线收益。
- `release_spirit_stones` 接收 `count` 正整数，提交前验证余额和容量，沿用操作 ID 防重。闭关报告新增可选 `spirit_ledger`，包含 `processed/loss/cultivation/nurture/returned`，后四项之和等于处理量。旧报告可缺字段。

## 2026-11-06：八系试学法术

- `spells` 表合并三阶段试学定义。稳定 ID 对应元素、灵力、冷却、目标、试学标记和等级效果。等级数组从 Lv.1 起逐项覆盖，旧定义继续使用原字段。
- 外层存档版本沿用 1。`player.spells[id]` 仍为等级，按对应定义上限校验。`player.spell_mastery[id]` 可选，保存当前级内余量。达到上限时余量为零。旧档缺试学 ID 时在内存补授 Lv.1；已有值照读。
- `player.spell_affixes[id][slot]` 保存已确认的词条 ID，槽号为字符串 `0` 或 `1`。`player.spell_affix_pending` 保存单个待确认结果，含 `id/slot/candidates/token`。没有结果时字段可省略。`random.spell_affix` 保存独立随机状态，旧档缺字段时从既存战斗随机状态派生。
- `battle.status` 仍保存临时战斗状态，新增状态可带 `layers/attack/applied_round/applied_actor`，护盾另存 `amount/maximum/effects`。旧灼烧、潮湿和护体记录可读。保存和读取均不执行新的行动或发放收益。

## 2026-11-06：拍卖与神识

- `state.auctions[auction_id]` 可选。保留 `cycle/step/index/phase`、入场时固定的 `terms`、已暂扣的 `leader/price`、询价、限制、参与者情绪和使用记录、最近动态和当期成交。高价仍有效时所占灵石已从各自钱包扣除。打开界面、保存和读取均不重新入场或结算。场所 ID、地点和已引用物品、NPC ID 保持稳定。
- `state.auction_accounts[auction_id]` 存累计 `fees/sales`。现有 `state.npcs[id].relations` 以人物 ID 为键，新增数值关系分在 -100 至 100。NPC 可选 `inventory` 和 `equipment_instances` 使用现有物品 ID 与实例格式。旧档可省略这些字段。
- `player.growth.attributes`、`state.spirit.hour_attributes` 和 `state.npcs[id].attributes` 可含 `spirit_sea/soul`。玩家和 NPC 在旧档读取时只补缺项，默认值与成长见 [拍卖专项](auction_review.md#识海神魂和威慑)。
- `random.auction` 以十进制字符串保存独立随机流，旧档缺字段时由现有随机状态派生。外层存档版本沿用 1。
- `state.auctions[auction_id].actors[npc_id].bids` 可选，记录 NPC 本件拍品的实际出价次数，用于后续选人权重。旧档缺项按零处理。停在第一次或第二次询价的场次可继续使用原步骤号和暂扣记录。

## 2026-11-07：战斗玩家输入点

- `state.battle.round_order` 是可选的本轮速度顺序，只接受 `["player","enemy"]` 或 `["enemy","player"]`。有效活动战斗保存在等待玩家输入的位置。怪物排第一时，本轮怪物已结算且 `turn` 已增加。玩家排第一时，下一轮将在玩家指令后增加 `turn`。
- 旧准备档维持准备状态。旧活动档缺字段时，既有 `turn` 代表已完成的轮数，从下一轮续接。已存在顺序的档案载入后直接等待玩家，先手伤害和奖励不会重复结算。
- `battle.events` 保存最近一次已提交的行动批次，可跨相邻回合。每个事件的 `turn` 标识其实际所属回合，外层存档版本仍为 1。


## NPC 人物档案（2026-11-07）

- 原型 NPC 的 `realm: 0` 表示凡人。月度模拟跳过其修炼。读入旧档时，原型已改为凡人的 NPC 同步为境界 0、修为 0，保留其他运行状态。

- `data/world/prototype.json` 的 NPC 可配置 `greeting` 与只读 `profile`。档案的 `spells` 引用现有法术 ID，`contacts` 以 NPC ID 映射到人物关系文案，`history` 是按顺序展示的时间标签与经历文案。
- 「查看」使用静态档案加运行时身份、年龄、已公开境界、识海、神魂和玩家关系。已装功法、装备和气运参与 NPC 属性计算，法术清单用于展示。缺少玩家关系记录时显示「陌生」。
- 新 NPC `npc_lin_zhaoxi` 从青岚镇加入现有模拟。版本 1 旧档缺少该 NPC 时，读档按已过年数补入其初始状态，保留存档中已有 NPC 的状态。静态档案与问候存放在配置中。

- NPC 档案的 `base` 定义基础战斗值，`foundation` 定义初始根基，`resources` 定义当前资源默认值。`innate_fortune` 和 `acquired_fortune` 条目通过 `bonuses` 加入统一属性计算，暴击、暴伤、闪避以比例表示。运行时根基覆盖对应默认根基。
- NPC 的 `profile.loadout` 是新档及旧档缺项时的装配默认值。`state.npcs[id].loadout` 记录已装功法 ID 到等级、装备部位到装备 ID 的映射。装配变更通过 `OperationService.set_npc_loadout` 验证后提交，引用装备定义，与拍卖物品实例独立。档案读取运行装配，和统一计算器的最终值及明细保持同步。当前 NPC 没有自动换装或切磋入口。
- `profile.rank` 和 `profile.personality` 是可选的展示字段。界面将数值关系按正、零、负显示为「友善」「陌生」「冷淡」，存档保留原始分数。青岚镇新增 `npc_shen_yunzhao`，版本 1 旧档按现有补录流程初始化缺失人物。NPC 寿元取原型基础寿元与当前境界寿元中较高者。

## 玩家天赋与气运（2026-11-07）

- 版本 1 玩家可含 `state.player.fortunes`，以正式 ID 为键，记录 `obtained_at`（TimeSystem 绝对秒）及 `source`（来源文本）。限时记录额外含 `expires_at`（同一时间轴）。永久、限时、战斗限定及一次性按配置判断。
- `state.player.fortune_wins` 为可选整数，范围 0–50，达到 50 与 `battle_veteran` 同一事务写入。旧档缺项按空记录和零胜场读取，历史事件不追补。
- `state.player.fortune_progress` 为可选的规则 ID 到整数进度映射；连续胜利在战败或逃跑时归零。活动战斗可含 `state.battle.fortune_triggers`，保存有限次触发标记。修炼路线余量可含 `fortune_carry`（0–99），缺项按零读取。
- 定义、加成和入口见 [玩家天赋与气运](systems/player_fortunes.md)。

## NPC 编辑器初始定义（2026-11-07）

`data/world/npc_overrides.json` 是可选的按稳定 NPC ID 索引的初始定义覆盖表。定义经 ContentCatalog 读取和校验，用于新档名册和开发构建中的显式调试导入。编辑版 NPC 随版本 1 存档保留自身档案、实例、装配、学习等级和永久气运记录。调试导入的可选 `introduced_year` 记录导入所在世界年，用于从配置年龄继续增长。旧档按原路径恢复。字段和边界见 [NPC 编辑器](systems/npc_editor.md)。
## 本机显示偏好

- `user://display_preferences.cfg` 的 `[display]` 保存画面亮度百分比（55–100，默认 100），由主界面应用到整个游戏画面，与角色存档分开。

