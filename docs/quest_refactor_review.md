# 任务规范化与现有沙盒闭环验收（2026-11-05）

## 一、范围与验收结论
本轮用户先要求按任务规范与沙盒规范重构最小可玩版本，随后明确选择“先完成现有内容闭环”，将六区域、新宗门玩法等缺少正式内容部分延后。
**PASS：本轮确认的现有任务闭环与自由通行改造。**
**PARTIAL：两份规范的完整远期沙盒内容**。没有宣称六个探索区域、宗门俸禄、宗门贡献兑换、完整NPC关系/世界事件链已经实现。

## 二、审查发现与最小方案
旧QuestSystem仅保存ACTIVE/COMPLETED及progress=0/1，普通talk广播NPC ID即可完成首任务；claim不校验发布者位置；描述“准备好”不可检测；任务页与首页分别拼接提示；云溪城被狼首任务锁住，狼首挑战要求接取任务；NPC月度模拟也等待云溪城到访。
改为原事务内统一任务目标服务，复用EventBus、Inventory、Battle、TimeSystem和已有UI模板，不增加Autoload或平行任务管理器。

## 三、实际实现
1. 三个原任务保留稳定ID、接取资格和奖励，改用静态多目标模板。首任务为“青岚山妖兽异动”，指定询问→持有凝血散→调查踪迹→专属报告，奖励仍30灵石与凝血散1。
2. 统一支持TALK_OPTION、VISIT_LOCATION、ITEM_POSSESSION、ITEM_DELIVERY、KILL_ENEMY、COMPLETE_EVENT、REPORT_NPC。串行逐阶段激活，serial=false时可并行；事件不能在同一串行任务中重复跳过阶段。
3. status/current_objective_id/current_count和目标status只存任务实例；AVAILABLE/LOCKED查询派生。支持全部要求的状态枚举；FAILED用于主动放弃或发布者死亡。未定义期限，因此不伪造自动EXPIRED规则。
4. TALK_OPTION与REPORT_NPC只由当前阶段的指定npc_option触发；普通talk不发布任务完成事件。NPC界面生成接取、询问、进展、交付、报告选项，不合阶段的选项服务端也拒绝。
5. 持有目标实时检查当前背包。任意合法来源满足，预购可用，不消耗；数量下降会取消未交付任务的持有满足状态，补齐后恢复。交付扣物品、任务计数和奖励在原候选状态事务内结算，失败不提交。
6. 击杀只在Battle有效胜利结算发布，失败/逃跑不触发。VISIT_LOCATION仅真实移动到达发布，点击当前地点不刷次数。
7. 新增event_beast_tracks静态调查事件。青岚山外围有真实入口，展示足迹场景文字，选择“辨认足迹并记录方向”，按配置消耗4游戏小时，由TimeSystem推进后发出明确事件。不是任务页“直接完成”按钮。使用现有探索4小时作为最小调查耗时，不新增奖励。
8. completed_events保存实际调查选项、时间和次数。允许先调查再接委托，但接取时仍显示第一阶段；前置询问/持有完成后才利用已获得线索。
9. 任务页显示真实阶段、每项目标/进度/指引、NPC及地点、奖励和追踪/暂放弃；首页追踪使用同一current()查询。已故NPC明确不可接触，离开指定地点提示当前位置和需返回目标地点；不会伪造同位置交谈。
10. 完成反馈列出真实灵石和道具，并从实际接取条件查询下一项可接委托，同时提示可自由探索/修炼。
11. 四个已有地点均不再依赖主线通行，云溪城初始低境界可访问；狼首挑战不要求接任务，但保留地点和危险提示，怪物不随玩家缩放。任务正式资格仍保留。
12. 现有NPC/价格月度模拟从新游戏起随TimeSystem执行，不再等待玩家到访云溪城；使用原有成长/迁移/经济数值。mvp1标志仍保留供既有设施和宗门资格使用，没有顺带改其规则。

## 四、存档兼容
外层存档version=1和校验/新修订写入方式不变；任务实例schema_version=2。
- 新增tracked_quest_id、completed_events，旧存档缺失时在内存补空值。
- 旧COMPLETED任务迁移为已完成目标并保留领取状态，不发任何补偿或重复奖励。
- 旧首任务ACTIVE不论progress=0/1，都从明确的询问阶段开始，因为普通交谈记录不能证明做过调查；玩家资源、时间、其他任务和其他系统不重置。
- 旧除狼/狼首任务progress=1保留已有击杀证据，后续交付/报告按新规则进行。
- 新实例、计数、阶段ID、事件记录先校验后迁移。未知任务/物品/NPC/地点/事件引用在加载或启动时报告错误。
- 读取不覆盖旧文件；仅玩家主动保存才产生新修订，原存档和备份保留。
迁移涉及行为变化已明确记录，不能将旧版“普通交谈后可领奖”的行为继续视为合法新流程。

## 五、修改文件
业务与配置：
- gameplay/quest/quest_system.gd：统一状态、目标、事件、交付、对话选项、追踪及迁移。
- gameplay/quest/quest_validation.gd（新增）：模板/引用与存档任务验证。
- core/operation_service.gd：有效行为事件、专属选项、调查事务、存读校验迁移、普通区域自由通行。
- core/event_bus.gd：原通知参数支持带类型/目标/地点/选项的事件对象。
- core/content_catalog.gd：注册事件表并进行任务引用校验。
- core/time_system.gd：现有月度世界模拟不再由玩家到访里程碑启动。
- data/quests/quests.json；data/world/events.json（新增）。
UI：ui/quest/task_page.gd、task_page.tscn；ui/world/world_page.gd、npc_dialogue.tscn；ui/main/main.gd、home_view.gd。
测试：新增tests/quest_refactor_tests.gd；调整game_tests.gd、regression_tests.gd、task_ui_preview.gd、world_ui_preview.gd及run_all.ps1。
文档：本报告、data_schema.md、content_changelog.md、decisions.md、development_plan.md。相关实际截图位于docs/screenshots。
兼容字段name/id/realm/previous等仍在同一配置保留，加载校验与新title/quest_id/requirements一致；没有建立两套独立任务数据源。

## 六、逐项验收与真实结果
正常权限Godot4.5 Mono，编辑器导入和无头启动通过，无程序集弹窗或GDScript错误。

| 用户任务验收项 | 结果与证据 |
|---|---|
| 1 接取即显示第一目标 | PASS，ask_disturbance激活 |
| 2 普通交谈不完成指定选项 | PASS，核心与NPC UI均验证 |
| 3 指定询问推进 | PASS，npc_option真实事务 |
| 4 初始凝血散自动满足 | PASS，不消耗 |
| 5 预购凝血散可用 | PASS，真实购买后再接取 |
| 6 未调查不能报告 | PASS，提前选项及通用claim均拒绝 |
| 7 调查完成进入交付流程 | PASS，4小时真实推进及READY_TO_TURN_IN |
| 8 报告正确发奖励 | PASS，30灵石及凝血散1 |
| 9 重复报告不重复奖励 | PASS，失败无状态变化 |
| 10 无关区域不自动完成 | PASS；重复当前位置不算到达次数 |
| 11 中途存读阶段恢复 | PASS，内存迁移与隔离磁盘保存加载 |
| 12 主线不阻止普通探索 | PASS，未接任务/低境界可进云溪城 |
| 13 详情/首页追踪/NPC一致 | PASS，统一当前目标，UI实测同一hint |
| 14 缺失引用明确报错 | PASS，分别测试NPC、地点、物品、事件与非法阶段ID |

检查计数：
- run_tests：19通过。
- game_tests：63通过。
- regression_tests：183通过（含3种种子的完整正常任务→战斗→经济→成长流程）。
- boundary_tests：27通过。
- quest_refactor_tests：45通过。
- task_ui_preview：38通过。
- world_ui_preview：46通过。
- home_layout_preview：76通过。
**共497项通过，0失败。** 基础回归由原280增至292，是加入实际调查操作后的更多断言；没有删除原失败测试或放宽奖励、防重复、存读断言。旧“普通交谈完成首任务”和“云溪城由主线解锁”断言已按本轮明确新规则改为相反行为测试。

已实际查看任务/NPC/调查截图、1920×1080及1280×720画面，沿用既有矩形布局；长目标列表使用原详情滚动区，底部操作可见。
主要证据：screenshots/task_ready_1920x1080.png、npc_dialogue_1920x1080.png、investigation_event_1920x1080.png、task_1280x720.png。

## 七、限制和下一步
用户明确延期的六区域、新宗门任务/兑换/职位/俸禄、NPC关系玩法及复杂世界事件链均未新增。现有仅四地点，其中一处探索区；不能称作完整六探索区域版。
FAILED/EXPIRED状态接口和展示可识别，但没有正式任务截止日期，未制作自动过期或周期重发系统。NPC离开原交付地点时提示并等待其返回，未新增追踪NPC或替代领奖人规则；死亡则任务失败。
静态配置验证覆盖本轮任务引用；没有重写所有旧表验证器或世界架构。
英文game_design/content_v0_1/combat_balance仍缺失，已读取项目中文原文、data_schema及批准记录。当前无Git仓库，未提交。建议提交说明：feat: normalize quest objectives and enable sandbox travel。
下一步建议：先体验新手四阶段与自由探索，再单独确认下一批地图、宗门或世界事件的正式内容；不自动扩展。
