# 战斗结算 V1.3 验收记录

日期：2026-11-05。结论：PASS（本轮UI与既有结算对接），等待用户视觉审核。

## 实现
原战斗背景上添加暗色遮罩和居中960×620弹窗，52/48成长与战利品两栏，三列物品网格、内部滚动、底部战斗详情与确认。基准位置480,230；小窗口沿用项目canvas_items缩放，额外以min(1,(可用宽-32)/960,(可用高-32)/620)统一缩放并居中。模板为真实容器、文字与按钮，可在编辑器打开。
多人仅接受实际成长接收者列表，不生成队友或宠物玩法；测试中使用明确布局测试名称及独立成长类型。
详情在原尺寸内切换显示已有回合日志。没有输出伤害、治疗量等记录，不伪造统计。

## 文件与复用
- ui/battle/battle_result_overlay.tscn、battle_result_overlay.gd：新增结算模板与只读展示。
- core/operation_service.gd：原_finish_battle事务附加battle_report，新增confirm_battle_result只更新确认标记。
- gameplay/battle/battle_system.gd：新战斗开始时清理上次展示报告，不改变奖励。
- ui/battle/battle_page.gd：可绑定结算前战场快照。
- ui/main/main.gd：未确认报告恢复战场背景并叠加弹窗，禁用背景按钮；确认回实际地点场景。
- tests/battle_result_tests.gd：41项结算与实际渲染检查。
复用原奖励事务、随机流、背包add、TimeSystem、境界required配置、SaveService以及现有地点名称映射。物品采用Godot原生tooltip展示已有类型、品质、描述，没有第二套物品说明系统。

节点：BattleResultOverlay / DimBackground + ResultPanel / Margin / Main；Main下Header、Content（GrowthPanel与LootPanel）、Details、Footer。各栏仅列表内部滚动。

## 发奖、防重与存档
奖励仍在战斗结束的原事务内自动发放，原随机抽取次数、概率、数值、首次狼首额外掉落及任务通知不变。记录实际发放掉落（非背包净差），因此最终回合用药不会误算奖励。
确认只改变confirmed，不修改钱、道具或修为；校验战斗ID及未确认状态，重复确认拒绝。奖励完成后battle清空，重复战斗行动不能再次结算。
新增可选state.battle_report，旧存档缺少时仍正常加载。新存档保存已结算结果、确认标记、成长、战场快照与日志；读档只展示，不重放发奖。未确认恢复弹窗，已确认保持关闭。测试文件写user://test_saves，不覆盖玩家存档。
现有战斗不奖励修为，真实页面显示+0；修为阈值读取现有境界表，不自动晋升。胜败惩罚原样保留；寿元结束仍允许关闭结算（无玩法奖励）。

## 验证与截图
Godot4.5 Mono OpenGL实际运行41项检查通过，包括真实胜负、原战败损失、真实掉落、单一/多种/空掉落、阈值不自动晋升、多人及部分成长接收者、不同成长类型、内部滚动、详情切换、居中960×620、1280×720、确认不发奖、重复确认、磁盘存读、旧档兼容及非法掉落引用。
tests/run_all.ps1全套通过，导入、原业务回归、边界、任务、无头启动无报错。
已实际查看result_win.png、result_lose.png、result_team_loot.png、result_1280.png，位于docs/screenshots。多人及多物品截图为隔离UI布局数据，不代表真实多人战斗或额外掉落规则。

## 边界
未添加战斗修为奖励、队友/宠物成长系统和未记录的伤害统计。首次战斗结算记录产生前的历史战利品无法追溯，不补造报告。
现有game_design.md、content_v0_1.md、combat_balance.md仍缺失，采用现有中文设计与内容文档。无Git仓库，未提交。
下一步：用户审核结算视觉与确认返回体验；不自动增加奖励或多人玩法。

## 2026-11-05：用户追加尺寸与按钮位置调整
用户要求开始战斗居屏幕中央、结算画面增加一半。Begin按钮移至battle_page.tscn根下，中心锚点、240×72；仍调用原begin_battle，开战后隐藏。
结算保持960×620内部布局，整体（含文字、图标和按钮）等比例放大1.5倍，1920×1080下实际显示1440×930，位置240,75；小窗口继续统一缩放居中。编辑器模板同步默认缩放与位置。
修改：battle_page.tscn、battle_result_overlay.tscn/gd、两份既有页面测试及本记录。未改业务数据、结算或存档。
实际Godot OpenGL验证：357项战斗页面检查、42项结算检查通过。已查看battle_prepare_center.png、更新后的result_win.png、result_1280.png，无遮挡或裁切。本轮仅UI调整，未重复执行上轮全套业务回归。
结论PASS，无新增已知问题；下一步等待用户视觉审核。
