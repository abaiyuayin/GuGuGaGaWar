class_name RoguelikeMapNode
extends RefCounted

## 地图节点数据（分支 DAG 的一个顶点）
## 类型枚举见 RoguelikeManager.NodeType。

## 所在层（从 0 起，0 = 最底层，MAP_FLOORS-1 = Boss 层）
var floor_index: int = 0
## 同层内的槽位序号（仅用于生成时排序）
var slot_index: int = 0
## 横向位置比例（0~1），地图 UI 用来在层内左右摆放
var x_ratio: float = 0.5
## 节点类型，取值 RoguelikeManager.NodeType
var node_type: int = 0
## 连通的下一层节点下标（在 RoguelikeManager.map_nodes 中的索引）
var next: Array[int] = []
## 是否已被玩家走过
var visited: bool = false
## 战斗类节点的敌军阶层上限（非战斗节点为默认值，不使用）
var enemy_tier: int = 1
## 战斗类节点的波数（非战斗节点为默认值，不使用）
var wave_count: int = 3
## 是否为 Boss 节点（影响导演刷怪强度）
var is_boss: bool = false
