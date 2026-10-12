class_name Unit
extends Node2D
# A combat unit (Chaser or Runner). Holds active buffs keyed by stack_group_id.
#互斥不变式：同组 buff 同时最多 1 个（v1 全部 REFRESH）。

@export var base_mp: int = 0

# key = stack_group_id (互斥由数据结构天然保证)
var buffs: Dictionary = {}

# 方案 X：眩晕立即生效 = mp_spent = base_mp（effective_mp 实时算，不破坏不变式）
var mp_spent: int = 0

func effective_mp() -> int:
	var delta := 0
	for key in buffs:
		var instance: BuffInstance = buffs[key]
		if instance.def.effect_type == BuffDef.EFFECT_MP_DELTA:
			delta += instance.def.mp_delta
	return base_mp + delta - mp_spent

func apply_buff(def: BuffDef) -> void:
	buffs[def.stack_group_id] = BuffInstance.new(def)
	# 眩晕立即生效：清零剩余 MP（方案 X：mp_spent = base_mp）
	if def.effect_type == BuffDef.EFFECT_RESTRICT and (def.restrict_flags & BuffDef.RESTRICT_STUN) != 0:
		mp_spent = base_mp

func tick_buffs() -> void:
	var to_remove := []
	for key in buffs:
		var instance: BuffInstance = buffs[key]
		instance.remaining_turns -= 1
		if instance.remaining_turns <= 0:
			to_remove.append(key)
	for key in to_remove:
		buffs.erase(key)

func can_move() -> bool:
	for key in buffs:
		var instance: BuffInstance = buffs[key]
		if instance.def.effect_type == BuffDef.EFFECT_RESTRICT:
			var flags = instance.def.restrict_flags
			if (flags & (BuffDef.RESTRICT_STUN | BuffDef.RESTRICT_ROOT)) != 0:
				return false
	return true

func can_skill() -> bool:
	for key in buffs:
		var instance: BuffInstance = buffs[key]
		if instance.def.effect_type == BuffDef.EFFECT_RESTRICT:
			var flags = instance.def.restrict_flags
			if (flags & (BuffDef.RESTRICT_STUN | BuffDef.RESTRICT_SILENCE)) != 0:
				return false
	return true
