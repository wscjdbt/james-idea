# Buff System Spec（2D 回合制追逐游戏）Spec

> Status: ALIGNED
> Author: user (via dev-grill-docs)
> Last updated: 2026-10-12

## Background

2D 像素回合制追逐游戏。核心循环：严格交替回合（1 回合 = Chaser 行动 + Runner 行动），Chaser 每回合 2 MP、Runner 每回合 3 MP；移动 1 格或使用 1 次技能各消耗 1 MP。Runner 坚持 20 个完整回合（双方各动 20 次）未被抓住则胜；任一时刻 Chaser 与 Runner 同格则 Chaser 胜。本 spec 定义 v1 buff 系统：5 个 buff + 简化叠加机制 + 互斥分组。

## In scope

- **属性修饰 buff**：
  - 加速（+1 MP，duration=3）
  - 减速（-1 MP，duration=3）
- **行为禁制 buff**：
  - 眩晕（立即生效：施加当回合内目标剩余 MP 作废，不能移动也不能用技能；duration=2）
  - 禁锢（不能移动，可用技能；duration=2）
  - 沉默（不能用技能，可移动；duration=2）
- **叠加机制（v1 简化子集）**：
  - v1 所有 buff 均使用 `StackingMode.REFRESH`（同名重复施加 → 时长刷新为满值，数值不叠加）
  - `StackingMode.NONE`（同名已存在则拒绝）留待 v2，v1 无服务对象
  - `StackGroup` 互斥分组：同组 buff 不能共存，冲突时后者替换前者（KeepNew）
    - 加速/减速 同属互斥组 `SPEED`
    - 眩晕、禁锢、沉默 各自为唯一组（`STUN` / `ROOT` / `SILENCE`）
- **衰减时机**：回合末双方所有 buff 的 remaining_turns 同时 -1，归零移除（Q3a=C）
- **抓捕判定**：任一时刻（任一方移动或技能位移后）Chaser 与 Runner 同格 → Chaser 立即胜（Q3b=A）

## Out of scope（v2+，接口预留不做实现）

- `Stack` / `RefreshAndStack` 数值层叠模式（配合中毒/护盾引入）
- `StackingMode.NONE`（v1 无服务对象，留待 v2 唯一性 buff）
- 虚弱/强壮、反伤盾、中毒、燃烧、护盾
- 地形 buff 传递（依赖燃烧）
- 驱散/清除机制
- 显示聚合 vs 底层独立（依赖层叠）
- HP / 伤害系统

## Assumptions

- v1 无 HP、无伤害：输赢只由抓捕与存活决定，buff 的战术价值是控制距离
- MP = 0 时不能移动也不能用技能（技能消耗"1 格移动机会"，无机会则不可用）
- buff 施加当回合即开始计时：施加时 remaining=N，本回合末即 -1（眩晕的"立即生效"针对的是当回合内剩余行动，衰减规则不变）
- MP 不会为负：加速/减速互斥后最坏情况 -1，Runner 最低 2 MP、Chaser 最低 1 MP
- 技能表（谁有什么技能、各施加什么 buff）不在本 spec 内，dev-plan 前需定义；v1 每方至少 1 个施加 buff 的技能

## Solution（sketch）

```text
BuffDef (静态 Resource)
  id: String
  stack_group_id: String        # 互斥组
  stacking_mode: REFRESH | NONE
  duration_turns: int
  effect: MP_DELTA(+1/-1) | RESTRICT(STUN/ROOT/SILENCE)

BuffInstance (运行时)
  def_id, remaining_turns

Unit
  buffs: Map<stack_group_id, BuffInstance>   # 同组互斥由数据结构天然保证
  effective_mp = base_mp + sum(MP_DELTA)     # 属性聚合 = 求和
  can_move    = not (STUN or ROOT)
  can_skill   = not (STUN or SILENCE)

回合流程：行动(移动|技能)* → 抓捕判定 → 回合末全体 buff remaining-1 → 移除归零者
```

## Edge cases & risks

| Category | Notes |
|---|---|
| Boundary conditions | 眩晕+禁锢+沉默可同时存在（不同组）：单位完全无法行动，但 buff 照常在回合末衰减 |
| Boundary conditions | 禁锢（ROOT）回合内 MP 无法消耗 → 该回合行动被跳过 |
| Failure modes | 减速替换加速（KeepNew）时，MP 变化必须立即重算，避免残留旧值 |
| Failure modes | 第 20 回合结束的判定：第 20 回合抓捕判定通过后仍同格 → Chaser 胜；否则 Runner 胜 |
| Risks | Chaser 2MP vs Runner 3MP 的速度差 + 减速技能可能导致 Runner 永远追不上/被追上，平衡需在 dev-plan 用数值模拟验证 |
| Mitigation | buff 时长与技能 MP 消耗做成 BuffDef/技能表数据，便于调参不改代码 |

## Acceptance criteria

- AC-1：对 Runner 施加减速后，其当回合可用 MP = 2（3 + (-1)）
- AC-2：Runner 已有加速（MP=4）时再施加减速 → 加速被替换移除（同组 KeepNew），减速效果生效，MP = 2（3 + (-1)）
- AC-3：对已有减速的单位再次施加减速 → remaining_turns 刷新为满值 3，MP 仍为 -1 修正（不叠加）
- AC-4：眩晕在施加当回合内立即生效——目标剩余 MP 作废，本回合不能再移动也不能用技能；该回合结束时眩晕 remaining-1（2→1）
- AC-5：禁锢单位可使用技能但不能移动；沉默单位可移动但不能使用技能
- AC-6：任意 buff remaining_turns 减至 0 → 立即移除，MP/禁制状态立即恢复
- AC-7：Chaser 与 Runner 在任一行动结算后同格 → 游戏立即结束，Chaser 胜
- AC-8：第 20 个完整回合（双方各完成 20 次行动）结束且未同格 → 游戏结束，Runner 胜

## 测试用最小技能集（供 dev-tdd 验证 AC）

为使 AC-1~AC-8 可执行，v1 至少需要以下"测试技能"（不代表正式技能表，仅用于跑通用例）：

| 技能 ID | 施放者 | 目标 | 效果 | 射程 | MP 消耗 |
|---|---|---|---|---|---|
| `T_SLOW` | Chaser | Runner | 施加减速（duration=3） | 2 格（曼哈顿距离） | 1 |
| `T_HASTE` | Runner | Self | 施加加速（duration=3） | 自身 | 1 |
| `T_STUN` | Chaser | Runner | 施加眩晕（duration=2） | 1 格（邻接） | 1 |
| `T_ROOT` | Chaser | Runner | 施加禁锢（duration=2） | 2 格 | 1 |
| `T_SILENCE` | Chaser | Runner | 施加沉默（duration=2） | 2 格 | 1 |

正式技能表（含更多技能、平衡数值）在 dev-plan 阶段定义。

## Open questions

- 正式技能表：双方完整技能列表、各施加什么 buff、射程与 MP 消耗、冷却（若有）——dev-plan 阶段定义

## Core entities (ontology)

| Entity | Type | Key fields | Relationship |
|---|---|---|---|
| Unit | 实体 | type(Chaser/Runner), base_mp, position, buffs | 持有多个 BuffInstance（按组唯一） |
| BuffDef | 静态定义 | id, stack_group_id, stacking_mode, duration_turns, effect | 被 BuffInstance 引用 |
| BuffInstance | 运行时状态 | def_id, remaining_turns | 属于一个 Unit |
| Turn | 概念 | turn_index(1..20), 行动→判定→衰减 三阶段 | 约束 Unit 行动与 buff 衰减 |

## Interview metadata

- Mode: default
- Waves: 3
- Final ambiguity: 16.6%
- Status: PASSED

### Clarity breakdown

| Dimension | Score | Weight | Weighted |
|---|---|---|---|
| Goal | 0.90 | 0.43 | 0.387 |
| Scope | 0.85 | 0.28 | 0.238 |
| AC | 0.72 | 0.29 | 0.209 |

### Ontology convergence

- Wave1→3 累计实体：Turn, Chaser, Runner, MP, MovePoint, Skill, TurnCap, WinCond, BuffDef, BuffInstance, StackGroup, StackingMode
- 无术语漂移（同名同义贯穿全程）；Wave3 stability = 7/11 ≈ 64%（4 个新实体均来自 buff 系统，属正常收敛）
