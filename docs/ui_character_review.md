# 角色页面 V4.0 布局重构验收（2026-11-05）

## 范围与结论
按用户两张图及附带V4.0规范实施：角色信息25/40/35，装备25/50/25；共用标题、返回和角色信息/装备/法宝三个标签。法宝只做三栏矩形占位。没有修改正式JSON、属性公式、装备事务、背包、任务、地图、战斗或存档字段。

布局及已存在功能自动验收PASS；完整V4.0数据展示为PARTIAL：项目没有六维资质与天赋定义，不伪造示例值；图中六个未实现装备部位禁用。独立法宝功能按要求不开发。用户视觉审核待完成。

## 文件与组件
- ui/character/character_page.tscn：可编辑原生容器模板，信息页、装备页和法宝占位共存。选择对应HBoxContainer的visible可在编辑器预览。
- ui/character/character_page.gd：只读显示与交互绑定。PARTS统一定义八个UI部位名称；武器weapon与衣服armor沿用真实定义，其他无定义部位禁用。
- ui/character/attribute_radar.gd：@tool自定义Control六轴/刻度/名称；没有六维数据时只画坐标框与缺失提示。set_values可绘制实际传入值，采用该组最大值归一化，仅用于显示，不生成属性或持久化字段。
- ui/character/equipment_slot.tscn、inventory_item_slot.tscn：矩形槽位与图标占位装备格组件。
- ui/main/main.gd：角色入口加载模板，沿用原操作与刷新流程，保留当前标签/分类/选择。
- core/operation_service.gd：equipment_availability在隔离副本调用原equip/unequip验证；character_stat_tooltip读取真实基础、装备及功法来源并显示现有stats最终值。未改原有业务执行分支。
- tests/character_ui_preview.gd：37项隔离检查及真实渲染截图。
- docs/development_plan.md、decisions.md：追加授权和进度记录。

复用：原GameManager、OperationService、CharacterSystem、装备实例、物品定义、属性计算及Godot原生Tooltip（自动隐藏及边界处理）。未重复创建业务系统；Tooltip不用额外场景。

## 数据边界
六维六个名称按新UI规范排布，但值显示“—”，Tooltip明确尚未定义；不会使用示例13/10等正式化。天赋无数据，显示暂无天赋及九格空占位，无假天赋。状态区只读当前已定义的玩家土甲防御状态；战斗数据的灼烧和潮湿针对敌人，不误标给玩家。角色暂无独立持续状态系统。灵根读取角色root；现有战斗规则同属性伤害加成显示为已有规则，不新增品质或修炼增益。

出生内容旧称青木剑为“法宝”，但目前数据equipment定义weapon、物品类型装备，且已有通用equip接口。本次按现有代码在普通装备页展示，保留加成；未将其迁移到独立法宝系统。

game_design.md/content_v0_1.md/combat_balance.md缺失，继续阅读项目中文原文、data_schema和批准记录。当前无Git仓库，未执行提交。

## 测试
正常权限启动Godot 4.5 Mono，无程序集弹窗，无GDScript解析/运行错误。
- tests/run_all.ps1：编辑器导入、无头启动，以及19+63+171+27=280项既有业务检查通过。
- tests/character_ui_preview.gd：37项通过，0失败。
- 合计317项。验证装备槽到分类、分类到槽位状态，清除隐藏物品操作，全部保留当前可见选择，真实装备/卸下及属性刷新、境界不足禁用、法宝切换不改状态、读档兼容、返回、三标签内容范围、小窗口操作按钮、九格完整可见和天赋/状态独立滚动、超宽分类横向滚动及雷达绘图输入。
- 分类横向滚动初测失败原因：1280物理窗口沿用1920逻辑分辨率，正常分类宽度未溢出，不应出现滚动条。改为明确超宽的UI测试夹具复测通过；没有降低断言或改变正式分类数据。
- 所有夹具仅测试内存或既有测试专用存档目录，不写正式玩家存档。

运行：tests/run_all.ps1 -Godot <引擎路径>；Godot --path . --script tests/character_ui_preview.gd --resolution 1920x1080。

## 截图
已查看实际输出（非设计稿）：
- screenshots/character_info_1920x1080.png
- screenshots/character_equipment_1920x1080.png
- screenshots/character_artifact_1920x1080.png
- screenshots/character_info_1280x720.png
- screenshots/character_equipment_1280x720.png

装备图使用隔离夹具增加现有素布道袍和精铁剑实例以验证已装备/未装备及条件，不改变新游戏配置；不会增加图中不存在的正式鞋子、戒指等内容。

下一步：用户审核布局。六维与天赋的真实内容接入需先有批准的数据定义，不在本轮新增玩法。
`n2026-11-05颜色调整：按用户要求将character_page.tscn生命ProgressBar填充设为红色，灵力填充设为蓝色；37项页面检查重新通过，并查看更新截图。
