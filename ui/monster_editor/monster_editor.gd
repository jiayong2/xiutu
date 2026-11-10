extends Control
## In-game monster editor (stages 1-5: attributes, skills, behaviour, loot,
## passives and special mechanics).
##
## UI only edits in-memory drafts and submits them to MonsterDatabase, which
## validates and writes the existing monsters.json / skills.json tables.
## Passive/special-mechanic tabs are data-driven editors over the same shared
## status/effect engine; unsupported capabilities are marked, not faked.

signal closed
signal test_battle_requested(monster_id: String)

const MonsterDatabase = preload("res://core/monsters/monster_database.gd")
const MonsterReferences = preload("res://core/monsters/monster_references.gd")
const Catalog = preload("res://core/content_catalog.gd")
const ItemDatabase = preload("res://core/items/item_database.gd")
const BattleStatus = preload("res://gameplay/battle/battle_status.gd")

const TAB_TITLES := ["基础属性", "技能配置", "行为规则", "被动效果", "掉落配置", "特殊机制"]
const TARGET_LABELS := {
	"self": "自身", "enemy": "单体敌人", "random_enemy": "随机敌人",
	"lowest_enemy": "生命最低敌人", "all_enemies": "全体敌人",
}
const EFFECT_LABELS := {
	"damage": "直接伤害", "status": "状态", "stat": "属性", "heal": "治疗",
	"shield": "护盾", "mana": "灵力", "cleanse": "驱散", "phase": "阶段",
}
const EFFECT_TYPES := ["damage", "status", "stat", "heal", "shield", "mana", "cleanse", "phase"]
const STAT_OPTIONS := ["attack", "defense", "speed", "crit"]
const STATUS_MODE_OPTIONS := ["stack", "refresh", "replace"]
const BEHAVIOR_CONDITION_LABELS := {
	"always": "无条件", "hp_below": "自身生命低于（%）", "hp_above": "自身生命高于（%）",
	"mp_at_least": "自身灵力至少", "action_every": "每第 N 次自身行动",
	"turn_every": "每第 N 回合", "turn_at_least": "第 N 回合及以后",
	"self_status": "自身拥有状态", "self_not_status": "自身没有状态",
	"target_status": "目标拥有状态", "target_not_status": "目标没有状态",
	"skill_uses_below": "技能使用次数少于", "skill_uses_at_least": "技能使用次数至少",
	"phase": "当前阶段", "has_available_skill": "存在可用技能",
}
const BEHAVIOR_CONDITION_OPTIONS := [
	"always", "hp_below", "hp_above", "mp_at_least", "action_every",
	"turn_every", "turn_at_least", "self_status", "self_not_status",
	"target_status", "target_not_status", "skill_uses_below",
	"skill_uses_at_least", "phase", "has_available_skill",
]
const BEHAVIOR_ACTION_LABELS := {
	"attack": "普通攻击", "skill": "使用技能", "defend": "防御", "charge": "蓄力",
	"flee": "逃跑", "heal": "使用技能（治疗别名）", "buff": "使用技能（增益别名）",
}
const BEHAVIOR_ACTION_OPTIONS := ["attack", "skill", "defend", "charge", "flee", "heal", "buff"]
const BEHAVIOR_TARGET_OPTIONS := ["self", "enemy", "random_enemy", "lowest_enemy", "all_enemies"]
const BEHAVIOR_MODE_LABELS := {"all": "全部满足（且）", "any": "任一满足（或）"}
const BEHAVIOR_ON_FAIL_LABELS := {"continue": "继续检查下一条规则", "fallback": "直接执行普通攻击"}
const PASSIVE_EFFECT_TYPES := ["status", "stat", "heal", "shield", "mana", "cleanse", "phase"]
const TRIGGER_EVENTS := ["battle_start", "hp_below", "turn_start"]
const TRIGGER_EVENT_LABELS := {
	"battle_start": "战斗开始", "hp_below": "生命阈值", "turn_start": "自身行动开始",
}

var catalog: Dictionary = {}
var runtime: Dictionary = {}
var data_path := MonsterDatabase.PATH
var skills_data_path := MonsterDatabase.SKILLS_PATH
var propagate_to_game := true

var _rows: Array = []
var _saved_rows: Array = []
var _skills: Array = []
var _saved_skills: Array = []
var _active_id := ""
var _selected_skill_id := ""
var _selected_behavior_id := ""
var _dirty := false
var _skills_dirty := false
var _dirty_skill_ids: Array = []
var _shared_confirmed: Dictionary = {}
var _loading_form := false
var _loading_skill := false
var _refreshing_skill_tree := false
var _loading_behavior := false
var _refreshing_behavior_tree := false
var _pending_delete_behavior_id := ""
var _selected_loot_index := -1
var _loading_loot := false
var _refreshing_loot_tree := false
var _loot_picker_mode := "add"
var _loot_picker_target_index := -1
var _pending_delete_loot_index := -1
var _pending_copy_loot_id := ""
var _selected_passive_index := -1
var _selected_trigger_id := ""
var _loading_passive := false
var _loading_trigger := false
var _refreshing_passive_tree := false
var _refreshing_trigger_tree := false
var _refreshing_monster_tree := false
var _pending_delete_passive_index := -1
var _pending_delete_trigger_id := ""
var _passive_picker_entries: Array = []
var _trigger_picker_entries: Array = []
var _effect_context := "skill"
var _effect_owner_id := ""
var _loading_effect := false
var _effect_container: VBoxContainer
var _effect_add_button: Button
var _condition_context := "behavior"
var _condition_trigger_id := ""
var _condition_container: VBoxContainer
var _load_failed := false
var _can_edit := true
var _pending_transition: Callable = Callable()
var _pending_delete_id := ""
var _pending_delete_is_draft := false

func _ready() -> void:
	if catalog.is_empty():
		var loaded := Catalog.new()
		if loaded.load_all():
			catalog = loaded.tables
		else:
			catalog = {}
	_can_edit = not catalog.is_empty() and (not data_path.begins_with("res://") or OS.has_feature("editor"))
	var loaded_rows := MonsterDatabase.read_rows(data_path)
	if not str(loaded_rows.get("error", "")).is_empty():
		_load_failed = true
		_rows = []
		_saved_rows = []
		_set_status("载入失败：" + str(loaded_rows.error), true)
	else:
		_rows = loaded_rows.rows
		_saved_rows = _rows.duplicate(true)
	var loaded_skills := MonsterDatabase.read_skills(skills_data_path)
	if not str(loaded_skills.get("error", "")).is_empty():
		_load_failed = true
		_skills = []
		_saved_skills = []
		_set_status("技能库载入失败：" + str(loaded_skills.error), true)
	else:
		_skills = loaded_skills.rows
		_saved_skills = _skills.duplicate(true)
	if catalog.is_empty():
		_set_status("内容目录未加载，编辑器只读；请先修复启动校验。", true)
	_set_tab_titles()
	_configure_tree()
	_configure_skill_tree()
	_configure_behavior_tree()
	_configure_loot_tree()
	_configure_passive_tree()
	_configure_trigger_tree()
	_connect_signals()
	_populate_filters()
	_populate_form_options()
	_populate_skill_options()
	_populate_behavior_options()
	_populate_passive_options()
	_populate_trigger_options()
	_update_edit_capability()
	if _rows.is_empty():
		_refresh_list()
		_clear_form()
		if _load_failed:
			_set_status("载入失败，编辑器只读；请检查数据文件或恢复备份。", true)
		else:
			_set_status("妖兽表为空；请检查 %s。" % data_path, true)
	else:
		var first_id := str(_rows[0].get("id", ""))
		_select_row(first_id)
		_refresh_list(first_id)
		var mode := "开发模式可写"
		if not _can_edit:
			mode = "只读 · 内容目录未加载" if catalog.is_empty() else "只读 · 导出版本"
		_set_status("数据源：%s · 已加载 %d 只妖兽（%s）。" % [data_path, _rows.size(), mode])
	_update_dirty_ui()
	%DataPathLabel.text = "妖兽：%s · 技能：%s" % [data_path, skills_data_path]

func _set_tab_titles() -> void:
	for index in TAB_TITLES.size():
		%Tabs.set_tab_title(index, TAB_TITLES[index])

func _configure_tree() -> void:
	%MonsterTree.select_mode = Tree.SELECT_ROW
	%MonsterTree.column_titles_visible = true
	%MonsterTree.hide_root = true
	%MonsterTree.set_column_title(0, "妖兽名称")
	%MonsterTree.set_column_title(1, "身份")
	%MonsterTree.set_column_title(2, "境界")
	%MonsterTree.set_column_expand(0, true)
	%MonsterTree.set_column_custom_minimum_width(0, 140)
	%MonsterTree.set_column_clip_content(0, true)
	%MonsterTree.set_column_expand(1, false)
	%MonsterTree.set_column_custom_minimum_width(1, 60)
	%MonsterTree.set_column_expand(2, false)
	%MonsterTree.set_column_custom_minimum_width(2, 110)
	%MonsterTree.set_column_clip_content(2, true)

func _configure_skill_tree() -> void:
	%SkillTree.select_mode = Tree.SELECT_ROW
	%SkillTree.column_titles_visible = true
	%SkillTree.hide_root = true
	var titles := ["技能名称", "技能 ID", "类型", "MP", "冷却", "效果摘要", "触发方式"]
	for index in titles.size():
		%SkillTree.set_column_title(index, titles[index])
	%SkillTree.set_column_expand(0, true)
	%SkillTree.set_column_custom_minimum_width(0, 130)
	%SkillTree.set_column_clip_content(0, true)
	for index in range(1, titles.size()):
		%SkillTree.set_column_expand(index, false)
	%SkillTree.set_column_custom_minimum_width(1, 190)
	%SkillTree.set_column_clip_content(1, true)
	%SkillTree.set_column_custom_minimum_width(2, 50)
	%SkillTree.set_column_custom_minimum_width(3, 40)
	%SkillTree.set_column_custom_minimum_width(4, 40)
	%SkillTree.set_column_custom_minimum_width(5, 220)
	%SkillTree.set_column_clip_content(5, true)
	%SkillTree.set_column_custom_minimum_width(6, 150)
	%SkillTree.set_column_clip_content(6, true)

func _configure_behavior_tree() -> void:
	%BehaviorTree.select_mode = Tree.SELECT_ROW
	%BehaviorTree.column_titles_visible = true
	%BehaviorTree.hide_root = true
	var titles := ["顺序", "规则名称", "优先级", "动作", "条件", "概率", "次数", "冷却", "状态"]
	for index in titles.size():
		%BehaviorTree.set_column_title(index, titles[index])
	%BehaviorTree.set_column_expand(1, true)
	%BehaviorTree.set_column_custom_minimum_width(1, 130)
	%BehaviorTree.set_column_clip_content(1, true)
	%BehaviorTree.set_column_expand(4, true)
	%BehaviorTree.set_column_custom_minimum_width(4, 180)
	%BehaviorTree.set_column_clip_content(4, true)
	%BehaviorTree.set_column_expand(0, false)
	%BehaviorTree.set_column_custom_minimum_width(0, 40)
	for index in [2, 3, 5, 6, 7, 8]:
		%BehaviorTree.set_column_expand(index, false)
	%BehaviorTree.set_column_custom_minimum_width(2, 50)
	%BehaviorTree.set_column_custom_minimum_width(3, 80)
	%BehaviorTree.set_column_custom_minimum_width(5, 48)
	%BehaviorTree.set_column_custom_minimum_width(6, 48)
	%BehaviorTree.set_column_custom_minimum_width(7, 48)
	%BehaviorTree.set_column_custom_minimum_width(8, 50)

func _configure_loot_tree() -> void:
	%LootTree.select_mode = Tree.SELECT_ROW
	%LootTree.column_titles_visible = true
	%LootTree.hide_root = true
	var titles := ["物品名称", "物品 ID", "最小数量", "最大数量", "掉落概率", "判定", "条件"]
	for index in titles.size():
		%LootTree.set_column_title(index, titles[index])
	%LootTree.set_column_expand(0, true)
	%LootTree.set_column_custom_minimum_width(0, 130)
	%LootTree.set_column_clip_content(0, true)
	for index in range(1, titles.size()):
		%LootTree.set_column_expand(index, false)
	%LootTree.set_column_custom_minimum_width(1, 190)
	%LootTree.set_column_clip_content(1, true)
	%LootTree.set_column_custom_minimum_width(2, 60)
	%LootTree.set_column_custom_minimum_width(3, 60)
	%LootTree.set_column_custom_minimum_width(4, 60)
	%LootTree.set_column_custom_minimum_width(5, 56)
	%LootTree.set_column_custom_minimum_width(6, 150)

func _configure_passive_tree() -> void:
	%PassiveTree.select_mode = Tree.SELECT_ROW
	%PassiveTree.column_titles_visible = true
	%PassiveTree.hide_root = true
	var titles := ["名称", "类型", "摘要", "持续", "叠加/层数", "可驱散"]
	for index in titles.size():
		%PassiveTree.set_column_title(index, titles[index])
	%PassiveTree.set_column_expand(0, true)
	%PassiveTree.set_column_custom_minimum_width(0, 130)
	%PassiveTree.set_column_clip_content(0, true)
	%PassiveTree.set_column_expand(2, true)
	%PassiveTree.set_column_custom_minimum_width(2, 200)
	%PassiveTree.set_column_clip_content(2, true)
	for index in [1, 3, 4, 5]:
		%PassiveTree.set_column_expand(index, false)
	%PassiveTree.set_column_custom_minimum_width(1, 86)
	%PassiveTree.set_column_custom_minimum_width(3, 60)
	%PassiveTree.set_column_custom_minimum_width(4, 100)
	%PassiveTree.set_column_custom_minimum_width(5, 90)

func _configure_trigger_tree() -> void:
	%TriggerTree.select_mode = Tree.SELECT_ROW
	%TriggerTree.column_titles_visible = true
	%TriggerTree.hide_root = true
	var titles := ["名称", "事件", "启用", "条件", "效果", "次数"]
	for index in titles.size():
		%TriggerTree.set_column_title(index, titles[index])
	%TriggerTree.set_column_expand(0, true)
	%TriggerTree.set_column_custom_minimum_width(0, 120)
	%TriggerTree.set_column_clip_content(0, true)
	%TriggerTree.set_column_expand(3, true)
	%TriggerTree.set_column_custom_minimum_width(3, 150)
	%TriggerTree.set_column_clip_content(3, true)
	%TriggerTree.set_column_expand(4, true)
	%TriggerTree.set_column_custom_minimum_width(4, 200)
	%TriggerTree.set_column_clip_content(4, true)
	for index in [1, 2, 5]:
		%TriggerTree.set_column_expand(index, false)
	%TriggerTree.set_column_custom_minimum_width(1, 100)
	%TriggerTree.set_column_custom_minimum_width(2, 50)
	%TriggerTree.set_column_custom_minimum_width(5, 70)

func _populate_passive_options() -> void:
	_loading_passive = true
	%PassiveTypeOption.clear()
	for kind in PASSIVE_EFFECT_TYPES:
		_add_option(%PassiveTypeOption, str(EFFECT_LABELS.get(kind, kind)), kind)
	%PassiveTypeOption.select(0)
	_loading_passive = false

func _populate_trigger_options() -> void:
	_loading_trigger = true
	%TriggerEventOption.clear()
	for event in TRIGGER_EVENTS:
		_add_option(%TriggerEventOption, str(TRIGGER_EVENT_LABELS.get(event, event)), event)
	%TriggerEventOption.select(0)
	_loading_trigger = false

func _populate_behavior_options() -> void:
	_loading_behavior = true
	%BehaviorModeOption.clear()
	for mode in ["all", "any"]:
		_add_option(%BehaviorModeOption, str(BEHAVIOR_MODE_LABELS.get(mode, mode)), mode)
	%BehaviorModeOption.select(0)
	%BehaviorActionOption.clear()
	for action in BEHAVIOR_ACTION_OPTIONS:
		_add_option(%BehaviorActionOption, str(BEHAVIOR_ACTION_LABELS.get(action, action)), action)
	%BehaviorActionOption.select(0)
	%BehaviorTargetOption.clear()
	for target in BEHAVIOR_TARGET_OPTIONS:
		_add_option(%BehaviorTargetOption, str(TARGET_LABELS.get(target, target)), target)
	%BehaviorTargetOption.select(1)
	%BehaviorOnFailOption.clear()
	for on_fail in ["continue", "fallback"]:
		_add_option(%BehaviorOnFailOption, str(BEHAVIOR_ON_FAIL_LABELS.get(on_fail, on_fail)), on_fail)
	%BehaviorOnFailOption.select(0)
	_loading_behavior = false

func _connect_signals() -> void:
	%Search.text_changed.connect(_on_search_changed)
	%RealmFilter.item_selected.connect(_on_filter_changed)
	%RankFilter.item_selected.connect(_on_filter_changed)
	%MonsterTree.item_selected.connect(_on_tree_item_selected)
	%NewBtn.pressed.connect(_request_new)
	%CopyBtn.pressed.connect(_request_copy)
	%DeleteBtn.pressed.connect(_request_delete)
	%SaveBtn.pressed.connect(_on_save_pressed)
	%DiscardBtn.pressed.connect(_request_reset)
	%CloseBtn.pressed.connect(request_close)
	%CheckBtn.pressed.connect(_run_check)
	%TestBattleBtn.pressed.connect(_request_test_battle)
	%Tabs.tab_changed.connect(_on_tab_changed)
	%NameEdit.text_changed.connect(_on_form_changed)
	%IdEdit.text_changed.connect(_on_form_changed)
	%RealmOption.item_selected.connect(_on_form_changed)
	%RankOption.item_selected.connect(_on_form_changed)
	%HpSpin.value_changed.connect(_on_form_changed)
	%MpSpin.value_changed.connect(_on_form_changed)
	%AttackSpin.value_changed.connect(_on_form_changed)
	%DefenseSpin.value_changed.connect(_on_form_changed)
	%SpeedSpin.value_changed.connect(_on_form_changed)
	%DescriptionEdit.text_changed.connect(_on_form_changed)
	%UnsavedDialog.confirmed.connect(func() -> void: _resolve_pending("save"))
	%UnsavedDialog.custom_action.connect(_on_unsaved_custom)
	%UnsavedDialog.canceled.connect(_cancel_pending)
	%UnsavedDialog.add_button("放弃修改", true, "discard")
	%DeleteDialog.confirmed.connect(_confirm_delete)
	%DeleteDialog.canceled.connect(_on_delete_canceled)
	%AddSkillBtn.pressed.connect(_open_skill_picker)
	%NewSkillBtn.pressed.connect(_create_new_skill)
	%CopySkillBtn.pressed.connect(_request_copy_skill)
	%RemoveSkillBtn.pressed.connect(_request_remove_skill)
	%SkillTree.item_selected.connect(_on_skill_tree_selected)
	%SkillNameEdit.text_changed.connect(_on_skill_name_changed)
	%SkillDescriptionEdit.text_changed.connect(_on_skill_description_changed)
	%SkillTargetOption.item_selected.connect(_on_skill_target_changed)
	%SkillMpSpin.value_changed.connect(_on_skill_mp_changed)
	%SkillCooldownSpin.value_changed.connect(_on_skill_cooldown_changed)
	%SkillOrdinaryCheck.toggled.connect(_on_skill_ordinary_toggled)
	%SharedConfirmCheck.toggled.connect(_on_shared_confirm_toggled)
	%AddEffectBtn.pressed.connect(_add_effect)
	%SaveSkillBtn.pressed.connect(_on_save_pressed)
	%SkillPickerSearch.text_changed.connect(_on_skill_picker_search)
	%SkillPickerList.item_selected.connect(_on_skill_picker_selected)
	%SkillPickerList.item_activated.connect(func(_index: int) -> void: _add_picked_skill())
	%SkillPickerAddBtn.pressed.connect(_add_picked_skill)
	%SkillPickerCancelBtn.pressed.connect(_close_skill_picker)
	%RemoveSkillDialog.confirmed.connect(_confirm_remove_skill)
	%RemoveSkillDialog.canceled.connect(func() -> void: %RemoveSkillDialog.hide())
	%AddRuleBtn.pressed.connect(_create_new_behavior)
	%CopyRuleBtn.pressed.connect(_request_copy_behavior)
	%DeleteRuleBtn.pressed.connect(_request_delete_behavior)
	%MoveUpBtn.pressed.connect(_move_behavior.bind(-1))
	%MoveDownBtn.pressed.connect(_move_behavior.bind(1))
	%BehaviorTree.item_selected.connect(_on_behavior_tree_selected)
	%BehaviorNameEdit.text_changed.connect(_on_behavior_name_changed)
	%BehaviorEnabledCheck.toggled.connect(_on_behavior_enabled_toggled)
	%BehaviorPrioritySpin.value_changed.connect(_on_behavior_priority_changed)
	%BehaviorModeOption.item_selected.connect(_on_behavior_mode_changed)
	%BehaviorActionOption.item_selected.connect(_on_behavior_action_changed)
	%BehaviorSkillOption.item_selected.connect(_on_behavior_skill_changed)
	%BehaviorTargetOption.item_selected.connect(_on_behavior_target_changed)
	%BehaviorChanceSpin.value_changed.connect(_on_behavior_chance_changed)
	%BehaviorMaxUsesSpin.value_changed.connect(_on_behavior_max_uses_changed)
	%BehaviorCooldownSpin.value_changed.connect(_on_behavior_cooldown_changed)
	%BehaviorOnFailOption.item_selected.connect(_on_behavior_on_fail_changed)
	%AddConditionBtn.pressed.connect(_add_behavior_condition)
	%SaveBehaviorBtn.pressed.connect(_on_save_pressed)
	%DeleteBehaviorDialog.confirmed.connect(_confirm_delete_behavior)
	%DeleteBehaviorDialog.canceled.connect(func() -> void: %DeleteBehaviorDialog.hide())
	%AddLootBtn.pressed.connect(func() -> void: _open_loot_item_picker("add"))
	%ChooseLootItemBtn.pressed.connect(func() -> void: _open_loot_item_picker("replace"))
	%CopyLootBtn.pressed.connect(_open_loot_copy_menu)
	%LootTree.item_selected.connect(_on_loot_tree_selected)
	%LootItemButton.pressed.connect(func() -> void: _open_loot_item_picker("replace"))
	%LootMoneyMinSpin.value_changed.connect(_on_loot_money_changed)
	%LootMoneyMaxSpin.value_changed.connect(_on_loot_money_changed)
	%LootMinSpin.value_changed.connect(_on_loot_min_changed)
	%LootMaxSpin.value_changed.connect(_on_loot_max_changed)
	%LootChanceSpin.value_changed.connect(_on_loot_chance_changed)
	%LootGuaranteedCheck.toggled.connect(_on_loot_guaranteed_toggled)
	%LootRankNormal.toggled.connect(_on_loot_condition_changed)
	%LootRankElite.toggled.connect(_on_loot_condition_changed)
	%LootRankBoss.toggled.connect(_on_loot_condition_changed)
	%LootRealmMinSpin.value_changed.connect(_on_loot_condition_changed)
	%DeleteLootBtn.pressed.connect(_request_delete_loot)
	%SaveLootBtn.pressed.connect(_on_save_pressed)
	%DeleteLootDialog.confirmed.connect(_confirm_delete_loot)
	%DeleteLootDialog.canceled.connect(func() -> void: %DeleteLootDialog.hide(); _pending_delete_loot_index = -1)
	%CopyLootDialog.confirmed.connect(_confirm_copy_loot)
	%CopyLootDialog.canceled.connect(func() -> void: %CopyLootDialog.hide(); _pending_copy_loot_id = "")
	%LootCopyMenu.id_pressed.connect(_on_loot_copy_selected)
	%LootItemSearch.text_changed.connect(_on_loot_item_search)
	%LootItemTypeFilter.item_selected.connect(_on_loot_item_type_filter)
	%LootItemList.item_selected.connect(_on_loot_item_selected)
	%LootItemList.item_activated.connect(func(_index: int) -> void: _confirm_loot_item_pick())
	%LootItemConfirmBtn.pressed.connect(_confirm_loot_item_pick)
	%LootItemCancelBtn.pressed.connect(_close_loot_item_picker)
	%AddPassiveBtn.pressed.connect(_open_passive_picker)
	%CopyPassiveBtn.pressed.connect(_request_copy_passive)
	%RemovePassiveBtn.pressed.connect(_request_remove_passive)
	%PassiveTree.item_selected.connect(_on_passive_tree_selected)
	%PassiveTypeOption.item_selected.connect(_on_passive_type_changed)
	%SavePassiveBtn.pressed.connect(_on_save_pressed)
	%PassivePickerMenu.id_pressed.connect(_on_passive_picked)
	%DeletePassiveDialog.confirmed.connect(_confirm_remove_passive)
	%DeletePassiveDialog.canceled.connect(func() -> void: %DeletePassiveDialog.hide(); _pending_delete_passive_index = -1)
	%AddTriggerBtn.pressed.connect(_open_trigger_picker)
	%CopyTriggerBtn.pressed.connect(_request_copy_trigger)
	%RemoveTriggerBtn.pressed.connect(_request_remove_trigger)
	%TriggerTree.item_selected.connect(_on_trigger_tree_selected)
	%TriggerNameEdit.text_changed.connect(_on_trigger_name_changed)
	%TriggerEnabledCheck.toggled.connect(_on_trigger_enabled_toggled)
	%TriggerEventOption.item_selected.connect(_on_trigger_event_changed)
	%TriggerOnceCheck.toggled.connect(_on_trigger_once_toggled)
	%TriggerMaxUsesSpin.value_changed.connect(_on_trigger_max_uses_changed)
	%AddTriggerConditionBtn.pressed.connect(_add_trigger_condition)
	%AddTriggerEffectBtn.pressed.connect(_add_trigger_effect)
	%SaveTriggerBtn.pressed.connect(_on_save_pressed)
	%TriggerPickerMenu.id_pressed.connect(_on_trigger_picked)
	%DeleteTriggerDialog.confirmed.connect(_confirm_remove_trigger)
	%DeleteTriggerDialog.canceled.connect(func() -> void: %DeleteTriggerDialog.hide(); _pending_delete_trigger_id = "")

func _populate_filters() -> void:
	var had_realm: bool = %RealmFilter.item_selected.is_connected(_on_filter_changed)
	var had_rank: bool = %RankFilter.item_selected.is_connected(_on_filter_changed)
	if had_realm:
		%RealmFilter.item_selected.disconnect(_on_filter_changed)
	if had_rank:
		%RankFilter.item_selected.disconnect(_on_filter_changed)
	%RealmFilter.clear()
	_add_option(%RealmFilter, "全部境界", 0)
	for level in range(MonsterDatabase.REALM_MIN, MonsterDatabase.REALM_MAX + 1):
		_add_option(%RealmFilter, MonsterDatabase.realm_label(level, catalog), level)
	%RealmFilter.select(0)
	%RankFilter.clear()
	_add_option(%RankFilter, "全部身份", "")
	for rank in MonsterDatabase.RANK_ORDER:
		_add_option(%RankFilter, MonsterDatabase.rank_label(rank), rank)
	%RankFilter.select(0)
	if had_realm:
		%RealmFilter.item_selected.connect(_on_filter_changed)
	if had_rank:
		%RankFilter.item_selected.connect(_on_filter_changed)

func _populate_form_options() -> void:
	_loading_form = true
	%RealmOption.clear()
	for level in range(MonsterDatabase.REALM_MIN, MonsterDatabase.REALM_MAX + 1):
		_add_option(%RealmOption, MonsterDatabase.realm_label(level, catalog), level)
	%RankOption.clear()
	for rank in MonsterDatabase.RANK_ORDER:
		_add_option(%RankOption, MonsterDatabase.rank_label(rank), rank)
	%RootOption.clear()
	%RootOption.add_item("未支持：妖兽没有灵根字段")
	%RootOption.select(0)
	_loading_form = false

func _populate_skill_options() -> void:
	_loading_skill = true
	%SkillTargetOption.clear()
	for key in ["enemy", "self", "random_enemy", "lowest_enemy", "all_enemies"]:
		_add_option(%SkillTargetOption, str(MonsterDatabase.SKILL_TARGET_LABELS.get(key, key)), key)
	%SkillTargetOption.select(0)
	_loading_skill = false

func _add_option(option: OptionButton, label: String, value: Variant) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)

func _select_option(option: OptionButton, value: Variant) -> bool:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return true
	return false

func _selected_metadata(option: OptionButton) -> Variant:
	if option.selected < 0:
		return null
	return option.get_item_metadata(option.selected)

func _filtered_rows() -> Array:
	var query: String = str(%Search.text).strip_edges().to_lower()
	var realm := int(_selected_metadata(%RealmFilter))
	var rank := str(_selected_metadata(%RankFilter))
	var result: Array = []
	for row in _rows:
		if not row is Dictionary:
			continue
		if realm != 0 and int(row.get("realm", 0)) != realm:
			continue
		if not rank.is_empty() and str(row.get("rank", "")) != rank:
			continue
		if not query.is_empty():
			var name := str(row.get("name", "")).to_lower()
			var monster_id := str(row.get("id", "")).to_lower()
			if not (name.contains(query) or monster_id.contains(query)):
				continue
		result.append(row)
	return result

func _refresh_list(select_id := "") -> void:
	if _refreshing_monster_tree:
		call_deferred("_refresh_list", select_id)
		return
	_rebuild_monster_list(select_id)

func _rebuild_monster_list(select_id := "") -> void:
	if not is_instance_valid(%MonsterTree):
		return
	var tree: Tree = %MonsterTree
	var had_select_signal := tree.item_selected.is_connected(_on_tree_item_selected)
	if had_select_signal:
		tree.item_selected.disconnect(_on_tree_item_selected)
	var target := select_id if not select_id.is_empty() else _active_id
	var keep_view := not target.is_empty() and target == _active_id
	_refreshing_monster_tree = true
	tree.clear()
	var root: TreeItem = tree.create_item()
	var shown := _filtered_rows()
	var selected_item: TreeItem = null
	for row in shown:
		var item: TreeItem = tree.create_item(root)
		var monster_id := str(row.get("id", ""))
		var rank := str(row.get("rank", "normal"))
		item.set_metadata(0, monster_id)
		item.set_text(0, str(row.get("name", "")) + ("  （草稿）" if _is_draft(monster_id) else ""))
		item.set_text(1, MonsterDatabase.rank_label(rank))
		item.set_text(2, MonsterDatabase.realm_label(int(row.get("realm", 0)), catalog))
		item.set_custom_color(1, _rank_color(rank))
		item.set_tooltip_text(0, "%s\n%s" % [str(row.get("name", "")), monster_id])
		if monster_id == target:
			selected_item = item
	if selected_item != null:
		selected_item.select(0)
		if not keep_view:
			tree.scroll_to_item(selected_item)
	_refreshing_monster_tree = false
	if had_select_signal:
		tree.item_selected.connect(_on_tree_item_selected)
	%ListCount.text = "显示 %d 只 · 共 %d 只" % [shown.size(), _rows.size()]

func _sync_monster_tree_selection(monster_id := "") -> void:
	var target := monster_id if not monster_id.is_empty() else _active_id
	if target.is_empty():
		return
	var root: TreeItem = %MonsterTree.get_root()
	if root == null:
		return
	_refreshing_monster_tree = true
	var item := root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == target:
			if %MonsterTree.get_selected() != item:
				item.select(0)
			_refreshing_monster_tree = false
			return
		item = item.get_next()
	_refreshing_monster_tree = false

func _rank_color(rank: String) -> Color:
	match rank:
		"boss":
			return Color("e0a08a")
		"elite":
			return Color("d8c27c")
		_:
			return Color("8fb2a7")

func _on_search_changed(_text: String) -> void:
	_refresh_list(_active_id)

func _on_filter_changed(_index: int) -> void:
	_refresh_list(_active_id)

func _on_tree_item_selected() -> void:
	if _refreshing_monster_tree:
		return
	var item: TreeItem = %MonsterTree.get_selected()
	if item == null:
		return
	# Finish handling the click before running editor actions that can update the tree.
	_request_select.call_deferred(str(item.get_metadata(0)))

func _request_select(monster_id: String) -> void:
	if monster_id.is_empty() or monster_id == _active_id:
		return
	if _row_index(monster_id) < 0:
		return
	if _dirty:
		_pending_transition = func() -> void: _select_row(monster_id)
		_show_unsaved()
		return
	_select_row(monster_id)

func _select_row(monster_id: String, keep_dirty := false) -> void:
	var index := _row_index(monster_id)
	if index < 0:
		return
	_active_id = monster_id
	if not keep_dirty:
		_dirty = false
	var row: Dictionary = _rows[index]
	_apply_form(row)
	_refresh_skill_page(row)
	_refresh_behavior_page(row)
	_refresh_loot_page(row)
	_refresh_passive_page(row)
	_refresh_trigger_page(row)
	_refresh_readonly_tabs(row)
	_sync_monster_tree_selection(monster_id)
	_update_dirty_ui()

func _row(monster_id: String) -> Dictionary:
	var index := _row_index(monster_id)
	return _rows[index] if index >= 0 else {}

func _row_index(monster_id: String) -> int:
	for index in _rows.size():
		if _rows[index] is Dictionary and str(_rows[index].get("id", "")) == monster_id:
			return index
	return -1

func _saved_index(monster_id: String) -> int:
	for index in _saved_rows.size():
		if _saved_rows[index] is Dictionary and str(_saved_rows[index].get("id", "")) == monster_id:
			return index
	return -1

func _is_draft(monster_id: String) -> bool:
	return not monster_id.is_empty() and _saved_index(monster_id) < 0

func _apply_form(row: Dictionary) -> void:
	_loading_form = true
	_set_form_enabled(_can_edit)
	%NameEdit.text = str(row.get("name", ""))
	%IdEdit.text = str(row.get("id", ""))
	%IdEdit.editable = _can_edit and _is_draft(str(row.get("id", "")))
	if not _select_option(%RealmOption, int(row.get("realm", 1))):
		_select_option(%RealmOption, 1)
	if not _select_option(%RankOption, str(row.get("rank", "normal"))):
		_select_option(%RankOption, "normal")
	%RootOption.select(0)
	%HpSpin.value = int(row.get("hp", 1))
	%MpSpin.value = int(row.get("mp", 0))
	%AttackSpin.value = int(row.get("attack", 0))
	%DefenseSpin.value = int(row.get("defense", 0))
	%SpeedSpin.value = int(row.get("speed", 0))
	%DescriptionEdit.text = str(row.get("description", ""))
	%CritChanceValue.text = "%.0f%%（全局）" % (float(catalog.get("rules", {}).get("crit_chance", 0.0)) * 100.0)
	%CritDamageValue.text = "%.0f%%（全局）" % (float(catalog.get("rules", {}).get("crit_multiplier", 1.0)) * 100.0)
	%BehaviorSummary.text = "%d 条（行为页已开放编辑）" % _array_size(row.get("behaviors", []))
	%LootSummary.text = _loot_summary(row)
	_update_preview_from_form()
	_loading_form = false

func _set_form_enabled(enabled: bool) -> void:
	%NameEdit.editable = enabled
	%IdEdit.editable = enabled
	%RealmOption.disabled = not enabled
	%RankOption.disabled = not enabled
	%HpSpin.editable = enabled
	%MpSpin.editable = enabled
	%AttackSpin.editable = enabled
	%DefenseSpin.editable = enabled
	%SpeedSpin.editable = enabled
	%DescriptionEdit.editable = enabled
	%RootOption.disabled = true
	%IconValue.editable = false
	%CritChanceValue.editable = false
	%CritDamageValue.editable = false

func _collect_form() -> void:
	if _active_id.is_empty():
		return
	var index := _row_index(_active_id)
	if index < 0:
		return
	var row: Dictionary = _rows[index]
	# The draft ID is only committed on save. Keeping the old keyword here lets
	# duplicate-ID validation report the real problem instead of losing the row.
	row["name"] = %NameEdit.text.strip_edges()
	row["description"] = %DescriptionEdit.text
	row["realm"] = int(_selected_metadata(%RealmOption))
	row["rank"] = str(_selected_metadata(%RankOption))
	row["hp"] = int(%HpSpin.value)
	row["mp"] = int(%MpSpin.value)
	row["attack"] = int(%AttackSpin.value)
	row["defense"] = int(%DefenseSpin.value)
	row["speed"] = int(%SpeedSpin.value)

func _on_form_changed(_value: Variant = null) -> void:
	if _loading_form or not _can_edit or _active_id.is_empty():
		return
	_collect_form()
	_dirty = true
	_update_active_tree_row()
	_update_preview_from_form()
	_update_dirty_ui()

func _update_active_tree_row() -> void:
	var root: TreeItem = %MonsterTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == _active_id:
			var row := _row(_active_id)
			item.set_text(0, str(%NameEdit.text) + ("  （草稿）" if _is_draft(_active_id) else ""))
			item.set_text(1, MonsterDatabase.rank_label(str(row.get("rank", "normal"))))
			item.set_text(2, MonsterDatabase.realm_label(int(row.get("realm", 0)), catalog))
			item.set_custom_color(1, _rank_color(str(row.get("rank", "normal"))))
			return
		item = item.get_next()

func _update_preview_from_form() -> void:
	if _active_id.is_empty():
		%PreviewName.text = "未选择妖兽"
		%PreviewMeta.text = "—"
		%PreviewHp.text = "—"
		%PreviewMp.text = "—"
		%PreviewAttack.text = "—"
		%PreviewDefense.text = "—"
		%PreviewSpeed.text = "—"
		%CountSkills.text = "0"
		%CountBehaviors.text = "0"
		%CountPassives.text = "0"
		%CountLoot.text = "0"
		return
	var row := _row(_active_id)
	var name: String = str(%NameEdit.text).strip_edges()
	%PreviewName.text = name if not name.is_empty() else "未命名妖兽"
	%SkillPageTitle.text = "技能配置 — " + (name if not name.is_empty() else "未命名妖兽")
	%BehaviorPageTitle.text = "行为规则 — " + (name if not name.is_empty() else "未命名妖兽")
	%LootPageTitle.text = "掉落配置 — " + (name if not name.is_empty() else "未命名妖兽")
	%PassivesPageTitle.text = "被动效果 — " + (name if not name.is_empty() else "未命名妖兽")
	%MechanicsPageTitle.text = "特殊机制 — " + (name if not name.is_empty() else "未命名妖兽")
	var realm := int(_selected_metadata(%RealmOption))
	var rank := str(_selected_metadata(%RankOption))
	%PreviewMeta.text = "%s · %s" % [MonsterDatabase.realm_label(realm, catalog), MonsterDatabase.rank_label(rank)]
	%PreviewIcon.color = _rank_background(rank)
	%PreviewHp.text = str(int(%HpSpin.value))
	%PreviewMp.text = str(int(%MpSpin.value))
	%PreviewAttack.text = str(int(%AttackSpin.value))
	%PreviewDefense.text = str(int(%DefenseSpin.value))
	%PreviewSpeed.text = str(int(%SpeedSpin.value))
	%CountSkills.text = str(_array_size(row.get("skill_ids", [])))
	%CountBehaviors.text = str(_array_size(row.get("behaviors", [])))
	%CountPassives.text = str(_array_size(row.get("passives", [])))
	%CountLoot.text = str(_loot_entry_count(row))
	%BehaviorSummary.text = "%d 条（第三阶段已开放编辑）" % _array_size(row.get("behaviors", []))
	%LootSummary.text = _loot_summary(row)
	_refresh_validation_preview()

func _rank_background(rank: String) -> Color:
	match rank:
		"boss":
			return Color("2a1c1a")
		"elite":
			return Color("2a271a")
		_:
			return Color("0f2623")

func _refresh_readonly_tabs(row: Dictionary) -> void:
	_on_tab_changed(%Tabs.current_tab)

func _refresh_skill_page(row: Dictionary) -> void:
	var monster_name := str(row.get("name", "未选择妖兽"))
	%SkillPageTitle.text = "技能配置 — " + monster_name
	var ids: Array = row.get("skill_ids", []) if row.get("skill_ids", []) is Array else []
	if _selected_skill_id.is_empty() or _selected_skill_id not in ids:
		_selected_skill_id = str(ids[0]) if not ids.is_empty() else ""
	_refresh_skill_tree()
	_apply_skill_form()
	_update_skill_buttons()

func _clear_skill_page() -> void:
	_selected_skill_id = ""
	%SkillTree.clear()
	_clear_children(%EffectsList)
	%SkillPageTitle.text = "技能配置 — 未选择妖兽"
	%SkillHint.text = "当前妖兽尚未选择。添加已有技能或新建技能后，可在此编辑技能定义与引用。"
	%SkillEditorTitle.text = "未选择技能"
	%SkillNameEdit.text = ""
	%SkillIdValue.text = ""
	%SkillDescriptionEdit.text = ""
	%SkillScopeValue.text = "—"
	%SharedSkillWarning.text = ""
	%SharedSkillWarning.hide()
	%SharedConfirmCheck.hide()
	%SharedConfirmCheck.button_pressed = false
	_set_skill_form_enabled(false)
	%SaveSkillBtn.disabled = true
	%CopySkillBtn.disabled = true
	%RemoveSkillBtn.disabled = true

func _refresh_skill_tree() -> void:
	%SkillTree.clear()
	var root: TreeItem = %SkillTree.create_item()
	var row := _row(_active_id)
	var ids: Array = row.get("skill_ids", []) if row.get("skill_ids", []) is Array else []
	var selected_item: TreeItem = null
	for skill_id in ids:
		var skill := _skill(str(skill_id))
		var item: TreeItem = %SkillTree.create_item(root)
		item.set_metadata(0, str(skill_id))
		var skill_name := str(skill.get("name", "缺失技能"))
		item.set_text(0, skill_name)
		item.set_text(1, str(skill_id))
		item.set_text(2, "主动")
		item.set_text(3, str(int(skill.get("mp", 0))) if not skill.is_empty() else "—")
		item.set_text(4, str(int(skill.get("cooldown", 0))) if not skill.is_empty() else "—")
		item.set_text(5, _skill_effect_summary(skill) if not skill.is_empty() else "—")
		item.set_text(6, _skill_trigger_label(row, str(skill_id)) if not skill.is_empty() else "技能定义缺失")
		item.set_tooltip_text(0, "%s\n%s\n%s" % [skill_name, str(skill_id), _skill_effect_summary(skill)])
		if skill.is_empty():
			for column in 7:
				item.set_custom_color(column, Color("ef8f86"))
		if str(skill_id) == _selected_skill_id:
			selected_item = item
	if selected_item != null:
		_refreshing_skill_tree = true
		selected_item.select(0)
		%SkillTree.scroll_to_item(selected_item)
		_refreshing_skill_tree = false
	%SkillHint.text = "技能库当前只有主动技能；被动效果在独立页（第五阶段）。修改共享技能前请先确认影响范围，或使用“复制技能”。" if not ids.is_empty() else "当前妖兽没有配置技能；可从技能库添加，或新建技能。"

func _skill_effect_summary(skill: Dictionary) -> String:
	var effects: Variant = skill.get("effects", [])
	if not effects is Array or effects.is_empty():
		return "—"
	var parts: Array = []
	for effect in effects:
		parts.append(_effect_summary(effect))
	var text := "；".join(parts)
	return text.substr(0, 48) + ("…" if text.length() > 48 else "")

func _skill_trigger_label(row: Dictionary, skill_id: String) -> String:
	var skill := _skill(skill_id)
	var ordinary := bool(skill.get("ordinary", false))
	var behaviors: Variant = row.get("behaviors", [])
	if behaviors is Array:
		for behavior in behaviors:
			if not behavior is Dictionary:
				continue
			if str(behavior.get("skill", "")) == skill_id:
				return "默认行动（普通攻击）" if ordinary else "行为规则：" + str(behavior.get("name", behavior.get("id", "")))
			var conditions: Variant = behavior.get("conditions", [])
			if conditions is Array:
				for condition in conditions:
					if condition is Dictionary and str(condition.get("skill", "")) == skill_id:
						return "行为条件：" + str(behavior.get("name", behavior.get("id", "")))
	return "普通攻击候选（未绑定行为）" if ordinary else "未绑定行为（不会主动施放）"

func _on_skill_tree_selected() -> void:
	if _refreshing_skill_tree:
		return
	var item: TreeItem = %SkillTree.get_selected()
	if item == null:
		return
	_select_skill(str(item.get_metadata(0)))

func _select_skill(skill_id: String) -> void:
	if skill_id.is_empty() or _skill_index(skill_id) < 0:
		return
	_selected_skill_id = skill_id
	_select_skill_tree_item(skill_id)
	_apply_skill_form()
	_refresh_validation_preview()
	_update_skill_buttons()
	_update_dirty_ui()

func _select_skill_tree_item(skill_id: String) -> void:
	var root: TreeItem = %SkillTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == skill_id:
			_refreshing_skill_tree = true
			item.select(0)
			%SkillTree.scroll_to_item(item)
			_refreshing_skill_tree = false
			return
		item = item.get_next()

func _apply_skill_form() -> void:
	_loading_skill = true
	_effect_context = "skill"
	_effect_owner_id = ""
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		%SkillEditorTitle.text = "未选择技能"
		%SharedSkillWarning.text = "当前妖兽没有可编辑技能。"
		%SharedSkillWarning.show()
		%SharedConfirmCheck.hide()
		%SkillNameEdit.text = ""
		%SkillIdValue.text = ""
		%SkillTypeValue.text = "—"
		%SkillDescriptionEdit.text = ""
		%SkillTargetOption.select(0)
		%SkillMpSpin.value = 0
		%SkillCooldownSpin.value = 0
		%SkillOrdinaryCheck.button_pressed = false
		%SkillScopeValue.text = "—"
		_clear_children(%EffectsList)
		_set_skill_form_enabled(false)
		%SaveSkillBtn.disabled = true
		_loading_skill = false
		return
	%SkillEditorTitle.text = "选中技能：" + str(skill.get("name", _selected_skill_id))
	%SkillNameEdit.text = str(skill.get("name", ""))
	%SkillIdValue.text = _selected_skill_id
	%SkillTypeValue.text = "主动"
	%SkillDescriptionEdit.text = str(skill.get("description", ""))
	if not _select_option(%SkillTargetOption, str(skill.get("target", "enemy"))):
		_select_option(%SkillTargetOption, "enemy")
	%SkillMpSpin.value = int(skill.get("mp", 0))
	%SkillCooldownSpin.value = int(skill.get("cooldown", 0))
	%SkillOrdinaryCheck.button_pressed = bool(skill.get("ordinary", false))
	var scope: Array = skill.get("scope", []) if skill.get("scope", []) is Array else []
	%SkillScopeValue.text = "、".join(scope) if not scope.is_empty() else "未设置"
	_set_skill_form_enabled(_can_edit)
	%SharedConfirmCheck.button_pressed = false
	_build_effects_list(%EffectsList, %AddEffectBtn)
	_update_skill_warning()
	_loading_skill = false

func _set_skill_form_enabled(enabled: bool) -> void:
	%SkillNameEdit.editable = enabled
	%SkillDescriptionEdit.editable = enabled
	%SkillTargetOption.disabled = not enabled
	%SkillMpSpin.editable = enabled
	%SkillCooldownSpin.editable = enabled
	%SkillOrdinaryCheck.disabled = not enabled
	%AddEffectBtn.disabled = not enabled

func _update_skill_buttons() -> void:
	var has_monster := not _active_id.is_empty()
	var has_skill := not _selected_skill_id.is_empty() and _skill_index(_selected_skill_id) >= 0
	%AddSkillBtn.disabled = not (_can_edit and has_monster)
	%NewSkillBtn.disabled = not (_can_edit and has_monster)
	%CopySkillBtn.disabled = not (_can_edit and has_skill)
	%RemoveSkillBtn.disabled = not (_can_edit and has_skill)
	%SaveSkillBtn.disabled = not (_can_edit and _dirty)
	%AddEffectBtn.disabled = not (_can_edit and has_skill)

func _on_skill_name_changed(text: String) -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["name"] = text
	_after_skill_edit()

func _on_skill_description_changed() -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["description"] = %SkillDescriptionEdit.text
	_after_skill_edit()

func _on_skill_target_changed(_index: int) -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["target"] = str(_selected_metadata(%SkillTargetOption))
	_after_skill_edit()

func _on_skill_mp_changed(value: float) -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["mp"] = int(value)
	_after_skill_edit()

func _on_skill_cooldown_changed(value: float) -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["cooldown"] = int(value)
	_after_skill_edit()

func _on_skill_ordinary_toggled(pressed: bool) -> void:
	if _loading_skill or not _can_edit:
		return
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["ordinary"] = pressed
	_after_skill_edit()

func _on_shared_confirm_toggled(pressed: bool) -> void:
	if _loading_skill:
		return
	if not _selected_skill_id.is_empty():
		_shared_confirmed[_selected_skill_id] = pressed

func _after_skill_edit() -> void:
	if _loading_skill or not _can_edit:
		return
	_dirty = true
	_skills_dirty = true
	if not _selected_skill_id.is_empty() and _selected_skill_id not in _dirty_skill_ids:
		_dirty_skill_ids.append(_selected_skill_id)
	_update_skill_tree_row()
	_update_skill_warning()
	_refresh_validation_preview()
	_update_dirty_ui()

func _update_skill_tree_row() -> void:
	var root: TreeItem = %SkillTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == _selected_skill_id:
			var skill := _skill(_selected_skill_id)
			var skill_name := str(skill.get("name", _selected_skill_id))
			item.set_text(0, skill_name)
			item.set_text(3, str(int(skill.get("mp", 0))))
			item.set_text(4, str(int(skill.get("cooldown", 0))))
			item.set_text(5, _skill_effect_summary(skill))
			item.set_text(6, _skill_trigger_label(_row(_active_id), _selected_skill_id))
			%SkillEditorTitle.text = "选中技能：" + skill_name
			return
		item = item.get_next()

func _update_skill_warning() -> void:
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		%SharedSkillWarning.hide()
		%SharedConfirmCheck.hide()
		return
	var references := MonsterDatabase.skill_references(_selected_skill_id, _rows)
	var other_monsters := {}
	for reference in references:
		if str(reference.get("monster_id", "")) != _active_id:
			other_monsters[str(reference.get("monster_id", ""))] = true
	var shared := not other_monsters.is_empty()
	%SharedSkillWarning.show()
	if shared:
		var names: Array = []
		for reference in references:
			var monster_id := str(reference.get("monster_id", ""))
			if monster_id != _active_id and monster_id not in names:
				names.append(monster_id)
		%SharedSkillWarning.text = "共享技能：仍被 %d 只其他妖兽引用（%s）。保存会修改公共技能定义，影响所有引用者；若只想修改当前妖兽，请先“复制技能”。" % [names.size(), "、".join(names)]
		%SharedConfirmCheck.show()
		%SharedConfirmCheck.text = "我确认修改公共技能定义（影响 %d 只其他妖兽）" % names.size()
		%SharedConfirmCheck.disabled = not _can_edit
		%SharedConfirmCheck.set_pressed_no_signal(bool(_shared_confirmed.get(_selected_skill_id, false)))
	else:
		%SharedSkillWarning.text = "仅当前妖兽引用此技能；保存只影响当前妖兽。新建技能和复制技能的副本会进入共享技能库，但当前只有本妖兽引用。"
		%SharedConfirmCheck.hide()
		%SharedConfirmCheck.set_pressed_no_signal(false)
		_shared_confirmed.erase(_selected_skill_id)

func _skill_is_shared(skill_id: String) -> bool:
	for reference in MonsterDatabase.skill_references(skill_id, _rows):
		if str(reference.get("monster_id", "")) != _active_id:
			return true
	return false

func _skill(skill_id: String) -> Dictionary:
	var index := _skill_index(skill_id)
	return _skills[index] if index >= 0 else {}

func _skill_index(skill_id: String) -> int:
	for index in _skills.size():
		if _skills[index] is Dictionary and str(_skills[index].get("id", "")) == skill_id:
			return index
	return -1

func _default_effect(kind: String) -> Dictionary:
	match kind:
		"status":
			return {"type": "status", "status": "poison", "chance": 1.0, "turns": 2, "layers": 1, "requires_hit": true, "target": "enemy"}
		"stat":
			return {"type": "stat", "stat": "attack", "value": 0.1, "turns": 2, "layers": 1, "chance": 1.0, "target": "self"}
		"heal":
			return {"type": "heal", "power": 0.5}
		"shield":
			return {"type": "shield", "power": 0.5, "turns": 2}
		"mana":
			return {"type": "mana", "amount": 5, "drain": false}
		"cleanse":
			return {"type": "cleanse", "count": 1}
		"phase":
			return {"type": "phase", "value": "phase_1"}
		_:
			return {"type": "damage", "power": 1.0}

func _default_effect_for_context(kind: String) -> Dictionary:
	var effect := _default_effect(kind)
	if _effect_context in ["passive", "trigger"] and str(effect.get("type", "")) in ["status", "stat"]:
		effect["target"] = "self"
		if str(effect.get("type", "")) == "status":
			effect["status"] = "attack_up"
			effect["requires_hit"] = false
	return effect

func _effect_owner_effects() -> Array:
	match _effect_context:
		"passive":
			var passives: Variant = _row(_active_id).get("passives", [])
			return passives if passives is Array else []
		"trigger":
			var trigger := _trigger_rule(_effect_owner_id)
			var effects: Variant = trigger.get("effects", [])
			return effects if effects is Array else []
		_:
			var skill := _skill(_selected_skill_id)
			var effects: Variant = skill.get("effects", [])
			return effects if effects is Array else []

func _add_effect() -> void:
	if not _can_edit:
		return
	var effects := _effect_owner_effects()
	if _effect_context == "skill" and _skill(_selected_skill_id).is_empty():
		return
	if _effect_context == "trigger" and _trigger_rule(_effect_owner_id).is_empty():
		return
	var default_kind := "damage" if _effect_context == "skill" else "stat"
	effects.append(_default_effect_for_context(default_kind))
	_after_effect_edit()
	_rebuild_effect_editor()

func _remove_effect(index: int) -> void:
	if not _can_edit:
		return
	var effects := _effect_owner_effects()
	if effects.size() <= 1:
		_set_status("至少需要一个效果组件；请先添加新效果再移除。", true)
		return
	if index < 0 or index >= effects.size():
		return
	effects.remove_at(index)
	_after_effect_edit()
	_rebuild_effect_editor.call_deferred()

func _change_effect_type(index: int, kind: String) -> void:
	if not _can_edit:
		return
	var effects := _effect_owner_effects()
	if index < 0 or index >= effects.size():
		return
	effects[index] = _default_effect_for_context(kind)
	_after_effect_edit()
	_rebuild_effect_editor.call_deferred()

func _rebuild_effect_editor() -> void:
	match _effect_context:
		"trigger":
			_build_effects_list(%TriggerEffectsList, %AddTriggerEffectBtn)
		"passive":
			_apply_passive_form()
		_:
			_build_effects_list()

func _effect_at(index: int) -> Dictionary:
	var effects := _effect_owner_effects()
	if index < 0 or index >= effects.size():
		return {}
	return effects[index] if effects[index] is Dictionary else {}

func _after_effect_edit() -> void:
	match _effect_context:
		"passive":
			_after_passive_edit()
		"trigger":
			_after_trigger_edit()
		_:
			_after_skill_edit()

func _set_effect_number(index: int, key: String, value: float, factor := 1.0, integer := false, zero_removes := false) -> void:
	if _loading_effect or _loading_skill or not _can_edit:
		return
	var effect := _effect_at(index)
	if effect.is_empty():
		return
	var stored: Variant = value * factor
	if integer:
		stored = int(value)
	if zero_removes and is_zero_approx(float(stored)):
		effect.erase(key)
	else:
		effect[key] = stored
	_after_effect_edit()

func _set_effect_bool(index: int, key: String, value: bool) -> void:
	if _loading_effect or _loading_skill or not _can_edit:
		return
	var effect := _effect_at(index)
	if effect.is_empty():
		return
	effect[key] = value
	_after_effect_edit()

func _set_effect_text(index: int, key: String, value: String) -> void:
	if _loading_effect or _loading_skill or not _can_edit:
		return
	var effect := _effect_at(index)
	if effect.is_empty():
		return
	effect[key] = value
	_after_effect_edit()

func _set_effect_option(index: int, key: String, option: OptionButton) -> void:
	if _loading_effect or _loading_skill or not _can_edit:
		return
	var effect := _effect_at(index)
	if effect.is_empty():
		return
	effect[key] = str(_selected_metadata(option))
	_after_effect_edit()

func _set_effect_optional_value(index: int, key: String, enabled: bool, spin: SpinBox) -> void:
	if _loading_effect or _loading_skill or not _can_edit:
		return
	var effect := _effect_at(index)
	if effect.is_empty():
		return
	if enabled:
		effect[key] = spin.value
	else:
		effect.erase(key)
	_after_effect_edit()

func _build_effects_list(container: VBoxContainer = null, add_button: Button = null) -> void:
	_effect_container = container if container != null else %EffectsList
	_effect_add_button = add_button if add_button != null else %AddEffectBtn
	_clear_children(_effect_container)
	var owner_exists := true
	match _effect_context:
		"passive":
			owner_exists = not _row(_active_id).is_empty()
		"trigger":
			owner_exists = not _trigger_rule(_effect_owner_id).is_empty()
		_:
			owner_exists = not _skill(_selected_skill_id).is_empty()
	if not owner_exists:
		_add_note(_effect_container, "未选择可编辑对象。")
		_effect_add_button.disabled = true
		return
	var effects := _effect_owner_effects()
	if effects.is_empty():
		_add_note(_effect_container, "当前没有效果组件；至少添加一个后才能保存。", Color("d8c27c"))
		_effect_add_button.disabled = true
		return
	var was_loading := _loading_effect
	_loading_effect = true
	for index in effects.size():
		if effects[index] is Dictionary:
			_build_effect_panel(_effect_container, index, effects[index])
	_loading_effect = was_loading
	_effect_add_button.disabled = not _can_edit

func _build_effect_panel(container: VBoxContainer, index: int, effect: Dictionary) -> void:
	var box := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "效果 %d" % (index + 1)
	title.custom_minimum_size.x = 76
	header.add_child(title)
	var type_option := OptionButton.new()
	var types: Array = EFFECT_TYPES if _effect_context == "skill" else PASSIVE_EFFECT_TYPES.duplicate()
	var current_type := str(effect.get("type", "damage"))
	if current_type not in types:
		types.push_front(current_type)
	for kind in types:
		_add_option(type_option, str(EFFECT_LABELS.get(kind, kind)), kind)
	_select_option(type_option, current_type)
	type_option.disabled = not _can_edit
	type_option.item_selected.connect(func(_selected: int) -> void: _change_effect_type(index, str(_selected_metadata(type_option))))
	header.add_child(type_option)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var remove := Button.new()
	remove.text = "移除此效果"
	remove.disabled = not _can_edit
	remove.pressed.connect(func() -> void: _remove_effect(index))
	header.add_child(remove)
	box.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_build_effect_fields(grid, index, effect)
	box.add_child(HSeparator.new())
	container.add_child(box)

func _build_effect_fields(grid: GridContainer, index: int, effect: Dictionary) -> void:
	var kind := str(effect.get("type", "damage"))
	var self_only := _effect_context in ["passive", "trigger"]
	if self_only and kind in ["status", "stat"]:
		effect["target"] = "self"
	match kind:
		"damage":
			_add_spin_cell(grid, "伤害倍率", float(effect.get("power", 0)), 0.0, 99.0, 0.05, index, "power")
			_add_spin_cell(grid, "攻击段数", float(effect.get("hits", 1)), 1, 99, 1, index, "hits", 1.0, true)
			_add_spin_cell(grid, "固定伤害", float(effect.get("flat", 0)), 0, 99999, 1, index, "flat", 1.0, true)
			_add_spin_cell(grid, "最大生命伤害（%）", float(effect.get("percent_max_hp", 0)) * 100.0, 0, 100, 1, index, "percent_max_hp", 0.01)
			_add_check_cell(grid, "可暴击", bool(effect.get("can_crit", false)), index, "can_crit")
			_add_spin_cell(grid, "吸血（%）", float(effect.get("lifesteal", 0)) * 100.0, 0, 100, 1, index, "lifesteal", 0.01)
		"status":
			_add_status_cell(grid, effect, index)
			_add_spin_cell(grid, "触发概率（%）", float(effect.get("chance", 1.0)) * 100.0, 0, 100, 1, index, "chance", 0.01)
			_add_spin_cell(grid, "持续回合", float(effect.get("turns", 1)), 1, 99, 1, index, "turns", 1.0, true)
			_add_spin_cell(grid, "层数", float(effect.get("layers", 1)), 1, 99, 1, index, "layers", 1.0, true)
			_add_mode_cell(grid, effect, index)
			if self_only:
				_add_note(grid, "作用目标：自身（被动/触发固定）")
			else:
				_add_effect_target_cell(grid, effect, index)
			if not self_only:
				_add_check_cell(grid, "需要命中", bool(effect.get("requires_hit", false)), index, "requires_hit")
			_add_check_cell(grid, "可驱散", bool(effect.get("dispellable", true)), index, "dispellable")
			_add_spin_cell(grid, "最大层数（0=不限）", float(effect.get("max_layers", 0)), 0, 99, 1, index, "max_layers", 1.0, true, true)
			_add_optional_value_cell(grid, effect, index)
		"stat":
			_add_stat_cell(grid, effect, index)
			_add_spin_cell(grid, "修正幅度（%）", float(effect.get("value", 0)) * 100.0, -100, 100, 1, index, "value", 0.01)
			_add_spin_cell(grid, "持续回合", float(effect.get("turns", 1)), 1, 99, 1, index, "turns", 1.0, true)
			_add_spin_cell(grid, "层数", float(effect.get("layers", 1)), 1, 99, 1, index, "layers", 1.0, true)
			_add_spin_cell(grid, "触发概率（%）", float(effect.get("chance", 1.0)) * 100.0, 0, 100, 1, index, "chance", 0.01)
			if self_only:
				_add_note(grid, "作用目标：自身（被动/触发固定）")
			else:
				_add_effect_target_cell(grid, effect, index)
			if not self_only:
				_add_check_cell(grid, "需要命中", bool(effect.get("requires_hit", false)), index, "requires_hit")
			_add_spin_cell(grid, "最大层数（0=不限）", float(effect.get("max_layers", 0)), 0, 99, 1, index, "max_layers", 1.0, true, true)
		"heal":
			_add_spin_cell(grid, "攻击倍率", float(effect.get("power", 0)), 0, 99, 0.05, index, "power")
			_add_spin_cell(grid, "固定治疗", float(effect.get("amount", 0)), 0, 999999, 1, index, "amount", 1.0, true)
			_add_spin_cell(grid, "最大生命治疗（%）", float(effect.get("percent_max_hp", 0)) * 100.0, 0, 100, 1, index, "percent_max_hp", 0.01)
		"shield":
			_add_spin_cell(grid, "攻击倍率", float(effect.get("power", 0)), 0, 99, 0.05, index, "power")
			_add_spin_cell(grid, "最大生命护盾（%）", float(effect.get("percent_max_hp", 0)) * 100.0, 0, 100, 1, index, "percent_max_hp", 0.01)
			_add_spin_cell(grid, "持续回合", float(effect.get("turns", 2)), 1, 99, 1, index, "turns", 1.0, true)
		"mana":
			_add_spin_cell(grid, "灵力数值", float(effect.get("amount", 0)), 0, 999999, 1, index, "amount", 1.0, true)
			if _effect_context == "skill":
				_add_check_cell(grid, "抽取目标灵力", bool(effect.get("drain", false)), index, "drain")
			else:
				_add_note(grid, "作用于自身：恢复灵力（被动/触发不支持抽取）")
		"cleanse":
			_add_spin_cell(grid, "驱散数量", float(effect.get("count", 1)), 1, 99, 1, index, "count", 1.0, true)
		"phase":
			_add_text_cell(grid, "阶段名称", str(effect.get("value", "")), index, "value")

func _add_field_cell(grid: GridContainer, label: String, control: Control) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caption := Label.new()
	caption.text = label
	cell.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(control)
	grid.add_child(cell)

func _add_spin_cell(grid: GridContainer, label: String, value: float, minimum: float, maximum: float, step: float,
		index: int, key: String, factor := 1.0, integer := false, zero_removes := false) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.editable = _can_edit
	spin.value_changed.connect(func(new_value: float) -> void: _set_effect_number(index, key, new_value, factor, integer, zero_removes))
	_add_field_cell(grid, label, spin)

func _add_check_cell(grid: GridContainer, label: String, value: bool, index: int, key: String) -> void:
	var check := CheckBox.new()
	check.text = "启用"
	check.button_pressed = value
	check.disabled = not _can_edit
	check.toggled.connect(func(pressed: bool) -> void: _set_effect_bool(index, key, pressed))
	_add_field_cell(grid, label, check)

func _add_text_cell(grid: GridContainer, label: String, value: String, index: int, key: String) -> void:
	var edit := LineEdit.new()
	edit.text = value
	edit.editable = _can_edit
	edit.text_changed.connect(func(text: String) -> void: _set_effect_text(index, key, text))
	_add_field_cell(grid, label, edit)

func _add_status_cell(grid: GridContainer, effect: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	var statuses: Dictionary = catalog.get("spell_growth", {}).get("statuses", {})
	var self_only := _effect_context in ["passive", "trigger"]
	var current := str(effect.get("status", "poison"))
	for status_id in statuses:
		var key := str(status_id)
		if self_only and not _monster_status_supported(key):
			continue
		_add_option(option, str(statuses[status_id].get("name", status_id)), status_id)
	if not _select_option(option, current):
		var suffix := "（当前/不支持）" if statuses.has(current) else "（不存在）"
		var current_name := str(statuses.get(current, {}).get("name", current)) if statuses.has(current) else current
		_add_option(option, current_name + suffix, current)
		_select_option(option, current)
	option.item_selected.connect(func(_selected: int) -> void: _set_effect_option(index, "status", option))
	_add_field_cell(grid, "状态", option)

func _add_stat_cell(grid: GridContainer, effect: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	for stat in STAT_OPTIONS:
		_add_option(option, str(MonsterDatabase.STAT_LABELS.get(stat, stat)), stat)
	_select_option(option, str(effect.get("stat", "attack")))
	option.item_selected.connect(func(_selected: int) -> void: _set_effect_option(index, "stat", option))
	_add_field_cell(grid, "属性", option)

func _add_mode_cell(grid: GridContainer, effect: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	for mode in STATUS_MODE_OPTIONS:
		_add_option(option, str(MonsterDatabase.STATUS_MODE_LABELS.get(mode, mode)), mode)
	_select_option(option, str(effect.get("mode", "stack")))
	option.item_selected.connect(func(_selected: int) -> void: _set_effect_option(index, "mode", option))
	_add_field_cell(grid, "叠加方式", option)

func _add_effect_target_cell(grid: GridContainer, effect: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	_add_option(option, "敌方", "enemy")
	_add_option(option, "自身", "self")
	_select_option(option, str(effect.get("target", "enemy")))
	option.item_selected.connect(func(_selected: int) -> void: _set_effect_option(index, "target", option))
	_add_field_cell(grid, "作用目标", option)

func _add_optional_value_cell(grid: GridContainer, effect: Dictionary, index: int) -> void:
	var row := HBoxContainer.new()
	var check := CheckBox.new()
	check.text = "启用"
	check.button_pressed = effect.has("value")
	check.disabled = not _can_edit
	var spin := SpinBox.new()
	spin.min_value = -100.0
	spin.max_value = 100.0
	spin.step = 0.01
	spin.value = float(effect.get("value", 0))
	spin.editable = check.button_pressed and _can_edit
	check.toggled.connect(func(pressed: bool) -> void:
		spin.editable = pressed and _can_edit
		_set_effect_optional_value(index, "value", pressed, spin))
	spin.value_changed.connect(func(new_value: float) -> void:
		if check.button_pressed:
			_set_effect_number(index, "value", new_value))
	row.add_child(check)
	row.add_child(spin)
	_add_field_cell(grid, "状态数值（可选）", row)

func _open_skill_picker() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	%SkillPickerSearch.text = ""
	_refresh_skill_picker()
	%SkillPickerOverlay.show()
	%SkillPickerSearch.grab_focus()

func _close_skill_picker() -> void:
	%SkillPickerOverlay.hide()

func _on_skill_picker_search(_text: String) -> void:
	_refresh_skill_picker()

func _refresh_skill_picker() -> void:
	var query := str(%SkillPickerSearch.text).strip_edges().to_lower()
	var row := _row(_active_id)
	var current: Array = row.get("skill_ids", []) if row.get("skill_ids", []) is Array else []
	%SkillPickerList.clear()
	var count := 0
	for skill in _skills:
		if not skill is Dictionary:
			continue
		var skill_id := str(skill.get("id", ""))
		if skill_id in current:
			continue
		var scope: Variant = skill.get("scope", [])
		if scope is Array and not scope.is_empty() and "monster" not in scope:
			continue
		var skill_name := str(skill.get("name", skill_id))
		if not query.is_empty() and not skill_name.to_lower().contains(query) and not skill_id.to_lower().contains(query):
			continue
		var index: int = int(%SkillPickerList.add_item("%s · %s · MP %d · 冷却 %d" % [skill_name, skill_id, int(skill.get("mp", 0)), int(skill.get("cooldown", 0))]))
		%SkillPickerList.set_item_metadata(index, skill_id)
		%SkillPickerList.set_item_tooltip(index, str(skill.get("description", "")))
		count += 1
	%SkillPickerInfo.text = "可添加技能：%d 个。技能引用现有共享技能库；添加不会复制定义。" % count if count > 0 else "没有可添加的技能（可能已全部配置，或搜索无结果）。"
	%SkillPickerAddBtn.disabled = true

func _on_skill_picker_selected(_index: int) -> void:
	var selected: PackedInt32Array = %SkillPickerList.get_selected_items()
	%SkillPickerAddBtn.disabled = selected.is_empty()
	if selected.is_empty():
		return
	var skill := _skill(str(%SkillPickerList.get_item_metadata(selected[0])))
	%SkillPickerInfo.text = "%s\n%s" % [str(skill.get("name", "")), str(skill.get("description", ""))]

func _add_picked_skill() -> void:
	var selected: PackedInt32Array = %SkillPickerList.get_selected_items()
	if selected.is_empty() or _active_id.is_empty():
		return
	var skill_id := str(%SkillPickerList.get_item_metadata(selected[0]))
	var row := _row(_active_id)
	if not row.get("skill_ids") is Array:
		row["skill_ids"] = []
	if skill_id in row.skill_ids:
		_close_skill_picker()
		return
	row.skill_ids.append(skill_id)
	_dirty = true
	_selected_skill_id = skill_id
	_close_skill_picker()
	_refresh_skill_page(row)
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已添加技能引用：%s（%s）。保存后写入妖兽配置。" % [str(_skill(skill_id).get("name", skill_id)), skill_id])

func _create_new_skill() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	var draft := MonsterDatabase.create_skill_draft(MonsterDatabase.ids_of(_skills))
	_skills.append(draft)
	var row := _row(_active_id)
	if not row.get("skill_ids") is Array:
		row["skill_ids"] = []
	row.skill_ids.append(str(draft.id))
	_selected_skill_id = str(draft.id)
	_dirty = true
	_skills_dirty = true
	if _selected_skill_id not in _dirty_skill_ids:
		_dirty_skill_ids.append(_selected_skill_id)
	_refresh_skill_page(row)
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已创建技能草稿：%s。填写效果后保存，技能库与妖兽引用会一起写入。" % _selected_skill_id)
	%SkillNameEdit.grab_focus()
	%SkillNameEdit.select_all()

func _request_copy_skill() -> void:
	if not _can_edit or _selected_skill_id.is_empty():
		return
	var source := _skill(_selected_skill_id).duplicate(true)
	if source.is_empty():
		return
	var original_id := _selected_skill_id
	# The copy gets the current edits. If the original was edited and is shared,
	# restore the saved definition so other monsters keep their original behavior.
	if original_id in _dirty_skill_ids:
		var saved := _saved_skill(original_id)
		var original_index := _skill_index(original_id)
		if not saved.is_empty() and original_index >= 0:
			_skills[original_index] = saved.duplicate(true)
		elif saved.is_empty() and original_index >= 0:
			# A new, never-saved skill has no other monster references; the copy
			# replaces it instead of leaving an orphan definition behind.
			_skills.remove_at(original_index)
		_dirty_skill_ids.erase(original_id)
		_shared_confirmed.erase(original_id)
	var copy := MonsterDatabase.copy_skill_draft(source, MonsterDatabase.ids_of(_skills))
	_skills.append(copy)
	MonsterDatabase.replace_skill_reference(_row(_active_id), original_id, str(copy.id))
	_selected_skill_id = str(copy.id)
	_dirty = true
	_skills_dirty = true
	if _selected_skill_id not in _dirty_skill_ids:
		_dirty_skill_ids.append(_selected_skill_id)
	_refresh_skill_page(_row(_active_id))
	_refresh_behavior_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已复制技能为副本：%s。当前妖兽的技能与行为引用已切换到副本；原技能和其他妖兽不受影响，保存后写入。" % _selected_skill_id)

func _saved_skill(skill_id: String) -> Dictionary:
	for skill in _saved_skills:
		if skill is Dictionary and str(skill.get("id", "")) == skill_id:
			return skill
	return {}

func _request_remove_skill() -> void:
	if not _can_edit or _selected_skill_id.is_empty():
		return
	var row := _row(_active_id)
	var behavior_refs: Array = []
	for reference in MonsterDatabase.skill_references(_selected_skill_id, [row]):
		if str(reference.get("detail", "")).begins_with("行为"):
			behavior_refs.append(reference)
	if not behavior_refs.is_empty():
		var lines: Array = ["技能“%s”仍被当前妖兽的行为规则引用，不能只从技能列表移除：" % str(_skill(_selected_skill_id).get("name", _selected_skill_id))]
		for reference in behavior_refs:
			lines.append("· " + str(reference.get("detail", "")))
		lines.append("请先在第三阶段开放的行为编辑中替换或移除对应规则。")
		_show_message("无法移除技能", "\n".join(lines), Vector2i(760, 360))
		return
	%RemoveSkillDialog.dialog_text = "从当前妖兽移除技能“%s”（%s）？\n只移除当前妖兽的引用，不删除技能库定义；其他妖兽引用不受影响。" % [
		str(_skill(_selected_skill_id).get("name", "")), _selected_skill_id]
	%RemoveSkillDialog.popup_centered(Vector2i(700, 280))

func _confirm_remove_skill() -> void:
	%RemoveSkillDialog.hide()
	if _selected_skill_id.is_empty():
		return
	var row := _row(_active_id)
	if not MonsterDatabase.remove_skill_from_monster(row, _selected_skill_id):
		return
	_dirty = true
	var ids: Array = row.get("skill_ids", []) if row.get("skill_ids", []) is Array else []
	_selected_skill_id = str(ids[0]) if not ids.is_empty() else ""
	_refresh_skill_page(row)
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已从当前妖兽移除技能引用。技能库定义保留，其他妖兽不受影响。")

func _refresh_behavior_page(row: Dictionary) -> void:
	var monster_name := str(row.get("name", "未选择妖兽"))
	%BehaviorPageTitle.text = "行为规则 — " + monster_name
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	if _selected_behavior_id.is_empty() or _behavior_index(_selected_behavior_id) < 0:
		_selected_behavior_id = str(rules[0].get("id", "")) if not rules.is_empty() and rules[0] is Dictionary else ""
	_refresh_behavior_tree()
	_apply_behavior_form()
	_update_behavior_buttons()

func _clear_behavior_page() -> void:
	_selected_behavior_id = ""
	%BehaviorTree.clear()
	_clear_children(%ConditionsList)
	%BehaviorPageTitle.text = "行为规则 — 未选择妖兽"
	%BehaviorHint.text = "当前妖兽尚未选择。添加规则后可配置条件、动作、概率、次数和冷却。"
	%BehaviorEditorTitle.text = "未选择规则"
	%BehaviorWarning.text = ""
	%BehaviorNameEdit.text = ""
	%BehaviorEnabledCheck.button_pressed = true
	%BehaviorPrioritySpin.value = 100
	%BehaviorModeOption.select(0)
	%BehaviorActionOption.select(0)
	%BehaviorTargetOption.select(1)
	%BehaviorChanceSpin.value = 100
	%BehaviorMaxUsesSpin.value = 0
	%BehaviorCooldownSpin.value = 0
	%BehaviorOnFailOption.select(0)
	%BehaviorSkillOption.clear()
	_set_behavior_form_enabled(false)
	%SaveBehaviorBtn.disabled = true
	%CopyRuleBtn.disabled = true
	%DeleteRuleBtn.disabled = true
	%MoveUpBtn.disabled = true
	%MoveDownBtn.disabled = true

func _sorted_behavior_indexes(row: Dictionary) -> Array:
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	var ordered: Array = []
	for index in rules.size():
		if rules[index] is Dictionary:
			ordered.append(index)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var pa := int(rules[a].get("priority", 0))
		var pb := int(rules[b].get("priority", 0))
		return pa > pb if pa != pb else a < b)
	return ordered

func _refresh_behavior_tree() -> void:
	%BehaviorTree.clear()
	var root: TreeItem = %BehaviorTree.create_item()
	var row := _row(_active_id)
	var ordered := _sorted_behavior_indexes(row)
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	var selected_item: TreeItem = null
	for position in ordered.size():
		var index: int = ordered[position]
		var rule: Dictionary = rules[index]
		var rule_id := str(rule.get("id", ""))
		var item: TreeItem = %BehaviorTree.create_item(root)
		item.set_metadata(0, rule_id)
		item.set_text(0, "%02d" % (position + 1))
		item.set_text(1, _behavior_display_name(rule))
		item.set_text(2, str(int(rule.get("priority", 0))))
		item.set_text(3, str(BEHAVIOR_ACTION_LABELS.get(str(rule.get("action", "attack")), rule.get("action", ""))))
		item.set_text(4, _behavior_condition_summary(rule))
		item.set_text(5, "%.0f%%" % (float(rule.get("chance", 1.0)) * 100.0))
		var max_uses := int(rule.get("max_uses", 0))
		item.set_text(6, "不限" if max_uses <= 0 else str(max_uses))
		item.set_text(7, str(int(rule.get("cooldown", 0))))
		item.set_text(8, "启用" if rule.get("enabled", true) == true else "停用")
		item.set_tooltip_text(1, "%s\n%s" % [_behavior_display_name(rule), rule_id])
		item.set_tooltip_text(4, _behavior_condition_summary(rule))
		if rule.get("enabled", true) != true:
			item.set_custom_color(8, Color("94a8a2"))
		if rule_id == _selected_behavior_id:
			selected_item = item
	if selected_item != null:
		_refreshing_behavior_tree = true
		selected_item.select(0)
		%BehaviorTree.scroll_to_item(selected_item)
		_refreshing_behavior_tree = false
	%BehaviorHint.text = "共 %d 条规则；按顺序检查。规则不满足时会继续下一条，全部失败时回退普通攻击。目标：一对一战斗固定为敌方，多目标/友方目标尚未接入。" % ordered.size() if not ordered.is_empty() else "当前妖兽没有行为规则；战斗会回退为普通攻击。可添加规则。"
	_update_behavior_buttons()

func _behavior_display_name(rule: Dictionary) -> String:
	var name := str(rule.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	var skill_id := str(rule.get("skill", ""))
	if not skill_id.is_empty():
		var skill := _skill(skill_id)
		if not skill.is_empty():
			return str(skill.get("name", skill_id))
	return str(BEHAVIOR_ACTION_LABELS.get(str(rule.get("action", "attack")), "行为规则"))

func _behavior_condition_summary(rule: Dictionary) -> String:
	var conditions: Array = rule.get("conditions", []) if rule.get("conditions", []) is Array else []
	if conditions.is_empty():
		return "无条件"
	var text := _conditions_summary(conditions)
	if str(rule.get("condition_mode", "all")) == "any" and conditions.size() > 1:
		return "任一：" + text.replace(" 且 ", " 或 ")
	return text

func _on_behavior_tree_selected() -> void:
	if _refreshing_behavior_tree:
		return
	var item: TreeItem = %BehaviorTree.get_selected()
	if item == null:
		return
	_select_behavior(str(item.get_metadata(0)))

func _select_behavior(rule_id: String) -> void:
	if rule_id.is_empty() or _behavior_index(rule_id) < 0:
		return
	_selected_behavior_id = rule_id
	_select_behavior_tree_item(rule_id)
	_apply_behavior_form()
	_refresh_validation_preview()
	_update_behavior_buttons()
	_update_dirty_ui()

func _select_behavior_tree_item(rule_id: String) -> void:
	var root: TreeItem = %BehaviorTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == rule_id:
			_refreshing_behavior_tree = true
			item.select(0)
			%BehaviorTree.scroll_to_item(item)
			_refreshing_behavior_tree = false
			return
		item = item.get_next()

func _behavior_rule(rule_id: String) -> Dictionary:
	var row := _row(_active_id)
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	for rule in rules:
		if rule is Dictionary and str(rule.get("id", "")) == rule_id:
			return rule
	return {}

func _behavior_index(rule_id: String) -> int:
	var row := _row(_active_id)
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	for index in rules.size():
		if rules[index] is Dictionary and str(rules[index].get("id", "")) == rule_id:
			return index
	return -1

func _apply_behavior_form() -> void:
	_loading_behavior = true
	_condition_context = "behavior"
	_condition_trigger_id = ""
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		%BehaviorEditorTitle.text = "未选择规则"
		%BehaviorWarning.text = "当前妖兽没有可编辑规则。添加规则或先在左侧选择一条规则。"
		%BehaviorNameEdit.text = ""
		%BehaviorEnabledCheck.button_pressed = true
		%BehaviorPrioritySpin.value = 100
		_select_option(%BehaviorModeOption, "all")
		_select_option(%BehaviorActionOption, "attack")
		_select_option(%BehaviorTargetOption, "enemy")
		_select_option(%BehaviorOnFailOption, "continue")
		%BehaviorChanceSpin.value = 100
		%BehaviorMaxUsesSpin.value = 0
		%BehaviorCooldownSpin.value = 0
		%BehaviorSkillOption.clear()
		_clear_children(%ConditionsList)
		_set_behavior_form_enabled(false)
		%SaveBehaviorBtn.disabled = true
		_loading_behavior = false
		return
	%BehaviorEditorTitle.text = "选中规则：" + _behavior_display_name(rule)
	%BehaviorNameEdit.text = _behavior_display_name(rule)
	%BehaviorEnabledCheck.button_pressed = rule.get("enabled", true) == true
	%BehaviorPrioritySpin.value = int(rule.get("priority", 0))
	_select_option(%BehaviorModeOption, str(rule.get("condition_mode", "all")))
	_select_option(%BehaviorActionOption, str(rule.get("action", "attack")))
	_select_option(%BehaviorTargetOption, str(rule.get("target", "enemy")))
	%BehaviorChanceSpin.value = float(rule.get("chance", 1.0)) * 100.0
	%BehaviorMaxUsesSpin.value = int(rule.get("max_uses", 0))
	%BehaviorCooldownSpin.value = int(rule.get("cooldown", 0))
	_select_option(%BehaviorOnFailOption, str(rule.get("on_fail", "continue")))
	_populate_behavior_skill_option(rule)
	_set_behavior_form_enabled(_can_edit)
	_build_conditions_list(%ConditionsList)
	_update_behavior_warning()
	_loading_behavior = false

func _populate_behavior_skill_option(rule: Dictionary) -> void:
	%BehaviorSkillOption.clear()
	_add_option(%BehaviorSkillOption, "（未选择）", "")
	var ids: Array = _row(_active_id).get("skill_ids", []) if _row(_active_id).get("skill_ids", []) is Array else []
	var selected := str(rule.get("skill", ""))
	for skill_id in ids:
		var skill := _skill(str(skill_id))
		_add_option(%BehaviorSkillOption, "%s（%s）" % [str(skill.get("name", skill_id)), str(skill_id)], str(skill_id))
	if not selected.is_empty() and not _option_has(%BehaviorSkillOption, selected):
		_add_option(%BehaviorSkillOption, "缺失引用：%s" % selected, selected)
	if not _select_option(%BehaviorSkillOption, selected):
		%BehaviorSkillOption.select(0)
	var action := str(rule.get("action", "attack"))
	%BehaviorSkillOption.disabled = not (_can_edit and action in ["skill", "heal", "buff"])

func _option_has(option: OptionButton, value: Variant) -> bool:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			return true
	return false

func _set_behavior_form_enabled(enabled: bool) -> void:
	%BehaviorNameEdit.editable = enabled
	%BehaviorEnabledCheck.disabled = not enabled
	%BehaviorPrioritySpin.editable = enabled
	%BehaviorModeOption.disabled = not enabled
	%BehaviorActionOption.disabled = not enabled
	%BehaviorTargetOption.disabled = true
	%BehaviorChanceSpin.editable = enabled
	%BehaviorMaxUsesSpin.editable = enabled
	%BehaviorCooldownSpin.editable = enabled
	%BehaviorOnFailOption.disabled = not enabled
	%AddConditionBtn.disabled = not enabled

func _update_behavior_buttons() -> void:
	var active := not _active_id.is_empty()
	var selected := not _selected_behavior_id.is_empty() and _behavior_index(_selected_behavior_id) >= 0
	%AddRuleBtn.disabled = not (_can_edit and active)
	%CopyRuleBtn.disabled = not (_can_edit and selected)
	%DeleteRuleBtn.disabled = not (_can_edit and selected)
	%SaveBehaviorBtn.disabled = not (_can_edit and _dirty)
	var can_move_up := false
	var can_move_down := false
	if selected:
		var ordered := _sorted_behavior_indexes(_row(_active_id))
		var index := _behavior_index(_selected_behavior_id)
		var pos := ordered.find(index)
		can_move_up = pos > 0
		can_move_down = pos >= 0 and pos < ordered.size() - 1
	%MoveUpBtn.disabled = not (_can_edit and can_move_up)
	%MoveDownBtn.disabled = not (_can_edit and can_move_down)

func _collect_behavior_form() -> void:
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	var display_name := str(%BehaviorNameEdit.text).strip_edges()
	if display_name.is_empty():
		display_name = _behavior_display_name(rule)
	rule["name"] = display_name
	rule["enabled"] = %BehaviorEnabledCheck.button_pressed
	rule["priority"] = int(%BehaviorPrioritySpin.value)
	rule["condition_mode"] = str(_selected_metadata(%BehaviorModeOption))
	rule["action"] = str(_selected_metadata(%BehaviorActionOption))
	rule["skill"] = str(_selected_metadata(%BehaviorSkillOption))
	rule["target"] = str(_selected_metadata(%BehaviorTargetOption))
	rule["chance"] = clampf(float(%BehaviorChanceSpin.value) / 100.0, 0.0, 1.0)
	rule["max_uses"] = int(%BehaviorMaxUsesSpin.value)
	rule["cooldown"] = int(%BehaviorCooldownSpin.value)
	rule["on_fail"] = str(_selected_metadata(%BehaviorOnFailOption))

func _on_behavior_name_changed(text: String) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["name"] = text
	_after_behavior_edit()

func _on_behavior_enabled_toggled(pressed: bool) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["enabled"] = pressed
	_after_behavior_edit()

func _on_behavior_priority_changed(value: float) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["priority"] = int(value)
	_after_behavior_edit()

func _on_behavior_mode_changed(_index: int) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["condition_mode"] = str(_selected_metadata(%BehaviorModeOption))
	_after_behavior_edit()

func _on_behavior_action_changed(_index: int) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	var action := str(_selected_metadata(%BehaviorActionOption))
	rule["action"] = action
	%BehaviorSkillOption.disabled = not (_can_edit and action in ["skill", "heal", "buff"])
	_after_behavior_edit()

func _on_behavior_skill_changed(_index: int) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["skill"] = str(_selected_metadata(%BehaviorSkillOption))
	_after_behavior_edit()

func _on_behavior_target_changed(_index: int) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["target"] = str(_selected_metadata(%BehaviorTargetOption))
	_after_behavior_edit()

func _on_behavior_chance_changed(value: float) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["chance"] = clampf(value / 100.0, 0.0, 1.0)
	_after_behavior_edit()

func _on_behavior_max_uses_changed(value: float) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["max_uses"] = int(value)
	_after_behavior_edit()

func _on_behavior_cooldown_changed(value: float) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["cooldown"] = int(value)
	_after_behavior_edit()

func _on_behavior_on_fail_changed(_index: int) -> void:
	if _loading_behavior or not _can_edit:
		return
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		return
	rule["on_fail"] = str(_selected_metadata(%BehaviorOnFailOption))
	_after_behavior_edit()

func _after_behavior_edit() -> void:
	if _loading_behavior or not _can_edit:
		return
	_dirty = true
	_refresh_behavior_tree()
	_update_behavior_warning()
	_refresh_validation_preview()
	_update_dirty_ui()

func _update_behavior_warning() -> void:
	var rule := _behavior_rule(_selected_behavior_id)
	if rule.is_empty():
		%BehaviorWarning.text = "当前妖兽没有可编辑规则；战斗会回退普通攻击。"
		return
	var action := str(rule.get("action", "attack"))
	var skill_id := str(rule.get("skill", ""))
	var warnings: Array = []
	if action in ["skill", "heal", "buff"]:
		if skill_id.is_empty():
			warnings.append("请选择技能；未选择时规则会跳过。")
		else:
			var ids: Array = _row(_active_id).get("skill_ids", []) if _row(_active_id).get("skill_ids", []) is Array else []
			if skill_id not in ids:
				warnings.append("技能 %s 不在当前妖兽技能列表中，运行时会跳过该规则；请先在技能页添加。" % skill_id)
	if action == "flee":
		warnings.append("逃跑命中时立即结束战斗：不发放战利品，不增加击杀进度；每场次数由“最大触发次数”控制。")
	if float(rule.get("chance", 1.0)) <= 0.0:
		warnings.append("执行概率为 0%，该规则永远不会触发。")
	var conditions: Array = rule.get("conditions", []) if rule.get("conditions", []) is Array else []
	if conditions.is_empty():
		warnings.append("没有条件 = 无条件；该规则到达优先级时会始终满足，请确认顺序。")
	elif str(rule.get("condition_mode", "all")) == "any" and conditions.size() > 1:
		warnings.append("条件组合为“任一满足”，任一条件成立就会执行。")
	%BehaviorWarning.text = "\n".join(warnings)
	%BehaviorWarning.add_theme_color_override("font_color", Color("d8c27c"))
	%BehaviorWarning.visible = not warnings.is_empty()

func _create_new_behavior() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	var row := _row(_active_id)
	if not row.get("behaviors") is Array:
		row["behaviors"] = []
	var draft := MonsterDatabase.create_behavior_draft(_behavior_ids(row))
	row.behaviors.append(draft)
	_selected_behavior_id = str(draft.id)
	_dirty = true
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已添加行为规则草稿：%s。保存后写入妖兽配置。" % _selected_behavior_id)

func _request_copy_behavior() -> void:
	if not _can_edit or _selected_behavior_id.is_empty():
		return
	var source := _behavior_rule(_selected_behavior_id)
	if source.is_empty():
		return
	var row := _row(_active_id)
	var copy := MonsterDatabase.copy_behavior_draft(source, _behavior_ids(row))
	copy["name"] = _behavior_display_name(source).substr(0, MonsterDatabase.NAME_MAX - 2) + "副本"
	row.behaviors.append(copy)
	_selected_behavior_id = str(copy.id)
	_dirty = true
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已复制行为规则：%s。保存后写入妖兽配置。" % _selected_behavior_id)

func _behavior_ids(row: Dictionary) -> Dictionary:
	var ids := {}
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	for rule in rules:
		if rule is Dictionary and rule.get("id") is String:
			ids[rule.id] = true
	return ids

func _request_delete_behavior() -> void:
	if not _can_edit or _selected_behavior_id.is_empty():
		return
	_pending_delete_behavior_id = _selected_behavior_id
	%DeleteBehaviorDialog.dialog_text = "确定删除行为规则“%s”（%s）？\n删除后该规则不再参与战斗判断；未保存前仍可通过“放弃修改”恢复。" % [
		_behavior_display_name(_behavior_rule(_selected_behavior_id)), _selected_behavior_id]
	%DeleteBehaviorDialog.popup_centered(Vector2i(700, 280))

func _confirm_delete_behavior() -> void:
	%DeleteBehaviorDialog.hide()
	if _pending_delete_behavior_id.is_empty():
		return
	var row := _row(_active_id)
	var rules: Array = row.get("behaviors", []) if row.get("behaviors", []) is Array else []
	var index := -1
	for i in rules.size():
		if rules[i] is Dictionary and str(rules[i].get("id", "")) == _pending_delete_behavior_id:
			index = i
			break
	if index < 0:
		_pending_delete_behavior_id = ""
		return
	var removed_name := _behavior_display_name(rules[index])
	rules.remove_at(index)
	_dirty = true
	_pending_delete_behavior_id = ""
	_selected_behavior_id = ""
	if not rules.is_empty():
		var next_index: int = clampi(index, 0, rules.size() - 1)
		_selected_behavior_id = str(rules[next_index].get("id", ""))
	_refresh_behavior_page(row)
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已删除行为规则：%s。保存后写入妖兽配置。" % removed_name)

func _move_behavior(direction: int) -> void:
	if not _can_edit or _selected_behavior_id.is_empty():
		return
	var row := _row(_active_id)
	var ordered := _sorted_behavior_indexes(row)
	var index := _behavior_index(_selected_behavior_id)
	var pos := ordered.find(index)
	var target_pos := pos + direction
	if pos < 0 or target_pos < 0 or target_pos >= ordered.size():
		return
	var rules: Array = row.get("behaviors", [])
	var a: Dictionary = rules[ordered[pos]]
	var b: Dictionary = rules[ordered[target_pos]]
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa == pb:
		var temp: Variant = rules[ordered[pos]]
		rules[ordered[pos]] = rules[ordered[target_pos]]
		rules[ordered[target_pos]] = temp
	else:
		a["priority"] = pb
		b["priority"] = pa
	_dirty = true
	_refresh_behavior_page(row)
	_update_dirty_ui()

func _condition_owner() -> Dictionary:
	match _condition_context:
		"trigger":
			return _trigger_rule(_condition_trigger_id)
		_:
			return _behavior_rule(_selected_behavior_id)

func _add_condition() -> void:
	if not _can_edit:
		return
	var owner := _condition_owner()
	if owner.is_empty():
		return
	if not owner.get("conditions") is Array:
		owner["conditions"] = []
	owner.conditions.append(_default_condition("hp_below"))
	_after_condition_edit()
	_rebuild_condition_editor()

func _remove_condition(index: int) -> void:
	if not _can_edit:
		return
	var owner := _condition_owner()
	if owner.is_empty():
		return
	var conditions: Array = owner.get("conditions", []) if owner.get("conditions", []) is Array else []
	if index < 0 or index >= conditions.size():
		return
	conditions.remove_at(index)
	_after_condition_edit()
	_rebuild_condition_editor.call_deferred()

func _change_condition_type(index: int, kind: String) -> void:
	if not _can_edit:
		return
	var owner := _condition_owner()
	if owner.is_empty():
		return
	var conditions: Array = owner.get("conditions", []) if owner.get("conditions", []) is Array else []
	if index < 0 or index >= conditions.size():
		return
	conditions[index] = _default_condition(kind)
	_after_condition_edit()
	_rebuild_condition_editor.call_deferred()

func _rebuild_condition_editor() -> void:
	match _condition_context:
		"trigger":
			_build_conditions_list(%TriggerConditionsList)
			%AddTriggerConditionBtn.disabled = not _can_edit
		_:
			_build_conditions_list(%ConditionsList)
			%AddConditionBtn.disabled = not _can_edit

func _after_condition_edit() -> void:
	match _condition_context:
		"trigger":
			_after_trigger_edit()
		_:
			_after_behavior_edit()

func _add_behavior_condition() -> void:
	_condition_context = "behavior"
	_add_condition()

func _remove_behavior_condition(index: int) -> void:
	_condition_context = "behavior"
	_remove_condition(index)

func _change_behavior_condition_type(index: int, kind: String) -> void:
	_condition_context = "behavior"
	_change_condition_type(index, kind)

func _default_condition(kind: String) -> Dictionary:
	var first_skill := ""
	var ids: Array = _row(_active_id).get("skill_ids", []) if _row(_active_id).get("skill_ids", []) is Array else []
	if not ids.is_empty():
		first_skill = str(ids[0])
	match kind:
		"hp_below", "hp_above":
			return {"type": kind, "value": 50}
		"mp_at_least":
			return {"type": kind, "value": 5}
		"action_every", "turn_every":
			return {"type": kind, "value": 2}
		"turn_at_least":
			return {"type": kind, "value": 2}
		"self_status", "self_not_status":
			return {"type": kind, "status": "poison"}
		"target_status", "target_not_status":
			return {"type": kind, "status": "poison", "side": "player"}
		"skill_uses_below", "skill_uses_at_least":
			return {"type": kind, "skill": first_skill, "value": 1}
		"phase":
			return {"type": kind, "value": "berserk"}
		"has_available_skill":
			return {"type": kind}
		_:
			return {"type": "always"}

func _condition_at(index: int) -> Dictionary:
	var owner := _condition_owner()
	if owner.is_empty():
		return {}
	var conditions: Array = owner.get("conditions", []) if owner.get("conditions", []) is Array else []
	if index < 0 or index >= conditions.size():
		return {}
	return conditions[index] if conditions[index] is Dictionary else {}

func _set_condition_number(index: int, key: String, value: float, factor := 1.0, integer := true) -> void:
	if _loading_behavior or _loading_trigger or not _can_edit:
		return
	var condition := _condition_at(index)
	if condition.is_empty():
		return
	condition[key] = int(value) if integer else value * factor
	_after_condition_edit()

func _set_condition_text(index: int, key: String, value: String) -> void:
	if _loading_behavior or _loading_trigger or not _can_edit:
		return
	var condition := _condition_at(index)
	if condition.is_empty():
		return
	condition[key] = value
	_after_condition_edit()

func _set_condition_option(index: int, key: String, option: OptionButton) -> void:
	if _loading_behavior or _loading_trigger or not _can_edit:
		return
	var condition := _condition_at(index)
	if condition.is_empty():
		return
	condition[key] = str(_selected_metadata(option))
	_after_condition_edit()

func _build_conditions_list(container: VBoxContainer = null) -> void:
	_condition_container = container if container != null else %ConditionsList
	_clear_children(_condition_container)
	var owner := _condition_owner()
	if owner.is_empty():
		_add_note(_condition_container, "未选择规则。")
		return
	var conditions: Array = owner.get("conditions", []) if owner.get("conditions", []) is Array else []
	if conditions.is_empty():
		_add_note(_condition_container, "没有条件 = 无条件；规则到达优先级时会始终满足。", Color("d8c27c"))
		return
	var was_loading := _loading_behavior
	_loading_behavior = true
	for index in conditions.size():
		if conditions[index] is Dictionary:
			_build_condition_panel(_condition_container, index, conditions[index])
	_loading_behavior = was_loading

func _build_condition_panel(container: VBoxContainer, index: int, condition: Dictionary) -> void:
	var box := VBoxContainer.new()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "条件 %d" % (index + 1)
	title.custom_minimum_size.x = 76
	header.add_child(title)
	var type_option := OptionButton.new()
	for kind in BEHAVIOR_CONDITION_OPTIONS:
		_add_option(type_option, str(BEHAVIOR_CONDITION_LABELS.get(kind, kind)), kind)
	_select_option(type_option, str(condition.get("type", "always")))
	type_option.disabled = not _can_edit
	type_option.item_selected.connect(func(_selected: int) -> void: _change_condition_type(index, str(_selected_metadata(type_option))))
	header.add_child(type_option)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var remove := Button.new()
	remove.text = "移除此条件"
	remove.disabled = not _can_edit
	remove.pressed.connect(func() -> void: _remove_condition(index))
	header.add_child(remove)
	box.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var kind := str(condition.get("type", "always"))
	match kind:
		"hp_below", "hp_above":
			_add_condition_spin(grid, "生命比例（%）", float(condition.get("value", 50)), 0, 100, 1, index, "value", true)
		"mp_at_least":
			_add_condition_spin(grid, "灵力至少", float(condition.get("value", 0)), 0, 999999, 1, index, "value", true)
		"action_every", "turn_every":
			_add_condition_spin(grid, "间隔", float(condition.get("value", 2)), 1, 999, 1, index, "value", true)
		"turn_at_least":
			_add_condition_spin(grid, "回合数", float(condition.get("value", 2)), 0, 999, 1, index, "value", true)
		"self_status", "self_not_status", "target_status", "target_not_status":
			_add_condition_status(grid, condition, index)
		"skill_uses_below", "skill_uses_at_least":
			_add_condition_skill(grid, condition, index)
			_add_condition_spin(grid, "次数", float(condition.get("value", 1)), 0, 999, 1, index, "value", true)
		"phase":
			_add_condition_text(grid, "阶段名称", str(condition.get("value", "")), index)
		_:
			_add_note(grid, "此条件没有额外参数。")
	box.add_child(HSeparator.new())
	container.add_child(box)

func _add_condition_spin(grid: GridContainer, label: String, value: float, minimum: float, maximum: float, step: float,
		index: int, key: String, integer: bool) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.editable = _can_edit
	spin.value_changed.connect(func(new_value: float) -> void: _set_condition_number(index, key, new_value, 1.0, integer))
	_add_field_cell(grid, label, spin)

func _add_condition_status(grid: GridContainer, condition: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	var statuses: Dictionary = catalog.get("spell_growth", {}).get("statuses", {})
	for status_id in statuses:
		_add_option(option, str(statuses[status_id].get("name", status_id)), status_id)
	_select_option(option, str(condition.get("status", "poison")))
	option.item_selected.connect(func(_selected: int) -> void: _set_condition_option(index, "status", option))
	_add_field_cell(grid, "状态", option)

func _add_condition_skill(grid: GridContainer, condition: Dictionary, index: int) -> void:
	var option := OptionButton.new()
	option.disabled = not _can_edit
	_add_option(option, "（未选择）", "")
	var ids: Array = _row(_active_id).get("skill_ids", []) if _row(_active_id).get("skill_ids", []) is Array else []
	for skill_id in ids:
		var skill := _skill(str(skill_id))
		_add_option(option, "%s（%s）" % [str(skill.get("name", skill_id)), str(skill_id)], str(skill_id))
	var selected := str(condition.get("skill", ""))
	if not selected.is_empty() and not _option_has(option, selected):
		_add_option(option, "缺失引用：%s" % selected, selected)
	_select_option(option, selected)
	option.item_selected.connect(func(_selected: int) -> void: _set_condition_option(index, "skill", option))
	_add_field_cell(grid, "技能", option)

func _add_condition_text(grid: GridContainer, label: String, value: String, index: int) -> void:
	var edit := LineEdit.new()
	edit.text = value
	edit.editable = _can_edit
	edit.text_changed.connect(func(text: String) -> void: _set_condition_text(index, "value", text))
	_add_field_cell(grid, label, edit)

func _passives() -> Array:
	var row := _row(_active_id)
	if not row.get("passives") is Array:
		row["passives"] = []
	return row.passives

func _passive_at(index: int) -> Dictionary:
	var passives := _passives()
	if index < 0 or index >= passives.size():
		return {}
	return passives[index] if passives[index] is Dictionary else {}

func _refresh_passive_page(row: Dictionary) -> void:
	var monster_name := str(row.get("name", "未选择妖兽"))
	%PassivesPageTitle.text = "被动效果 — " + monster_name
	var passives: Array = row.get("passives", []) if row.get("passives", []) is Array else []
	if _selected_passive_index < 0 or _selected_passive_index >= passives.size():
		_selected_passive_index = 0 if not passives.is_empty() else -1
	_refresh_passive_tree()
	_apply_passive_form()
	_update_passive_buttons()

func _clear_passive_page() -> void:
	_selected_passive_index = -1
	%PassiveTree.clear()
	%PassivesPageTitle.text = "被动效果 — 未选择妖兽"
	%PassiveEditorTitle.text = "未选择被动"
	%PassiveWarning.text = ""
	%PassiveWarning.hide()
	%PassiveTypeOption.clear()
	_clear_children(%PassiveFieldsGrid)
	_set_passive_form_enabled(false)
	%SavePassiveBtn.disabled = true
	%CopyPassiveBtn.disabled = true
	%RemovePassiveBtn.disabled = true

func _refresh_passive_tree() -> void:
	%PassiveTree.clear()
	var root: TreeItem = %PassiveTree.create_item()
	var passives := _passives()
	var selected_item: TreeItem = null
	for index in passives.size():
		if not passives[index] is Dictionary:
			continue
		var effect: Dictionary = passives[index]
		var tree_item: TreeItem = %PassiveTree.create_item(root)
		tree_item.set_metadata(0, index)
		tree_item.set_text(0, _passive_display_name(effect))
		tree_item.set_text(1, str(EFFECT_LABELS.get(str(effect.get("type", "")), effect.get("type", ""))))
		tree_item.set_text(2, _effect_summary(effect))
		tree_item.set_text(3, _passive_duration(effect))
		tree_item.set_text(4, _passive_layers(effect))
		tree_item.set_text(5, _passive_dispel(effect))
		tree_item.set_tooltip_text(0, _passive_display_name(effect))
		tree_item.set_tooltip_text(2, _effect_summary(effect))
		if index == _selected_passive_index:
			selected_item = tree_item
	if selected_item != null:
		_refreshing_passive_tree = true
		selected_item.select(0)
		%PassiveTree.scroll_to_item(selected_item)
		_refreshing_passive_tree = false
	_update_passive_buttons()

func _passive_display_name(effect: Dictionary) -> String:
	var kind := str(effect.get("type", ""))
	match kind:
		"stat":
			var stat := str(effect.get("stat", "attack"))
			var value := float(effect.get("value", 0))
			var direction := "提升" if value >= 0 else "降低"
			return "%s%s" % [str(MonsterDatabase.STAT_LABELS.get(stat, stat)), direction]
		"status":
			return _status_name(str(effect.get("status", ""))) + "（自身）"
		"shield":
			return "护盾"
		"heal":
			return "战斗开始治疗"
		"mana":
			return "战斗开始回灵"
		"cleanse":
			return "清心"
		"phase":
			return "阶段：" + str(effect.get("value", ""))
		"damage":
			return "直接伤害（不支持）"
	return str(EFFECT_LABELS.get(kind, kind))

func _passive_duration(effect: Dictionary) -> String:
	var kind := str(effect.get("type", ""))
	if kind in ["status", "stat", "shield"]:
		return "%d 回合" % int(effect.get("turns", 1))
	return "即时"

func _passive_layers(effect: Dictionary) -> String:
	var kind := str(effect.get("type", ""))
	if kind == "status":
		var mode := str(effect.get("mode", "stack"))
		var mode_label: String = {"stack": "叠加", "refresh": "刷新", "replace": "替换"}.get(mode, mode)
		return "%d 层/%s" % [int(effect.get("layers", 1)), mode_label]
	if kind == "stat":
		return "%d 层" % int(effect.get("layers", 1))
	return "—"

func _passive_dispel(effect: Dictionary) -> String:
	var kind := str(effect.get("type", ""))
	if kind == "status":
		return "可驱散" if effect.get("dispellable", true) == true else "不可驱散"
	if kind in ["stat", "shield"]:
		return "按状态默认"
	return "—"

func _on_passive_tree_selected() -> void:
	if _refreshing_passive_tree:
		return
	var item: TreeItem = %PassiveTree.get_selected()
	if item == null:
		return
	_select_passive(int(item.get_metadata(0)))

func _select_passive(index: int) -> void:
	if index < 0 or index >= _passives().size():
		return
	_selected_passive_index = index
	_select_passive_tree_item(index)
	_apply_passive_form()
	_update_passive_buttons()

func _select_passive_tree_item(index: int) -> void:
	var root: TreeItem = %PassiveTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if int(item.get_metadata(0)) == index:
			_refreshing_passive_tree = true
			item.select(0)
			%PassiveTree.scroll_to_item(item)
			_refreshing_passive_tree = false
			return
		item = item.get_next()

func _apply_passive_form() -> void:
	_loading_passive = true
	_effect_context = "passive"
	_effect_owner_id = ""
	var effect := _passive_at(_selected_passive_index)
	if effect.is_empty():
		%PassiveEditorTitle.text = "未选择被动"
		%PassiveWarning.text = "当前妖兽没有被动。" if _passives().is_empty() else "请选择一条被动。"
		%PassiveWarning.show()
		%PassiveTypeOption.clear()
		_clear_children(%PassiveFieldsGrid)
		%PassiveTargetValue.text = "自身（战斗开始时）"
		%PassiveConditionValue.text = "战斗开始（固定）"
		%PassiveDispelValue.text = "—"
		_set_passive_form_enabled(false)
		%SavePassiveBtn.disabled = true
		_loading_passive = false
		return
	%PassiveEditorTitle.text = "选中被动：" + _passive_display_name(effect)
	%PassiveTypeOption.clear()
	var types: Array = PASSIVE_EFFECT_TYPES.duplicate()
	var current_type := str(effect.get("type", "stat"))
	if current_type not in types:
		types.push_front(current_type)
	for kind in types:
		_add_option(%PassiveTypeOption, str(EFFECT_LABELS.get(kind, kind)), kind)
	_select_option(%PassiveTypeOption, current_type)
	%PassiveTargetValue.text = "自身（战斗开始时）"
	%PassiveConditionValue.text = "战斗开始（固定）"
	%PassiveDispelValue.text = _passive_dispel(effect)
	_clear_children(%PassiveFieldsGrid)
	_loading_effect = true
	_build_effect_fields(%PassiveFieldsGrid, _selected_passive_index, effect)
	_loading_effect = false
	_set_passive_form_enabled(_can_edit)
	_update_passive_warning()
	_loading_passive = false

func _set_passive_form_enabled(enabled: bool) -> void:
	%PassiveTypeOption.disabled = not enabled
	%SavePassiveBtn.disabled = not (_can_edit and _dirty)

func _update_passive_buttons() -> void:
	var active := not _active_id.is_empty()
	var selected := _selected_passive_index >= 0 and _selected_passive_index < _passives().size()
	%AddPassiveBtn.disabled = not (_can_edit and active)
	%CopyPassiveBtn.disabled = not (_can_edit and selected)
	%RemovePassiveBtn.disabled = not (_can_edit and selected)
	%SavePassiveBtn.disabled = not (_can_edit and _dirty)

func _on_passive_type_changed(_index: int) -> void:
	if _loading_passive or not _can_edit:
		return
	_effect_context = "passive"
	_effect_owner_id = ""
	var effect := _passive_at(_selected_passive_index)
	if effect.is_empty():
		return
	var kind := str(_selected_metadata(%PassiveTypeOption))
	if kind == str(effect.get("type", "")):
		return
	var passives := _passives()
	passives[_selected_passive_index] = _default_effect_for_context(kind)
	_after_passive_edit()
	_apply_passive_form()

func _after_passive_edit() -> void:
	if _loading_passive or not _can_edit:
		return
	_dirty = true
	_refresh_passive_tree()
	_update_passive_warning()
	_refresh_validation_preview()
	_update_preview_from_form()
	_update_dirty_ui()

func _update_passive_warning() -> void:
	var effect := _passive_at(_selected_passive_index)
	var warnings: Array = []
	if effect.is_empty():
		warnings.append("请选择或添加被动。")
	else:
		var kind := str(effect.get("type", ""))
		if kind == "damage":
			warnings.append("直接伤害不能作为被动；保存会被校验拒绝。")
		elif kind not in PASSIVE_EFFECT_TYPES:
			warnings.append("不支持的效果类型：%s；保存会被校验拒绝。" % kind)
		if kind in ["status", "stat"] and str(effect.get("target", "self")) != "self":
			warnings.append("被动效果固定作用于自身；保存时目标会按自身处理。")
		if kind == "status":
			var status_id := str(effect.get("status", ""))
			if not _monster_status_supported(status_id):
				warnings.append("状态 %s 不适用于怪物自身；保存后不会产生预期效果。" % status_id)
			else:
				warnings.append("状态效果按共享状态表结算；可驱散由状态参数控制。")
		warnings.append("被动在战斗开始时按列表顺序执行一次。")
	%PassiveWarning.text = "\n".join(warnings)
	%PassiveWarning.visible = not warnings.is_empty()

func _open_passive_picker() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	%PassivePickerMenu.clear()
	_passive_picker_entries.clear()
	_add_passive_template("模板：攻击提升（+10%）", {"type": "stat", "stat": "attack", "value": 0.1, "turns": 99, "layers": 1, "target": "self"})
	_add_passive_template("模板：防御提升（+10%）", {"type": "stat", "stat": "defense", "value": 0.1, "turns": 99, "layers": 1, "target": "self"})
	_add_passive_template("模板：速度提升（+10%）", {"type": "stat", "stat": "speed", "value": 0.1, "turns": 99, "layers": 1, "target": "self"})
	_add_passive_template("模板：暴击提升（+10%）", {"type": "stat", "stat": "crit", "value": 0.1, "turns": 99, "layers": 1, "target": "self"})
	_add_passive_template("模板：护盾（攻击×0.5，3 回合）", {"type": "shield", "power": 0.5, "turns": 3})
	_add_passive_template("模板：减伤（10%，2 回合）", {"type": "status", "status": "damage_reduction", "layers": 1, "turns": 2, "chance": 1.0, "target": "self", "requires_hit": false, "dispellable": true})
	_add_passive_template("模板：清心（驱散 1 个负面）", {"type": "cleanse", "count": 1})
	_add_passive_template("模板：阶段", {"type": "phase", "value": "phase_1"})
	_add_passive_template("模板：战斗开始治疗（攻击×0.2）", {"type": "heal", "power": 0.2})
	_add_passive_template("模板：战斗开始回灵（5 点）", {"type": "mana", "amount": 5})
	%PassivePickerMenu.add_separator()
	var seen := {}
	for monster in _rows:
		if not monster is Dictionary or not monster.get("passives") is Array:
			continue
		for effect in monster.passives:
			if not effect is Dictionary:
				continue
			var key := JSON.stringify(effect)
			if seen.has(key):
				continue
			seen[key] = true
			_add_passive_template("已有被动：%s — %s" % [str(monster.get("name", monster.get("id", ""))), _effect_summary(effect)], effect.duplicate(true))
	%PassivePickerMenu.add_separator()
	var statuses: Dictionary = catalog.get("spell_growth", {}).get("statuses", {})
	for status_id in statuses:
		var key := str(status_id)
		if not _monster_status_supported(key):
			continue
		var status: Dictionary = statuses[status_id] if statuses[status_id] is Dictionary else {}
		var status_effect := {"type": "status", "status": key, "layers": 1, "turns": int(status.get("turns", 2)), "chance": 1.0, "target": "self", "requires_hit": false, "dispellable": true}
		_add_passive_template("状态：%s（作用于自身）" % str(status.get("name", status_id)), status_effect)
	%PassivePickerMenu.add_separator()
	for unavailable in ["不可用：反伤", "不可用：吸血被动", "不可用：召唤", "不可用：群体强化", "不可用：敌方增益驱散"]:
		%PassivePickerMenu.add_item(unavailable)
		%PassivePickerMenu.set_item_disabled(%PassivePickerMenu.item_count - 1, true)
	%PassivePickerMenu.popup_centered(Vector2i(620, 620))

func _add_passive_template(label: String, effect: Dictionary) -> void:
	var id := _passive_picker_entries.size()
	%PassivePickerMenu.add_item(label, id)
	_passive_picker_entries.append(effect.duplicate(true))

func _on_passive_picked(id: int) -> void:
	if not _can_edit or id < 0 or id >= _passive_picker_entries.size():
		return
	var passives := _passives()
	passives.append(_passive_picker_entries[id].duplicate(true))
	_selected_passive_index = passives.size() - 1
	_dirty = true
	_refresh_passive_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已添加被动效果；保存后写入妖兽配置。")

func _request_copy_passive() -> void:
	if not _can_edit:
		return
	var effect := _passive_at(_selected_passive_index)
	if effect.is_empty():
		return
	var passives := _passives()
	passives.append(effect.duplicate(true))
	_selected_passive_index = passives.size() - 1
	_dirty = true
	_refresh_passive_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已复制被动效果；保存后写入妖兽配置。")

func _request_remove_passive() -> void:
	if not _can_edit:
		return
	var effect := _passive_at(_selected_passive_index)
	if effect.is_empty():
		return
	_pending_delete_passive_index = _selected_passive_index
	%DeletePassiveDialog.dialog_text = "确定移除被动“%s”？\n保存后生效；未保存前可放弃修改。" % _passive_display_name(effect)
	%DeletePassiveDialog.popup_centered(Vector2i(700, 280))

func _confirm_remove_passive() -> void:
	%DeletePassiveDialog.hide()
	if _pending_delete_passive_index < 0:
		return
	var passives := _passives()
	if _pending_delete_passive_index < passives.size():
		passives.remove_at(_pending_delete_passive_index)
	_dirty = true
	_selected_passive_index = 0 if not passives.is_empty() else -1
	_pending_delete_passive_index = -1
	_refresh_passive_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已移除被动效果；保存后生效。")

func _loot_of(row: Dictionary) -> Dictionary:
	if not row.get("loot") is Dictionary:
		row["loot"] = {"money": [0, 0], "entries": []}
	var loot: Dictionary = row.loot
	if not loot.get("money") is Array or loot.money.size() != 2:
		loot["money"] = [0, 0]
	if not loot.get("entries") is Array:
		loot["entries"] = []
	return loot

func _has_item_named(fragment: String) -> bool:
	for item in catalog.get("items", {}).values():
		if item is Dictionary and str(item.get("name", "")).contains(fragment):
			return true
	return false

func _loot_entries() -> Array:
	var loot := _loot_of(_row(_active_id))
	return loot.get("entries", [])

func _loot_entry(index: int) -> Dictionary:
	var entries := _loot_entries()
	if index < 0 or index >= entries.size():
		return {}
	return entries[index] if entries[index] is Dictionary else {}

func _refresh_loot_page(row: Dictionary) -> void:
	var monster_name := str(row.get("name", "未选择妖兽"))
	%LootPageTitle.text = "掉落配置 — " + monster_name
	var has_danyao := _has_item_named("妖丹")
	%LootHint.text = "物品必须存在于现有物品库；" + ("妖丹已在物品库中，可正常选择。" if has_danyao else "妖丹尚未加入正式物品库，暂不可选。") + "当前没有身份默认掉落，所有物品仅来自本表，避免双来源重复发放。"
	%LootStaticNote.text = ("妖丹已加入物品库，可通过本表添加；当前没有身份默认掉落，不会重复发放。" if has_danyao else "身份默认掉落：当前不存在；妖丹尚未加入正式物品库。所有掉落仅来自本表，因此不会与身份默认掉落重复发放同一份妖丹。")
	var loot := _loot_of(row)
	var money: Array = loot.get("money", [0, 0])
	%LootMoneyMinSpin.set_value_no_signal(int(money[0]))
	%LootMoneyMaxSpin.set_value_no_signal(int(money[1]))
	var entries: Array = loot.get("entries", [])
	if _selected_loot_index < 0 or _selected_loot_index >= entries.size():
		_selected_loot_index = 0 if not entries.is_empty() else -1
	_refresh_loot_tree()
	_apply_loot_form()
	_update_loot_buttons()

func _clear_loot_page() -> void:
	_selected_loot_index = -1
	%LootTree.clear()
	%LootPageTitle.text = "掉落配置 — 未选择妖兽"
	%LootMoneyMinSpin.set_value_no_signal(0)
	%LootMoneyMaxSpin.set_value_no_signal(0)
	%LootEditorTitle.text = "未选择掉落"
	%LootWarning.text = ""
	%LootWarning.hide()
	%LootItemButton.text = "选择物品"
	%LootMinSpin.set_value_no_signal(1)
	%LootMaxSpin.set_value_no_signal(1)
	%LootChanceSpin.set_value_no_signal(100)
	%LootGuaranteedCheck.set_pressed_no_signal(false)
	%LootIndependentValue.text = "独立概率判定（固定）"
	%LootOnceValue.text = ""
	%LootLegacyValue.text = ""
	%LootRankNormal.set_pressed_no_signal(false)
	%LootRankElite.set_pressed_no_signal(false)
	%LootRankBoss.set_pressed_no_signal(false)
	%LootRealmMinSpin.set_value_no_signal(0)
	_set_loot_form_enabled(false)
	%SaveLootBtn.disabled = true
	%ChooseLootItemBtn.disabled = true
	%DeleteLootBtn.disabled = true

func _refresh_loot_tree() -> void:
	%LootTree.clear()
	var root: TreeItem = %LootTree.create_item()
	var entries := _loot_entries()
	var selected_item: TreeItem = null
	for index in entries.size():
		if not entries[index] is Dictionary:
			continue
		var entry: Dictionary = entries[index]
		var item_id := str(entry.get("item_id", ""))
		var item: Dictionary = catalog.get("items", {}).get(item_id, {})
		var item_name := str(item.get("name", "缺失物品"))
		var guaranteed := bool(entry.get("guaranteed", false))
		var tree_item: TreeItem = %LootTree.create_item(root)
		tree_item.set_metadata(0, index)
		tree_item.set_text(0, item_name)
		tree_item.set_text(1, item_id)
		tree_item.set_text(2, str(int(entry.get("min", 1))))
		tree_item.set_text(3, str(int(entry.get("max", 1))))
		tree_item.set_text(4, "100%" if guaranteed else "%.0f%%" % (float(entry.get("chance", 0.0)) * 100.0))
		var judgement := "独立"
		if entry.get("independent", true) != true:
			judgement = "非独立"
		elif guaranteed:
			judgement = "必得"
		tree_item.set_text(5, judgement)
		tree_item.set_text(6, _loot_condition_text(entry))
		tree_item.set_tooltip_text(0, "%s\n%s" % [item_name, item_id])
		if catalog.get("items", {}).get(item_id, {}).is_empty():
			for column in 7:
				tree_item.set_custom_color(column, Color("ef8f86"))
		if index == _selected_loot_index:
			selected_item = tree_item
	if selected_item != null:
		_refreshing_loot_tree = true
		selected_item.select(0)
		%LootTree.scroll_to_item(selected_item)
		_refreshing_loot_tree = false
	_update_loot_buttons()

func _loot_condition_text(entry: Dictionary) -> String:
	var conditions: Dictionary = entry.get("conditions", {}) if entry.get("conditions", {}) is Dictionary else {}
	var parts: Array = []
	var ranks: Variant = conditions.get("rank", [])
	if ranks is Array:
		for rank in ranks:
			parts.append(MonsterDatabase.rank_label(str(rank)))
	var realm_min := int(conditions.get("realm_min", 0))
	if realm_min > 0:
		parts.append("境界≥%d" % realm_min)
	return "、".join(parts) if not parts.is_empty() else "任意"

func _on_loot_tree_selected() -> void:
	if _refreshing_loot_tree:
		return
	var item: TreeItem = %LootTree.get_selected()
	if item == null:
		return
	_select_loot(int(item.get_metadata(0)))

func _select_loot(index: int) -> void:
	if index < 0 or index >= _loot_entries().size():
		return
	_selected_loot_index = index
	_select_loot_tree_item(index)
	_apply_loot_form()
	_update_loot_buttons()

func _select_loot_tree_item(index: int) -> void:
	var root: TreeItem = %LootTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if int(item.get_metadata(0)) == index:
			_refreshing_loot_tree = true
			item.select(0)
			%LootTree.scroll_to_item(item)
			_refreshing_loot_tree = false
			return
		item = item.get_next()

func _apply_loot_form() -> void:
	_loading_loot = true
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty():
		%LootEditorTitle.text = "未选择掉落"
		%LootWarning.text = "当前没有选中的掉落条目。添加掉落后在下方编辑。" if _loot_entries().is_empty() else "请选择一条掉落。"
		%LootWarning.show()
		%LootItemButton.text = "选择物品"
		%LootMinSpin.set_value_no_signal(1)
		%LootMaxSpin.set_value_no_signal(1)
		%LootChanceSpin.set_value_no_signal(100)
		%LootGuaranteedCheck.set_pressed_no_signal(false)
		%LootIndependentValue.text = "独立概率判定（固定）"
		%LootOnceValue.text = ""
		%LootLegacyValue.text = ""
		%LootRankNormal.set_pressed_no_signal(false)
		%LootRankElite.set_pressed_no_signal(false)
		%LootRankBoss.set_pressed_no_signal(false)
		%LootRealmMinSpin.set_value_no_signal(0)
		_set_loot_form_enabled(false)
		%SaveLootBtn.disabled = true
		_loading_loot = false
		return
	var item_id := str(entry.get("item_id", ""))
	var item: Dictionary = catalog.get("items", {}).get(item_id, {})
	%LootEditorTitle.text = "选中掉落：" + str(item.get("name", "缺失物品")) + "（" + item_id + "）"
	%LootItemButton.text = "%s（%s）" % [str(item.get("name", "缺失物品：" + item_id)), item_id]
	%LootMinSpin.set_value_no_signal(int(entry.get("min", 1)))
	%LootMaxSpin.set_value_no_signal(int(entry.get("max", 1)))
	var guaranteed := bool(entry.get("guaranteed", false))
	%LootChanceSpin.set_value_no_signal(100.0 if guaranteed else float(entry.get("chance", 1.0)) * 100.0)
	%LootGuaranteedCheck.set_pressed_no_signal(guaranteed)
	%LootChanceSpin.editable = _can_edit and not guaranteed
	%LootIndependentValue.text = "独立概率判定（固定）" if entry.get("independent", true) == true else "非独立判定（当前不支持）"
	%LootOnceValue.text = str(entry.get("once", ""))
	%LootLegacyValue.text = str(entry.get("legacy_flag", ""))
	var conditions: Dictionary = entry.get("conditions", {}) if entry.get("conditions", {}) is Dictionary else {}
	var ranks: Variant = conditions.get("rank", [])
	var rank_list: Array = ranks if ranks is Array else []
	%LootRankNormal.set_pressed_no_signal("normal" in rank_list)
	%LootRankElite.set_pressed_no_signal("elite" in rank_list)
	%LootRankBoss.set_pressed_no_signal("boss" in rank_list)
	%LootRealmMinSpin.set_value_no_signal(int(conditions.get("realm_min", 0)))
	_set_loot_form_enabled(_can_edit)
	%LootChanceSpin.editable = _can_edit and not guaranteed
	_update_loot_warning()
	_loading_loot = false

func _set_loot_form_enabled(enabled: bool) -> void:
	%LootItemButton.disabled = not enabled
	%LootMinSpin.editable = enabled
	%LootMaxSpin.editable = enabled
	%LootChanceSpin.editable = enabled
	%LootGuaranteedCheck.disabled = not enabled
	%LootRankNormal.disabled = not enabled
	%LootRankElite.disabled = not enabled
	%LootRankBoss.disabled = not enabled
	%LootRealmMinSpin.editable = enabled
	%DeleteLootBtn.disabled = not enabled

func _update_loot_buttons() -> void:
	var active := not _active_id.is_empty()
	var selected := _selected_loot_index >= 0 and _selected_loot_index < _loot_entries().size()
	%AddLootBtn.disabled = not (_can_edit and active)
	%CopyLootBtn.disabled = not (_can_edit and active)
	%ChooseLootItemBtn.disabled = not (_can_edit and selected)
	%DeleteLootBtn.disabled = not (_can_edit and selected)
	%SaveLootBtn.disabled = not (_can_edit and _dirty)

func _on_loot_money_changed(_value: float = 0.0) -> void:
	if _loading_loot or not _can_edit or _active_id.is_empty():
		return
	var loot := _loot_of(_row(_active_id))
	loot["money"] = [int(%LootMoneyMinSpin.value), int(%LootMoneyMaxSpin.value)]
	_after_loot_edit(false)

func _on_loot_min_changed(value: float) -> void:
	if _loading_loot or not _can_edit:
		return
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty():
		return
	entry["min"] = int(value)
	_after_loot_edit()

func _on_loot_max_changed(value: float) -> void:
	if _loading_loot or not _can_edit:
		return
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty():
		return
	entry["max"] = int(value)
	_after_loot_edit()

func _on_loot_chance_changed(value: float) -> void:
	if _loading_loot or not _can_edit:
		return
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty() or %LootGuaranteedCheck.button_pressed:
		return
	entry["chance"] = clampf(value / 100.0, 0.0, 1.0)
	_after_loot_edit()

func _on_loot_guaranteed_toggled(pressed: bool) -> void:
	if _loading_loot or not _can_edit:
		return
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty():
		return
	entry["guaranteed"] = pressed
	if pressed:
		entry["chance"] = 1.0
		%LootChanceSpin.set_value_no_signal(100.0)
	else:
		entry["chance"] = clampf(float(%LootChanceSpin.value) / 100.0, 0.0, 1.0)
	%LootChanceSpin.editable = _can_edit and not pressed
	_after_loot_edit()

func _on_loot_condition_changed(_value: Variant = null) -> void:
	if _loading_loot or not _can_edit:
		return
	var entry := _loot_entry(_selected_loot_index)
	if entry.is_empty():
		return
	var ranks: Array = []
	if %LootRankNormal.button_pressed:
		ranks.append("normal")
	if %LootRankElite.button_pressed:
		ranks.append("elite")
	if %LootRankBoss.button_pressed:
		ranks.append("boss")
	var conditions := {}
	if not ranks.is_empty():
		conditions["rank"] = ranks
	var realm_min := int(%LootRealmMinSpin.value)
	if realm_min > 0:
		conditions["realm_min"] = realm_min
	if conditions.is_empty():
		entry.erase("conditions")
	else:
		entry["conditions"] = conditions
	_after_loot_edit()

func _after_loot_edit(refresh_tree := true) -> void:
	if _loading_loot or not _can_edit:
		return
	_dirty = true
	if refresh_tree:
		_refresh_loot_tree()
	_update_loot_warning()
	_refresh_validation_preview()
	_update_preview_from_form()
	_update_dirty_ui()

func _update_loot_warning() -> void:
	var warnings: Array = []
	var entries := _loot_entries()
	if entries.is_empty():
		warnings.append("掉落表为空：战斗胜利时不会掉落物品或灵石以外的条目。")
	var entry := _loot_entry(_selected_loot_index)
	if not entry.is_empty():
		var item_id := str(entry.get("item_id", ""))
		if catalog.get("items", {}).get(item_id, {}).is_empty():
			warnings.append("物品 %s 不存在于现有物品库；保存会被拒绝。" % item_id)
		if int(entry.get("max", 1)) < int(entry.get("min", 1)):
			warnings.append("最大数量不能小于最小数量。")
		if entry.get("independent", true) != true:
			warnings.append("当前条目不是独立判定；本编辑器只支持独立判定，保存会被拒绝。")
		if bool(entry.get("guaranteed", false)):
			warnings.append("必定掉落：忽略概率，满足条件后必定发放。")
		elif float(entry.get("chance", 0.0)) <= 0.0:
			warnings.append("掉落概率为 0%，该条目不会发放。")
		if entry.has("once"):
			warnings.append("单次掉落标记：%s；按妖兽 ID 命名空间记录。" % str(entry.get("once", "")))
	var seen := {}
	for candidate in entries:
		if not candidate is Dictionary:
			continue
		var item_id := str(candidate.get("item_id", ""))
		if item_id.is_empty():
			continue
		if seen.has(item_id):
			warnings.append("物品 %s 出现多次；结算会合并数量，建议合并为一条。" % item_id)
		else:
			seen[item_id] = true
	%LootWarning.text = "\n".join(warnings)
	%LootWarning.visible = not warnings.is_empty()

func _collect_loot_form() -> void:
	if _active_id.is_empty():
		return
	var loot := _loot_of(_row(_active_id))
	loot["money"] = [int(%LootMoneyMinSpin.value), int(%LootMoneyMaxSpin.value)]

func _item_name(item_id: String) -> String:
	var item: Dictionary = catalog.get("items", {}).get(item_id, {})
	return str(item.get("name", item_id))

func _open_loot_item_picker(mode: String) -> void:
	if not _can_edit or _active_id.is_empty():
		return
	if mode == "replace" and _loot_entry(_selected_loot_index).is_empty():
		_set_status("请先选择一条掉落，再选择物品。", true)
		return
	_loot_picker_mode = mode
	_loot_picker_target_index = _selected_loot_index
	%LootItemSearch.text = ""
	_populate_loot_item_type_filter()
	_refresh_loot_item_picker()
	%LootItemOverlay.show()
	%LootItemSearch.grab_focus()

func _close_loot_item_picker() -> void:
	%LootItemOverlay.hide()

func _populate_loot_item_type_filter() -> void:
	%LootItemTypeFilter.clear()
	_add_option(%LootItemTypeFilter, "全部物品", "")
	var types := {}
	for item in catalog.get("items", {}).values():
		if item is Dictionary and item.get("type") is String and not item.type.is_empty():
			types[item.type] = true
	var sorted_types: Array = types.keys()
	sorted_types.sort()
	for item_type in sorted_types:
		_add_option(%LootItemTypeFilter, str(item_type), str(item_type))
	%LootItemTypeFilter.select(0)

func _on_loot_item_search(_text: String) -> void:
	_refresh_loot_item_picker()

func _on_loot_item_type_filter(_index: int) -> void:
	_refresh_loot_item_picker()

func _refresh_loot_item_picker() -> void:
	var query := str(%LootItemSearch.text).strip_edges().to_lower()
	var type_filter := str(_selected_metadata(%LootItemTypeFilter))
	var items: Array = []
	for item in catalog.get("items", {}).values():
		if not item is Dictionary:
			continue
		if not type_filter.is_empty() and str(item.get("type", "")) != type_filter:
			continue
		var item_name := str(item.get("name", ""))
		var item_id := str(item.get("id", ""))
		if not query.is_empty() and not item_name.to_lower().contains(query) and not item_id.to_lower().contains(query):
			continue
		items.append(item)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	%LootItemList.clear()
	for item in items:
		var index: int = int(%LootItemList.add_item("%s · %s · %s" % [str(item.get("name", "")), str(item.get("type", "")), str(item.get("id", ""))]))
		%LootItemList.set_item_metadata(index, str(item.get("id", "")))
		%LootItemList.set_item_tooltip(index, "%s\n%s · %s\n%s" % [
			str(item.get("name", "")), str(item.get("type", "")),
			ItemDatabase.rarity_label(str(item.get("rarity", "common"))), str(item.get("description", ""))])
	var message := "可选择物品：%d 个。仅列出现有物品库，不能输入不存在的 ID。" % items.size()
	if items.is_empty() and query.contains("妖丹"):
		message = "未找到妖丹：妖丹尚未加入正式物品库，暂不可选；加入后会走同一掉落表。"
	elif items.is_empty():
		message = "没有匹配的物品。"
	%LootItemInfo.text = message
	%LootItemConfirmBtn.disabled = true

func _on_loot_item_selected(_index: int) -> void:
	var selected: PackedInt32Array = %LootItemList.get_selected_items()
	%LootItemConfirmBtn.disabled = selected.is_empty()
	if selected.is_empty():
		return
	var item_id := str(%LootItemList.get_item_metadata(selected[0]))
	var item: Dictionary = catalog.get("items", {}).get(item_id, {})
	%LootItemInfo.text = "%s（%s）\n%s · %s\n%s" % [
		str(item.get("name", item_id)), item_id, str(item.get("type", "")),
		ItemDatabase.rarity_label(str(item.get("rarity", "common"))), str(item.get("description", ""))]

func _confirm_loot_item_pick() -> void:
	var selected: PackedInt32Array = %LootItemList.get_selected_items()
	if selected.is_empty() or not _can_edit:
		return
	var item_id := str(%LootItemList.get_item_metadata(selected[0]))
	if item_id.is_empty() or catalog.get("items", {}).get(item_id, {}).is_empty():
		_set_status("所选物品不存在，不能写入掉落表。", true)
		return
	var entries := _loot_entries()
	var duplicate_index := -1
	for index in entries.size():
		if entries[index] is Dictionary and str(entries[index].get("item_id", "")) == item_id:
			duplicate_index = index
			break
	if _loot_picker_mode == "add":
		if duplicate_index >= 0:
			_selected_loot_index = duplicate_index
			_close_loot_item_picker()
			_refresh_loot_page(_row(_active_id))
			_set_status("物品已在掉落表中；已选中现有条目。", true)
			return
		entries.append({"item_id": item_id, "min": 1, "max": 1, "chance": 1.0, "guaranteed": false, "independent": true})
		_selected_loot_index = entries.size() - 1
		_dirty = true
		_close_loot_item_picker()
		_refresh_loot_page(_row(_active_id))
		_update_preview_from_form()
		_update_dirty_ui()
		_set_status("已添加掉落：%s（%s）。" % [_item_name(item_id), item_id])
		return
	if _loot_picker_target_index < 0 or _loot_picker_target_index >= entries.size():
		_set_status("目标掉落条目已不存在。", true)
		return
	if duplicate_index >= 0 and duplicate_index != _loot_picker_target_index:
		%LootItemInfo.text = "该物品已被第 %d 条掉落使用；为避免重复，请选择其他物品。" % (duplicate_index + 1)
		return
	entries[_loot_picker_target_index]["item_id"] = item_id
	_selected_loot_index = _loot_picker_target_index
	_dirty = true
	_close_loot_item_picker()
	_refresh_loot_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已将掉落物品改为：%s（%s）。" % [_item_name(item_id), item_id])

func _open_loot_copy_menu() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	%LootCopyMenu.clear()
	var count := 0
	for monster in _rows:
		if not monster is Dictionary or str(monster.get("id", "")) == _active_id:
			continue
		var loot: Variant = monster.get("loot", {})
		if not loot is Dictionary:
			continue
		var entries: Variant = loot.get("entries", [])
		if not entries is Array:
			continue
		var money: Array = loot.get("money", [0, 0]) if loot.get("money", [0, 0]) is Array else [0, 0]
		%LootCopyMenu.add_item("%s（%d 条 · 灵石 %d–%d）" % [
			str(monster.get("name", monster.get("id", ""))), entries.size(),
			int(money[0]) if money.size() >= 1 else 0, int(money[1]) if money.size() >= 2 else 0])
		var index: int = %LootCopyMenu.item_count - 1
		%LootCopyMenu.set_item_metadata(index, str(monster.get("id", "")))
		count += 1
	if count == 0:
		_set_status("没有其他妖兽的掉落表可复制。", true)
		return
	%LootCopyMenu.popup_centered(Vector2i(560, 500))

func _on_loot_copy_selected(id: int) -> void:
	var monster_id := str(%LootCopyMenu.get_item_metadata(id))
	if monster_id.is_empty() or _row_index(monster_id) < 0:
		return
	_pending_copy_loot_id = monster_id
	var source: Dictionary = _loot_of(_row(monster_id))
	var entries: Array = source.get("entries", [])
	%CopyLootDialog.dialog_text = "将“%s”的掉落表（%d 条）复制到当前妖兽，替换现有 %d 条掉落和灵石区间？\n保存后生效；未保存前可放弃修改。" % [
		str(_row(monster_id).get("name", monster_id)), entries.size(), _loot_entries().size()]
	%CopyLootDialog.popup_centered(Vector2i(760, 300))

func _confirm_copy_loot() -> void:
	%CopyLootDialog.hide()
	if _pending_copy_loot_id.is_empty():
		return
	var source_row := _row(_pending_copy_loot_id)
	if source_row.is_empty():
		_pending_copy_loot_id = ""
		return
	_row(_active_id)["loot"] = _loot_of(source_row).duplicate(true)
	_selected_loot_index = 0 if not _loot_entries().is_empty() else -1
	_dirty = true
	_pending_copy_loot_id = ""
	_refresh_loot_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已复制掉落表；保存后写入当前妖兽。")

func _request_delete_loot() -> void:
	if not _can_edit or _loot_entry(_selected_loot_index).is_empty():
		return
	_pending_delete_loot_index = _selected_loot_index
	var entry := _loot_entry(_selected_loot_index)
	%DeleteLootDialog.dialog_text = "确定删除掉落“%s”（%s）？\n保存后生效；未保存前可放弃修改。" % [
		_item_name(str(entry.get("item_id", ""))), str(entry.get("item_id", ""))]
	%DeleteLootDialog.popup_centered(Vector2i(700, 280))

func _confirm_delete_loot() -> void:
	%DeleteLootDialog.hide()
	if _pending_delete_loot_index < 0:
		return
	var entries := _loot_entries()
	if _pending_delete_loot_index < entries.size():
		entries.remove_at(_pending_delete_loot_index)
	_dirty = true
	if entries.is_empty():
		_selected_loot_index = -1
	else:
		_selected_loot_index = mini(_pending_delete_loot_index, entries.size() - 1)
	_pending_delete_loot_index = -1
	_refresh_loot_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已删除掉落条目；保存后生效。")

func _triggers() -> Array:
	var row := _row(_active_id)
	if not row.get("triggers") is Array:
		row["triggers"] = []
	return row.triggers

func _trigger_index(trigger_id: String) -> int:
	var triggers := _triggers()
	for index in triggers.size():
		if triggers[index] is Dictionary and str(triggers[index].get("id", "")) == trigger_id:
			return index
	return -1

func _trigger_rule(trigger_id: String) -> Dictionary:
	var index := _trigger_index(trigger_id)
	if index < 0:
		return {}
	return _triggers()[index]

func _trigger_ids() -> Dictionary:
	var ids := {}
	for trigger in _triggers():
		if trigger is Dictionary:
			ids[str(trigger.get("id", ""))] = true
	return ids

func _refresh_trigger_page(row: Dictionary) -> void:
	var monster_name := str(row.get("name", "未选择妖兽"))
	%MechanicsPageTitle.text = "特殊机制 — " + monster_name
	var triggers: Array = row.get("triggers", []) if row.get("triggers", []) is Array else []
	if _selected_trigger_id.is_empty() or _trigger_index(_selected_trigger_id) < 0:
		_selected_trigger_id = str(triggers[0].get("id", "")) if not triggers.is_empty() and triggers[0] is Dictionary else ""
	_refresh_trigger_tree()
	_apply_trigger_form()
	_update_trigger_buttons()

func _clear_trigger_page() -> void:
	_selected_trigger_id = ""
	%TriggerTree.clear()
	%MechanicsPageTitle.text = "特殊机制 — 未选择妖兽"
	%TriggerEditorTitle.text = "未选择机制"
	%TriggerWarning.text = ""
	%TriggerWarning.hide()
	%TriggerNameEdit.text = ""
	%TriggerEnabledCheck.button_pressed = true
	%TriggerOnceCheck.button_pressed = true
	%TriggerMaxUsesSpin.value = 1
	%TriggerMaxUsesSpin.editable = false
	_clear_children(%TriggerConditionsList)
	_clear_children(%TriggerEffectsList)
	_set_trigger_form_enabled(false)
	%SaveTriggerBtn.disabled = true
	%CopyTriggerBtn.disabled = true
	%RemoveTriggerBtn.disabled = true

func _refresh_trigger_tree() -> void:
	%TriggerTree.clear()
	var root: TreeItem = %TriggerTree.create_item()
	var triggers := _triggers()
	var selected_item: TreeItem = null
	for index in triggers.size():
		if not triggers[index] is Dictionary:
			continue
		var trigger: Dictionary = triggers[index]
		var tree_item: TreeItem = %TriggerTree.create_item(root)
		tree_item.set_metadata(0, str(trigger.get("id", "")))
		tree_item.set_text(0, _trigger_display_name(trigger))
		tree_item.set_text(1, str(TRIGGER_EVENT_LABELS.get(str(trigger.get("event", "")), trigger.get("event", ""))))
		tree_item.set_text(2, "启用" if trigger.get("enabled", true) != false else "停用")
		tree_item.set_text(3, _conditions_summary(trigger.get("conditions", [])))
		var effect_texts: Array = []
		for effect in trigger.get("effects", []) if trigger.get("effects", []) is Array else []:
			effect_texts.append(_effect_summary(effect))
		tree_item.set_text(4, "；".join(effect_texts) if not effect_texts.is_empty() else "无效果")
		tree_item.set_text(5, _trigger_uses_label(trigger))
		tree_item.set_tooltip_text(0, _trigger_display_name(trigger))
		tree_item.set_tooltip_text(3, _conditions_summary(trigger.get("conditions", [])))
		tree_item.set_tooltip_text(4, "；".join(effect_texts))
		if str(trigger.get("id", "")) == _selected_trigger_id:
			selected_item = tree_item
	if selected_item != null:
		_refreshing_trigger_tree = true
		selected_item.select(0)
		%TriggerTree.scroll_to_item(selected_item)
		_refreshing_trigger_tree = false
	_update_trigger_buttons()

func _trigger_display_name(trigger: Dictionary) -> String:
	var name := str(trigger.get("name", "")).strip_edges()
	if not name.is_empty():
		return name
	var event_label := str(TRIGGER_EVENT_LABELS.get(str(trigger.get("event", "")), "特殊机制"))
	var effects: Array = trigger.get("effects", []) if trigger.get("effects", []) is Array else []
	if not effects.is_empty():
		return "%s · %s" % [event_label, _effect_summary(effects[0])]
	return event_label + "机制"

func _on_trigger_tree_selected() -> void:
	if _refreshing_trigger_tree:
		return
	var item: TreeItem = %TriggerTree.get_selected()
	if item == null:
		return
	_select_trigger(str(item.get_metadata(0)))

func _select_trigger(trigger_id: String) -> void:
	if _trigger_index(trigger_id) < 0:
		return
	_selected_trigger_id = trigger_id
	_select_trigger_tree_item(trigger_id)
	_apply_trigger_form()
	_update_trigger_buttons()

func _select_trigger_tree_item(trigger_id: String) -> void:
	var root: TreeItem = %TriggerTree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == trigger_id:
			_refreshing_trigger_tree = true
			item.select(0)
			%TriggerTree.scroll_to_item(item)
			_refreshing_trigger_tree = false
			return
		item = item.get_next()

func _apply_trigger_form() -> void:
	_loading_trigger = true
	_condition_context = "trigger"
	_condition_trigger_id = _selected_trigger_id
	_effect_context = "trigger"
	_effect_owner_id = _selected_trigger_id
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		%TriggerEditorTitle.text = "未选择机制"
		%TriggerWarning.text = "当前妖兽没有特殊机制。" if _triggers().is_empty() else "请选择一条特殊机制。"
		%TriggerWarning.show()
		%TriggerNameEdit.text = ""
		%TriggerEnabledCheck.button_pressed = true
		%TriggerOnceCheck.button_pressed = true
		%TriggerMaxUsesSpin.value = 1
		%TriggerMaxUsesSpin.editable = false
		_clear_children(%TriggerConditionsList)
		_clear_children(%TriggerEffectsList)
		_set_trigger_form_enabled(false)
		%SaveTriggerBtn.disabled = true
		_loading_trigger = false
		return
	%TriggerEditorTitle.text = "选中机制：" + _trigger_display_name(trigger)
	%TriggerNameEdit.text = str(trigger.get("name", ""))
	%TriggerNameEdit.placeholder_text = "未命名机制"
	%TriggerEnabledCheck.button_pressed = trigger.get("enabled", true) != false
	if not _select_option(%TriggerEventOption, str(trigger.get("event", "battle_start"))):
		var event_id := str(trigger.get("event", "battle_start"))
		_add_option(%TriggerEventOption, event_id, event_id)
		_select_option(%TriggerEventOption, event_id)
	var once: bool = trigger.get("once", true) != false
	%TriggerOnceCheck.button_pressed = once
	%TriggerMaxUsesSpin.value = int(trigger.get("max_uses", 1 if once else 0))
	%TriggerMaxUsesSpin.editable = not once
	_set_trigger_form_enabled(_can_edit)
	_build_effects_list(%TriggerEffectsList, %AddTriggerEffectBtn)
	_build_conditions_list(%TriggerConditionsList)
	%AddTriggerConditionBtn.disabled = not _can_edit
	_update_trigger_warning()
	_update_trigger_buttons()
	_loading_trigger = false

func _set_trigger_form_enabled(enabled: bool) -> void:
	%TriggerNameEdit.editable = enabled
	%TriggerEnabledCheck.disabled = not enabled
	%TriggerEventOption.disabled = not enabled
	%TriggerOnceCheck.disabled = not enabled
	%TriggerMaxUsesSpin.editable = enabled and not %TriggerOnceCheck.button_pressed
	%AddTriggerConditionBtn.disabled = not enabled
	%AddTriggerEffectBtn.disabled = not enabled
	%SaveTriggerBtn.disabled = not (_can_edit and _dirty)

func _update_trigger_buttons() -> void:
	var active := not _active_id.is_empty()
	var selected := _trigger_index(_selected_trigger_id) >= 0
	%AddTriggerBtn.disabled = not (_can_edit and active)
	%CopyTriggerBtn.disabled = not (_can_edit and selected)
	%RemoveTriggerBtn.disabled = not (_can_edit and selected)
	%SaveTriggerBtn.disabled = not (_can_edit and _dirty)

func _on_trigger_name_changed(text: String) -> void:
	if _loading_trigger or not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	trigger["name"] = text.strip_edges()
	_after_trigger_edit()

func _on_trigger_enabled_toggled(pressed: bool) -> void:
	if _loading_trigger or not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	trigger["enabled"] = pressed
	_after_trigger_edit()

func _on_trigger_event_changed(_index: int) -> void:
	if _loading_trigger or not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	trigger["event"] = str(_selected_metadata(%TriggerEventOption))
	_after_trigger_edit()

func _on_trigger_once_toggled(pressed: bool) -> void:
	if _loading_trigger or not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	trigger["once"] = pressed
	_loading_trigger = true
	if pressed:
		trigger["max_uses"] = 1
		%TriggerMaxUsesSpin.value = 1
		%TriggerMaxUsesSpin.editable = false
	else:
		%TriggerMaxUsesSpin.editable = true
		trigger["max_uses"] = int(%TriggerMaxUsesSpin.value)
	_loading_trigger = false
	_after_trigger_edit()

func _on_trigger_max_uses_changed(value: float) -> void:
	if _loading_trigger or not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	if trigger.get("once", true) != false:
		return
	trigger["max_uses"] = int(value)
	_after_trigger_edit()

func _after_trigger_edit() -> void:
	if _loading_trigger or not _can_edit:
		return
	_dirty = true
	_refresh_trigger_tree()
	_update_trigger_warning()
	_refresh_validation_preview()
	_update_preview_from_form()
	_update_dirty_ui()

func _update_trigger_warning() -> void:
	var trigger := _trigger_rule(_selected_trigger_id)
	var warnings: Array = []
	if trigger.is_empty():
		warnings.append("请选择或添加特殊机制。")
	else:
		var event_id := str(trigger.get("event", ""))
		if event_id not in TRIGGER_EVENTS:
			warnings.append("触发事件不受支持；保存会被校验拒绝。")
		var effects: Array = trigger.get("effects", []) if trigger.get("effects", []) is Array else []
		if effects.is_empty():
			warnings.append("至少需要一个触发效果；保存会被校验拒绝。")
		for effect in effects:
			if not effect is Dictionary:
				continue
			var effect_type := str(effect.get("type", ""))
			if effect_type == "damage":
				warnings.append("伤害型触发效果会被校验拒绝；主动伤害请使用技能。")
				break
			if effect_type not in PASSIVE_EFFECT_TYPES:
				warnings.append("不支持的触发效果类型：%s；保存会被校验拒绝。" % effect_type)
				break
			if effect_type == "status":
				var status_id := str(effect.get("status", ""))
				if not _monster_status_supported(status_id):
					warnings.append("状态 %s 不适用于怪物自身；保存后不会产生预期效果。" % status_id)
		var once_value: bool = trigger.get("once", true) != false
		var max_uses_value := int(trigger.get("max_uses", 1 if once_value else 0))
		if once_value and max_uses_value != 1:
			warnings.append("单次标记与最大次数不一致；取消勾选“只触发一次”后调整次数。")
		var conditions: Array = trigger.get("conditions", []) if trigger.get("conditions", []) is Array else []
		if conditions.is_empty():
			warnings.append("没有条件 = 事件到达时直接触发。")
		warnings.append("触发效果固定作用于自身；召唤、反伤、吸血、群体强化、敌方增益驱散未接入；减伤可用共享 damage_reduction 状态。")
		warnings.append("周期蓄力请用行为规则页的蓄力动作；此页只做周期性属性/状态/阶段强化。")
		warnings.append("特定状态触发只在战斗开始、生命阈值、自身行动开始时检查；命中/受击/状态施加事件未接入。")
	%TriggerWarning.text = "\n".join(warnings)
	%TriggerWarning.visible = not warnings.is_empty()

func _add_trigger_condition() -> void:
	_condition_context = "trigger"
	_condition_trigger_id = _selected_trigger_id
	_add_condition()
	_set_status("已添加触发条件；条件全部满足时触发。")

func _add_trigger_effect() -> void:
	_effect_context = "trigger"
	_effect_owner_id = _selected_trigger_id
	_add_effect()
	_set_status("已添加触发效果；保存后生效。")

func _open_trigger_picker() -> void:
	if not _can_edit or _active_id.is_empty():
		return
	%TriggerPickerMenu.clear()
	_trigger_picker_entries.clear()
	_add_trigger_template("模板：生命低于 50% 狂暴（每场一次）", {
		"name": "狂暴", "event": "hp_below", "enabled": true, "once": true, "max_uses": 1,
		"conditions": [{"type": "hp_below", "value": 50}],
		"effects": [
			{"type": "stat", "stat": "attack", "value": 0.25, "turns": 99, "layers": 1, "target": "self"},
			{"type": "stat", "stat": "defense", "value": -0.15, "turns": 99, "layers": 1, "target": "self"},
			{"type": "phase", "value": "berserk"},
		],
	})
	_add_trigger_template("模板：战斗开始攻击提升（+10%，整场）", {
		"name": "战意", "event": "battle_start", "enabled": true, "once": true, "max_uses": 1,
		"conditions": [],
		"effects": [{"type": "stat", "stat": "attack", "value": 0.1, "turns": 99, "layers": 1, "target": "self"}],
	})
	_add_trigger_template("模板：战斗开始防御提升（+10%，整场）", {
		"name": "铁壁", "event": "battle_start", "enabled": true, "once": true, "max_uses": 1,
		"conditions": [],
		"effects": [{"type": "stat", "stat": "defense", "value": 0.1, "turns": 99, "layers": 1, "target": "self"}],
	})
	_add_trigger_template("模板：每 3 回合攻击强化（+10%，2 回合）", {
		"name": "周期强化", "event": "turn_start", "enabled": true, "once": false, "max_uses": 0,
		"conditions": [{"type": "turn_every", "value": 3}],
		"effects": [{"type": "stat", "stat": "attack", "value": 0.1, "turns": 2, "layers": 1, "target": "self"}],
	})
	_add_trigger_template("模板：自身被封脉时清心（驱散 2 个）", {
		"name": "清心", "event": "turn_start", "enabled": true, "once": false, "max_uses": 0,
		"conditions": [{"type": "self_status", "status": "seal"}],
		"effects": [{"type": "cleanse", "count": 2}],
	})
	_add_trigger_template("模板：生命首次低于 30% 获得护盾", {
		"name": "垂死护盾", "event": "hp_below", "enabled": true, "once": true, "max_uses": 1,
		"conditions": [{"type": "hp_below", "value": 30}],
		"effects": [{"type": "shield", "power": 0.5, "turns": 3}],
	})
	_add_trigger_template("空白机制：战斗开始攻击 +10%（可继续编辑）", MonsterDatabase.create_trigger_draft({}))
	%TriggerPickerMenu.add_separator()
	var seen := {}
	for monster in _rows:
		if not monster is Dictionary or not monster.get("triggers") is Array:
			continue
		for trigger in monster.triggers:
			if not trigger is Dictionary:
				continue
			var key := JSON.stringify(trigger)
			if seen.has(key):
				continue
			seen[key] = true
			_add_trigger_template("已有机制：%s — %s" % [str(monster.get("name", monster.get("id", ""))), _trigger_display_name(trigger)], trigger.duplicate(true))
	%TriggerPickerMenu.add_separator()
	for unavailable in [
		"不可用：召唤", "不可用：反伤", "不可用：吸血被动/触发",
		"不可用：群体强化（1 对 1）", "不可用：敌方增益驱散",
		"不可用：命中/受击/状态施加事件",
		"说明：周期蓄力请用行为规则页",
	]:
		%TriggerPickerMenu.add_item(unavailable)
		%TriggerPickerMenu.set_item_disabled(%TriggerPickerMenu.item_count - 1, true)
	%TriggerPickerMenu.popup_centered(Vector2i(720, 680))

func _add_trigger_template(label: String, trigger: Dictionary) -> void:
	var id := _trigger_picker_entries.size()
	%TriggerPickerMenu.add_item(label, id)
	_trigger_picker_entries.append(trigger.duplicate(true))

func _on_trigger_picked(id: int) -> void:
	if not _can_edit or id < 0 or id >= _trigger_picker_entries.size():
		return
	var trigger: Dictionary = _trigger_picker_entries[id].duplicate(true)
	trigger["id"] = MonsterDatabase.next_id(str(trigger.get("id", "trigger_new")), _trigger_ids())
	var triggers := _triggers()
	triggers.append(trigger)
	_selected_trigger_id = str(trigger.get("id", ""))
	_dirty = true
	_refresh_trigger_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已添加特殊机制；保存后写入妖兽配置。")

func _request_copy_trigger() -> void:
	if not _can_edit:
		return
	var source := _trigger_rule(_selected_trigger_id)
	if source.is_empty():
		return
	var trigger := MonsterDatabase.copy_trigger_draft(source, _trigger_ids())
	var triggers := _triggers()
	triggers.append(trigger)
	_selected_trigger_id = str(trigger.get("id", ""))
	_dirty = true
	_refresh_trigger_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已复制特殊机制；保存后写入妖兽配置。")

func _request_remove_trigger() -> void:
	if not _can_edit:
		return
	var trigger := _trigger_rule(_selected_trigger_id)
	if trigger.is_empty():
		return
	_pending_delete_trigger_id = _selected_trigger_id
	%DeleteTriggerDialog.dialog_text = "确定删除特殊机制“%s”？\n保存后生效；未保存前可放弃修改。" % _trigger_display_name(trigger)
	%DeleteTriggerDialog.popup_centered(Vector2i(700, 280))

func _confirm_remove_trigger() -> void:
	%DeleteTriggerDialog.hide()
	if _pending_delete_trigger_id.is_empty():
		return
	var index := _trigger_index(_pending_delete_trigger_id)
	var triggers := _triggers()
	if index >= 0 and index < triggers.size():
		triggers.remove_at(index)
	_dirty = true
	_selected_trigger_id = str(triggers[0].get("id", "")) if not triggers.is_empty() and triggers[0] is Dictionary else ""
	_pending_delete_trigger_id = ""
	_refresh_trigger_page(_row(_active_id))
	_update_preview_from_form()
	_update_dirty_ui()
	_set_status("已删除特殊机制；保存后生效。")

func _on_tab_changed(tab: int) -> void:
	match tab:
		3:
			_effect_context = "passive"
			_effect_owner_id = ""
		5:
			_effect_context = "trigger"
			_effect_owner_id = _selected_trigger_id
		_:
			_effect_context = "skill"
			_effect_owner_id = ""
	if tab == 5:
		_condition_context = "trigger"
		_condition_trigger_id = _selected_trigger_id
	else:
		_condition_context = "behavior"
		_condition_trigger_id = ""
	var label: String = str(TAB_TITLES[clampi(tab, 0, TAB_TITLES.size() - 1)])
	var name: String = str(%NameEdit.text).strip_edges() if not _active_id.is_empty() else "未选择妖兽"
	%EditTitle.text = "%s — %s%s" % [label, name if not name.is_empty() else "未命名妖兽", "  *" if _dirty else ""]

func _update_dirty_ui() -> void:
	var active := not _active_id.is_empty()
	%SaveBtn.disabled = not (_can_edit and active and _dirty)
	%DiscardBtn.disabled = not (_can_edit and active and _dirty)
	%NewBtn.disabled = not _can_edit
	%CopyBtn.disabled = not (_can_edit and active)
	%DeleteBtn.disabled = not (_can_edit and active)
	%CheckBtn.disabled = not (active and _can_edit)
	var test_disabled := not (_can_edit and active and not _is_draft(_active_id)) or not OS.is_debug_build()
	%TestBattleBtn.disabled = test_disabled
	if test_disabled:
		%TestBattleBtn.tooltip_text = "测试战斗仅开发构建可用；且必须先保存当前妖兽。" if not OS.is_debug_build() else "请先保存当前妖兽；测试战斗只读取已保存配置。"
	else:
		%TestBattleBtn.tooltip_text = "使用现有战斗入口开始 1 对 1 测试战斗。"
	if _dirty:
		%DirtyLabel.text = "● 未保存修改"
		%DirtyLabel.add_theme_color_override("font_color", Color("e8c878"))
	else:
		%DirtyLabel.text = "无未保存修改"
		%DirtyLabel.add_theme_color_override("font_color", Color("94a8a2"))
	_update_skill_buttons()
	_update_behavior_buttons()
	_update_loot_buttons()
	_update_passive_buttons()
	_update_trigger_buttons()
	_on_tab_changed(%Tabs.current_tab)

func _update_edit_capability() -> void:
	var touches_res := data_path.begins_with("res://") or skills_data_path.begins_with("res://")
	_can_edit = not _load_failed and not catalog.is_empty() and (not touches_res or OS.has_feature("editor"))
	%NewBtn.disabled = not _can_edit
	_update_skill_buttons()
	_update_behavior_buttons()
	_update_loot_buttons()
	_update_passive_buttons()
	_update_trigger_buttons()
	if not _can_edit:
		_set_status("只读模式：妖兽/技能文件载入失败、内容目录未加载，或导出版本不能写入 res:// 静态配置。", true)

func _clear_form() -> void:
	_active_id = ""
	_dirty = false
	_skills_dirty = false
	_loading_form = true
	%NameEdit.text = ""
	%IdEdit.text = ""
	%DescriptionEdit.text = ""
	_clear_skill_page()
	_clear_behavior_page()
	_clear_loot_page()
	_clear_passive_page()
	_clear_trigger_page()
	_update_preview_from_form()
	_loading_form = false

func _set_status(text: String, error := false) -> void:
	%StatusLabel.text = text
	%StatusLabel.add_theme_color_override("font_color", Color("ef8f86") if error else Color("b8c9c3"))

func _on_save_pressed() -> void:
	_save_current()

func _collect_skill_form() -> void:
	var skill := _skill(_selected_skill_id)
	if skill.is_empty():
		return
	skill["name"] = str(%SkillNameEdit.text).strip_edges()
	skill["description"] = %SkillDescriptionEdit.text
	skill["mp"] = int(%SkillMpSpin.value)
	skill["cooldown"] = int(%SkillCooldownSpin.value)
	skill["target"] = str(_selected_metadata(%SkillTargetOption))
	skill["ordinary"] = %SkillOrdinaryCheck.button_pressed

func _save_current() -> bool:
	if _active_id.is_empty() or not _can_edit:
		_set_status("当前不可保存：未选择妖兽或运行在只读模式。", true)
		return false
	_collect_form()
	_collect_skill_form()
	_collect_behavior_form()
	_collect_loot_form()
	for skill_id in _dirty_skill_ids:
		if _skill_is_shared(str(skill_id)) and not bool(_shared_confirmed.get(skill_id, false)):
			_selected_skill_id = str(skill_id)
			_apply_skill_form()
			_refresh_skill_tree()
			_set_status("技能 %s 被其他妖兽引用。请勾选“我确认修改公共技能定义”，或使用“复制技能”只改当前妖兽。" % str(skill_id), true)
			return false
	var index := _row_index(_active_id)
	if index < 0:
		_set_status("当前妖兽已不存在，请重新选择。", true)
		return false
	var previous_saved_rows: Array = _saved_rows.duplicate(true)
	var previous_saved_skills: Array = _saved_skills.duplicate(true)
	var previous_rows: Array = _rows.duplicate(true)
	var previous_skills: Array = _skills.duplicate(true)
	var previous_active := _active_id
	var previous_skills_dirty := _skills_dirty
	var catalog_before: Dictionary = catalog.duplicate(true)
	var candidate_rows: Array = _rows.duplicate(true)
	var candidate_row: Dictionary = candidate_rows[index]
	if _is_draft(previous_active):
		candidate_row["id"] = str(%IdEdit.text).strip_edges()
	candidate_row["name"] = str(candidate_row.get("name", "")).strip_edges()
	candidate_row["id"] = str(candidate_row.get("id", "")).strip_edges()
	candidate_row["description"] = str(candidate_row.get("description", ""))
	var candidate_skills: Array = _skills.duplicate(true)
	for skill in candidate_skills:
		if skill is Dictionary:
			skill["name"] = str(skill.get("name", "")).strip_edges()
			skill["description"] = str(skill.get("description", ""))
	var result := MonsterDatabase.write_tables(candidate_rows, candidate_skills, catalog, data_path, skills_data_path, _skills_dirty)
	if not result.success:
		_set_status("保存失败：" + str(result.message), true)
		var save_issues: Array = result.get("issues", [])
		if not save_issues.is_empty():
			_update_validation_view(save_issues)
		return false
	var new_id := str(candidate_row.get("id", previous_active))
	_rows = candidate_rows
	_saved_rows = candidate_rows.duplicate(true)
	_skills = candidate_skills
	_saved_skills = candidate_skills.duplicate(true)
	_active_id = new_id
	var reload := _reload_game_data()
	if not reload.ok:
		var rollback := MonsterDatabase.write_tables(previous_saved_rows, previous_saved_skills, catalog_before,
			data_path, skills_data_path, previous_skills_dirty)
		if rollback.success:
			_rows = previous_rows
			_saved_rows = previous_saved_rows.duplicate(true)
			_skills = previous_skills
			_saved_skills = previous_saved_skills.duplicate(true)
			_active_id = previous_active
			_skills_dirty = previous_skills_dirty
			_dirty = true
			_reload_game_data_after_rollback()
			_set_status("保存后重新加载失败，已回滚：" + str(reload.message), true)
			_refresh_all_views()
			if _row_index(_active_id) >= 0:
				_select_row(_active_id)
			return false
		_rows = previous_rows
		_saved_rows = previous_saved_rows.duplicate(true)
		_skills = previous_skills
		_saved_skills = previous_saved_skills.duplicate(true)
		_active_id = previous_active
		_skills_dirty = previous_skills_dirty
		_dirty = true
		_set_status("文件已写入，但重新加载失败；回滚也失败：" + str(rollback.message) + " / " + str(reload.message), true)
		_refresh_all_views()
		return false
	_dirty = false
	_skills_dirty = false
	_dirty_skill_ids.clear()
	_shared_confirmed.clear()
	var suffix := ""
	if not str(result.get("warning", "")).is_empty():
		suffix = " · " + str(result.warning)
	var skill_suffix := "、%d 个技能" % _skills.size() if previous_skills_dirty else ""
	_set_status("已保存：%s（%d 只妖兽%s）%s" % [new_id, _rows.size(), skill_suffix, suffix])
	_refresh_all_views()
	_select_row(_active_id)
	return true

func _reload_game_data() -> Dictionary:
	if not propagate_to_game or data_path != MonsterDatabase.PATH or skills_data_path != MonsterDatabase.SKILLS_PATH:
		return {"ok": true, "message": ""}
	var manager := get_node_or_null("/root/GameManager")
	if manager == null:
		return {"ok": false, "message": "GameManager 不可用，无法重新加载运行时数据"}
	if not manager.catalog.load_all():
		return {"ok": false, "message": manager.catalog.error}
	manager.operations.configure(manager.catalog.tables)
	catalog = manager.catalog.tables
	runtime = manager.operations.snapshot()
	manager.operations.changed.emit()
	return {"ok": true, "message": ""}

func _reload_game_data_after_rollback() -> void:
	if not propagate_to_game or data_path != MonsterDatabase.PATH or skills_data_path != MonsterDatabase.SKILLS_PATH:
		return
	var manager := get_node_or_null("/root/GameManager")
	if manager == null:
		return
	if manager.catalog.load_all():
		manager.operations.configure(manager.catalog.tables)
		catalog = manager.catalog.tables
		runtime = manager.operations.snapshot()
		manager.operations.changed.emit()

func _request_new() -> void:
	_guard_or_call(Callable(self, "_new_draft"))

func _new_draft() -> void:
	_reset_list_filters()
	var draft := MonsterDatabase.create_draft(MonsterDatabase.ids_of(_rows), catalog.get("monster_skills", {}))
	_rows.append(draft)
	_active_id = str(draft.id)
	_dirty = true
	%Tabs.current_tab = 0
	_apply_form(draft)
	_refresh_all_views()
	_select_row(_active_id, true)
	_set_status("已创建未保存草稿：%s。默认掉落表为空（无物品掉落），第四阶段开放掉落编辑。" % _active_id)
	%NameEdit.grab_focus()
	%NameEdit.select_all()

func _request_copy() -> void:
	if _active_id.is_empty():
		return
	_guard_or_call(Callable(self, "_copy_active"))

func _copy_active() -> void:
	var source := _row(_active_id)
	if source.is_empty():
		return
	var draft := MonsterDatabase.copy_draft(source, MonsterDatabase.ids_of(_rows))
	_reset_list_filters()
	_rows.append(draft)
	_active_id = str(draft.id)
	_dirty = true
	%Tabs.current_tab = 0
	_apply_form(draft)
	_refresh_all_views()
	_select_row(_active_id, true)
	_set_status("已复制为草稿：%s。技能、行为、被动与掉落配置一并复制；保存后生成新妖兽。" % _active_id)

func _reset_list_filters() -> void:
	%Search.text = ""
	%RealmFilter.select(0)
	%RankFilter.select(0)
	_refresh_list()

func _request_delete() -> void:
	if _active_id.is_empty():
		return
	_guard_or_call(Callable(self, "_delete_active"))

func _delete_active() -> void:
	if _active_id.is_empty():
		return
	%UnsavedDialog.hide()
	%DeleteDialog.hide()
	_pending_delete_id = _active_id
	_pending_delete_is_draft = _is_draft(_active_id)
	if _pending_delete_is_draft:
		%DeleteDialog.dialog_text = "确定删除未保存草稿“%s”？此操作不会写入正式数据库。" % str(_row(_active_id).get("name", _active_id))
		%DeleteDialog.popup_centered(Vector2i(620, 240))
		return
	var references := MonsterReferences.query(_active_id, catalog, runtime)
	if int(references.get("total", 0)) > 0:
		_pending_delete_id = ""
		_show_message("无法删除", _reference_block_message(_active_id, references), Vector2i(860, 520))
		return
	%DeleteDialog.dialog_text = "确定删除“%s”（%s）？\n将写入 %s。\n当前静态配置与运行状态未发现引用；历史存档未逐个检查，旧档可能仍记录该妖兽 ID。" % [
		str(_row(_active_id).get("name", "")), _active_id, data_path]
	%DeleteDialog.popup_centered(Vector2i(720, 320))

func _reference_block_message(monster_id: String, references: Dictionary) -> String:
	var lines: Array = ["妖兽 %s 仍在以下位置被引用，不能删除：" % monster_id]
	for group in references.get("groups", []):
		for row in group.get("rows", []):
			lines.append("· %s：%s（%s）" % [str(group.get("title", "")), str(row.get("label", "")), str(row.get("detail", ""))])
	lines.append("")
	lines.append("请先修改对应任务、路线、地图图例或运行状态。气运/事件脚本引用需单独处理。")
	return "\n".join(lines)

func _confirm_delete() -> void:
	%DeleteDialog.hide()
	if _pending_delete_id.is_empty():
		return
	var index := _row_index(_pending_delete_id)
	if index < 0:
		_pending_delete_id = ""
		return
	if _pending_delete_is_draft:
		_rows.remove_at(index)
		_skills = _saved_skills.duplicate(true)
		_active_id = ""
		_dirty = false
		_skills_dirty = false
		_dirty_skill_ids.clear()
		_shared_confirmed.clear()
		_set_status("已删除未保存草稿及其未保存技能库修改。")
		_refresh_all_views()
		_select_first_visible()
		_pending_delete_id = ""
		return
	var removed: Dictionary = _rows[index]
	var removed_id := str(removed.get("id", _pending_delete_id))
	var previous_saved: Array = _saved_rows.duplicate(true)
	var previous_rows: Array = _rows.duplicate(true)
	var catalog_before: Dictionary = catalog.duplicate(true)
	_rows.remove_at(index)
	var result := MonsterDatabase.write_rows(_rows, catalog, data_path)
	if not result.success:
		_rows.insert(index, removed)
		_set_status("删除失败：" + str(result.message), true)
		var delete_issues: Array = result.get("issues", [])
		if not delete_issues.is_empty():
			_update_validation_view(delete_issues)
		_pending_delete_id = ""
		return
	_saved_rows = _rows.duplicate(true)
	_active_id = ""
	_dirty = false
	_pending_delete_id = ""
	var reload := _reload_game_data()
	if not reload.ok:
		var restore := MonsterDatabase.write_rows(previous_saved, catalog_before, data_path)
		if restore.success:
			_rows = previous_rows
			_saved_rows = previous_saved.duplicate(true)
			_active_id = removed_id
			_dirty = false
			_reload_game_data_after_rollback()
			_refresh_all_views()
			if _row_index(_active_id) >= 0:
				_select_row(_active_id)
			_set_status("删除后重新加载失败，已回滚：" + str(reload.message), true)
			return
		_set_status("删除已写入，但重新加载失败；回滚也失败：" + str(restore.message) + " / " + str(reload.message), true)
	else:
		_set_status("已删除妖兽并保存：%s" % removed_id)
	_refresh_all_views()
	_select_first_visible()

func _on_delete_canceled() -> void:
	%DeleteDialog.hide()
	_pending_delete_id = ""
	_pending_delete_is_draft = false

func _request_reset() -> void:
	if _active_id.is_empty() or (not _dirty and not _skills_dirty):
		return
	var index := _row_index(_active_id)
	if index < 0:
		return
	if _is_draft(_active_id):
		_rows.remove_at(index)
		_skills = _saved_skills.duplicate(true)
		_active_id = ""
		_dirty = false
		_skills_dirty = false
		_dirty_skill_ids.clear()
		_shared_confirmed.clear()
		_refresh_all_views()
		_select_first_visible()
		_set_status("已丢弃未保存草稿及其技能库修改。")
		return
	var saved_index := _saved_index(_active_id)
	if saved_index < 0:
		return
	_rows[index] = _saved_rows[saved_index].duplicate(true)
	_skills = _saved_skills.duplicate(true)
	_active_id = str(_rows[index].get("id", ""))
	_dirty = false
	_skills_dirty = false
	_dirty_skill_ids.clear()
	_shared_confirmed.clear()
	_apply_form(_rows[index])
	_refresh_all_views()
	_select_row(_active_id)
	_set_status("已放弃当前修改及未保存的技能库修改。")

func _guard_or_call(action: Callable) -> void:
	if _dirty:
		_pending_transition = action
		_show_unsaved()
	else:
		action.call()

func _show_unsaved() -> void:
	%DeleteDialog.hide()
	%MessageDialog.hide()
	%UnsavedDialog.dialog_text = "“%s”有未保存修改。\n请选择保存并继续、放弃修改，或取消。" % str(_row(_active_id).get("name", "当前妖兽"))
	%UnsavedDialog.popup_centered(Vector2i(660, 270))

func _on_unsaved_custom(action: StringName) -> void:
	if str(action) == "discard":
		_resolve_pending("discard")

func _resolve_pending(choice: String) -> void:
	var action := _pending_transition
	_pending_transition = Callable()
	%UnsavedDialog.hide()
	if not action.is_valid():
		return
	if choice == "save":
		if not _save_current():
			return
	elif choice == "discard":
		_discard_changes()
	action.call()

func _cancel_pending() -> void:
	_pending_transition = Callable()
	%UnsavedDialog.hide()
	_refresh_list(_active_id)

func _discard_changes() -> void:
	var previous := _active_id
	_rows = _saved_rows.duplicate(true)
	_skills = _saved_skills.duplicate(true)
	_dirty = false
	_skills_dirty = false
	_dirty_skill_ids.clear()
	_shared_confirmed.clear()
	if _row_index(previous) >= 0:
		_refresh_list(previous)
		_select_row(previous)
	else:
		# The discarded item was a draft. Do not auto-select another row here:
		# the pending action (for example delete) must not accidentally target it.
		_active_id = ""
		_clear_form()
		_refresh_all_views()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if %LootItemOverlay.visible:
			_close_loot_item_picker()
			get_viewport().set_input_as_handled()
		elif %SkillPickerOverlay.visible:
			_close_skill_picker()
			get_viewport().set_input_as_handled()

func focus_monster(monster_id: String) -> void:
	_select_row(monster_id)

func request_close() -> void:
	if _dirty:
		_pending_transition = Callable(self, "_close_now")
		_show_unsaved()
		return
	_close_now()

func _close_now() -> void:
	closed.emit()

func _refresh_all_views() -> void:
	_refresh_list(_active_id)
	if not _active_id.is_empty() and _row_index(_active_id) >= 0:
		_refresh_skill_page(_row(_active_id))
		_refresh_behavior_page(_row(_active_id))
		_refresh_loot_page(_row(_active_id))
		_refresh_passive_page(_row(_active_id))
		_refresh_trigger_page(_row(_active_id))
		_refresh_readonly_tabs(_row(_active_id))
	else:
		_clear_form()
	_update_preview_from_form()
	_update_dirty_ui()

func _select_first_visible() -> void:
	var shown := _filtered_rows()
	if shown.is_empty():
		_clear_form()
		_update_dirty_ui()
		return
	var first_id := str(shown[0].get("id", ""))
	_refresh_list(first_id)
	_select_row(first_id)

func _run_check() -> void:
	if _active_id.is_empty():
		return
	if catalog.is_empty() or not _can_edit:
		_set_status("内容目录未加载或当前为只读模式，无法执行完整配置验证。", true)
		return
	_collect_form()
	_collect_skill_form()
	var issues := MonsterDatabase.validate_rows(_rows_for_validation(), catalog, _skills)
	_update_validation_view(issues)
	if issues.is_empty():
		_set_status("验证通过：当前妖兽表未发现配置错误。")
	else:
		_set_status("验证发现 %d 个问题；请查看右侧数据验证列表。" % issues.size(), true)

func _rows_for_validation() -> Array:
	var rows: Array = _rows.duplicate(true)
	if _active_id.is_empty() or not _is_draft(_active_id):
		return rows
	var index := _row_index(_active_id)
	if index >= 0:
		rows[index]["id"] = str(%IdEdit.text).strip_edges()
	return rows

func _refresh_validation_preview() -> void:
	if catalog.is_empty() or _load_failed:
		%ValidationState.text = "只读"
		%ValidationState.add_theme_color_override("font_color", Color("d8c27c"))
		%ValidationBody.text = "[color=#d8c27c]数据文件或内容目录未完整加载，无法执行完整配置验证。[/color]"
		return
	if _active_id.is_empty():
		%ValidationState.text = "未选择"
		%ValidationState.add_theme_color_override("font_color", Color("94a8a2"))
		%ValidationBody.text = "[color=#94a8a2]请先选择妖兽。[/color]"
		return
	var row: Dictionary = _row(_active_id).duplicate(true)
	var tables: Dictionary = catalog.duplicate(true)
	tables["monster_skills"] = MonsterDatabase.rows_to_index(_skills)
	var issues: Array = []
	if _is_draft(_active_id):
		var id_text := str(%IdEdit.text).strip_edges()
		row["id"] = id_text
		if MonsterDatabase.valid_id(id_text) and id_text != _active_id and _row_index(id_text) >= 0:
			issues.append({"row": _row_index(_active_id) + 1, "id": id_text, "field": "id",
				"message": "妖兽 ID 重复：%s" % id_text, "group": "monster"})
	issues.append_array(MonsterDatabase.validate_row(row, tables, _row_index(_active_id) + 1))
	if not _selected_skill_id.is_empty():
		var skill := _skill(_selected_skill_id).duplicate(true)
		if not skill.is_empty():
			issues.append_array(MonsterDatabase.validate_skill_row(skill, tables, _skill_index(_selected_skill_id) + 1))
	_update_validation_view(issues)

func _update_validation_view(issues: Array) -> void:
	if issues.is_empty():
		%ValidationState.text = "通过"
		%ValidationState.add_theme_color_override("font_color", Color("7fd1a8"))
		%ValidationBody.text = "[color=#7fd1a8]当前配置未发现错误。[/color]\n[color=#94a8a2]验证范围：妖兽 ID/名称/数值、妖兽技能定义与效果、技能引用、行为条件、被动/触发、掉落物品。历史存档未逐个检查。[/color]"
		return
	%ValidationState.text = "%d 个问题" % issues.size()
	%ValidationState.add_theme_color_override("font_color", Color("ef8f86"))
	var lines: Array = []
	for issue in issues:
		var field := str(issue.get("field", "config"))
		var issue_id := str(issue.get("id", ""))
		var prefix := ""
		if str(issue.get("group", "")) == "skill":
			prefix = "技能 " + issue_id + " · "
		elif not issue_id.is_empty() and issue_id != _active_id:
			prefix = issue_id + " · "
		lines.append("[color=#ef8f86]• [%s] %s%s[/color]" % [field, prefix, str(issue.get("message", ""))])
	lines.append("[color=#94a8a2]历史存档、当前战斗快照与作者草稿未逐个检查。[/color]")
	%ValidationBody.text = "\n".join(lines)

func _show_message(title: String, text: String, size: Vector2i) -> void:
	%MessageDialog.title = title
	%MessageDialog.dialog_text = text
	%MessageDialog.popup_centered(size)

func _request_test_battle() -> void:
	if _active_id.is_empty() or _is_draft(_active_id):
		_set_status("请先保存当前妖兽，再进入测试战斗。", true)
		return
	_guard_or_call(Callable(self, "_emit_test_battle"))

func _emit_test_battle() -> void:
	if _active_id.is_empty() or _is_draft(_active_id):
		_set_status("请先保存当前妖兽，再进入测试战斗。", true)
		return
	test_battle_requested.emit(_active_id)

func show_test_battle_error(text: String) -> void:
	_set_status(text, true)

func _array_size(value: Variant) -> int:
	return value.size() if value is Array else 0

func _loot_entry_count(row: Dictionary) -> int:
	var loot: Variant = row.get("loot", {})
	if not loot is Dictionary:
		return 0
	var entries: Variant = loot.get("entries", [])
	return entries.size() if entries is Array else 0

func _loot_summary(row: Dictionary) -> String:
	var loot: Variant = row.get("loot", {})
	if not loot is Dictionary:
		return "掉落表：无效（掉落页已开放编辑）"
	var money: Array = loot.get("money", [0, 0]) if loot.get("money", [0, 0]) is Array else [0, 0]
	var count := _loot_entry_count(row)
	return "掉落表：%d 条物品 · 灵石 %d–%d（掉落页已开放编辑）" % [
		count, int(money[0]) if money.size() >= 1 else 0, int(money[1]) if money.size() >= 2 else 0]

func _conditions_summary(conditions: Variant) -> String:
	if conditions is Dictionary:
		conditions = [conditions]
	if not conditions is Array or conditions.is_empty():
		return "无条件"
	var parts: Array = []
	for condition in conditions:
		if not condition is Dictionary:
			continue
		var kind := str(condition.get("type", "always"))
		match kind:
			"always":
				parts.append("无条件")
			"hp_below":
				parts.append("生命 ≤ %.0f%%" % float(condition.get("value", 100)))
			"hp_above":
				parts.append("生命 ≥ %.0f%%" % float(condition.get("value", 0)))
			"mp_at_least":
				parts.append("灵力 ≥ %d" % int(condition.get("value", 0)))
			"self_status":
				parts.append("自身拥有状态 %s" % _status_name(str(condition.get("status", ""))))
			"self_not_status":
				parts.append("自身没有状态 %s" % _status_name(str(condition.get("status", ""))))
			"target_status":
				parts.append("目标拥有状态 %s" % _status_name(str(condition.get("status", ""))))
			"target_not_status":
				parts.append("目标没有状态 %s" % _status_name(str(condition.get("status", ""))))
			"action_every":
				parts.append("每第 %d 次自身行动" % int(condition.get("value", 0)))
			"turn_every":
				parts.append("每第 %d 回合" % int(condition.get("value", 0)))
			"turn_at_least":
				parts.append("第 %d 回合后" % int(condition.get("value", 0)))
			"skill_uses_below":
				parts.append("技能 %s 使用少于 %d 次" % [str(condition.get("skill", "")), int(condition.get("value", 0))])
			"skill_uses_at_least":
				parts.append("技能 %s 使用至少 %d 次" % [str(condition.get("skill", "")), int(condition.get("value", 0))])
			"phase":
				parts.append("阶段为 %s" % str(condition.get("value", "")))
			"ally_count_at_least":
				parts.append("友方数量 ≥ %d" % int(condition.get("value", 0)))
			"enemy_count_at_least":
				parts.append("敌方数量 ≥ %d" % int(condition.get("value", 0)))
			"has_available_skill":
				parts.append("存在可用技能")
			_:
				parts.append(kind)
	return " 且 ".join(parts)

func _trigger_uses_label(trigger: Dictionary) -> String:
	var once: bool = trigger.get("once", true) != false
	var max_uses := int(trigger.get("max_uses", 1 if once else 0))
	if max_uses <= 0:
		return "不限"
	if once and max_uses == 1:
		return "每场一次"
	return "%d 次" % max_uses

func _status_name(status_id: String) -> String:
	var status: Variant = catalog.get("spell_growth", {}).get("statuses", {}).get(status_id, {})
	if status is Dictionary:
		return str(status.get("name", status_id))
	return status_id

func _monster_status_supported(status_id: String) -> bool:
	return not (BattleStatus.is_player(status_id) or status_id in ["enemy_shield", "enemy_guard", "charge"])

func _effect_summary(effect: Variant) -> String:
	if not effect is Dictionary:
		return "无效效果"
	var kind := str(effect.get("type", ""))
	match kind:
		"damage":
			var parts: Array = ["直接伤害 ×%.2f" % float(effect.get("power", 0))]
			if effect.has("hits"):
				parts.append("%d 段" % int(effect.hits))
			if effect.has("flat"):
				parts.append("固定 %d" % int(effect.flat))
			if effect.has("percent_max_hp"):
				parts.append("最大生命 %.0f%%" % (float(effect.percent_max_hp) * 100.0))
			if effect.has("lifesteal"):
				parts.append("吸血 %.0f%%" % (float(effect.lifesteal) * 100.0))
			return " · ".join(parts)
		"status":
			return "状态：%s · %d 层 · %d 回合" % [
				_status_name(str(effect.get("status", ""))), int(effect.get("layers", 1)), int(effect.get("turns", 1))]
		"stat":
			var stat := str(effect.get("stat", ""))
			return "属性：%s %s%.2f" % [
				str(MonsterDatabase.STAT_LABELS.get(stat, stat)), "+" if float(effect.get("value", 0)) >= 0 else "", float(effect.get("value", 0))]
		"heal":
			return "治疗：%s" % _amount_summary(effect)
		"shield":
			return "护盾：倍率 %.2f / 最大生命 %.0f%%" % [
				float(effect.get("power", 0)), float(effect.get("percent_max_hp", 0)) * 100.0]
		"mana":
			return "灵力：%s%d" % ["抽取 " if bool(effect.get("drain", false)) else "恢复 ", int(effect.get("amount", 0))]
		"cleanse":
			return "驱散：%d 个可驱散负面状态" % int(effect.get("count", 1))
		"phase":
			return "阶段：%s" % str(effect.get("value", ""))
	return "%s %s" % [kind, JSON.stringify(effect)]

func _amount_summary(effect: Dictionary) -> String:
	var parts: Array = []
	if effect.has("amount"):
		parts.append("固定 %d" % int(effect.amount))
	if effect.has("power"):
		parts.append("攻击 ×%.2f" % float(effect.power))
	if effect.has("percent_max_hp"):
		parts.append("最大生命 %.0f%%" % (float(effect.percent_max_hp) * 100.0))
	return " / ".join(parts) if not parts.is_empty() else "未配置数值"

func _add_heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("9fe0c9"))
	parent.add_child(label)

func _add_text(parent: Node, text: String, color := Color("d3e1dc")) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _add_note(parent: Node, text: String, color := Color("94a8a2")) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
