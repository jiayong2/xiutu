# 客栈 V1.0 本轮验收记录
2026-11-05。用户明确选择“先接现有住宿；其他房型和用膳明确占位”。该确认范围：PASS；完整三房型/用膳增益未实现。

## 实现及文件
- 新增data/towns/inns.json：青岚客栈、云溪客栈，共用inn_id入口；名称、位置、类型、介绍、场景描述、观察、掌柜引用、房型、菜单与NPC列表。只配置已批准的原住宿方案，菜单及NPC列表空，不补造人物。
- 新增ui/inn/inn_page.tscn、inn_page.gd：沿用现有店铺灰蓝主题、思源黑体与25/50/25三栏；原生可编辑模板。顶部角色/地点/灵石/时间，左信息及返回，中首页/住宿/用膳占位/打听消息/观察，右NPC与历史消息。只切换中央HomeContent/Secondary，保留侧栏节点。
- 修改core/content_catalog.gd：注册inns静态配置并验证地点、房型重复ID、可用布尔、动作及NPC引用。
- 修改core/operation_service.gd：inn_stay先验证inn_id、room_id、位置与availability，再复用原inn事务；价格10、1日与HP/MP恢复规则未改。
- 修改ui/main/home_view.gd、ui/main/main.gd：城镇客栈建筑现在进入首页，不再点击即扣费休息；现有两城按当前位置选择配置。统一NPC弹窗、会话消息、ESC层级与返回接通。
- 新增tests/inn_ui_preview.gd。

## 复用与安全
住宿复用原inn、钱包/角色属性和TimeSystem，不创建独立时间或恢复数值；不奖励修为。失败不提交，世界时间、资源及随机均由原OperationService事务保护。
一次入住表单持有稳定operation_id，UI确认立即防重复；成功后同表单不能再次执行，重复业务请求由已有operations拒绝。重新进入住宿表示新的主动休息。保存沿用原state/operations，不新增住宿奖励、待处理操作或独立存档结构；磁盘存读后同operation_id仍拒绝。
角色或NPC界面不在UI直接写资源。NPC使用现有inn.npc_list、owner_npc_id或实际NPC的inn_id过滤，并要求当前地点和存活；点击统一open_npc_interaction，关闭仍保留InnPage实例。
消息复用recent_messages与state.news。观察与住宿有具体反馈，不只显示操作成功。

## 明确占位与数据缺口
其他房型、全部用膳及临时增益按用户确认留占位，不扣费、不制造食物/Buff或成功反馈。
现有配置没有客栈掌柜/伙计/住客，显示暂无人物资料/附近暂无人物；不从其他商店挪掌柜，不把所有镇内NPC当客栈住客。NPC入口以隔离放置的现有人物验证。
原系统无客房数量/入住库存，不声称尚有几间空房，只显示可住宿；配置available=false则禁止该房型。
世界news仅有公开字符串记录，无真实地区、发生日期、来源或有效期。打听页面标明往日历史、非当前事件，并提供静态住宿说明，不编造妖兽暴动、商队或宗门事件。不将消息自动转为任务，也不冒充每日传闻数量；左侧使用历史传闻数量。
没有开发经营、寻路、随机事件生成、长期租房或室内地图。

## 验证
Godot4.5实际OpenGL执行48项客栈检查全部通过：默认首页不发起行动，两分辨率10个区域按钮完整可见，仅中央变化，真实10灵石/24小时/full HP MP且不加修为，重复点击、重复operation_id及读档后防重、余额不足、未知/关闭房间原子拒绝、无效NPC引用校验、用膳占位无状态变动、静态/历史消息、观察、NPC弹窗保留客栈、ESC二级返回、第二座客栈复用及磁盘存档一致。
tests/home_layout_preview.gd的51项通过；tests/run_all.ps1全套原业务检查通过，导入和无头启动正常。
已实际查看inn_home_1920.png、inn_home_1280.png及inn_stay_1280.png，无重叠和裁切。
测试NPC与客房关闭标记仅修改隔离运行副本，不写正式NPC配置或玩家存档。测试磁盘文件仍在user://test_saves。
历史game_design.md/content_v0_1.md/combat_balance.md英文文档缺失仍在，沿用已有中文设计、data_schema与decisions。当前无Git仓库，未提交。

## 下一步
审核客栈首页及住宿流程。若后续开放食物、其他房型、掌柜住客或有时效的地区传闻，需先提供/确认对应正式数据；本轮不自动扩展。
