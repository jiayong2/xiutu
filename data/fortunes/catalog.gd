extends RefCounted

# Stable catalog IDs are save keys. Keep existing IDs when editing the catalog.
const DEFINITIONS := {
	"mountain_origin": {
		"name":"山野出身", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"mountain_origin.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+5%"},
			{"id":"mountain_origin.2","type":"herb_yield","dependency":"gathering","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"草药额外收获概率+5%"},
		],
	},
	"fortune_002": {
		"name":"粗通拳脚", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_002.1","type":"normal_damage","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"普通攻击伤害+5%"},
			{"id":"fortune_002.2","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":-3,"unit":"%","targets":[],"elements":[],"description":"法术伤害-3%"},
		],
	},
	"fortune_003": {
		"name":"体弱多病", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_003.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-10,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限-10%"},
			{"id":"fortune_003.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+5"},
		],
	},
	"fortune_004": {
		"name":"勤学苦练", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_004.1","type":"study","dependency":"progression","status":"B","implemented":false,"value":5,"unit":"%","targets":[],"elements":[],"description":"功法修炼经验获取+5%"},
			{"id":"fortune_004.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":-5,"unit":"%","targets":["blood"],"elements":[],"description":"气血上限-5%"},
		],
	},
	"fortune_005": {
		"name":"天生迟钝", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_005.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-8,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性-8"},
			{"id":"fortune_005.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":2,"unit":"fixed","targets":["defense"],"elements":[],"description":"防御+2"},
		],
	},
	"fortune_006": {
		"name":"心浮气躁", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_006.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"法术伤害+5%"},
			{"id":"fortune_006.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"灵力消耗+5%"},
		],
	},
	"fortune_007": {
		"name":"识药童子", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_007.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"炼丹成功率+3个百分点"},
			{"id":"fortune_007.2","type":"herb_yield","dependency":"gathering","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"采药额外收获概率+5%"},
		],
	},
	"fortune_008": {
		"name":"天性谨慎", "kind":"innate", "quality":"凡品", "group":"凡品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_008.1","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":-3,"unit":"个百分点","targets":[],"elements":[],"description":"受到暴击概率-3个百分点"},
			{"id":"fortune_008.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":-1,"unit":"fixed","targets":["speed"],"elements":[],"description":"速度-1"},
		],
	},
	"fortune_009": {
		"name":"天生聪慧", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_009.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+8"},
			{"id":"fortune_009.2","type":"study","dependency":"progression","status":"B","implemented":false,"value":-5,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-5%"},
		],
	},
	"fortune_010": {
		"name":"皮糙肉厚", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_010.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+8%"},
			{"id":"fortune_010.2","type":"incoming_normal","dependency":"battle","status":"A","implemented":true,"value":-3,"unit":"%","targets":[],"elements":[],"description":"受到普通攻击伤害-3%"},
		],
	},
	"fortune_011": {
		"name":"气血旺盛", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_011.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["blood"],"elements":[],"description":"气血上限+10%"},
			{"id":"fortune_011.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"%","targets":["体修"],"elements":[],"description":"体修修为获取+5%"},
		],
	},
	"fortune_012": {
		"name":"灵气亲和", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_012.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+8%"},
			{"id":"fortune_012.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+5%"},
		],
	},
	"fortune_013": {
		"name":"精于算计", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_013.1","type":"buy_price","dependency":"trade","status":"A","implemented":true,"value":-5,"unit":"%","targets":[],"elements":[],"description":"普通商品购买价格-5%"},
			{"id":"fortune_013.2","type":"sell_price","dependency":"trade","status":"A","implemented":true,"value":3,"unit":"%","targets":[],"elements":[],"description":"出售价格+3%"},
		],
	},
	"fortune_014": {
		"name":"草木亲缘", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_014.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":["木"],"description":"木系法术伤害+8%"},
			{"id":"fortune_014.2","type":"herb_yield","dependency":"gathering","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"采药额外收获概率+5%"},
		],
	},
	"fortune_015": {
		"name":"意志坚定", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_015.1","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":-5,"unit":"个百分点","targets":[],"elements":[],"description":"被控制状态命中概率-5个百分点"},
		],
	},
	"fortune_016": {
		"name":"身轻如燕", "kind":"innate", "quality":"良品", "group":"良品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_016.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":2,"unit":"fixed","targets":["speed"],"elements":[],"description":"速度+2"},
			{"id":"fortune_016.2","type":"dodge","dependency":"battle","status":"A","implemented":true,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"闪避率+3个百分点"},
		],
	},
	"fortune_017": {
		"name":"经脉通畅", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_017.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":8,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+8%"},
			{"id":"fortune_017.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":-4,"unit":"%","targets":[],"elements":[],"description":"法术灵力消耗-4%"},
		],
	},
	"abundant_qi_sea": {
		"name":"气海充盈", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"abundant_qi_sea.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":15,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+15%"},
			{"id":"abundant_qi_sea.2","type":"first_spell_cost","dependency":"battle","status":"A","implemented":true,"value":-1,"unit":"fixed","targets":[],"elements":[],"description":"每回合首次施法灵力消耗-1，最低为1"},
		],
	},
	"fortune_019": {
		"name":"强筋健骨", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_019.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+10%"},
			{"id":"fortune_019.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["defense"],"elements":[],"description":"防御+5%"},
			{"id":"fortune_019.3","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"%","targets":["体修"],"elements":[],"description":"体修修为获取+5%"},
		],
	},
	"fortune_020": {
		"name":"过目不忘", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_020.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":12,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+12"},
			{"id":"fortune_020.2","type":"study","dependency":"progression","status":"B","implemented":false,"value":-10,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-10%"},
		],
	},
	"fortune_021": {
		"name":"丹火亲和", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_021.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":6,"unit":"个百分点","targets":[],"elements":[],"description":"炼丹成功率+6个百分点"},
			{"id":"fortune_021.2","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":5,"unit":"%","targets":[],"elements":[],"description":"5%概率返还1份辅材"},
		],
	},
	"fortune_022": {
		"name":"天生剑感", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_022.1","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"剑类法术伤害+10%"},
			{"id":"fortune_022.2","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":-8,"unit":"%","targets":[],"elements":[],"description":"剑类法术参悟耗时-8%"},
		],
	},
	"fortune_023": {
		"name":"识海清明", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_023.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"fixed","targets":["spirit_sea"],"elements":[],"description":"识海+5"},
			{"id":"fortune_023.2","type":"intimidation","dependency":"npc_auction","status":"A","implemented":true,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"神识威慑成功率+5个百分点"},
		],
	},
	"fortune_024": {
		"name":"五行通感", "kind":"innate", "quality":"上品", "group":"上品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_024.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":4,"unit":"%","targets":[],"elements":["金","木","水","火","土"],"description":"金木水火土法术伤害+4%"},
			{"id":"fortune_024.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+5%"},
		],
	},
	"fortune_025": {
		"name":"天生道骨", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_025.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":8,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+8%"},
			{"id":"fortune_025.2","type":"foundation_chance","dependency":"cultivation","status":"A","implemented":true,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"大境界突破成功率+3个百分点","scope":"仅筑基概率判定生效；后续确定成功的大境界不受影响"},
		],
	},
	"fortune_026": {
		"name":"百脉俱通", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_026.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"fixed","targets":["meridians"],"elements":[],"description":"经脉+8"},
			{"id":"fortune_026.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":-8,"unit":"%","targets":[],"elements":[],"description":"法术灵力消耗-8%"},
		],
	},
	"fortune_027": {
		"name":"剑心初成", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_027.1","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"剑类法术暴击率+5个百分点"},
			{"id":"fortune_027.2","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"暴击伤害+10个百分点"},
		],
	},
	"fortune_028": {
		"name":"丹道奇才", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_028.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"炼丹成功率+10个百分点"},
			{"id":"fortune_028.2","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":-15,"unit":"%","targets":[],"elements":[],"description":"炼丹参悟耗时-15%"},
		],
	},
	"fortune_029": {
		"name":"天工巧手", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_029.1","type":"refining","dependency":"refining","status":"D","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"炼器成功率+10个百分点"},
			{"id":"fortune_029.2","type":"refining","dependency":"refining","status":"D","implemented":false,"value":5,"unit":"%","targets":[],"elements":[],"description":"炼器材料返还概率+5%"},
		],
	},
	"iron_body": {
		"name":"铁骨铜身", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"iron_body.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":15,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+15%"},
			{"id":"iron_body.2","type":"incoming_final","dependency":"battle","status":"A","implemented":true,"value":-5,"unit":"%","targets":[],"elements":[],"description":"受到最终伤害-5%"},
		],
	},
	"fortune_031": {
		"name":"幽冥灵瞳", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_031.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"fixed","targets":["spirit_sea"],"elements":[],"description":"识海+8"},
			{"id":"fortune_031.2","type":"battle_modifier","dependency":"battle","status":"B","implemented":false,"value":0,"unit":"fixed","targets":[],"elements":[],"description":"战斗开始时识破目标一个可见增益状态"},
		],
	},
	"fortune_032": {
		"name":"阴阳调和", "kind":"innate", "quality":"玄品", "group":"玄品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_032.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+5%"},
			{"id":"fortune_032.2","type":"battle_start_mana","dependency":"battle","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":[],"description":"战斗开始时恢复最大灵力10%"},
		],
	},
	"fortune_033": {
		"name":"先天灵体", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"spirit_body",
		"effects":[
			{"id":"fortune_033.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":20,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+20%"},
			{"id":"fortune_033.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":15,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+15%"},
		],
	},
	"fortune_034": {
		"name":"纯阳道体", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"yin_yang_body",
		"effects":[
			{"id":"fortune_034.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":15,"unit":"%","targets":[],"elements":["火"],"description":"火系法术伤害+15%"},
			{"id":"fortune_034.2","type":"battle_trigger","dependency":"battle","status":"C","implemented":false,"value":1,"unit":"fixed","targets":[],"elements":[],"description":"每回合首次造成灼烧时持续时间+1回合"},
		],
	},
	"fortune_035": {
		"name":"玄阴道体", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"yin_yang_body",
		"effects":[
			{"id":"fortune_035.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":12,"unit":"%","targets":[],"elements":["冰","水"],"description":"冰、水系法术伤害+12%"},
			{"id":"fortune_035.2","type":"element_resist","dependency":"battle","status":"B","implemented":false,"value":8,"unit":"%","targets":[],"elements":[],"description":"受到火系伤害+8%"},
		],
	},
	"fortune_036": {
		"name":"不灭战体", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_036.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":20,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+20%"},
			{"id":"fortune_036.2","type":"incoming_low_hp","dependency":"battle","status":"A","implemented":true,"value":-10,"unit":"%","targets":[],"elements":[],"description":"生命低于30%时受到伤害-10%","condition":{"hp_below":30}},
		],
	},
	"fortune_037": {
		"name":"无垢灵心", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_037.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":15,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+15"},
			{"id":"fortune_037.2","type":"study","dependency":"progression","status":"B","implemented":false,"value":-15,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-15%"},
			{"id":"fortune_037.3","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"控制抗性+5个百分点"},
		],
	},
	"fortune_038": {
		"name":"风雷灵躯", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_038.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":12,"unit":"%","targets":[],"elements":["风","雷"],"description":"风、雷系法术伤害+12%"},
			{"id":"fortune_038.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":3,"unit":"fixed","targets":["speed"],"elements":[],"description":"速度+3"},
		],
	},
	"fortune_039": {
		"name":"万木长生体", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_039.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":12,"unit":"%","targets":[],"elements":["木"],"description":"木系法术伤害+12%"},
			{"id":"fortune_039.2","type":"wood_heal","dependency":"battle","status":"A","implemented":true,"value":15,"unit":"%","targets":[],"elements":["木"],"description":"每回合首次木系治疗量+15%"},
		],
	},
	"fortune_040": {
		"name":"天生神念", "kind":"innate", "quality":"地品", "group":"地品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_040.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"fixed","targets":["spirit_sea","soul"],"elements":[],"description":"识海、神魂各+10"},
			{"id":"fortune_040.2","type":"intimidation","dependency":"npc_auction","status":"A","implemented":true,"value":8,"unit":"个百分点","targets":[],"elements":[],"description":"神识威慑成功率+8个百分点"},
		],
	},
	"fortune_041": {
		"name":"先天道胎", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_041.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":20,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+20%"},
			{"id":"fortune_041.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":20,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+20"},
			{"id":"fortune_041.3","type":"foundation_chance","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"大境界突破成功率+5个百分点","scope":"仅筑基概率判定生效；后续确定成功的大境界不受影响"},
		],
	},
	"fortune_042": {
		"name":"太初灵体", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"spirit_body",
		"effects":[
			{"id":"fortune_042.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":25,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+25%"},
			{"id":"fortune_042.2","type":"round_mana","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"每回合开始恢复最大灵力5%，至少1点"},
		],
	},
	"fortune_043": {
		"name":"九转不灭身", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_043.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":25,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+25%"},
			{"id":"fortune_043.2","type":"battle_trigger","dependency":"battle","status":"C","implemented":false,"value":1,"unit":"点","targets":[],"elements":[],"description":"每场战斗首次受到致命伤害保留1点生命，战后进入虚弱状态"},
		],
	},
	"fortune_044": {
		"name":"混元道骨", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_044.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":["金","木","水","火","土","风","雷","冰"],"description":"八系法术伤害+8%"},
			{"id":"fortune_044.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":10,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+10%"},
		],
	},
	"fortune_045": {
		"name":"天衍慧心", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_045.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":25,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+25"},
			{"id":"fortune_045.2","type":"study","dependency":"progression","status":"B","implemented":false,"value":-20,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-20%"},
			{"id":"fortune_045.3","type":"insight_point","dependency":"enlightenment","status":"D","implemented":false,"value":1,"unit":"点","targets":[],"elements":[],"description":"突破大境界额外获得1点悟道点（仅在悟道点系统已存在时生效）"},
		],
	},
	"fortune_046": {
		"name":"苍雷圣体", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_046.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":20,"unit":"%","targets":[],"elements":["雷"],"description":"雷系法术伤害+20%"},
			{"id":"fortune_046.2","type":"battle_trigger","dependency":"battle","status":"C","implemented":false,"value":15,"unit":"%","targets":[],"elements":[],"description":"每回合首次造成雷伤时15%概率麻痹目标1回合"},
		],
	},
	"fortune_047": {
		"name":"太阴玄体", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_047.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":18,"unit":"%","targets":[],"elements":["冰"],"description":"冰系法术伤害+18%"},
			{"id":"fortune_047.2","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"施加迟缓概率+10个百分点"},
			{"id":"fortune_047.3","type":"element_resist","dependency":"battle","status":"B","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"受到火系伤害+10%"},
		],
	},
	"fortune_048": {
		"name":"阴阳同修", "kind":"innate", "quality":"天品", "group":"天品（8种）",
		"acquisition":{"event":"character_creation","description":"角色创建","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_048.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":15,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+15%"},
			{"id":"fortune_048.2","type":"dual_realm_stat","dependency":"cultivation","status":"B","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"双修境界同步达标时生命、灵力上限各+10%"},
		],
	},
	"fortune_049": {
		"name":"灵气盈身", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_049","description":"高灵气环境累计修炼30日","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_049.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":5,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+5%"},
		],
	},
	"fortune_050": {
		"name":"经脉温养", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_050","description":"完成经脉温养事件","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_050.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":3,"unit":"fixed","targets":["meridians"],"elements":[],"description":"经脉+3"},
			{"id":"fortune_050.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":-3,"unit":"%","targets":[],"elements":[],"description":"法术消耗-3%"},
		],
	},
	"fortune_051": {
		"name":"气海凝实", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_051","description":"突破达成优良气海品质","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_051.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+8%"},
		],
	},
	"stable_foundation": {
		"name":"根基稳固", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"highest_first_breakthrough","description":"完成高品质大境界突破","connected":true,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"stable_foundation.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["hp","mp"],"elements":[],"description":"生命、灵力上限各+5%"},
		],
	},
	"fortune_053": {
		"name":"厚积薄发", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_053","description":"突破前修为达到要求120%以上且完成巩固","connected":false,"threshold":1}, "duration":{"type":"once"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_053.1","type":"breakthrough_chance","dependency":"cultivation","status":"E","implemented":false,"value":8,"unit":"个百分点","targets":[],"elements":[],"description":"本次突破成功率+8个百分点，使用后消失"},
		],
	},
	"breakthrough_echo": {
		"name":"破境余韵", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"major_breakthrough","description":"突破大境界","connected":true,"threshold":1}, "duration":{"type":"timed","days":30}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"breakthrough_echo.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":10,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+10%，持续30游戏日"},
		],
	},
	"fortune_055": {
		"name":"道心通明", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_055","description":"完成重要悟道事件","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_055.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+8"},
			{"id":"fortune_055.2","type":"study","dependency":"progression","status":"B","implemented":false,"value":-5,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-5%"},
		],
	},
	"fortune_056": {
		"name":"逆境求道", "kind":"acquired", "quality":"凡品", "group":"1. 修炼与突破（8种）",
		"acquisition":{"event":"fortune_056","description":"突破失败恢复后再次成功突破","connected":false,"threshold":1}, "duration":{"type":"once"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_056.1","type":"breakthrough_chance","dependency":"cultivation","status":"E","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"下次大境界突破成功率+5个百分点，使用后消失"},
		],
	},
	"battle_veteran": {
		"name":"百战余勇", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"battle_win_total","description":"赢得50场有效战斗","connected":true,"threshold":50}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"battle_veteran.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":3,"unit":"%","targets":["attack"],"elements":[],"description":"攻击+3%"},
			{"id":"battle_veteran.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":3,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+3%"},
		],
	},
	"fortune_058": {
		"name":"临危不乱", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"fortune_058","description":"低于20%生命赢得重要战斗","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_058.1","type":"defense_low_hp","dependency":"battle","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":[],"description":"生命低于30%时防御+8%","condition":{"hp_below":30}},
		],
	},
	"fortune_059": {
		"name":"斩妖除魔", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"beast_victory","description":"击杀100只有效妖兽","connected":true,"threshold":100,"targets":["monster_gray_wolf","monster_mountain_boar","monster_green_fox","monster_wolf_leader"]}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_059.1","type":"beast_damage","dependency":"battle","status":"A","implemented":true,"value":6,"unit":"%","targets":["monster_gray_wolf","monster_mountain_boar","monster_green_fox","monster_wolf_leader"],"elements":[],"description":"对妖兽伤害+6%"},
		],
	},
	"fortune_060": {
		"name":"剑意初悟", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"fortune_060","description":"使用剑类法术赢得30场有效战斗","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_060.1","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":6,"unit":"%","targets":[],"elements":[],"description":"剑类法术伤害+6%"},
		],
	},
	"fortune_061": {
		"name":"浴血奋战", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"battle_low_hp","description":"战斗中首次生命低于30%","connected":true,"threshold":1}, "duration":{"type":"battle"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_061.1","type":"blood_recovery_on_grant","dependency":"battle","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":[],"description":"战斗中首次生命低于30%时，恢复10%最大气血"},
			{"id":"fortune_061.2","type":"damage","dependency":"battle","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":[],"description":"战斗期间伤害+8%，战后消失"},
		],
	},
	"battle_streak": {
		"name":"战意高昂", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"battle_win_streak","description":"连续赢得5场有效战斗","connected":true,"threshold":5}, "duration":{"type":"timed","days":7}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"battle_streak.1","type":"damage","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"伤害+5%，持续7游戏日"},
		],
	},
	"fortune_063": {
		"name":"绝处逢生", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"fortune_063","description":"从致命陷阱或秘境险境幸存","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_063.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+5%"},
			{"id":"fortune_063.2","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"控制抵抗+3个百分点"},
		],
	},
	"fortune_064": {
		"name":"心魔初破", "kind":"acquired", "quality":"凡品", "group":"2. 战斗与历练（8种）",
		"acquisition":{"event":"fortune_064","description":"战胜心魔幻境","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_064.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"fixed","targets":["soul"],"elements":[],"description":"神魂+5"},
			{"id":"fortune_064.2","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":8,"unit":"个百分点","targets":[],"elements":[],"description":"精神负面状态抗性+8个百分点"},
		],
	},
	"fortune_065": {
		"name":"灵泉洗髓", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_065","description":"完成灵泉洗髓奇遇","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_065.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"%","targets":["blood"],"elements":[],"description":"气血上限+8%"},
			{"id":"fortune_065.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":3,"unit":"%","targets":["体修"],"elements":[],"description":"体修修为获取+3%"},
		],
	},
	"fortune_066": {
		"name":"洞天福缘", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_066","description":"发现并探索隐藏洞府","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_066.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+5"},
			{"id":"fortune_066.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+5%"},
		],
	},
	"fortune_067": {
		"name":"古修遗泽", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_067","description":"获得古修士传承","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_067.1","type":"study","dependency":"progression","status":"B","implemented":false,"value":-10,"unit":"%","targets":[],"elements":[],"description":"功法参悟耗时-10%"},
		],
	},
	"fortune_068": {
		"name":"灵脉眷顾", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_068","description":"修复一处灵脉","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_068.1","type":"cultivation_gain","dependency":"cultivation","status":"B","implemented":false,"value":10,"unit":"%","targets":["法修"],"elements":[],"description":"灵脉环境法修修为获取+10%"},
		],
	},
	"fortune_069": {
		"name":"青木生机", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_069","description":"完成古木秘境机缘","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_069.1","type":"wood_heal","dependency":"battle","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":["木"],"description":"木系治疗量+10%"},
			{"id":"fortune_069.2","type":"herb_yield","dependency":"gathering","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"采药额外收获概率+5%"},
		],
	},
	"fortune_070": {
		"name":"星辉入体", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_070","description":"完成星象祭坛奇遇","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_070.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+10%"},
			{"id":"fortune_070.2","type":"stat","dependency":"character","status":"A","implemented":true,"value":5,"unit":"fixed","targets":["spirit_sea"],"elements":[],"description":"识海+5"},
		],
	},
	"fortune_071": {
		"name":"雷池淬体", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_071","description":"在雷池淬炼中存活","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_071.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":["雷"],"description":"雷系伤害+8%"},
			{"id":"fortune_071.2","type":"element_resist","dependency":"battle","status":"B","implemented":false,"value":-8,"unit":"%","targets":[],"elements":[],"description":"受到雷系伤害-8%"},
		],
	},
	"fortune_072": {
		"name":"天降鸿运", "kind":"acquired", "quality":"凡品", "group":"3. 机缘与探索（8种）",
		"acquisition":{"event":"fortune_072","description":"特殊奇遇获得","connected":false,"threshold":1}, "duration":{"type":"timed","days":30}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_072.1","type":"event_modifier","dependency":"encounter","status":"D","implemented":false,"value":15,"unit":"%","targets":[],"elements":[],"description":"稀有奇遇奖励权重+15%，持续30游戏日"},
		],
	},
	"alchemy_apprentice": {
		"name":"丹道入门", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"alchemy_total","description":"炼制30炉有效丹药","connected":true,"threshold":30}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"alchemy_apprentice.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"炼丹成功率+5个百分点"},
		],
	},
	"fortune_074": {
		"name":"药性通明", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"fortune_074","description":"炼出高品质丹药","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_074.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"高一档丹药品质概率+3个百分点"},
		],
	},
	"alchemy_expert": {
		"name":"丹火纯熟", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"alchemy_total","description":"成功炼制100炉丹药","connected":true,"threshold":100}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"alchemy_expert.1","type":"alchemy","dependency":"alchemy","status":"B","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"炼丹成功率+5个百分点"},
			{"id":"alchemy_expert.2","type":"craft_time","dependency":"alchemy","status":"A","implemented":true,"value":-5,"unit":"%","targets":[],"elements":[],"description":"炼丹耗时-5%"},
		],
	},
	"fortune_076": {
		"name":"百炼成器", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"fortune_076","description":"炼制30件有效装备","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_076.1","type":"refining","dependency":"refining","status":"D","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"炼器成功率+5个百分点"},
		],
	},
	"fortune_077": {
		"name":"天工灵感", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"fortune_077","description":"炼出当前境界极品装备","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_077.1","type":"refining","dependency":"refining","status":"D","implemented":false,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"装备高一档品质概率+3个百分点"},
		],
	},
	"fortune_078": {
		"name":"采药识途", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"herb_gather_total","description":"采集100株有效灵药","connected":true,"threshold":100}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_078.1","type":"herb_yield","dependency":"gathering","status":"A","implemented":true,"value":8,"unit":"%","targets":[],"elements":[],"description":"采药额外收获概率+8%"},
		],
	},
	"herb_grower": {
		"name":"灵植妙手", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"harvest_total","description":"培育50株成熟灵植","connected":true,"threshold":50}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"herb_grower.1","type":"plant_speed","dependency":"planting","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":[],"description":"灵植生长速度+10%"},
		],
	},
	"trade_expert": {
		"name":"商道亨通", "kind":"acquired", "quality":"凡品", "group":"4. 炼丹炼器与生活（8种）",
		"acquisition":{"event":"shop_trade_total","description":"完成20次有效商贸交易","connected":true,"threshold":20}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"trade_expert.1","type":"buy_price","dependency":"trade","status":"A","implemented":true,"value":-5,"unit":"%","targets":[],"elements":[],"description":"购买价格-5%"},
			{"id":"trade_expert.2","type":"sell_price","dependency":"trade","status":"A","implemented":true,"value":3,"unit":"%","targets":[],"elements":[],"description":"出售价格+3%"},
		],
	},
	"fortune_081": {
		"name":"宗门新秀", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_081","description":"晋升内门弟子","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_081.1","type":"contribution","dependency":"sect","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":[],"description":"宗门贡献获取+10%"},
		],
	},
	"fortune_082": {
		"name":"师门垂青", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_082","description":"师徒亲近并完成师门任务","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_082.1","type":"study","dependency":"sect","status":"D","implemented":false,"value":-10,"unit":"%","targets":[],"elements":[],"description":"师门功法参悟耗时-10%"},
		],
	},
	"fortune_083": {
		"name":"宗门栋梁", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_083","description":"完成宗门重大事件","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_083.1","type":"contribution","dependency":"sect","status":"A","implemented":true,"value":15,"unit":"%","targets":[],"elements":[],"description":"贡献获取+15%"},
			{"id":"fortune_083.2","type":"sect_price","dependency":"sect","status":"D","implemented":false,"value":-5,"unit":"%","targets":[],"elements":[],"description":"宗门商店购买价格-5%"},
		],
	},
	"fortune_084": {
		"name":"广结善缘", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_084","description":"与10位不同NPC达到友善","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_084.1","type":"relationship","dependency":"npc_social","status":"D","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"正面社交好感收益+10%"},
		],
	},
	"fortune_085": {
		"name":"行善积德", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_085","description":"完成20次不同的行善事件","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_085.1","type":"relationship","dependency":"npc_social","status":"D","implemented":false,"value":5,"unit":"fixed","targets":[],"elements":[],"description":"善良NPC初始好感+5"},
			{"id":"fortune_085.2","type":"event_modifier","dependency":"encounter","status":"D","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"善缘奇遇权重+10%"},
		],
	},
	"fortune_086": {
		"name":"恩怨分明", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_086","description":"完成5次复仇或报恩事件","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_086.1","type":"relationship","dependency":"npc_social","status":"D","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"恩人、仇人专属交互成功率+10个百分点"},
		],
	},
	"fortune_087": {
		"name":"名动一方", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_087","description":"在区域达到高声望","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_087.1","type":"quest_reward","dependency":"regional_reputation","status":"D","implemented":false,"value":5,"unit":"%","targets":[],"elements":[],"description":"本区域普通任务报酬+5%"},
		],
	},
	"fortune_088": {
		"name":"贵人相助", "kind":"acquired", "quality":"凡品", "group":"5. 宗门、声望与人际（8种）",
		"acquisition":{"event":"fortune_088","description":"关键剧情获得高境界NPC帮助","connected":false,"threshold":1}, "duration":{"type":"once"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_088.1","type":"event_modifier","dependency":"encounter","status":"D","implemented":false,"value":10,"unit":"个百分点","targets":[],"elements":[],"description":"下次非战斗奇遇负面判定成功率+10个百分点，触发后消失"},
		],
	},
	"fortune_089": {
		"name":"龙血洗礼", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_089","description":"古龙血池传承","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_089.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":15,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限+15%"},
			{"id":"fortune_089.2","type":"round_heal","dependency":"battle","status":"A","implemented":true,"value":2,"unit":"%","targets":[],"elements":[],"description":"每回合结束恢复最大生命2%"},
		],
	},
	"fortune_090": {
		"name":"凤火余烬", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_090","description":"凤凰残火传承","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_090.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":12,"unit":"%","targets":[],"elements":["火"],"description":"火系法术伤害+12%"},
			{"id":"fortune_090.2","type":"battle_trigger","dependency":"battle","status":"C","implemented":false,"value":0,"unit":"fixed","targets":[],"elements":[],"description":"每场战斗首次受到灼烧时免疫此次灼烧"},
		],
	},
	"fortune_091": {
		"name":"太古剑意", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_091","description":"古剑仙传承","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_091.1","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":12,"unit":"%","targets":[],"elements":[],"description":"剑类法术伤害+12%"},
			{"id":"fortune_091.2","type":"sword_modifier","dependency":"spell_class","status":"B","implemented":false,"value":5,"unit":"个百分点","targets":[],"elements":[],"description":"剑类法术暴击率+5个百分点"},
		],
	},
	"fortune_092": {
		"name":"万毒不侵", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_092","description":"毒谷洗髓试炼","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_092.1","type":"status_modifier","dependency":"battle_status","status":"B","implemented":false,"value":30,"unit":"个百分点","targets":[],"elements":[],"description":"中毒抗性+30个百分点"},
			{"id":"fortune_092.2","type":"poison_damage","dependency":"battle_status","status":"A","implemented":true,"value":-20,"unit":"%","targets":[],"elements":[],"description":"持续毒伤-20%"},
		],
	},
	"fortune_093": {
		"name":"九霄雷印", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_093","description":"九霄雷殿传承","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_093.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":15,"unit":"%","targets":[],"elements":["雷"],"description":"雷系法术伤害+15%"},
			{"id":"fortune_093.2","type":"lightning_first_hit","dependency":"battle","status":"A","implemented":true,"value":20,"unit":"%","targets":[],"elements":["雷"],"description":"每场战斗首次雷系攻击追加攻击力20%的雷伤"},
		],
	},
	"fortune_094": {
		"name":"玄龟护命", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_094","description":"玄龟血脉祝福","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_094.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["defense"],"elements":[],"description":"防御+10%"},
			{"id":"fortune_094.2","type":"battle_trigger","dependency":"battle","status":"C","implemented":false,"value":30,"unit":"%","targets":[],"elements":[],"description":"每场战斗首次生命低于30%获得最大生命15%的护盾，持续2回合"},
		],
	},
	"fortune_095": {
		"name":"造化灵息", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_095","description":"造化秘境灌注","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_095.1","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":8,"unit":"%","targets":["法修","体修"],"elements":[],"description":"法修、体修修为获取+8%"},
			{"id":"fortune_095.2","type":"stat","dependency":"character","status":"B","implemented":false,"value":5,"unit":"年","targets":["lifespan"],"elements":[],"description":"寿元上限+5年"},
		],
	},
	"fortune_096": {
		"name":"天道垂青", "kind":"acquired", "quality":"凡品", "group":"6. 特殊传承（8种）",
		"acquisition":{"event":"fortune_096","description":"天道级奇遇","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"", "exclusive_group":"",
		"effects":[
			{"id":"fortune_096.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"fixed","targets":["insight"],"elements":[],"description":"悟性+10"},
			{"id":"fortune_096.2","type":"event_modifier","dependency":"encounter","status":"D","implemented":false,"value":10,"unit":"%","targets":[],"elements":[],"description":"稀有奇遇奖励权重+10%"},
			{"id":"fortune_096.3","type":"foundation_chance","dependency":"cultivation","status":"A","implemented":true,"value":3,"unit":"个百分点","targets":[],"elements":[],"description":"大境界突破成功率+3个百分点","scope":"仅筑基概率判定生效；后续确定成功的大境界不受影响"},
		],
	},
	"fortune_097": {
		"name":"经脉暗伤", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_097","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"高品质疗伤丹或专门疗伤", "exclusive_group":"",
		"effects":[
			{"id":"fortune_097.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-10,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限-10%"},
			{"id":"fortune_097.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":5,"unit":"%","targets":[],"elements":[],"description":"法术消耗+5%"},
		],
	},
	"fortune_098": {
		"name":"气血亏空", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_098","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"温养气血、疗伤", "exclusive_group":"",
		"effects":[
			{"id":"fortune_098.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-10,"unit":"%","targets":["hp"],"elements":[],"description":"生命上限-10%"},
			{"id":"fortune_098.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":-10,"unit":"%","targets":["体修"],"elements":[],"description":"体修修为获取-10%"},
		],
	},
	"fortune_099": {
		"name":"神魂不稳", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_099","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"神魂修复机缘", "exclusive_group":"",
		"effects":[
			{"id":"fortune_099.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-8,"unit":"fixed","targets":["soul"],"elements":[],"description":"神魂-8"},
			{"id":"fortune_099.2","type":"intimidation","dependency":"npc_auction","status":"A","implemented":true,"value":-10,"unit":"个百分点","targets":[],"elements":[],"description":"神识威慑成功率-10个百分点"},
		],
	},
	"fortune_100": {
		"name":"丹毒积累", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_100","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"清除丹毒", "exclusive_group":"",
		"effects":[
			{"id":"fortune_100.1","type":"pill_recovery","dependency":"inventory","status":"A","implemented":true,"value":-15,"unit":"%","targets":[],"elements":[],"description":"丹药恢复效果-15%"},
			{"id":"fortune_100.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":-5,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取-5%"},
		],
	},
	"fortune_101": {
		"name":"心魔缠身", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_101","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"心魔试炼", "exclusive_group":"",
		"effects":[
			{"id":"fortune_101.1","type":"foundation_chance","dependency":"cultivation","status":"A","implemented":true,"value":-10,"unit":"个百分点","targets":[],"elements":[],"description":"大境界突破成功率-10个百分点","scope":"仅筑基概率判定生效；后续确定成功的大境界不受影响"},
		],
	},
	"fortune_102": {
		"name":"天煞孤星", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_102","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"特殊命数奇遇", "exclusive_group":"",
		"effects":[
			{"id":"fortune_102.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["attack"],"elements":[],"description":"攻击+10%"},
			{"id":"fortune_102.2","type":"relationship","dependency":"npc_social","status":"D","implemented":false,"value":-10,"unit":"fixed","targets":[],"elements":[],"description":"普通NPC初始好感-10"},
			{"id":"fortune_102.3","type":"event_modifier","dependency":"encounter","status":"D","implemented":false,"value":-15,"unit":"%","targets":[],"elements":[],"description":"友善事件权重-15%"},
		],
	},
	"fortune_103": {
		"name":"血煞缠身", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_103","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"净化血煞", "exclusive_group":"",
		"effects":[
			{"id":"fortune_103.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":8,"unit":"%","targets":["attack"],"elements":[],"description":"攻击+8%"},
			{"id":"fortune_103.2","type":"battle_start_hp","dependency":"battle","status":"A","implemented":true,"value":-5,"unit":"%","targets":[],"elements":[],"description":"每场战斗开始损失5%最大生命"},
		],
	},
	"fortune_104": {
		"name":"逆脉修行", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_104","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"重塑经脉", "exclusive_group":"",
		"effects":[
			{"id":"fortune_104.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":12,"unit":"%","targets":[],"elements":[],"description":"法术伤害+12%"},
			{"id":"fortune_104.2","type":"spell_cost","dependency":"battle","status":"A","implemented":true,"value":15,"unit":"%","targets":[],"elements":[],"description":"法术灵力消耗+15%"},
		],
	},
	"fortune_105": {
		"name":"寿元亏损", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_105","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"延寿机缘", "exclusive_group":"",
		"effects":[
			{"id":"fortune_105.1","type":"stat","dependency":"character","status":"B","implemented":false,"value":-10,"unit":"年","targets":["lifespan"],"elements":[],"description":"寿元上限-10年"},
			{"id":"fortune_105.2","type":"cultivation_gain","dependency":"cultivation","status":"A","implemented":true,"value":10,"unit":"%","targets":["法修"],"elements":[],"description":"法修修为获取+10%"},
		],
	},
	"fortune_106": {
		"name":"灵气驳杂", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_106","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"凝练灵气", "exclusive_group":"",
		"effects":[
			{"id":"fortune_106.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":10,"unit":"%","targets":["mp"],"elements":[],"description":"灵力上限+10%"},
			{"id":"fortune_106.2","type":"foundation_chance","dependency":"cultivation","status":"A","implemented":true,"value":-8,"unit":"个百分点","targets":[],"elements":[],"description":"突破成功率-8个百分点","scope":"仅筑基概率判定生效；后续确定成功的大境界不受影响"},
		],
	},
	"fortune_107": {
		"name":"阴火侵体", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_107","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"驱除阴火", "exclusive_group":"",
		"effects":[
			{"id":"fortune_107.1","type":"spell_damage","dependency":"battle","status":"A","implemented":true,"value":10,"unit":"%","targets":[],"elements":["火"],"description":"火系伤害+10%"},
			{"id":"fortune_107.2","type":"fire_hp_cost","dependency":"battle","status":"A","implemented":true,"value":2,"unit":"%","targets":[],"elements":["火"],"description":"每回合首次火系法术损失最大生命2%"},
		],
	},
	"fortune_108": {
		"name":"天劫余伤", "kind":"negative", "quality":"负面", "group":"五、12种负面及代价气运",
		"acquisition":{"event":"fortune_108","description":"负面事件待正式接入","connected":false,"threshold":1}, "duration":{"type":"permanent"}, "removal":"渡劫后调养", "exclusive_group":"",
		"effects":[
			{"id":"fortune_108.1","type":"stat","dependency":"character","status":"A","implemented":true,"value":-10,"unit":"%","targets":["defense"],"elements":[],"description":"防御-10%"},
			{"id":"fortune_108.2","type":"element_resist","dependency":"battle","status":"B","implemented":false,"value":15,"unit":"%","targets":[],"elements":[],"description":"受到雷系伤害+15%"},
		],
	},
}
