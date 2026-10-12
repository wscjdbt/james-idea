# Buff System Implementation Plan

> Status: APPROVED
> Source: .claude/artifacts/designs/buff-system.md
> Mode: (default)
> Iterations: 2 / 3
> Author: user (via dev-plan)
> Last updated: 2026-10-12

## Requirements summary

为 2D 像素回合制追逐游戏实现 v1 buff 系统：5 个 buff（加速/减速/眩晕/禁锢/沉默）、REFRESH 叠加模式、StackGroup 互斥分组（KeepNew）、回合末衰减、抓捕同格判定、20 完整回合胜率条件，配 5 个测试技能以验证 8 条二值 AC。引擎 Godot 4 / GDScript。

## Acceptance criteria（继承自 spec）

- AC-1：对 Runner 施加减速后，其当回合可用 MP = 2（3 + (-1)）
- AC-2：Runner 已有加速（MP=4）时再施加减速 → 加速被替换移除，减速生效，MP = 2
- AC-3：对已有减速的单位再次施加减速 → remaining_turns 刷新为满值 3，MP 仍为 -1 修正
- AC-4：眩晕在施加当回合内立即生效——目标剩余 MP 作废，本回合不能再移动也不能用技能；回合末 remaining-1（2→1）
- AC-5：禁锢单位可使用技能但不能移动；沉默单位可移动但不能使用技能
- AC-6：任意 buff remaining_turns 减至 0 → 立即移除，MP/禁制状态立即恢复
- AC-7：Chaser 与 Runner 在任一行动结算后同格 → 游戏立即结束，Chaser 胜
- AC-8：第 20 个完整回合（双方各完成 20 次行动）结束且未同格 → 游戏结束，Runner 胜

## RALPLAN-DR

### Principles

- **最小代码**：v1 只 2 个 Unit，不抽 BuffManager 组件；Unit 直接管 buffs 字典
- **数据驱动**：BuffDef / SkillDef 均为 Resource，5+5 个 .tres 文件，便于调参不改代码
- **外科手术式**：只建 buff 系统所需文件，不预设 HP/伤害/地形系统（spec Out of scope）
- **可验证**：每条 AC 对应一个 GUTS 测试用例，先红后绿
- **跟随 spec 边界**：不擅自实现 NONE 模式 / 数值层叠 / 驱散（v2）

### Decision drivers

1. **实现速度**——v1 需快速跑通核心循环验证玩法
2. **可测试性**——8 条 AC 必须能独立跑通
3. **数据驱动调参**——buff 时长/MP 修正需在不改代码下调整平衡

### Viable options

**Option A：Unit 单体 + 轻量 Resource（最小代码派）**
- 实现思路：Unit.gd 直接持有 `buffs: Dictionary[String, BuffInstance]`（key=stack_group_id 天然互斥），内联 `apply_buff` / `tick_buffs` / `effective_mp` / `can_move` / `can_skill` 方法。BuffDef 与 SkillDef 是 Resource 子类，数据走 .tres。
- 改动文件：`scripts/buff_system/buff_def.gd`、`scripts/buff_system/buff_instance.gd`、`scripts/combat/unit.gd`、`scripts/combat/turn_manager.gd`、`scripts/skills/skill_def.gd`、`scripts/game/match.gd`、5 buff .tres、5 skill .tres、`tests/test_buff_system.gd`
- Pros：层数最少；Unit 既是数据载体又是行为主体，符合 Godot 节点哲学；字典 key=stack_group_id 让互斥成数据结构不变式而非运行时检查
- Cons：Unit.gd 会胖（~150 行），buff 逻辑与单位状态混居

**Option B：BuffManager 子节点组件（解耦派）**
- 实现思路：Unit.gd 只管 position/base_mp；BuffManager.gd 作为 Unit 子节点管所有 buff 逻辑，通过信号 `_buff_applied` / `_buff_removed` 通知 Unit 重算 effective_mp。
- 改动文件：同 A + `scripts/buff_system/buff_manager.gd`（多一个文件）
- Pros：buff 逻辑可复用到 NPC / 多单位场景；Unit.gd 精简
- Cons：v1 只有 Chaser/Runner 两个单位，多一层间接与信号连接是过度设计；违反 baseline「单次使用不抽象」

**Option C：EventBus 单例 + buff 自订阅（事件派）**
- 实现思路：全局 EventBus 单例广播 `turn_ended` / `action_completed`，每个 BuffInstance 自己订阅事件并 tick。
- 改动文件：同 A + `scripts/core/event_bus.gd` + 每个 BuffInstance 需 connect/disconnect
- Pros：最解耦，未来扩展地形 buff / 跨单位 buff 最顺
- Cons：v1 无跨单位 buff 需求；5 个 buff 各自管订阅是过度工程；调试栈深

**Invalidation rationale**：B 被砍因 v1 单位数=2，BuffManager 无第二个 caller，属 baseline 明令禁止的"单次使用抽象"；C 被砍因 v1 无跨单位/地形事件源，EventBus 是为 v2 地形传递预留，现在做是预判性设计。

### Implementation steps（基于 Option A）

> 注：greenfield 项目，所有路径为新建文件。

1. **项目骨架** — 创建 Godot 4 项目结构与 `.gitignore`；`project.godot` 配置 GUTS 插件路径
2. **BuffDef 资源类** — `scripts/buff_system/buff_def.gd` 新建 `class_name BuffDef extends Resource`，`@export var id: String`、`stack_group_id: String`、`stacking_mode: int`（枚举 REFRESH=0/NONE=1，v1 仅 REFRESH 用）、`duration_turns: int`、`effect_type: int`（枚举 MP_DELTA=0/RESTRICT=1）、`mp_delta: int`、`restrict_flags: int`（位掩码 STUN/ROOT/SILENCE）
3. **BuffInstance 运行时** — `scripts/buff_system/buff_instance.gd` 新建 `class_name BuffInstance extends RefCounted`，`var def: BuffDef`、`var remaining_turns: int`，`func apply_refresh()` 重置 remaining
4. **5 个 buff 数据** — `resources/buffs/speed_up.tres`（加速，SPEED 组，MP_DELTA，mp_delta=+1，duration=3）、`resources/buffs/slow_down.tres`（减速，SPEED 组，mp_delta=-1，duration=3）、`resources/buffs/stun.tres`（眩晕，STUN 组，RESTRICT，flag STUN|ROOT|SILENCE，duration=2）、`resources/buffs/root.tres`（禁锢，ROOT 组，flag ROOT，duration=2）、`resources/buffs/silence.tres`（沉默，SILENCE 组，flag SILENCE，duration=2）
5. **Unit 类** — `scripts/combat/unit.gd` 新建 `class_name Unit extends Node2D`，`@export var base_mp: int`、`var buffs: Dictionary`（key=stack_group_id）、`var position: Vector2i`、`func effective_mp() -> int`（base_mp + sum mp_delta）、`func can_move() -> bool`（无 STUN/ROOT flag）、`func can_skill() -> bool`（无 STUN/SILENCE flag）、`func apply_buff(def: BuffDef)`（互斥组 KeepNew + REFRESH 逻辑）、`func tick_buffs()`（remaining-1，归零 remove，触发 MP 重算）、`func consume_stun_actions()`（眩晕立即作废剩余 MP）
6. **SkillDef 资源类** — `scripts/skills/skill_def.gd` 新建 `class_name SkillDef extends Resource`，`@export var id: String`、`caster: int`（CHASER/RUNNER）、`target: int`（SELF/OTHER）、`buff_def: BuffDef`、`range_cells: int`、`mp_cost: int`
7. **5 个测试技能数据** — `resources/skills/t_slow.tres`、`t_haste.tres`、`t_stun.tres`、`t_root.tres`、`t_silence.tres`（按 spec 测试技能表）
8. **TurnManager** — `scripts/combat/turn_manager.gd` 新建 `class_name TurnManager extends Node`，`var turn_index: int`、`var chaser: Unit`、`var runner: Unit`、`signal turn_ended(turn_index)`、`func run_action(unit, action)`（移动或技能）→ 抓捕判定 → 若 unit 为 Chaser 则切到 Runner 行动 → 行动结束后若双方都动过则 `tick_buffs()` + turn_index+1 → 检查 20 回合
9. **Match 主控** — `scripts/game/match.gd` 新建 `class_name Match extends Node2D`，初始化 Chaser/Runner/TurnManager，暴露 `on_unit_acted` 接收前端输入，检查 AC-7/AC-8 胜负
10. **GUTS 测试** — `tests/test_buff_system.gd` 新建，8 个测试方法 `test_ac1_slow_reduces_mp` ... `test_ac8_runner_survives_20_turns`，每条 AC 一个，先红后绿

## Workspace setup

- Run `git status --short` and `git branch --show-current` before implementation.
- 当前为 greenfield 空目录，working tree 干净。本 plan 会新建多文件，**建议**先 `git init` 并创建初始 commit 作为回滚锚点；是否创建 worktree 由用户决定（greenfield 无 main 分支冲突风险，可直接在主工作树实施）。
- 实施前确认 Godot 4.x 已安装且可在命令行运行 `godot --headless`。

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| 眩晕"立即生效"在严格交替下，Chaser 施加给 Runner 时 Runner 尚未行动——需 clear 当前 MP 而非下回合 MP | `apply_buff` 内检测 RESTRICT 含 STUN 时立即调用 `target.consume_stun_actions()` 清零剩余 MP，与衰减规则解耦 |
| 加速/减速互斥替换时 effective_mp 缓存未失效 | `effective_mp()` 设计为实时计算而非缓存，每次调用重算（v1 单位数=2 性能无忧） |
| 第 20 回合判定时机：Runner 第 20 次行动后未同格即胜，但 Chaser 在第 20 回合先动可能已抓到 | TurnManager 严格按 Chaser→Runner→判定→衰减顺序，第 20 回合 Chaser 动后判一次、Runner 动后再判一次，任一同格 Chaser 胜 |
| 眩晕连控：Chaser 反复上眩晕，Runner 永久跳过 | v1 接受此风险（spec 假设），平衡在 dev-plan 后用数值模拟验证；若需缓解可给眩晕 duration=1（已=2）或加递减，但属 v2 |
| GUTS 插件未安装 | Step 1 在 project.godot 配置插件路径，若 GUTS 不可用则改用 GDScript 内联 assert 测试 |

## Verification steps

- **AC-1**：`test_ac1_slow_reduces_mp` — Runner.apply_buff(slow_down) → assert `effective_mp() == 2`
- **AC-2**：`test_ac2_slow_replaces_haste` — Runner.apply_buff(speed_up) → apply_buff(slow_down) → assert `not buffs.has("SPEED_haste")` 且 `effective_mp() == 2`
- **AC-3**：`test_ac3_slow_refresh_duration` — Runner.apply_buff(slow_down) → apply_buff(slow_down) → assert `buffs["SPEED"].remaining_turns == 3` 且 `effective_mp() == 2`
- **AC-4**：`test_ac4_stun_immediate` — Chaser.apply_buff(stun) on Runner（Runner 有 3 MP）→ assert `runner.can_move() == false` 且 `runner.can_skill() == false` 且剩余 MP 已清零；回合末 `tick_buffs` 后 `remaining == 1`
- **AC-5**：`test_ac5_root_vs_silence` — apply root → assert `can_move()==false, can_skill()==true`；apply silence → assert `can_move()==true, can_skill()==false`
- **AC-6**：`test_ac6_buff_expiry_restores` — apply slow（duration=3）→ tick 3 次 → assert `not buffs.has("SPEED")` 且 `effective_mp() == 3`
- **AC-7**：`test_ac7_catch_same_tile` — Chaser 移动到 Runner 同格 → assert Match 状态 == CHASER_WIN
- **AC-8**：`test_ac8_runner_survives_20_turns` — 模拟 20 回合 Runner 始终逃开 → assert 第 20 回合末 Match 状态 == RUNNER_WIN
- 运行：`godot --headless --script tests/test_buff_system.gd`（或 GUTS CLI）
- 全绿才算通过；任一红则定位失败 case 修复后重跑

## ADR

- **Decision**：Option A（Unit 单体 + 轻量 Resource），不抽 BuffManager 组件，buffs 字典 key=stack_group_id 实现互斥不变式
- **Drivers**：实现速度（v1 需快速验证玩法）、可测试性（8 AC 一一对应测试）、数据驱动调参（.tres 文件）起决定作用
- **Alternatives considered**：
  - Option A — **chosen**：层数最少，Unit 自管 buffs 符合 Godot 节点哲学，字典 key 实现互斥不变式
  - Option B（BuffManager 组件）— **rejected**：v1 单位数=2，无第二个 caller，属 baseline 禁止的"单次使用抽象"
  - Option C（EventBus）— **rejected**：v1 无跨单位/地形事件源，是为 v2 预判性设计
- **Why chosen**：v1 scope 紧凑（5 buff + 5 测试技能 + 8 AC），最小代码原则下 Unit 单体足够；互斥用字典 key 而非运行时检查，把不变式写进数据结构；后续若 v2 引入中毒层叠或地形传递，再抽 BuffManager 与 EventBus，届时已有清晰 caller
- **Consequences**：
  - 正：实施快，调试栈浅，AC 测试直接打 Unit 方法
  - 负：Unit.gd ~150 行偏胖，buff 逻辑与单位状态混居——v2 扩展时需重构分离
  - 约束：v2 引入 Stack/RefreshAndStack 时需改 `apply_buff` 与字典结构（同组多实例不再唯一），届时 BuffManager 抽取点已明
- **Follow-ups**：正式技能表（超出 5 测试技能）、v2 层叠/地形/驱散、平衡数值模拟（眩晕连控风险验证）

## Review trail

- **Planner draft v1**：推荐 Option A，列 A/B/C 三 option，B/C 给 invalidation rationale；实施步骤 10 步全 cite 新建文件路径
- **Architect challenge v1**：steelman Option B——"Unit.gd 会胖到 150 行，buff 逻辑与单位状态混居不利 v2 扩展；字典 key 互斥虽优雅但 REFRESH 同名 buff 重复施加时若 v2 引入 Stack 模式则字典 key 不再唯一，需重构"——这是真 tension。要求 Planner 在 ADR 标注 v2 重构点
- **Critic verdict v1**：REVISE — AC-4 verification 步骤未明确"眩晕立即生效"如何测试（consume_stun_actions 何时调用）；Risk 表眩晕连控 mitigation 含糊
- **Planner draft v2**：Risk 表加"apply_buff 内检测 STUN 立即 consume_stun_actions"明确时机；Verification AC-4 加"剩余 MP 已清零"断言；ADR Follow-ups 加"v2 重构点：字典 key 改为多值容器"
- **Architect challenge v2**：tension 已记录在 ADR Consequences，无新意见
- **Critic verdict v2**：APPROVED with 1 reservation（见下）
- **Final iterations**：2 / 3

### Critic final reservation

> AC-4 的 `consume_stun_actions` 实现 detail 未在 plan 主体写明——是清零 base_mp 剩余还是设 `mp_spent = base_mp`？前者会破坏"effective_mp 实时计算"不变式。**保留意见**：dev-tdd 阶段实现 AC-4 时需先定 mp 消耗模型（建议引入 `mp_spent: int` 字段，effective_mp = base_mp + buff_modifiers - mp_spent，眩晕清零即 `mp_spent = base_mp`），否则 effective_mp 实时重算与"眩晕清零 MP"会冲突。此模型决策应在 dev-tdd 首测试前确认。
