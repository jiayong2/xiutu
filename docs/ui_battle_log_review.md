# 战斗日志语义配色验收（2026-11-05）

## 完成范围

保留原 battle_page 日志面板位置和尺寸，使用原 RichTextLabel 开启 BBCode。战斗结算详情复用相同格式化器，不新增图片、Shader、插件或战斗规则。

所有十种颜色集中于 ui/battle/battle_log_formatter.gd 的 COLORS：普通 #D5DFE4、伤害 #F07878、恢复 #78C995、暴击 #F4C766、灵气/法术 #82BCE5、增益 #86CDB3、减益 #C8A1E8、闪避/格挡 #D6C990、系统 #A4B7C1、胜利 #F0D597。

配色按结构化 type/kind/critical/status ID/outcome/result 决定，不搜索中文关键词。伤害日志可在同一行显示蓝色法术名与红色数值，暴击的关键词和数值统一金色且不再嵌套红色。其余描述保持浅灰。回合开头只生成一次简洁分隔。

## 数据与兼容

- BattleSystem 在原行动已经完成后，把实际 before/after 快照转成紧凑 log_entries。记录 round/action/hp/mp/status/defend/result，记录真实 HP/MP 差值、暴击、状态施加/刷新/剩余回合及结束。没有改变伤害公式、概率、随机调用、顺序或状态处理。
- 胜负/逃跑记录由原 _finish_battle 加入结算报告的 battle 快照，仅用于展示，不触发结算。原奖励、时间、任务等逻辑不变。
- 旧 battle.log 纯文字继续保留，供旧消费者使用。旧存档没有 log_entries 时正常读取；继续行动时把既有历史包装为 legacy 记录，随后追加新语义记录，不猜测旧文本颜色，也不丢弃历史。
- log_entries 随 battle / battle_report.background.battle 保存，新增可选字段，不改外层存档版本。加载检查记录类型、所需字段及真实数值差值，损坏记录原子拒绝，不污染当前状态。
- 格式化器一次转义动态文本中的左右方括号。角色/NPC名称、物品名、法术名、历史文本与错误消息均按原文显示，不能注入 color/img 等标签。
- 日志以同一历史重绘，内容未变不重复解析；不写入 BBCode 到业务数据。不显示通用“操作成功”，结算已由结构化结果显示时不再次附加相同结果消息。
- 末尾阅读自动跟随；向上查看保留滚动值。每条记录保留，未强制截断历史。此实现不声称无限长度零开销，长历史在操作更新时重新格式化，不做每帧扫描。

## 修改文件

1. ui/battle/battle_log_formatter.gd（新增及 uid）：集中配色、BBCode 转义、语义格式化和旧历史回退。
2. gameplay/battle/battle_system.gd：真实展示记录生成及可选日志校验接口；原纯文本历史兼容。
3. core/operation_service.gd：结果展示记录、存档加载时的结构化历史校验。
4. ui/battle/battle_page.gd、battle_page.tscn：启用 BBCode、原面板内展示、系统错误和滚动保留。
5. ui/battle/battle_result_overlay.gd：原详情复用统一格式化器。
6. ui/main/main.gd：传递真实 log_entries，错误消息通过统一转义入口显示。
7. tests/battle_log_preview.gd（新增及 uid）：真实结算、颜色、长历史、文本注入和兼容性测试。
8. docs/ui_battle_log_review.md、data_schema.md、decisions.md、development_plan.md：本轮技术和验收记录。
9. docs/screenshots/battle_log_*.png：Godot 实际运行截图，非游戏美术资源；其他既有战斗截图在回归运行时更新。

## 验证结果

- 战斗日志专项：111 项，0 失败。使用隔离测试存档执行真实普攻、暴击、回春、法术消耗、回灵道具、护体、灼烧、防御、胜利及失败；逐项核对 HP/MP 差值与配色，验证渲染不修改状态、重复绑定不重复日志。
- 闪避/格挡：使用明确隔离的 typed avoidance 格式记录，检查 #D6C990 且不带伤害红；正式系统没有该机制，本轮不伪造结果，也不把防御减伤冒充格挡。
- 多语义同一行、回合分隔、结果一次显示、结算详情、动态物品/角色/法术名和系统错误转义、旧档继续行动、损坏历史原子拒绝均通过。
- 长历史：将八类真实测试行动记录复制为隔离的展示历史，1440 个回合分隔全部保留，底部自动滚动、向上查看、新记录及错误追加均通过；不把复制历史写入正式状态。
- 既有动画：165 项，0 失败；布局：357 项，0 失败；结算：42 项，0 失败。
- tests/run_all.ps1：配置、导入、核心、玩法、回归、边界、任务与无头启动全部通过。
- 实际检查 1920×1080 与 1280×720 截图，以及暴击、法术/伤害同一行的截图；原日志矩形尺寸与位置断言通过。

## 问题与结论

本轮日志显示范围 PASS。唯一验收边界是当前正式战斗没有闪避、格挡生产者，两类只验证格式化能力；没有擅自增加机制。旧历史缺少结构化元数据，按浅灰原文展示，无法可靠追溯配色，未通过文本猜测补色。

AGENTS.md 指定的 game_design.md、content_v0_1.md、combat_balance.md 不存在，使用现有中文设计/内容文档、阶段计划、数据规范及已批准决策。工作目录未初始化 Git，未提交、重置或覆盖存档。下一步建议实际游玩确认色彩可读性，不自动开发新战斗机制。

## 2026-11-05：暴击飘字颜色修复
用户反馈暴击飘字不是金色。真实攻击复现：原代码虽追加“暴击”字样，但颜色只区分恢复/伤害，所有负值仍走红色分支；原日志 BBCode 的暴击颜色正常。
最小修复 ui/battle/battle_page.gd：只有真实负伤且为非行动者的暴击使用 LOG_FORMAT.COLORS.critical（#F4C766），与日志共享配色；普通伤害仍红色，治疗仍绿色。42字号、中心上浮、持续时长与原结算保持。
新增 tests/critical_float_preview.gd（及 uid），用真实固定随机种子分别执行普通攻击、暴击，核对实际伤害/暴击标记、飘字RGB、字号和表现期间状态不变。修复前16项中1项失败，修复后16项全部通过，实际截图 battle_floating_critical.png 已检查。无核心规则或数值改动，UI范围PASS。
修改文件：ui/battle/battle_page.gd、tests/critical_float_preview.gd、其Godot uid、本记录、development_plan.md、decisions.md；两张实际运行截图位于docs/screenshots/battle_floating_normal.png与battle_floating_critical.png。下一步建议实际体验暴击提示，不自动扩展表现或规则。
