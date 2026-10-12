# Context

## Glossary

| Term | Meaning | Notes |
|---|---|---|
| Chaser | 追逐者，每回合 2 MP，目标是与 Runner 同格 | 抓捕判定 = 同格，任一行动结算后立即判 |
| Runner | 被追者，每回合 3 MP，目标是从游戏开始坚持 20 个完整回合 | TurnCap = 20（双方各动 20 次） |
| MP (MovePoint) | 移动点数；移动 1 格或使用 1 次技能各消耗 1 MP | MP=0 时不能移动也不能用技能 |
| Turn (回合) | 1 回合 = Chaser 行动 + Runner 行动；回合末双方 buff 同时 -1 | 严格交替制 |
| BuffDef / BuffInstance | buff 的静态定义 / 运行时实例（remaining_turns 计时） | 数据驱动，见 buff-system spec |
| StackGroup (互斥组) | 同组 buff 不能共存，冲突时后者替换前者（KeepNew） | 加速/减速同组 SPEED；眩晕/禁锢/沉默各自唯一组 |
| StackingMode | v1 全部 REFRESH；NONE/Stack/RefreshAndStack 留待 v2 | v1 无 NONE 服务对象 |
| 眩晕 | 立即生效：施加当回合内目标剩余 MP 作废，不能移动也不能用技能 | duration=2；与"跳过下回合"语义不同 |
| 禁锢 / 沉默 | 禁移动可技能 / 禁技能可移动 | 可同时存在（不同组） |
