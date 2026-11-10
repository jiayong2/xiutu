@tool
extends RefCounted

const GROUPS := {
	"怪物与修士": ["M01", "M02", "M03", "M04", "N01", "N02", "N03", "N04"],
	"宝物与采集": ["O01", "O02", "O03", "O04", "O05", "O06", "O07", "O08"],
	"机关与事件": ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"],
}
const ICONS := {
	"M01": ["普通妖兽", "#f3949c", "beast"], "M02": ["精英妖兽", "#d0a0ff", "beast"],
	"M03": ["Boss首领", "#ff8077", "beast"], "M04": ["守卫妖兽", "#ffc28b", "beast"],
	"N01": ["普通NPC", "#a5e7df", "person"], "N02": ["宗门长老", "#f1d388", "person"],
	"N03": ["商人", "#ffc776", "person"], "N04": ["敌对修士", "#ff959e", "person"],
	"O01": ["普通宝箱", "#f0c679", "chest"], "O02": ["稀有宝箱", "#cf9cf6", "chest"],
	"O03": ["灵草", "#a6eab1", "herb"], "O04": ["灵矿", "#9ad5ef", "ore"],
	"O05": ["灵石堆", "#f1db95", "ore"], "O06": ["丹炉", "#f6ab81", "furnace"],
	"O07": ["灵气泉眼", "#98e7eb", "spring"], "O08": ["遗迹宝物", "#f1d388", "relic"],
	"S01": ["传送法阵", "#a1edf5", "disc"], "S02": ["遗迹入口", "#afcfee", "gate"],
	"S03": ["陷阱", "#ff9b94", "trap"], "S04": ["机关", "#f2c278", "disc"],
	"S05": ["随机事件", "#d2aff1", "question"], "S06": ["隐藏机缘", "#ffe095", "star"],
	"S07": ["地图入口", "#a2e4bf", "gate"], "S08": ["地图出口", "#9ddff4", "gate"],
}

static func title(id: String) -> String:
	return ICONS[id][0] if ICONS.has(id) else "无图例"

