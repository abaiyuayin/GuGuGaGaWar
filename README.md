# 咕嘎嘎战争

<p align="left">
  <strong>语言：</strong> 中文 ｜ <a href="README_EN.md">English</a>
</p>

**咕嘎嘎战争** 是一款基于 Godot 4 引擎开发的 Q 版即时战略对战游戏。你指挥一群画风可爱、却战力不俗的咕嘎doro菲比糯糯小兵们，在城堡攻防的战场上排兵布阵，与 AI 或好友一决高下。游戏融合了战役推图、自由对战、双人乱斗等多种玩法，并配有图鉴、成就、隐藏事件等丰富系统。

---

如果你觉得这个游戏好玩，或是项目对你有帮助，欢迎请我喝杯奶茶！

<p align="center">
  <img src="assets/ui/donate_wechat.jpg" width="180" alt="微信赞赏二维码"/>
  <img src="assets/ui/donate_alipay.jpg" width="180" alt="支付宝赞赏二维码"/>
</p>

---

## 目录

- [游戏特色](#游戏特色)
- [游戏模式](#游戏模式)
- [兵种体系](#兵种体系)
- [操作指南](#操作指南)
- [本地运行](#本地运行)
- [导出与打包](#导出与打包)
- [项目结构](#项目结构)
- [开源协议与致谢](#开源协议与致谢)
- [联系作者 / 社区](#联系作者--社区)

## 游戏特色

- **Q 版中世纪手绘美术**：木板、羊皮纸、砖石城堡的童话冒险质感，粗黑轮廓 + 暖灰配色，可爱又硬核。
- **多模式玩法**：单人对战役、自由全面战争、本地双人对战一网打尽。
- **24 种兵种 + 英雄单位**：四大阵营（咕嘎 / Doro / 菲比 / 糯糯）各有特色，通过关卡、战功、星星、隐藏成就逐步解锁。
- **丰富战术系统**：流血 / 中毒 / 晕眩 / 减速 / 击退 / 冰冻 / 侵蚀等词条、护盾与魔法伤害、游戏中特殊事件。
- **成就与图鉴**：内置成就系统（含隐藏成就）与只读百科图鉴，记录你的征战历程。
- **多语言支持**：内置简体中文、English、English(UK)、한국어、日本語、ไทย、Français、Italiano 等本地化。
- **多端支持**：支持 Windows 桌面端与 Android 双端游戏，安卓端提供触屏布兵体验。

## 游戏模式

| 模式 | 说明 |
|------|------|
| **战役模式** | 推进 10 个关卡、攻克三大阵营，难度分普通 / 困难 / 地狱；通关获得战功，解锁更多兵种。 |
| **全面战争（单人）** | 自由选择简单 / 普通 / 困难难度，与 AI 实时对战，AI 会按克制关系与战场态势动态调兵。 |
| **双人模式** | 本地同屏双人对战，关闭战役与 AI，纯玩家博弈。 |


## 兵种体系

游戏共有 **24 个常驻兵种** 与 **2 个英雄单位**，外加仅在开发工具 / 异象事件中登场的特殊兵种。解锁途径如下：

- **常驻 5**：G1 / G2 / G3 / D1 / D3（开局即拥有）
- **关卡解锁 10**：L1→G4 … L10→N4（随战役推进解锁）
- **战功解锁 7**：D2 / G5 / D5 / F4 / N5 / G6 / D6（消耗战役首通累计的 1150 点战功）
- **星星解锁 2**：Hero1 爱弥斯 / Hero2 Doro 勇士（各需 20 星）
- **神秘单位**：仓*，蓝*，死*，凑*，我*，香*，爱*等多个需要特殊条件解锁的强大单位或是敌人。



## 操作指南

- **布兵 / 索敌**：选择兵种后自动召单位，单位按攻击距离自动索敌与攻击；远程单位存在进 / 退射程滞回带以避免抖动。
- **调试控制台**：开发者模式下，可实时调整所有兵种精灵在局内的显示宽高。

## 本地运行

环境要求：

- **Godot 4.7.x**（项目基于 Godot 4.7.1 开发）
- 桌面端：Windows / Linux / macOS 均可运行编辑器

步骤：

1. 克隆本仓库：`git clone <本仓库地址>`
2. 用 Godot 4.7 打开项目根目录（含 `project.godot` 的文件夹）。
3. 在编辑器内按 <kbd>F5</kbd> 直接运行，或导入后点击「运行项目」。

## 导出与打包

项目已内置两个导出预设（见 `export_presets.cfg`）：

- **Windows Desktop**：导出为 `GuGuGaGa War.exe`，应用图标与控制台图标已配置。
- **Android**：导出为 `Android/GuGuGaGaWar.apk`，启动图标 / 自适应图标 / 启动屏图标已配置（包名 `com.gugugaga.war`）。

导出前请在 Godot 编辑器「项目 → 导出」中指定对应平台模板，Android 还需配置签名 keystore。

## 项目结构

```
GuGuGaGaWar/
├── addons/            # 插件（gdUnit4 测试框架、Godot MCP 等）
├── assets/            # 美术、音频、字体、本地化资源
├── autoload/          # 全局单例管理器（GameManager / 经济 / 战役 / 成就 …）
├── data/              # 兵种配置等数据 JSON
├── resources/         # Godot 资源文件（图集 / 材质 / 动画资源 …）
├── scenes/            # 场景（ui / battle / units / main …）
├── scripts/           # 运行时 GDScript 模块（AI / 战斗 / 对象池 / 肉鸽 / 工具类）
├── project.godot      # 引擎配置
├── export_presets.cfg # 导出预设
├── default_bus_layout.tres # 默认音频总线
├── LICENSE            # MIT 协议
├── README.md          # 中文说明
└── README_EN.md       # English README
```

## 开源协议与致谢

本项目以 **MIT 协议** 开源，详见 [LICENSE](LICENSE)。

- 游戏原作与美术设计：[@阿白与阿银](https://space.bilibili.com/382838394)
- 特别感谢 Godot 引擎社区与所有为本项目提供建议与素材的朋友们。

## 联系作者 / 社区

<p>
  <strong>B 站：</strong>
  <a href="https://space.bilibili.com/382838394">@阿白与阿银</a>
  <img src="assets/ui/bilibili_icon.png" width="40" alt="B站图标" style="vertical-align:middle"/>
</p>

<p>
  <strong>官方 QQ 群：</strong>
  939936934（<a href="https://qm.qq.com/q/H0BklLFTEK">点击加入</a>）
  <img src="assets/ui/qq_group.jpg" width="40" alt="QQ群图标" style="vertical-align:middle"/>
</p>

如果你在游玩或二次开发中遇到问题，欢迎加入社区一起交流！
