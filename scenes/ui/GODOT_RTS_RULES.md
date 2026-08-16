# Godot 4 RTS 项目专用开发规范 (AI 协作版)

> **目标受众：AI 开发助手**
> 本文件是 RTS（即时战略）类型项目的**扩展规范**，必须与 `GODOT_GENERAL_RULES.md` 通用规范一并使用。
> 所有 RTS 相关代码生成、文件创建、场景搭建必须同时遵守通用规范和本扩展规范。

---

## 一、RTS 扩展目录结构

在通用目录结构基础上，RTS 项目需要在 `src/` 下增加以下专属目录：

```
res://
├── src/
│   ├── scenes/
│   │   ├── actors/
│   │   │   ├── units/              # RTS 单位（步兵、骑兵、建筑）
│   │   │   ├── buildings/          # 建筑（兵营、矿场、基地）
│   │   │   └── projectiles/        # 弹道、箭矢、法术
│   │   ├── ui/
│   │   │   ├── command/            # RTS 指挥面板、编队栏
│   │   │   ├── minimap/            # 小地图场景
│   │   │   └── selection/          # 选择框、多选高亮
│   │   └── levels/
│   │       └── maps/               # 战役地图、遭遇战地图
│   ├── scripts/
│   │   ├── components/
│   │   │   ├── command/            # 指挥相关组件
│   │   │   │   ├── selectable_component.gd
│   │   │   │   ├── movable_component.gd
│   │   │   │   └── attack_component.gd
│   │   │   └── economy/            # 经济相关组件
│   │   │       ├── harvester_component.gd
│   │   │       └── producer_component.gd
│   │   ├── managers/
│   │   │   ├── rts_controller.gd   # RTS 主控管理器（选择/移动/攻击）
│   │   │   ├── battle_manager.gd   # 战斗管理器
│   │   │   ├── economy_manager.gd  # 经济系统（资源、生产队列）
│   │   │   └── formation_manager.gd# 阵型管理器
│   │   └── states/
│   │       └── unit_states/        # 单位状态机（闲置、移动、攻击、采集）
│   │           ├── idle_state.gd
│   │           ├── move_state.gd
│   │           ├── attack_state.gd
│   │           └── harvest_state.gd
│   ├── resources/
│   │   ├── units/                  # 单位/兵种属性模板
│   │   ├── buildings/              # 建筑属性模板
│   │   ├── factions/               # 阵营定义（科技树、可用单位）
│   │   ├── formations/             # 阵型数据（方阵、楔形阵）
│   │   └── tech_trees/             # 科技树定义
│   └── tilesets/
│       └── terrain/                # 地形瓦片集（草地、水域、道路）
└── project.godot
```

---

## 二、RTS 核心系统规范

### 1. 单位系统 (Unit System)
- 每个可操控单位必须包含以下基础组件：
  - `SelectableComponent` — 支持框选和点击选择
  - `MovableComponent` — 支持寻路移动
  - `HealthComponent` — 生命值管理
- 单位根节点使用 `CharacterBody2D`（2D）或 `CharacterBody3D`（3D）。
- 单位资源 (`UnitResource`) 必须包含：`cost`、`build_time`、`hp`、`speed`、`attack`、`armor`、`sight_range`。
- **禁止**在单位脚本中直接处理输入事件，所有输入由 `RTSController` 统一接收后分发。

### 2. 指挥系统 (Command System)
- 所有玩家输入（点击、框选、快捷键）由 `RTSController` (Autoload) 统一处理。
- `RTSController` 负责维护当前选中的单位列表 (`selected_units`)。
- 对选中单位下达命令时，通过调用各单位组件的公共方法实现，**禁止**直接修改单位内部状态。
- 命令类型枚举：
  ```gdscript
  enum CommandType {
      MOVE,
      ATTACK,
      ATTACK_MOVE,
      STOP,
      HOLD_POSITION,
      PATROL,
      HARVEST,
      BUILD
  }
  ```

### 3. 经济系统 (Economy System)
- 资源类型使用 `Resource` 定义，至少包含：`gold`、`wood`、`food`、`supply`。
- 资源数值由 `EconomyManager` (Autoload) 统一管理。
- 建筑生产单位时，消耗资源并将单位加入生产队列。
- 采集单位 (`HarvesterComponent`) 将资源交回指定建筑后，通过信号通知 `EconomyManager` 增加资源。

### 4. 编队系统 (Formation System)
- 编队数据存储在 `src/resources/formations/` 下的 `.tres` 文件中。
- `FormationManager` 负责将选中的单位按编队模板排列。
- 编队模板包含：阵型名称、阵型图标、单位间距、阵型形状（网格坐标数组）。
- 移动时，编队保持相对位置；遇敌时，编队自动解散进入战斗状态。

### 5. 阵营与科技树 (Faction & Tech Tree)
- 阵营定义 (`FactionResource`) 包含：阵营名称、可用单位列表、可用建筑列表、起始资源。
- 科技树 (`TechTreeResource`) 使用有向图结构定义解锁关系。
- 建筑或单位的可用性由 `FactionManager` 根据当前已解锁科技动态判断。

---

## 三、RTS UI 规范

在通用 UI 规范基础上，RTS 项目需遵循以下额外规则：

### 层级设计
```
RTSUI (CanvasLayer, layer 1)
├── Minimap (Control)              # 小地图
├── CommandPanel (Control)         # 底部指挥面板
│   ├── UnitPortrait               # 选中单位头像
│   ├── CommandButtons             # 移动/攻击/停止等按钮
│   └── ProductionQueue            # 生产队列显示
├── SelectionBox (Control)         # 框选矩形（仅在拖拽时显示）
├── ResourceBar (Control)          # 顶部资源条
│   ├── GoldLabel
│   ├── WoodLabel
│   ├── FoodLabel
│   └── SupplyLabel
└── HUD (Control)                  # 其他 HUD 元素
```

### 小地图 (Minimap)
- 小地图使用单独的 `SubViewport` 渲染简化版世界视图。
- 小地图点击/拖拽时，将相机移动到对应世界坐标。
- 小地图上的单位用对应阵营颜色的圆点表示。

### 选择框 (Selection Box)
- 框选时使用 `SelectionBox` 控件绘制矩形边框。
- 矩形范围内的可选取单位被加入选中列表。
- **禁止**使用物理碰撞检测实现框选，应使用屏幕坐标 AABB 检测。

---

## 四、RTS 全局管理器（Autoload）

RTS 项目需要在通用管理器基础上，增加以下专用 Autoload：

| 管理器 | 职责 | 类名示例 |
|--------|------|----------|
| `RTSController` | 输入处理、单位选择、命令分发 | `RTSController.gd` |
| `BattleManager` | 战斗逻辑、伤害计算、死亡处理 | `BattleManager.gd` |
| `EconomyManager` | 资源管理、生产队列、消耗结算 | `EconomyManager.gd` |
| `FormationManager` | 编队生成、阵型维护、移动协调 | `FormationManager.gd` |
| `FactionManager` | 阵营配置、科技解锁、单位可用性 | `FactionManager.gd` |
| `AIManager` | AI 行为树、敌方决策（如需要） | `AIManager.gd` |

- 管理器之间通过信号通信，禁止直接互相调用方法。
- `RTSController` 是唯一直接接收输入事件的管理器。

---

## 五、RTS 组件通信规范

在通用组件通信规范基础上，RTS 项目需增加以下信号约定：

### 单位组件信号
```gdscript
# SelectableComponent
signal selected
signal deselected

# MovableComponent
signal movement_started(target_position: Vector2)
signal movement_completed
signal movement_blocked

# AttackComponent
signal attack_started(target: Node)
signal attack_landed(target: Node, damage: int)
signal target_destroyed(target: Node)

# HarvesterComponent
signal resource_harvested(amount: int, resource_type: String)
signal resource_delivered(amount: int, resource_type: String)
```

### 管理器信号
```gdscript
# EconomyManager
signal resources_changed(gold: int, wood: int, food: int, supply: int)
signal production_started(unit_id: String, queue_position: int)
signal production_completed(unit_id: String)

# RTSController
signal selection_changed(selected_units: Array[Node])
signal command_issued(command_type: int, target)
```

---

## 六、RTS AI 代码生成检查清单

在生成 RTS 相关代码之前，AI 必须在通用检查清单基础上，额外自检以下内容：

1. [ ] 单位是否包含 `SelectableComponent` 和 `MovableComponent`？
2. [ ] 输入事件是否由 `RTSController` 统一处理，而非各单位自行监听？
3. [ ] 资源消耗是否通过 `EconomyManager` 结算？
4. [ ] 编队数据是否使用 `FormationResource` 定义？
5. [ ] 阵营和科技树是否使用 `FactionResource` / `TechTreeResource` 定义？
6. [ ] UI 层级是否正确区分了小地图、指挥面板、资源条？
7. [ ] 框选逻辑是否使用屏幕坐标检测，而非物理碰撞？
8. [ ] 管理器之间是否通过信号通信，而非直接方法调用？

---

**本规范作为通用规范的扩展，与 `GODOT_GENERAL_RULES.md` 一并生效。所有 RTS 项目代码和资源产出必须同时遵守两份规范。**
