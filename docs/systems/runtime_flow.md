# 核心运行与跨系统调用

核对：2026-11-06。本页描述当前源码事实，不创设新玩法。设计依据见 [决策记录](../decisions.md)，精确字段以 [数据契约](../data_schema.md)及源码为准。本轮未运行游戏。

## 启动与所有权
- `project.godot`注册AppLog、GameManager，主场景`ui/main/main.tscn`。
- GameManager._ready加载出生配置及ContentCatalog表，成功后configure操作服务。ContentCatalog.PATHS是当前表注册入口；使用UTF-8 JSON。
- OperationService._state拥有完整运行状态；snapshot()返回深拷贝。configure复制配置，GameManager为UI请求/保存/加载入口。
- 各玩法服务处理传入的候选状态；UI读取快照/展示接口并请求命令，不应持有或修改内部可变状态。
- 此架构已将部分旅行、探索、功法装配、洞府设施和宗门操作放在OperationService；不是已有独立宗门/探索/炼丹管理器。本轮记录，不为“理想结构”新增空服务。

## 命令提交
公共入口：GameManager.request(action, args = {}, operation_id = "") → OperationService.request，返回success/message及成功进入事务路径时的operation_id。
1. 检查角色存在、忙碌、寿元与重复ID。
2. 未提供ID时生成序列ID；复制_state并保存随机流。
3. _execute路由目标系统；成功时刷新任务，记录操作ID并提交规范化状态；失败不提交候选状态并恢复随机流。
4. 提交后发changed信号，GameManager记录日志，UI刷新。
失败不会提交候选游戏资源；序号可能已递增，不承诺所有内部字段逐位回滚。
显式相同operation_id被拒；不同ID的语义防重还依赖任务/田地/战斗状态，不应宣称所有命令天然幂等。

关键命令族：buy/sell/sell_equipment；use_item/equip/unequip/slot/upgrade；accept/claim/npc_option/track_quest/abandon_quest；travel/explore/investigate/challenge；practice/retreat/retreat_target/promote；plant/harvest/craft/formation/warehouse/cave_upgrade；join_sect/donate；begin_battle/battle_action/confirm_battle_result；inn_stay。
具体参数以_execute及调用者为准，勿将设计文档的示例接口直接当作现有API。

## 时间与世界
- GameManager._process → advance_session：累积现实秒，读取time_rules倍率，调用OperationService.advance_realtime。
- 自动推进有独立同步候选事务，不每秒追加操作ID；提交后发time_changed，再由GameManager转发time_ui_changed，不走普通命令的changed信号。
- TimeSystem.advance/advance_seconds为日期唯一写入方；先将区间裁至寿元，再分月界累计修为、更新hours/time_seconds，月界依次补货、阵法维护、WorldSimulator月度模拟，末尾更新年龄。
- WorldSimulator改NPC年龄/死亡/成长/迁移、两城价格与有限新闻；无完整宗门/人口演化。
- 山门按 [DEC-038](../decisions.md) 接入。OperationService 用相同基础资格校验入门与山门通行，`travel` 校验后调用 TimeSystem 并写入实际地点及到达事件。`sect_residence_access` 在打开驻地时重新核对资格和实际地点。山门没有已配置的灵气池，照常推进世界时间。
- 驻地按 [DEC-039](../decisions.md) 打开专用场景，配置经 ContentCatalog 加载。四区预览由界面管理；山门出口只返回地图，离开实际地点须经原旅行事务。人物快捷按钮复用宗门人物页。
- 自动时间不再因战斗、窗口或主菜单而暂停；无角色和寿元终局不模拟，无离线补偿。闭关收益和报告通过同一时钟与真实状态差量产生。
- 具体收益/边界/批准规则复用 [时间专项](../world_time_review.md)，最后取消暂停条目覆盖前面的暂停设计。
- 法体成长按 [DEC-031](../decisions.md#dec-031--2026-11-06法体双修与温养首版)。默认时间模式的修炼路线仍是法修，首页切换是显示选择；主动修炼和闭关请求显式传路线。TimeSystem 在原有月界区间调用 CultivationSystem，后者验证对应功法、累计该路线的修为和温养，不重复推进时间。修为封顶后可继续温养至属性上限；属性封顶后不储存超额温养。
- 主动淬体沿用安全地点及 1/3/10 日入口，炼体突破经原 promote 事务执行。功法门槛只管修炼结算，装备属性、丹药效果和法修突破的规则沿用。闭关预估与实跑共用路线、固定点速率和月界结算，报告读取状态差量。
- 正式 practice 请求走 TimeSystem。旧 CultivationSystem 独立累计入口已移除。
- [DEC-032](../decisions.md) 扩展了两条路线的突破上限及根基衍生属性。大突破在候选事务内先校验完整条件再扣资源。角色属性仍由 CharacterSystem 统一计算。
- F1 灵气试算调用 SpiritFlowSimulation，按固定小时段模拟局部和周边储量、吸纳、运转、炼化和损耗。试算不会提交操作、修改玩家资源或推进世界时钟。正式接入边界和实测见 [V3.1 迁移记录](../spirit_flow_v3_1_review.md)。
- DEC-033 正式切换后，TimeSystem 在原月界前按小时边界结算 SpiritCultivation，再执行世界月结。运行期间所有地点均恢复或逸散，修炼只提取所在地点的灵气。小时参考浓度和根基快照保证分钟推进与整段推进一致；灵石释放立即更新当地引气参考值，时钟外的其他系统不结算环境。
- 目标闭关在同一路径中寻找达到瓶颈的最早游戏秒。状态稳定且无修炼时跳过小时段，仍执行月结。正式环境和余量在 OperationService 候选状态内更新，F1 配置与试算保持独立。

## 战斗与奖励
- BattleSystem.begin 按速度确定本轮顺序，若怪物先手则立即结算怪物。BattleSystem.action 执行当前等待的玩家指令，再结算本轮后手和下一轮的怪物先手，最后停在下一个玩家输入点。每个行动只结算一次。伤害、灵力、状态、冷却及随机仍由业务层处理。
- 表现按本次提交的行动快照播放。主界面在播放时锁住输入，播放结束后从当前等待队列高亮玩家并刷新日志。旧进行中战斗缺少当前轮顺序时，在战斗页开启下一轮。
- 2026-11-07 无界面回归通过，战斗先手专项 36 项，覆盖先手开局、同速、跨轮换速、先手致死、旧档和按钮及高亮状态。实际窗口表现本轮未验收。
- 八系法术复用同一行动提交。等级效果由 SpellProgression 读取，SpellEffectResolver 使用同一直接伤害公式和 BattleStatus 状态结算。新增法术的修炼通过 OperationService 和 TimeSystem 提交，参悟使用独立的 spell_affix 随机流及待确认结果。见 [主动法术专项](../spell_trials_review.md)。
- OperationService._finish_battle统一处理胜败/逃跑、loot随机流、掉落、任务击杀事件、返回地点、battle_report及额外耗时。
- 报告写入时奖励已经结算；confirm_battle_result只确认报告，不能再次发奖。
- events/log_entries是已结算事件的表现记录；Tween回放、跳过或关闭页面不得再次提交结算。正式玩法当前1对1，多人UI夹具不是多人业务。

## 任务、交易和洞府
- EventBus.domain_event在候选事务内调用QuestSystem.notify；它与提交后changed展示通知不同，不能在此做不可回滚的外部副作用。
- 七类目标与任务局部schema_version=2、旧档迁移、实时持有/交付/报告逻辑见 [任务机制](../quest_refactor_review.md)；奖励和完成状态同事务提交。
- ShopSystem.trade检查数量、地点、NPC状态/财富、库存及玩家余额；InventorySystem区分堆叠数量与唯一装备实例，装配后CharacterSystem.stats统一求属性。
- AuctionSystem 通过同一 OperationService 候选状态结算。TimeSystem 提供入场窗口，玩家请求推进竞价；最高价暂扣在原钱包，旧高价退款与新高价同时提交。NPC 归属及关系进入原状态，神识属性读取共用根基。见 [拍卖与神识专项](../auction_review.md)。
- CaveSystem执行plant/harvest/craft；OperationService检查地点并通过TimeSystem结算炼丹耗时。仓库、阵法、升级及加入宗门/捐献在操作服务路由，不存在独立完整发展系统。

## 存读与兼容

- 开发构建 F12 玩家属性面板保存并临时设置场景树暂停状态。非战斗时，`debug_set_player_values` 在同一候选事务中验证并写入 `player.base` 的 hp、mp、attack、defense、speed 及原钱包 `player.spirit_stones`。沿用统一属性计算及资源夹取，当前生命、灵力只在超过新上限时降低。提交后发 `changed`；保存时使用原字段，无格式迁移。无头验收入口为 `tests/player_debug_panel_tests.gd`。
- export_save返回version/state/random/sequence；SaveService.write将payload序列化、SHA-256校验，写新修订临时文件后重命名，保留原存档。
- read验证外层版本、结构和校验；restore_save先validate_save，再规范化数值、移除旧暂停字段、迁移旧任务、恢复随机流/序列并发changed。
- random各流以十进制字符串保存64位状态。固定种子、初态和操作序列用于重放，随机角色身份另由Crypto生成。
- 正式路径user://saves，测试user://test_saves；不读取现实时间补离线收益，不因读档重播奖励。
- 不支持任意未知历史格式；未发现完整自动损坏恢复/备份轮转机制，不能把校验和等同全部恢复能力。

## 维护与测试
修改请求/字段时检查GameManager、main路由、相关服务、存档校验/迁移及tests调用者。参考 [系统索引测试入口](../system_index.md)；字段不在此复制第二份。
风险：操作ID表/战斗日志随会话增长；部分常量/ID仍在路由与玩法脚本；不能据本页认为已完成全部数据驱动或长期性能验收。

NPC 编辑器通过可选覆盖表输入新档定义，编辑版 NPC 的档案随存档保存。属性预览与 NPC 档案同用 `CharacterSystem.npc_stats`。见 [NPC 编辑器](npc_editor.md)。
