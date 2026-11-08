# 系统索引

核对：2026-11-06，源码/路由/配置与历史记录交叉检查，未重跑游戏。实现状态定义见根规范；PLAYABLE只指下列原型范围，不是整阶段COMPLETE。
设计依据统一由 [decisions.md](decisions.md)及原中文设计提供：历史授权记录沿用APPROVED范围，原型参数待最终验收；无依据扩展为UNCONFIRMED/PROPOSED，不因代码存在推定已批准。

所有代码路径相对项目根目录；依赖列使用系统ID。公共请求及状态所有权见 [runtime_flow](systems/runtime_flow.md)。

| ID / 系统职责 | 状态与边界 | 核心代码 | 机制/验收文档 | 直接依赖 |
| --- | --- | --- | --- | --- |
| SYS-CORE 操作/事务入口 | PLAYABLE：副本提交、防重与失败恢复 | `autoload/game_manager.gd`、`core/operation_service.gd`、`core/event_bus.gd` | [运行机制](systems/runtime_flow.md) | SYS-DATA、SYS-RNG及目标玩法 |
| SYS-DATA 配置加载/引用验证 | PLAYABLE：现有JSON表 | `core/data_repository.gd`、`core/content_catalog.gd` | [数据契约](data_schema.md) | 无 |
| SYS-RNG 可复现随机流 | PLAYABLE：battle/loot/exploration/world | `core/random_service.gd` | [运行机制](systems/runtime_flow.md) | 无 |
| SYS-TIME 唯一世界时间 | PLAYABLE：在线/行动时间、月界结算 | `core/time_system.gd`、`core/time_report.gd` | [时间专项](world_time_review.md)，末尾取消暂停覆盖前文 | SYS-CULT、SYS-NPC、SYS-SHOP |
| SYS-CULT 修炼与突破 | PLAYABLE：法体九阶、真实地点灵气、四项温养、双路线闭关报告 | `gameplay/cultivation/cultivation_system.gd`、`gameplay/cultivation/spirit_cultivation.gd` | [V3.1 迁移记录](spirit_flow_v3_1_review.md)、[时间专项](world_time_review.md) | SYS-CHAR、SYS-DATA、SYS-RNG；正式修炼由SYS-TIME调用累计 |
| SYS-CHAR 角色与属性 | PLAYABLE：出生、基础/装备/功法加成、六维资质；玩家气运 108 条已配置，部分效果和来源已接通 | `gameplay/character/character_system.gd` | [角色专项](ui_character_review.md)、[玩家天赋与气运](systems/player_fortunes.md)、[逐效果依赖](systems/fortune_dependencies.md)、[数据契约](data_schema.md) | SYS-DATA |
| SYS-TECH 功法 | PLAYABLE：学习/3槽/升级；10格不是全部解锁 | `core/operation_service.gd`、`gameplay/character/character_system.gd`、`ui/technique/technique_page.gd` | [功法专项](ui_technique_review.md) | SYS-INV、SYS-CHAR |
| SYS-SPELL 法术 | PLAYABLE：原学习和装配、32 个试学法术、五级熟练度、共享参悟池、单挑施放 | `core/operation_service.gd`、`gameplay/battle/spell_progression.gd`、`gameplay/battle/spell_effect_resolver.gd`、`ui/technique/spell_page.tscn` | [主动法术专项](spell_trials_review.md)、[功法专项](ui_technique_review.md) | SYS-INV、SYS-TIME、SYS-BATTLE |
| SYS-BATTLE 回合制战斗 | PARTIAL：1对1五指令可玩，多人/自动未实现 | `gameplay/battle/battle_system.gd`、`core/operation_service.gd` | [战斗](ui_battle_review.md)、[结果](ui_battle_result_review.md)、[表现](ui_battle_animation_review.md)、[日志](ui_battle_log_review.md)、[顺序条](ui_turn_order_review.md) | SYS-CHAR、SYS-INV、SYS-RNG、SYS-TIME、SYS-QUEST |
| SYS-INV 背包/道具/装备 | PLAYABLE：数量、唯一实例、使用/学习、八部位装卸、一次性领取炼气套装 | `gameplay/inventory/inventory_system.gd`、`core/operation_service.gd` | [背包专项](ui_inventory_review.md) | SYS-DATA、SYS-CHAR |
| SYS-SHOP 经济/商店 | PLAYABLE：交易、库存、商人财富、月度价格/补货 | `gameplay/shop/shop_system.gd`、`world/world_simulator.gd` | [交易页](ui_shop_review.md)、[店铺首页](ui_shop_home_review.md) | SYS-INV、SYS-NPC、SYS-RNG；SYS-TIME调度 |
| SYS-AUCTION 拍卖会 | PLAYABLE：云溪城试点、轮次竞拍、互动、落槌、关系与物品持久化 | `gameplay/auction/auction_system.gd`、`ui/auction/auction_page.tscn` | [拍卖与神识专项](auction_review.md) | SYS-TIME、SYS-NPC、SYS-CHAR、SYS-INV、SYS-RNG、SYS-SAVE |
| SYS-TIANJI 天机楼 | SCAFFOLD（2026-11-07）：云溪城建筑入口、三列总览、分类切换与空态；正式执事、情报、线索、榜单和秘闻待接入 | `ui/tianji/tianji_page.tscn`、`ui/tianji/tianji_page.gd`、`ui/main/home_view.gd` | — | SYS-MAP、SYS-CORE（只读玩家灵石） |
| SYS-QUEST 任务/追踪/调查 | PLAYABLE：三项原委托、药铺收集测试委托、七目标类型、持有/交付/报告、迁移 | `gameplay/quest/quest_system.gd`、`gameplay/quest/quest_validation.gd`、`core/event_bus.gd` | [任务机制](quest_refactor_review.md)、[数据契约](data_schema.md)、[页面](ui_task_review.md) | SYS-INV、SYS-DATA、NPC状态；SYS-CORE发布事件 |
| SYS-BOARD 城镇公告栏 | PLAYABLE：三项既有委托及重复击杀/材料交付测试委托、接取/交付、地图/任务跳转、云溪城空态 | `ui/quest/town_board.tscn`、`gameplay/quest/town_announcements.gd`、`data/towns/announcements.json` | [榜文数据契约](data_schema.md#2026-11-07城镇榜文)、[清剿山狼验收](quest_kill_review.md) | SYS-QUEST、SYS-TIME、SYS-MAP、SYS-DATA |
| SYS-NPC NPC模拟/交互 | PARTIAL：月度成长/迁移/死亡、交谈/任务/交易、人物档案与装配属性计算；其他互动占位 | `world/world_simulator.gd`、`world/npc_interaction.gd`、`ui/npc/npc_interaction.gd`、`ui/npc/npc_profile.tscn` | [交互专项](ui_npc_interaction_review.md)、[时间专项](world_time_review.md) | SYS-RNG、SYS-DATA、SYS-QUEST；SYS-TIME调度 |
| SYS-SECT 宗门 | PARTIAL：加入/捐献/贡献持久化、青岳宗山门通行和驻地四区界面；受限区域仅可预览 | `core/operation_service.gd`、`ui/sect/sect_page.gd`、`ui/sect/sect_residence.tscn` | [宗门专项](ui_sect_review.md) | SYS-CORE、SYS-DATA、SYS-TIME |
| SYS-CAVE 洞府/灵田 | PLAYABLE：四田/仓库/阵法/Lv2原型 | `gameplay/cave/cave_system.gd`、`core/operation_service.gd` | [洞府专项](ui_cave_review.md) | SYS-INV、SYS-TIME |
| SYS-ALCHEMY 炼丹 | PLAYABLE：两丹方真实消耗/产出；无独立AlchemySystem | `gameplay/cave/cave_system.gd`的craft | [洞府专项](ui_cave_review.md)、[数据契约](data_schema.md) | SYS-CAVE、SYS-INV、SYS-TIME |
| SYS-MAP 地图/探索 | PLAYABLE：四地点、事件/调查/挑战；不是完整开放世界 | `core/operation_service.gd`、`ui/world/world_page.gd`、`ui/world/map_routes.gd` | [地图](ui_world_review.md)、[地点首页](ui_location_home_review.md)、[任务机制](quest_refactor_review.md) | SYS-TIME、SYS-RNG、SYS-BATTLE、SYS-QUEST |
| SYS-INN 客栈 | PLAYABLE：原住宿闭环；房型/用膳扩展占位 | `core/operation_service.gd`、`ui/inn/inn_page.gd` | [客栈专项](ui_inn_review.md) | SYS-TIME、SYS-CHAR、SYS-DATA |
| SYS-SAVE 存档 | PLAYABLE：版本/校验/新修订/随机恢复及局部迁移 | `core/save_service.gd`、`core/operation_service.gd` | [数据契约](data_schema.md)、[运行机制](systems/runtime_flow.md) | SYS-CORE、SYS-RNG、SYS-QUEST |
| SYS-UI 页面与路由 | PARTIAL：真实入口及已确认模板；存在占位和视觉待审 | `ui/main/main.gd`、`ui/main/home_view.tscn` | 下列模板导航及各UI报告 | SYS-CORE与只读展示接口 |
| SYS-DEBUG 日志/调试 | PARTIAL：日志/F1展示；开发构建 F12 玩家基础属性与持有灵石 | `autoload/app_log.gd`、`ui/main/main.gd`、`ui/main/player_debug_panel.gd` | [运行机制](systems/runtime_flow.md) | SYS-CORE、SYS-CHAR |
| SYS-ARTIFACT 独立法宝玩法 | SCAFFOLD：8 件法宝配置已加载，独立法宝页占位，战斗与祭炼未接入 | `ui/character/character_page.tscn` | [角色专项](ui_character_review.md) | 扩展依赖未定 |
| SYS-SECT-WORLD 宗门外交/战争发展 | NOT_STARTED | 未建立 | 仅总设计规划，不建空机制文档 | 未确定 |
| SYS-POPULATION 后代/人口演变 | NOT_STARTED | 未建立 | 仅总设计规划 | 未确定 |
| SYS-EVENT-QUEUE 精确日期世界事件队列 | NOT_STARTED：现有月界及单次调查不等于此系统 | 未建立 | [时间专项边界](world_time_review.md) | 未确定 |

## 已确认模板导航
以decisions授权范围为准；以下已有文件应保护，不自行再生成未确认页面。
- 当前地点首页：`ui/main/home_view.tscn`；任务：`ui/quest/task_page.tscn`。
- 地图：`ui/world/world_map.tscn`；历史地点与NPC模板保留于`ui/world/location_scene.tscn`、`ui/world/npc_dialogue.tscn`，当前统一NPC入口为`ui/npc/npc_interaction.tscn`，不要据旧文件名恢复旧路由。
- 商店交易/首页：`ui/shop/shop_page.tscn`、`ui/shop/shop_home.tscn`；客栈：`ui/inn/inn_page.tscn`。
- 功法、角色、洞府、背包、宗门分别在`ui/technique/technique_page.tscn`、`ui/character/character_page.tscn`、`ui/cave/cave_page.tscn`、`ui/inventory/inventory_page.tscn`、`ui/sect/sect_page.tscn`。
- 战斗与报告：`ui/battle/battle_page.tscn`、`ui/battle/battle_result_overlay.tscn`、`ui/cave/retreat_report.tscn`；相关子模板按各专项报告定位。

## 验证入口
- `tests/run_all.ps1 -Godot '<本机Godot控制台可执行文件绝对路径>'`：导入、基础、玩法、回归、边界、任务、世界时间、时间基线、短无头启动；只在任务风险需要时运行。
- 业务：`tests/game_tests.gd`、`tests/regression_tests.gd`、`tests/boundary_tests.gd`。
- 任务：`tests/quest_refactor_tests.gd`；公告栏：`tests/town_board_tests.gd`；时间：`tests/world_time_tests.gd`、`tests/time_system_baseline.gd`。
- 法体成长及存档：`tests/cultivation_growth_tests.gd`。
- 九阶突破与灵气试算：`tests/realm_tier_tests.gd`、`tests/spirit_flow_tests.gd`。
- 正式灵气池、分账与旧档迁移：`tests/spirit_live_tests.gd`。
- UI按专项报告选对应preview/test脚本；结算为`tests/battle_result_tests.gd`，洞府入口为`tests/cave_entry_tests.gd`。不要假定run_all覆盖UI。
- `tests/world_ui_preview.gd`覆盖当前地图、地点首页、NPC弹窗和任务/探索联动，可用Godot无头运行。地图细节与截图参考`tests/map_layout_preview.gd`，时间页面参考`tests/world_time_ui_preview.gd`。

- SYS-NPC-EDITOR（PARTIAL）位于 `addons/npc_editor` 与 `core/npc_definitions.gd`，依赖 SYS-DATA、SYS-NPC、SYS-CHAR、SYS-SAVE。初始定义、资源装配和验证范围见 [NPC 编辑器](systems/npc_editor.md)。
