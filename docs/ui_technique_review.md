# 功法与主动法术 UI 重构验收（2026-11-05）

状态：PASS（自动验收）。正常权限下补跑编辑器导入、无头启动、280项业务检查和20项页面检查全部通过，无程序集错误。页面视觉仍待用户审核。

## 完成内容和边界

仅重构功法入口，三栏比例25/40/35，32px外边距、16px面板间隔；功法/主动法术独立切换，列表滚动，选择不执行操作，装备与升级集中于右侧底部。功法采用2列5行共10格，现有initial_slots开放3格，其余锁定；法术槽读取同一现有规则，不定义最终上限。空列表、安全禁用及失败原因已接入。

运行实例化ui/technique/technique_page.tscn。该场景可在编辑器直接调整，槽位及列表项分别为technique_slot.tscn、technique_list_item.tscn。静态预览文字不进入游戏状态。新增skill_presentation只读服务用隔离副本执行原slot/upgrade验证；效果根据现有属性和战斗公式展示。原执行流程、属性计算、正式JSON、存档版本均未改动。

主要文件：
- ui/main/main.gd：替换旧功法纵向列表入口。
- ui/technique/technique_page.gd、technique_page.tscn、technique_slot.tscn、technique_list_item.tscn。
- core/operation_service.gd：只读详情与操作可用性查询。
- tests/technique_ui_preview.gd：隔离角色及夹具，不覆盖玩家存档。
- 本文档、development_plan.md、decisions.md和三张screenshots/technique或spell截图。

## 测试结果

Godot 4.5 Mono图形模式执行：
- run_tests.gd：19通过，0失败。
- game_tests.gd：63通过，0失败。
- regression_tests.gd：171通过，0失败。
- boundary_tests.gd：27通过，0失败。
- technique_ui_preview.gd：20通过，0失败。
合计300项通过。包括真实装备卸下及属性刷新、两类升级、条件不足、槽满、空列表、滚动、动态法术槽数、存读、返回及1280×720操作按钮可见。既有业务回归涵盖完整战斗和存档恢复。

实际渲染并查看1920×1080功法和法术截图以及1280×720截图，未发现文字溢出或按钮重叠。测试截图使用明确隔离的升级角色，不代表修改出生配置。
截图：screenshots/technique_1920x1080.png、spell_1920x1080.png、technique_1280x720.png。

环境异常：现有Mono引擎每次启动报告“.NET: Assemblies not found”；图形模式仍执行全部上述GDScript检查且退出码0，无GDScript解析/运行错误。无头/编辑器启动出现signal 11崩溃，run_all.ps1未完成，不计为通过。首次默认用户目录无写权限，后续APPDATA使用工程内.test_userdata隔离目录。未修改项目引擎版本或项目设置。

本地复核：用完整安装的Godot 4.x打开项目，进入主界面→功法，切换两类；点击条目、槽位和装备/升级/返回；打开technique_page.tscn检查可编辑预览。再用tests/run_all.ps1 -Godot <完整引擎路径>及Godot --path . --script tests/technique_ui_preview.gd复测。

## 问题与下一步

game_design.md、content_v0_1.md、combat_balance.md不存在；已采用项目中文设计与内容原文、data_schema及批准记录，不擅自补写规则。目录无Git仓库，未提交。建议先审核页面视觉，再解决Mono环境并重跑无头与编辑器检查；不进入其他页面重构。


## 同日纠正：程序集弹窗来自测试启动权限

此前将程序集错误归因于引擎环境缺失不准确。报错路径下GodotSharp.dll等程序集完整存在，日期未改变。同一引擎、同一项目改用正常权限启动后，无头启动正常；tests/run_all.ps1完整结束并输出ALL CHECKS PASSED（280检查），technique_ui_preview.gd再次20检查通过，均无程序集错误。确认受限测试启动方式触发了此前弹窗及崩溃，不需要重装引擎或修改项目配置。先前环境异常段落仅保留为历史过程，已不构成当前阻断。
