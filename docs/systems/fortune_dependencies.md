# 气运逐效果依赖清单

核对日期 2026-11-07。配置与运行态状态以 [气运数据表](../../data/fortunes/catalog.gd) 为准。此表用于定位接入和回归。A 表示对应处理器已接通；能否在正式玩法获得须另外看来源。B 为已有系统但目标规则或事件未齐，C 为可独立补建的通用触发，D 为未来玩法，E 为设计冲突。尚未接入的效果均由统一处理器排除。

## 数量

- 108 条，196 个效果。A 134，B 38，C 5，D 17，E 2。
- 57 条全部效果已接通，28 条部分效果已接通。47 条有创建或正式获取入口，其中 46 条至少有一个已接通效果，共 77 个效果。
- 表中“接口”指已接通的结算或未来接入目标。专项和相关回归覆盖基础处理器与部分正式发放，逐条独立数值和图形测试仍待执行。

| 气运 ID／名称 | 效果 ID | 效果 | 状态 | 依赖 | 接口 | 获取来源 | 独立测试 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mountain_origin 山野出身 | mountain_origin.1 | 生命上限+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| mountain_origin 山野出身 | mountain_origin.2 | 草药额外收获概率+5% | A | gathering | OperationService.explore | 已接通 · 角色创建 | 未逐项执行 |
| fortune_002 粗通拳脚 | fortune_002.1 | 普通攻击伤害+5% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_002 粗通拳脚 | fortune_002.2 | 法术伤害-3% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_003 体弱多病 | fortune_003.1 | 生命上限-10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_003 体弱多病 | fortune_003.2 | 悟性+5 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_004 勤学苦练 | fortune_004.1 | 功法修炼经验获取+5% | B | progression | 功法进阶待补接口 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_004 勤学苦练 | fortune_004.2 | 气血上限-5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_005 天生迟钝 | fortune_005.1 | 悟性-8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_005 天生迟钝 | fortune_005.2 | 防御+2 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_006 心浮气躁 | fortune_006.1 | 法术伤害+5% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_006 心浮气躁 | fortune_006.2 | 灵力消耗+5% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_007 识药童子 | fortune_007.1 | 炼丹成功率+3个百分点 | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 角色创建 | 未逐项执行 |
| fortune_007 识药童子 | fortune_007.2 | 采药额外收获概率+5% | A | gathering | OperationService.explore | 待接入 · 角色创建 | 未逐项执行 |
| fortune_008 天性谨慎 | fortune_008.1 | 受到暴击概率-3个百分点 | B | battle_status | BattleStatus | 已接通 · 角色创建 | 未逐项执行 |
| fortune_008 天性谨慎 | fortune_008.2 | 速度-1 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_009 天生聪慧 | fortune_009.1 | 悟性+8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_009 天生聪慧 | fortune_009.2 | 功法参悟耗时-5% | B | progression | 功法进阶待补接口 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_010 皮糙肉厚 | fortune_010.1 | 生命上限+8% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_010 皮糙肉厚 | fortune_010.2 | 受到普通攻击伤害-3% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_011 气血旺盛 | fortune_011.1 | 气血上限+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_011 气血旺盛 | fortune_011.2 | 体修修为获取+5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_012 灵气亲和 | fortune_012.1 | 灵力上限+8% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_012 灵气亲和 | fortune_012.2 | 法修修为获取+5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_013 精于算计 | fortune_013.1 | 普通商品购买价格-5% | A | trade | ShopSystem.unit_price | 已接通 · 角色创建 | 未逐项执行 |
| fortune_013 精于算计 | fortune_013.2 | 出售价格+3% | A | trade | ShopSystem.unit_price | 已接通 · 角色创建 | 未逐项执行 |
| fortune_014 草木亲缘 | fortune_014.1 | 木系法术伤害+8% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_014 草木亲缘 | fortune_014.2 | 采药额外收获概率+5% | A | gathering | OperationService.explore | 已接通 · 角色创建 | 未逐项执行 |
| fortune_015 意志坚定 | fortune_015.1 | 被控制状态命中概率-5个百分点 | B | battle_status | BattleStatus | 待接入 · 角色创建 | 未逐项执行 |
| fortune_016 身轻如燕 | fortune_016.1 | 速度+2 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_016 身轻如燕 | fortune_016.2 | 闪避率+3个百分点 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_017 经脉通畅 | fortune_017.1 | 法修修为获取+8% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_017 经脉通畅 | fortune_017.2 | 法术灵力消耗-4% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| abundant_qi_sea 气海充盈 | abundant_qi_sea.1 | 灵力上限+15% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| abundant_qi_sea 气海充盈 | abundant_qi_sea.2 | 每回合首次施法灵力消耗-1，最低为1 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_019 强筋健骨 | fortune_019.1 | 生命上限+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_019 强筋健骨 | fortune_019.2 | 防御+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_019 强筋健骨 | fortune_019.3 | 体修修为获取+5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_020 过目不忘 | fortune_020.1 | 悟性+12 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_020 过目不忘 | fortune_020.2 | 功法参悟耗时-10% | B | progression | 功法进阶待补接口 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_021 丹火亲和 | fortune_021.1 | 炼丹成功率+6个百分点 | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 角色创建 | 未逐项执行 |
| fortune_021 丹火亲和 | fortune_021.2 | 5%概率返还1份辅材 | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 角色创建 | 未逐项执行 |
| fortune_022 天生剑感 | fortune_022.1 | 剑类法术伤害+10% | B | spell_class | 法术分类待补接口 | 待接入 · 角色创建 | 未逐项执行 |
| fortune_022 天生剑感 | fortune_022.2 | 剑类法术参悟耗时-8% | B | spell_class | 法术分类待补接口 | 待接入 · 角色创建 | 未逐项执行 |
| fortune_023 识海清明 | fortune_023.1 | 识海+5 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_023 识海清明 | fortune_023.2 | 神识威慑成功率+5个百分点 | A | npc_auction | Mental.chance / AuctionSystem | 已接通 · 角色创建 | 未逐项执行 |
| fortune_024 五行通感 | fortune_024.1 | 金木水火土法术伤害+4% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_024 五行通感 | fortune_024.2 | 灵力上限+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_025 天生道骨 | fortune_025.1 | 法修、体修修为获取+8% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_025 天生道骨 | fortune_025.2 | 大境界突破成功率+3个百分点（仅筑基概率判定生效；后续确定成功的大境界不受影响） | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_026 百脉俱通 | fortune_026.1 | 经脉+8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_026 百脉俱通 | fortune_026.2 | 法术灵力消耗-8% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_027 剑心初成 | fortune_027.1 | 剑类法术暴击率+5个百分点 | B | spell_class | 法术分类待补接口 | 待接入 · 角色创建 | 未逐项执行 |
| fortune_027 剑心初成 | fortune_027.2 | 暴击伤害+10个百分点 | B | spell_class | 法术分类待补接口 | 待接入 · 角色创建 | 未逐项执行 |
| fortune_028 丹道奇才 | fortune_028.1 | 炼丹成功率+10个百分点 | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 角色创建 | 未逐项执行 |
| fortune_028 丹道奇才 | fortune_028.2 | 炼丹参悟耗时-15% | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 角色创建 | 未逐项执行 |
| fortune_029 天工巧手 | fortune_029.1 | 炼器成功率+10个百分点 | D | refining | 炼器待开放 | 待接入 · 角色创建 | 未逐项执行 |
| fortune_029 天工巧手 | fortune_029.2 | 炼器材料返还概率+5% | D | refining | 炼器待开放 | 待接入 · 角色创建 | 未逐项执行 |
| iron_body 铁骨铜身 | iron_body.1 | 生命上限+15% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 角色创建 | 未逐项执行 |
| iron_body 铁骨铜身 | iron_body.2 | 受到最终伤害-5% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_031 幽冥灵瞳 | fortune_031.1 | 识海+8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_031 幽冥灵瞳 | fortune_031.2 | 战斗开始时识破目标一个可见增益状态 | B | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_032 阴阳调和 | fortune_032.1 | 法修、体修修为获取+5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_032 阴阳调和 | fortune_032.2 | 战斗开始时恢复最大灵力10% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_033 先天灵体 | fortune_033.1 | 灵力上限+20% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_033 先天灵体 | fortune_033.2 | 法修修为获取+15% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_034 纯阳道体 | fortune_034.1 | 火系法术伤害+15% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_034 纯阳道体 | fortune_034.2 | 每回合首次造成灼烧时持续时间+1回合 | C | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_035 玄阴道体 | fortune_035.1 | 冰、水系法术伤害+12% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_035 玄阴道体 | fortune_035.2 | 受到火系伤害+8% | B | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_036 不灭战体 | fortune_036.1 | 生命上限+20% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 角色创建 | 未逐项执行 |
| fortune_036 不灭战体 | fortune_036.2 | 生命低于30%时受到伤害-10% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_037 无垢灵心 | fortune_037.1 | 悟性+15 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_037 无垢灵心 | fortune_037.2 | 功法参悟耗时-15% | B | progression | 功法进阶待补接口 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_037 无垢灵心 | fortune_037.3 | 控制抗性+5个百分点 | B | battle_status | BattleStatus | 已接通 · 角色创建 | 未逐项执行 |
| fortune_038 风雷灵躯 | fortune_038.1 | 风、雷系法术伤害+12% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_038 风雷灵躯 | fortune_038.2 | 速度+3 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_039 万木长生体 | fortune_039.1 | 木系法术伤害+12% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_039 万木长生体 | fortune_039.2 | 每回合首次木系治疗量+15% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_040 天生神念 | fortune_040.1 | 识海、神魂各+10 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_040 天生神念 | fortune_040.2 | 神识威慑成功率+8个百分点 | A | npc_auction | Mental.chance / AuctionSystem | 已接通 · 角色创建 | 未逐项执行 |
| fortune_041 先天道胎 | fortune_041.1 | 法修修为获取+20% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_041 先天道胎 | fortune_041.2 | 悟性+20 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_041 先天道胎 | fortune_041.3 | 大境界突破成功率+5个百分点（仅筑基概率判定生效；后续确定成功的大境界不受影响） | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_042 太初灵体 | fortune_042.1 | 灵力上限+25% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_042 太初灵体 | fortune_042.2 | 每回合开始恢复最大灵力5%，至少1点 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_043 九转不灭身 | fortune_043.1 | 生命上限+25% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 角色创建 | 未逐项执行 |
| fortune_043 九转不灭身 | fortune_043.2 | 每场战斗首次受到致命伤害保留1点生命，战后进入虚弱状态 | C | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_044 混元道骨 | fortune_044.1 | 八系法术伤害+8% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_044 混元道骨 | fortune_044.2 | 法修、体修修为获取+10% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_045 天衍慧心 | fortune_045.1 | 悟性+25 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 角色创建 | 未逐项执行 |
| fortune_045 天衍慧心 | fortune_045.2 | 功法参悟耗时-20% | B | progression | 功法进阶待补接口 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_045 天衍慧心 | fortune_045.3 | 突破大境界额外获得1点悟道点（仅在悟道点系统已存在时生效） | D | enlightenment | 悟道点待开放 | 已接通 · 角色创建 | 未逐项执行 |
| fortune_046 苍雷圣体 | fortune_046.1 | 雷系法术伤害+20% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_046 苍雷圣体 | fortune_046.2 | 每回合首次造成雷伤时15%概率麻痹目标1回合 | C | battle | BattleSystem / SpellEffectResolver | 已接通 · 角色创建 | 未逐项执行 |
| fortune_047 太阴玄体 | fortune_047.1 | 冰系法术伤害+18% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_047 太阴玄体 | fortune_047.2 | 施加迟缓概率+10个百分点 | B | battle_status | BattleStatus | 待接入 · 角色创建 | 未逐项执行 |
| fortune_047 太阴玄体 | fortune_047.3 | 受到火系伤害+10% | B | battle | BattleSystem / SpellEffectResolver | 待接入 · 角色创建 | 未逐项执行 |
| fortune_048 阴阳同修 | fortune_048.1 | 法修、体修修为获取+15% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_048 阴阳同修 | fortune_048.2 | 双修境界同步达标时生命、灵力上限各+10% | B | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 角色创建 | 未逐项执行 |
| fortune_049 灵气盈身 | fortune_049.1 | 法修修为获取+5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 高灵气环境累计修炼30日 | 未逐项执行 |
| fortune_050 经脉温养 | fortune_050.1 | 经脉+3 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 完成经脉温养事件 | 未逐项执行 |
| fortune_050 经脉温养 | fortune_050.2 | 法术消耗-3% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 完成经脉温养事件 | 未逐项执行 |
| fortune_051 气海凝实 | fortune_051.1 | 灵力上限+8% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 突破达成优良气海品质 | 未逐项执行 |
| stable_foundation 根基稳固 | stable_foundation.1 | 生命、灵力上限各+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 完成高品质大境界突破 | 未逐项执行 |
| fortune_053 厚积薄发 | fortune_053.1 | 本次突破成功率+8个百分点，使用后消失 | E | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 突破前修为达到要求120%以上且完成巩固 | 未逐项执行 |
| breakthrough_echo 破境余韵 | breakthrough_echo.1 | 法修、体修修为获取+10%，持续30游戏日 | A | cultivation | SpiritCultivation / CultivationSystem.promote | 已接通 · 突破大境界 | 未逐项执行 |
| fortune_055 道心通明 | fortune_055.1 | 悟性+8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 完成重要悟道事件 | 未逐项执行 |
| fortune_055 道心通明 | fortune_055.2 | 功法参悟耗时-5% | B | progression | 功法进阶待补接口 | 待接入 · 完成重要悟道事件 | 未逐项执行 |
| fortune_056 逆境求道 | fortune_056.1 | 下次大境界突破成功率+5个百分点，使用后消失 | E | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 突破失败恢复后再次成功突破 | 未逐项执行 |
| battle_veteran 百战余勇 | battle_veteran.1 | 攻击+3% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 赢得50场有效战斗 | 未逐项执行 |
| battle_veteran 百战余勇 | battle_veteran.2 | 生命上限+3% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 已接通 · 赢得50场有效战斗 | 未逐项执行 |
| fortune_058 临危不乱 | fortune_058.1 | 生命低于30%时防御+8% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 低于20%生命赢得重要战斗 | 未逐项执行 |
| fortune_059 斩妖除魔 | fortune_059.1 | 对妖兽伤害+6% | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 击杀100只有效妖兽 | 未逐项执行 |
| fortune_060 剑意初悟 | fortune_060.1 | 剑类法术伤害+6% | B | spell_class | 法术分类待补接口 | 待接入 · 使用剑类法术赢得30场有效战斗 | 未逐项执行 |
| fortune_061 浴血奋战 | fortune_061.1 | 战斗中首次生命低于30%时，恢复10%最大气血 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 战斗中首次生命低于30% | 未逐项执行 |
| fortune_061 浴血奋战 | fortune_061.2 | 战斗期间伤害+8%，战后消失 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 战斗中首次生命低于30% | 未逐项执行 |
| battle_streak 战意高昂 | battle_streak.1 | 伤害+5%，持续7游戏日 | A | battle | BattleSystem / SpellEffectResolver | 已接通 · 连续赢得5场有效战斗 | 未逐项执行 |
| fortune_063 绝处逢生 | fortune_063.1 | 生命上限+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 从致命陷阱或秘境险境幸存 | 未逐项执行 |
| fortune_063 绝处逢生 | fortune_063.2 | 控制抵抗+3个百分点 | B | battle_status | BattleStatus | 待接入 · 从致命陷阱或秘境险境幸存 | 未逐项执行 |
| fortune_064 心魔初破 | fortune_064.1 | 神魂+5 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 战胜心魔幻境 | 未逐项执行 |
| fortune_064 心魔初破 | fortune_064.2 | 精神负面状态抗性+8个百分点 | B | battle_status | BattleStatus | 待接入 · 战胜心魔幻境 | 未逐项执行 |
| fortune_065 灵泉洗髓 | fortune_065.1 | 气血上限+8% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 完成灵泉洗髓奇遇 | 未逐项执行 |
| fortune_065 灵泉洗髓 | fortune_065.2 | 体修修为获取+3% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 完成灵泉洗髓奇遇 | 未逐项执行 |
| fortune_066 洞天福缘 | fortune_066.1 | 悟性+5 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 发现并探索隐藏洞府 | 未逐项执行 |
| fortune_066 洞天福缘 | fortune_066.2 | 灵力上限+5% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 发现并探索隐藏洞府 | 未逐项执行 |
| fortune_067 古修遗泽 | fortune_067.1 | 功法参悟耗时-10% | B | progression | 功法进阶待补接口 | 待接入 · 获得古修士传承 | 未逐项执行 |
| fortune_068 灵脉眷顾 | fortune_068.1 | 灵脉环境法修修为获取+10% | B | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 修复一处灵脉 | 未逐项执行 |
| fortune_069 青木生机 | fortune_069.1 | 木系治疗量+10% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 完成古木秘境机缘 | 未逐项执行 |
| fortune_069 青木生机 | fortune_069.2 | 采药额外收获概率+5% | A | gathering | OperationService.explore | 待接入 · 完成古木秘境机缘 | 未逐项执行 |
| fortune_070 星辉入体 | fortune_070.1 | 灵力上限+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 完成星象祭坛奇遇 | 未逐项执行 |
| fortune_070 星辉入体 | fortune_070.2 | 识海+5 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 完成星象祭坛奇遇 | 未逐项执行 |
| fortune_071 雷池淬体 | fortune_071.1 | 雷系伤害+8% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 在雷池淬炼中存活 | 未逐项执行 |
| fortune_071 雷池淬体 | fortune_071.2 | 受到雷系伤害-8% | B | battle | BattleSystem / SpellEffectResolver | 待接入 · 在雷池淬炼中存活 | 未逐项执行 |
| fortune_072 天降鸿运 | fortune_072.1 | 稀有奇遇奖励权重+15%，持续30游戏日 | D | encounter | 奇遇奖池待开放 | 待接入 · 特殊奇遇获得 | 未逐项执行 |
| alchemy_apprentice 丹道入门 | alchemy_apprentice.1 | 炼丹成功率+5个百分点 | B | alchemy | CaveSystem.craft / OperationService | 已接通 · 炼制30炉有效丹药 | 未逐项执行 |
| fortune_074 药性通明 | fortune_074.1 | 高一档丹药品质概率+3个百分点 | B | alchemy | CaveSystem.craft / OperationService | 待接入 · 炼出高品质丹药 | 未逐项执行 |
| alchemy_expert 丹火纯熟 | alchemy_expert.1 | 炼丹成功率+5个百分点 | B | alchemy | CaveSystem.craft / OperationService | 已接通 · 成功炼制100炉丹药 | 未逐项执行 |
| alchemy_expert 丹火纯熟 | alchemy_expert.2 | 炼丹耗时-5% | A | alchemy | CaveSystem.craft / OperationService | 已接通 · 成功炼制100炉丹药 | 未逐项执行 |
| fortune_076 百炼成器 | fortune_076.1 | 炼器成功率+5个百分点 | D | refining | 炼器待开放 | 待接入 · 炼制30件有效装备 | 未逐项执行 |
| fortune_077 天工灵感 | fortune_077.1 | 装备高一档品质概率+3个百分点 | D | refining | 炼器待开放 | 待接入 · 炼出当前境界极品装备 | 未逐项执行 |
| fortune_078 采药识途 | fortune_078.1 | 采药额外收获概率+8% | A | gathering | OperationService.explore | 已接通 · 采集100株有效灵药 | 未逐项执行 |
| herb_grower 灵植妙手 | herb_grower.1 | 灵植生长速度+10% | A | planting | CaveSystem.plant | 已接通 · 培育50株成熟灵植 | 未逐项执行 |
| trade_expert 商道亨通 | trade_expert.1 | 购买价格-5% | A | trade | ShopSystem.unit_price | 已接通 · 完成20次有效商贸交易 | 未逐项执行 |
| trade_expert 商道亨通 | trade_expert.2 | 出售价格+3% | A | trade | ShopSystem.unit_price | 已接通 · 完成20次有效商贸交易 | 未逐项执行 |
| fortune_081 宗门新秀 | fortune_081.1 | 宗门贡献获取+10% | A | sect | OperationService.donate | 待接入 · 晋升内门弟子 | 未逐项执行 |
| fortune_082 师门垂青 | fortune_082.1 | 师门功法参悟耗时-10% | D | sect | OperationService.donate | 待接入 · 师徒亲近并完成师门任务 | 未逐项执行 |
| fortune_083 宗门栋梁 | fortune_083.1 | 贡献获取+15% | A | sect | OperationService.donate | 待接入 · 完成宗门重大事件 | 未逐项执行 |
| fortune_083 宗门栋梁 | fortune_083.2 | 宗门商店购买价格-5% | D | sect | OperationService.donate | 待接入 · 完成宗门重大事件 | 未逐项执行 |
| fortune_084 广结善缘 | fortune_084.1 | 正面社交好感收益+10% | D | npc_social | 社会关系与事件待开放 | 待接入 · 与10位不同NPC达到友善 | 未逐项执行 |
| fortune_085 行善积德 | fortune_085.1 | 善良NPC初始好感+5 | D | npc_social | 社会关系与事件待开放 | 待接入 · 完成20次不同的行善事件 | 未逐项执行 |
| fortune_085 行善积德 | fortune_085.2 | 善缘奇遇权重+10% | D | encounter | 奇遇奖池待开放 | 待接入 · 完成20次不同的行善事件 | 未逐项执行 |
| fortune_086 恩怨分明 | fortune_086.1 | 恩人、仇人专属交互成功率+10个百分点 | D | npc_social | 社会关系与事件待开放 | 待接入 · 完成5次复仇或报恩事件 | 未逐项执行 |
| fortune_087 名动一方 | fortune_087.1 | 本区域普通任务报酬+5% | D | regional_reputation | 区域声望待开放 | 待接入 · 在区域达到高声望 | 未逐项执行 |
| fortune_088 贵人相助 | fortune_088.1 | 下次非战斗奇遇负面判定成功率+10个百分点，触发后消失 | D | encounter | 奇遇奖池待开放 | 待接入 · 关键剧情获得高境界NPC帮助 | 未逐项执行 |
| fortune_089 龙血洗礼 | fortune_089.1 | 生命上限+15% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 古龙血池传承 | 未逐项执行 |
| fortune_089 龙血洗礼 | fortune_089.2 | 每回合结束恢复最大生命2% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 古龙血池传承 | 未逐项执行 |
| fortune_090 凤火余烬 | fortune_090.1 | 火系法术伤害+12% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 凤凰残火传承 | 未逐项执行 |
| fortune_090 凤火余烬 | fortune_090.2 | 每场战斗首次受到灼烧时免疫此次灼烧 | C | battle | BattleSystem / SpellEffectResolver | 待接入 · 凤凰残火传承 | 未逐项执行 |
| fortune_091 太古剑意 | fortune_091.1 | 剑类法术伤害+12% | B | spell_class | 法术分类待补接口 | 待接入 · 古剑仙传承 | 未逐项执行 |
| fortune_091 太古剑意 | fortune_091.2 | 剑类法术暴击率+5个百分点 | B | spell_class | 法术分类待补接口 | 待接入 · 古剑仙传承 | 未逐项执行 |
| fortune_092 万毒不侵 | fortune_092.1 | 中毒抗性+30个百分点 | B | battle_status | BattleStatus | 待接入 · 毒谷洗髓试炼 | 未逐项执行 |
| fortune_092 万毒不侵 | fortune_092.2 | 持续毒伤-20% | A | battle_status | BattleStatus | 待接入 · 毒谷洗髓试炼 | 未逐项执行 |
| fortune_093 九霄雷印 | fortune_093.1 | 雷系法术伤害+15% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 九霄雷殿传承 | 未逐项执行 |
| fortune_093 九霄雷印 | fortune_093.2 | 每场战斗首次雷系攻击追加攻击力20%的雷伤 | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 九霄雷殿传承 | 未逐项执行 |
| fortune_094 玄龟护命 | fortune_094.1 | 防御+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 玄龟血脉祝福 | 未逐项执行 |
| fortune_094 玄龟护命 | fortune_094.2 | 每场战斗首次生命低于30%获得最大生命15%的护盾，持续2回合 | C | battle | BattleSystem / SpellEffectResolver | 待接入 · 玄龟血脉祝福 | 未逐项执行 |
| fortune_095 造化灵息 | fortune_095.1 | 法修、体修修为获取+8% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 造化秘境灌注 | 未逐项执行 |
| fortune_095 造化灵息 | fortune_095.2 | 寿元上限+5年 | B | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 造化秘境灌注 | 未逐项执行 |
| fortune_096 天道垂青 | fortune_096.1 | 悟性+10 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 天道级奇遇 | 未逐项执行 |
| fortune_096 天道垂青 | fortune_096.2 | 稀有奇遇奖励权重+10% | D | encounter | 奇遇奖池待开放 | 待接入 · 天道级奇遇 | 未逐项执行 |
| fortune_096 天道垂青 | fortune_096.3 | 大境界突破成功率+3个百分点（仅筑基概率判定生效；后续确定成功的大境界不受影响） | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 天道级奇遇 | 未逐项执行 |
| fortune_097 经脉暗伤 | fortune_097.1 | 灵力上限-10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_097 经脉暗伤 | fortune_097.2 | 法术消耗+5% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_098 气血亏空 | fortune_098.1 | 生命上限-10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_098 气血亏空 | fortune_098.2 | 体修修为获取-10% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_099 神魂不稳 | fortune_099.1 | 神魂-8 | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_099 神魂不稳 | fortune_099.2 | 神识威慑成功率-10个百分点 | A | npc_auction | Mental.chance / AuctionSystem | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_100 丹毒积累 | fortune_100.1 | 丹药恢复效果-15% | A | inventory | InventorySystem.use | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_100 丹毒积累 | fortune_100.2 | 法修修为获取-5% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_101 心魔缠身 | fortune_101.1 | 大境界突破成功率-10个百分点（仅筑基概率判定生效；后续确定成功的大境界不受影响） | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_102 天煞孤星 | fortune_102.1 | 攻击+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_102 天煞孤星 | fortune_102.2 | 普通NPC初始好感-10 | D | npc_social | 社会关系与事件待开放 | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_102 天煞孤星 | fortune_102.3 | 友善事件权重-15% | D | encounter | 奇遇奖池待开放 | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_103 血煞缠身 | fortune_103.1 | 攻击+8% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_103 血煞缠身 | fortune_103.2 | 每场战斗开始损失5%最大生命 | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_104 逆脉修行 | fortune_104.1 | 法术伤害+12% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_104 逆脉修行 | fortune_104.2 | 法术灵力消耗+15% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_105 寿元亏损 | fortune_105.1 | 寿元上限-10年 | B | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_105 寿元亏损 | fortune_105.2 | 法修修为获取+10% | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_106 灵气驳杂 | fortune_106.1 | 灵力上限+10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_106 灵气驳杂 | fortune_106.2 | 突破成功率-8个百分点（仅筑基概率判定生效；后续确定成功的大境界不受影响） | A | cultivation | SpiritCultivation / CultivationSystem.promote | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_107 阴火侵体 | fortune_107.1 | 火系伤害+10% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_107 阴火侵体 | fortune_107.2 | 每回合首次火系法术损失最大生命2% | A | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_108 天劫余伤 | fortune_108.1 | 防御-10% | A | character | CharacterSystem.stats / 人物资质 / Mental.effective | 待接入 · 负面事件待正式接入 | 未逐项执行 |
| fortune_108 天劫余伤 | fortune_108.2 | 受到雷系伤害+15% | B | battle | BattleSystem / SpellEffectResolver | 待接入 · 负面事件待正式接入 | 未逐项执行 |
